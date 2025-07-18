import Charts
import Foundation
import Combine
import os.log

final class CurrencyConverterViewModel: ObservableObject {
    // Logger для отладки
    private let logger = Logger(subsystem: "com.Procent.Procent", category: "CurrencyConverter")
    // Форматтер для отправки запросов
    private let inputDateFormatter: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "yyyy-MM-dd"
        return f
    }()
    
    // Форматтер для отображения времени последнего обновления - исправлено для обновления при смене языка
    private var outputDateFormatter: DateFormatter {
        return LocalizationManager.shared.createDateFormatter(format: "d MMM yyyy HH:mm")
    }

    // CRITICAL PERFORMANCE: Remove @Published from frequently updated properties
    private var _lastUpdate: String = ""
    var lastUpdate: String {
        get { _lastUpdate }
        set { 
            _lastUpdate = newValue
            // CRITICAL PERFORMANCE: Remove UI update from setter - will be handled centrally
        }
    }
    
    private var _currencies: [Currency] = []
    var currencies: [Currency] {
        get { _currencies }
        set { 
            _currencies = newValue
            // CRITICAL PERFORMANCE: Remove UI update from setter - will be handled centrally
        }
    }
    
    private var _amounts: [String: String] = [:]
    
    // CRITICAL: Use manual update control instead of @Published
    var amounts: [String: String] {
        get { _amounts }
        set { 
            _amounts = newValue
            // REMOVED: objectWillChange.send() to prevent cascade updates
            // UI will be updated through dedicated update methods only
        }
    }
    
    // Массив видимых валют (макс. 10 по умолчанию)
    private var _visibleCurrencies: [Currency] = []
    var visibleCurrencies: [Currency] {
        get { _visibleCurrencies }
        set { 
            _visibleCurrencies = newValue
            _currencies = newValue // Update currencies for compatibility
            // CRITICAL PERFORMANCE: Remove UI update from setter - will be handled centrally
        }
    }
    
    // Все доступные валюты
    private var _allCurrencies: [Currency] = []
    var allCurrencies: [Currency] {
        get { _allCurrencies }
        set { 
            _allCurrencies = newValue
            // REMOVED: objectWillChange.send() to prevent cascade updates
            // UI will be updated through dedicated update methods only
        }
    }
    
    // CRITICAL: Control when to update view with much longer intervals
    private var shouldUpdateView = true
    private var lastUpdateTime: Date = Date()
    private let minUpdateInterval: TimeInterval = 0.15 // Minimum 150ms between updates (было 2000ms)
    private let maxUpdateInterval: TimeInterval = 2.0 // Maximum 2000ms between forced updates
    
    // Константа для максимального количества отображаемых валют по умолчанию
    private let defaultMaxVisibleCurrencies = 10
    
    // Performance optimization: debounce timer for saves
    private var saveDebouncer: AnyCancellable?
    private let saveQueue = DispatchQueue(label: "com.app.savequeue", qos: .utility)
    
    // Cache for formatted values to avoid repeated formatting
    private var formattedCache: [String: [String: String]] = [:]
    
    // CRITICAL PERFORMANCE: Track active field to update only it immediately
    private var activeFieldCode: String?
    private var pendingCalculation: AnyCancellable?
    private let calculationQueue = DispatchQueue(label: "com.app.calculation", qos: .userInteractive)

    struct HistoryPoint: Identifiable, Equatable {
        let id = UUID()
        let date: Date
        let rate: Double
        let change: Double
        let changePercent: Double
        
        static func == (lhs: HistoryPoint, rhs: HistoryPoint) -> Bool {
            return lhs.date == rhs.date && lhs.rate == rhs.rate && lhs.change == rhs.change && lhs.changePercent == rhs.changePercent
        }
        
        // Инициализатор для обратной совместимости
        init(date: Date, rate: Double) {
            self.date = date
            self.rate = rate
            self.change = 0.0
            self.changePercent = 0.0
        }
        
        // Инициализатор для новых данных
        init(date: Date, rate: Double, change: Double, changePercent: Double) {
            self.date = date
            self.rate = rate
            self.change = change
            self.changePercent = changePercent
        }
    }
    
    @Published var history: [HistoryPoint] = []
    @Published var isLoading: Bool = false
    @Published var errorMessage: String? = nil

    // Удалены приватные поля _history, _isLoading, _errorMessage и их геттеры/сеттеры
    
    private let service = CurrencyService() // Добавляем сервис исторических данных
    private var cancellables = Set<AnyCancellable>()
    
    // CRITICAL: Add semaphore to prevent multiple simultaneous API calls
    private let apiSemaphore = DispatchSemaphore(value: 1)
    private var lastApiCall: Date?
    private let apiCallThrottleInterval: TimeInterval = 5.0 // Increased from 2.0 to 5.0 seconds

    /// Applies a dictionary of rates to update trackedCodes, currencies, and reset amounts.
    private func applyRates(_ ratesDict: [String: Double], base: String) {
        // Фильтруем устаревшие валюты
        let filteredRates = ratesDict.filter { !CurrencyFlag.isDeprecatedCurrency($0.key) }
        
        // Assemble codes in order: priority → cisGroup → others alphabetically
        let all = Array(filteredRates.keys).sorted()
        var sorted: [String] = []
        sorted += priority.filter(all.contains)
        sorted += cisGroup.filter(all.contains)
        sorted += all.filter { !priority.contains($0) && !cisGroup.contains($0) }

        // Update state on main thread with minimal UI updates
        DispatchQueue.main.async {
            self._trackedCodes = sorted
            
            // Создаем массив всех валют с локализованными названиями на текущем языке приложения
            self._allCurrencies = sorted.map { code in
                Currency(
                    code: code,
                    name: LocalizationManager.shared.currentLocale().localizedString(forCurrencyCode: code) ?? code,
                    flagName: code,
                    rate: filteredRates[code] ?? 0
                )
            }
            
            // Загружаем сохраненные видимые валюты или используем первые 10 по умолчанию
            if let savedVisibleCodes = UserDefaults.standard.stringArray(forKey: "visibleCurrencyCodes") {
                // Фильтруем только действительно существующие коды и удаляем устаревшие валюты
                let validCodes = savedVisibleCodes.filter { sorted.contains($0) && !CurrencyFlag.isDeprecatedCurrency($0) }
                
                if !validCodes.isEmpty {
                    // Создаем массив видимых валют из сохраненных кодов
                    self._visibleCurrencies = validCodes.compactMap { code in
                        self._allCurrencies.first { $0.code == code }
                    }
                } else {
                    // Если нет сохраненных или они все недействительны, используем первые 10
                    self._visibleCurrencies = Array(self._allCurrencies.prefix(self.defaultMaxVisibleCurrencies))
                }
            } else {
                // Если нет сохраненных кодов, используем первые 10
                self._visibleCurrencies = Array(self._allCurrencies.prefix(self.defaultMaxVisibleCurrencies))
            }
            
            // Для обратной совместимости присваиваем видимые валюты в currencies
            self._currencies = self._visibleCurrencies
            
            // Очищаем amounts только если нет сохраненных данных
            if self._amounts.isEmpty {
                self.loadSavedAmounts()
            }
            
            // CRITICAL PERFORMANCE: Single UI update at the end
            self.triggerUIUpdateIfNeeded()
        }
    }

    /// Коды валют в порядке приоритета
    private let priority: [String] = ["USD", "EUR", "CHF", "CNY", "TRY", "RUB"]
    private let cisGroup: [String]  = ["BYN","KZT","UAH","AZN","AMD","KGS","UZS","TJS"]

    // CRITICAL PERFORMANCE: Remove @Published from trackedCodes
    private var _trackedCodes: [String] = []
    var trackedCodes: [String] {
        get { _trackedCodes }
        set { 
            _trackedCodes = newValue
            // No UI update needed for this property
        }
    }

    // При инициализации ViewModel, если visibleCurrencies пуст, добавить 8 валют
    init() {
        logger.debug("DEBUG: CurrencyConverterViewModel инициализирован")
        // Load cached rates immediately for offline-first startup
        if let data = UserDefaults.standard.data(forKey: "cachedRates_USD"),
           let cached = try? JSONDecoder().decode([String: Double].self, from: data) {
            applyRates(cached, base: "USD")
        }
        // Then fetch fresh rates
        reloadRates(base: "USD")
        
        // Загружаем сохраненные значения amounts
        loadSavedAmounts()
        
        if visibleCurrencies.isEmpty {
            visibleCurrencies = [
                Currency(code: "USD", name: "Доллар США", flagName: "USD", rate: 0),
                Currency(code: "EUR", name: "Евро", flagName: "EUR", rate: 0),
                Currency(code: "CNY", name: "Китайский юань", flagName: "CNY", rate: 0),
                Currency(code: "CHF", name: "Швейцарский франк", flagName: "CHF", rate: 0),
                Currency(code: "TRY", name: "Турецкая лира", flagName: "TRY", rate: 0),
                Currency(code: "RUB", name: "Российский рубль", flagName: "RUB", rate: 0),
                Currency(code: "KZT", name: "Казахстанский тенге", flagName: "KZT", rate: 0),
                Currency(code: "AZN", name: "Азербайджанский манат", flagName: "AZN", rate: 0)
            ]
            // Обновить UI
            triggerUIUpdate()
        }
    }
    
    deinit {
        // CRITICAL PERFORMANCE: Clean up any pending save operations and release resources
        saveDebouncer?.cancel()
        pendingCalculation?.cancel()
        formattedCache.removeAll()
        cancellables.removeAll()
    }
    
    /// Добавляет валюту в список видимых
    func addCurrencyToVisible(_ currency: Currency) {
        // Проверяем, не добавлена ли уже эта валюта
        if !_visibleCurrencies.contains(where: { $0.code == currency.code }) {
            // Добавляем валюту в конец списка
            _visibleCurrencies.append(currency)
            // Обновляем currencies для совместимости
            _currencies = _visibleCurrencies
            // Сохраняем список видимых валют
            saveVisibleCurrencies()
            // CRITICAL PERFORMANCE: Update UI only once
            triggerUIUpdateIfNeeded()
        }
    }
    
    /// Удаляет валюту из списка видимых
    func removeCurrencyFromVisible(_ code: String) {
        // Удаляем валюту из списка
        _visibleCurrencies.removeAll { $0.code == code }
        // Обновляем currencies для совместимости
        _currencies = _visibleCurrencies
        // Сохраняем список видимых валют
        saveVisibleCurrencies()
        // CRITICAL PERFORMANCE: Update UI only once
        triggerUIUpdateIfNeeded()
    }
    
    /// Сохраняет список видимых валют в UserDefaults
    func saveVisibleCurrencies() {
        let codes = _visibleCurrencies.map { $0.code }
        UserDefaults.standard.set(codes, forKey: "visibleCurrencyCodes")
    }
    
    /// Обновляет названия валют при смене языка
    func updateCurrencyNames() {
        // Обновляем названия валют в visibleCurrencies
        for i in 0..<_visibleCurrencies.count {
            let code = _visibleCurrencies[i].code
            if let updatedCurrency = _allCurrencies.first(where: { $0.code == code }) {
                _visibleCurrencies[i] = updatedCurrency
            }
        }
        
        // Обновляем currencies для совместимости
        _currencies = _visibleCurrencies
        
        // CRITICAL PERFORMANCE: Use throttled UI update instead of direct call
        triggerUIUpdateIfNeeded()
    }

    /// Перезагружает список курсов (и сбрасывает конвертацию)
    func reloadRates(base: String, symbols: [String]? = nil) {
        // CRITICAL: Prevent multiple simultaneous API calls
        let now = Date()
        
        // Check if we should throttle the API call
        if let lastCall = lastApiCall, now.timeIntervalSince(lastCall) < apiCallThrottleInterval {
            logger.debug("🚫 API call throttled - too frequent")
            return
        }
        
        // Try to acquire semaphore (non-blocking)
        if apiSemaphore.wait(timeout: .now()) != .success {
            logger.debug("🚫 API call skipped - another call in progress")
            return
        }
        
        lastApiCall = now
        _lastUpdate = outputDateFormatter.string(from: Date())
        
        service.fetchLatestRates(base: base, symbols: symbols)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] ratesDict in
                guard let self = self else { 
                    self?.apiSemaphore.signal()
                    return 
                }
                self.applyRates(ratesDict, base: base)
                self.apiSemaphore.signal() // Release semaphore
            }
            .store(in: &cancellables)
    }
    
    /// Mark field as active for instant updates
    func setActiveField(_ code: String?) {
        // Если активируется новое поле, очищаем все значения
        if let newCode = code, activeFieldCode != newCode {
            clearAllAmounts()
        }
        activeFieldCode = code
    }

    /// CRITICAL PERFORMANCE: Update only active field immediately, defer others
    func updateAmounts(changedCode: String, enteredText: String) {
        // CRITICAL PERFORMANCE: Skip if text is empty or unchanged
        if enteredText.isEmpty {
            _amounts[changedCode] = ""
            performAmountCalculation(changedCode: changedCode, enteredText: enteredText)
            return
        }
        // INSTANT UPDATE: Update the active field immediately without any calculation
        _amounts[changedCode] = enteredText
        // Без debounce: сразу пересчитываем
        performAmountCalculation(changedCode: changedCode, enteredText: enteredText)
    }
    
    /// CRITICAL: Single point of UI updates with proper throttling
    private func triggerUIUpdate() {
        let now = Date()
        if now.timeIntervalSince(lastUpdateTime) >= minUpdateInterval {
            objectWillChange.send()
            lastUpdateTime = now
        }
    }
    
    /// CRITICAL PERFORMANCE: Even more restrictive UI updates - only when really needed
    private func triggerUIUpdateIfNeeded() {
        let now = Date()
        // CRITICAL: Increased throttling to prevent CPU overload
        if now.timeIntervalSince(lastUpdateTime) >= minUpdateInterval {
            DispatchQueue.main.async { [weak self] in
                guard let self = self else { return }
                self.objectWillChange.send()
                self.lastUpdateTime = now
            }
        }
    }
    
    private func performAmountCalculation(changedCode: String, enteredText: String) {
        let start = Date()
        // Check cache first to avoid redundant calculations
        let cacheKey = "\(changedCode):\(enteredText)"
        if let cachedResult = formattedCache[cacheKey] {
            // Use cached result if available
            updateAmountsFromCache(changedCode: changedCode, cachedResult: cachedResult)
            return
        }
        // Clean the entered text for calculation
        let cleanedText = enteredText.replacingOccurrences(of: ",", with: ".")
        guard let entered = Double(cleanedText), entered >= 0 else {
            return
        }
        // Find the base rate for the changed currency
        guard let baseRate = currencies.first(where: { $0.code == changedCode })?.rate, baseRate > 0 else {
            return
        }
        calculationQueue.async { [weak self] in
            guard let self = self else { return }
            var newAmounts: [String: String] = [:]
            let limitedCurrencies = Array(self.currencies.prefix(self.currencies.count)) // Show all visible currencies
            for c in limitedCurrencies {
                if c.code == changedCode {
                    newAmounts[c.code] = enteredText
                } else {
                    let value = entered / baseRate * c.rate
                    if value.isNaN || value.isInfinite {
                        newAmounts[c.code] = "0,00"
                    } else {
                        newAmounts[c.code] = String(format: "%.2f", value)
                            .replacingOccurrences(of: ".", with: ",")
                    }
                }
            }
            self.formattedCache[cacheKey] = newAmounts
            self.clearCacheIfNeeded()
            DispatchQueue.main.async { [weak self] in
                guard let self = self else { return }
                for (code, value) in newAmounts {
                    if code != self.activeFieldCode {
                        self._amounts[code] = value
                    }
                }
                let end = Date()
                self.logger.debug("Время расчёта performAmountCalculation: \(end.timeIntervalSince(start)) сек")
                self.triggerUIUpdate()
                // self.debouncedSaveAmounts() // Отключено для диагностики
            }
        }
    }
    
    private func updateAmountsFromCache(changedCode: String, cachedResult: [String: String]) {
        // Update UI on main thread with cached values
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            
            for (code, value) in cachedResult {
                if code != self.activeFieldCode {
                    self._amounts[code] = value
                }
            }
            
            // SINGLE UI UPDATE: Use centralized update method
            self.triggerUIUpdate()
        }
    }

    /// Заменяет валюту в списке (при выборе нового кода) - теперь свапает выбранную валюту и новую
    func replaceCode(at index: Int, with newCode: String) {
        guard index < currencies.count,
              let targetIndex = currencies.firstIndex(where: { $0.code == newCode })
        else { return }
        // Swap the two currency entries
        currencies.swapAt(index, targetIndex)
        trackedCodes.swapAt(index, targetIndex)
    }
    
    /// Перемещает валюту с одной позиции на другую
    func moveCurrency(from source: Int, to destination: Int) {
        print("🔄 moveCurrency called: from \(source) to \(destination), count: \(_visibleCurrencies.count)")
        
        guard source != destination,
              source >= 0, source < _visibleCurrencies.count,
              destination >= 0, destination < _visibleCurrencies.count else { 
            print("❌ moveCurrency: Invalid parameters - source: \(source), destination: \(destination), count: \(_visibleCurrencies.count)")
            return 
        }
        
        // Сохраняем перемещаемую валюту
        let movedCurrency = _visibleCurrencies[source]
        print("📦 Moving currency: \(movedCurrency.code) from \(source) to \(destination)")
        
        // Выполняем перемещение
        _visibleCurrencies.remove(at: source)
        _visibleCurrencies.insert(movedCurrency, at: destination)
        
        // Обновляем currencies для совместимости и принудительно уведомляем SwiftUI об изменениях
        currencies = _visibleCurrencies
        
        print("✅ Currency moved successfully. New order: \(_visibleCurrencies.map { $0.code }.joined(separator: ", "))")
        
        // Сохраняем список видимых валют
        saveVisibleCurrencies()
        
        // Принудительно обновляем UI
        DispatchQueue.main.async {
            self.objectWillChange.send()
        }
    }

    /// Загружает историю изменений курса по дням (fallback реализация через intermediary USD)
    // MARK: - Метод для загрузки исторических данных через FawazCurrencyService
    
    func fetchHistoricalData(from: String, to: String, days: Int) {
        logger.debug("🔍 ViewModel: fetchHistoricalData called with \(from) -> \(to), days: \(days)")
        history = []
        isLoading = true
        errorMessage = nil
        
        // Используем CurrencyService (FawazCurrencyService) для загрузки исторических данных
        service.fetchHistoricalData(from: from, to: to, days: days)
            .receive(on: DispatchQueue.main)
            .sink(
                receiveCompletion: { [weak self] completion in
                    self?.logger.debug("🔍 ViewModel: Completion received")
                    self?.isLoading = false
                    self?.logger.debug("✅ ViewModel: Historical data loading finished successfully")
                },
                receiveValue: { [weak self] historicalData in
                    self?.logger.debug("🔍 ViewModel: Received \(historicalData.count) historical data points")
                    let historyPoints = historicalData.map { dataPoint in
                        HistoryPoint(date: dataPoint.date, rate: dataPoint.rate)
                    }
                    self?.history = historyPoints
                    self?.errorMessage = nil
                    self?.logger.debug("✅ Успешно загружены исторические данные через Fawaz API: \(historyPoints.count) точек")
                }
            )
            .store(in: &cancellables)
    }
    
    func fetchTimeSeriesHistory(base: String,
                                symbol: String,
                                start: Date,
                                end: Date) {
        logger.debug("DEBUG: Вызван fetchTimeSeriesHistory: base=\(base), symbol=\(symbol), start=\(start), end=\(end)")
        isLoading = true
        errorMessage = nil
        let calendar = Calendar.current
        
        // Используем переданные даты напрямую без дополнительных корректировок
        // так как они уже правильно вычислены в EnhancedCurrencyHistoryView
        logger.debug("🔄 Начинаем загрузку истории курсов \(base)/\(symbol)")
        logger.debug("📅 Период: с \(start) по \(end)")
        
        // Вычисляем количество дней между датами
        let days = calendar.dateComponents([.day], from: start, to: end).day ?? 7
        logger.debug("📅 Количество дней для запроса: \(days)")
        
        // Используем новый метод fetchHistoricalData с String параметрами
        service.fetchHistoricalData(from: base, to: symbol, days: days)
            .receive(on: DispatchQueue.main)
            .sink(
                receiveCompletion: { [weak self] completion in
                    self?.isLoading = false
                    self?.logger.debug("✅ CurrencyConverterViewModel: Historical data loading finished successfully")
                },
                receiveValue: { [weak self] historicalData in
                    guard let self = self else { return }
                    let historyPoints = historicalData.map { dataPoint in
                        HistoryPoint(date: dataPoint.date, rate: dataPoint.rate)
                    }
                    self.history = historyPoints
                    self.errorMessage = nil
                    self.logger.debug("✅ CurrencyConverterViewModel: Загружена история через Fawaz API для пары \(base)/\(symbol): \(historyPoints.count) точек")
                    self.logger.debug("📊 CurrencyConverterViewModel: history.count = \(self.history.count)")
                    self.cacheHistoryData(base: base, symbol: symbol, start: start, end: end, points: historyPoints)
                }
            )
            .store(in: &cancellables)
    }
    
    /// Генерирует демонстрационные данные для графика
    private func generateDemoHistoryPoints(base: String, symbol: String, start: Date, end: Date) -> [HistoryPoint] {
        var demoPoints: [HistoryPoint] = []
        
        // Определяем начальное значение в зависимости от валютной пары
        let startValue: Double
        if base == "USD" && symbol == "RUB" {
            startValue = 70.0
        } else if base == "EUR" && symbol == "RUB" {
            startValue = 85.0
        } else if base == "RUB" {
            startValue = 0.014 // Для обратной конвертации (RUB -> другая валюта)
        } else if base == symbol {
            startValue = 1.0 // Для одинаковой валюты
        } else {
            startValue = 1.2 // Дефолтное значение для других пар
        }
        
        var currentValue = startValue
        
        // Генерируем даты для выбранного периода
        let calendar = Calendar.current
        var currentDate = start
        
        while currentDate <= end {
            // Генерируем более реалистичные данные с трендом
            let daysSinceStart = calendar.dateComponents([.day], from: start, to: currentDate).day ?? 0
            
            // Создаем основной тренд
            let trendComponent = sin(Double(daysSinceStart) / 15.0) // Долгосрочный тренд (синусоида)
                + cos(Double(daysSinceStart) / 7.0) * 0.5 // Среднесрочный тренд (косинусоида)
            
            // Добавляем небольшую случайность
            let randomComponent = Double.random(in: -0.2...0.2)
            
            let fluctuation = (trendComponent + randomComponent) * (startValue * 0.01) // Процент от базового курса
            currentValue += fluctuation
            
            // Гарантируем, что значение не станет отрицательным
            if currentValue < 0.001 { currentValue = 0.001 }
            
            demoPoints.append(HistoryPoint(date: currentDate, rate: currentValue))
            guard let nextDate = calendar.date(byAdding: .day, value: 1, to: currentDate) else { break }
            currentDate = nextDate
        }
        
        logger.debug("🔄 Созданы демо-данные для графика: \(demoPoints.count) точек")
        return demoPoints.sorted(by: { $0.date < $1.date })
    }

    private func processHistory(_ seriesPair: ([(Date, Double)], [(Date, Double)])) -> [HistoryPoint] {
        let (baseSeries, symbolSeries) = seriesPair
        // Build dictionaries keyed by date
        let baseDict = Dictionary(uniqueKeysWithValues: baseSeries)
        let symbolDict = Dictionary(uniqueKeysWithValues: symbolSeries)
        // Find common dates
        let commonDates = Set(baseDict.keys).intersection(symbolDict.keys).sorted()
        // Build history points
        return commonDates.compactMap { date in
            guard let bRate = baseDict[date], bRate > 0 else { return nil }
            let sRate = symbolDict[date] ?? 0
            return HistoryPoint(date: date, rate: sRate / bRate)
        }
    }

    /// Вспомогательный метод для проверки и загрузки кэшированных данных для истории
    func loadHistoryCacheIfAvailable(base: String, symbol: String, start: Date, end: Date) -> [HistoryPoint]? {
        // Генерируем тот же ключ кэша
        let startStr = inputDateFormatter.string(from: start)
        let endStr = inputDateFormatter.string(from: end)
        let cacheKey = "history_\(base)_\(symbol)_\(startStr)_\(endStr)"
        
        // Безопасное извлечение данных из UserDefaults
        guard let timestampsArray = UserDefaults.standard.array(forKey: "\(cacheKey)_timestamps"),
              let ratesArray = UserDefaults.standard.array(forKey: "\(cacheKey)_rates"),
              timestampsArray.count == ratesArray.count,
              !timestampsArray.isEmpty else {
            return nil
        }
        
        // Безопасное приведение к нужным типам
        let timestamps = timestampsArray.compactMap { $0 as? Double }
        let rates = ratesArray.compactMap { $0 as? Double }
        
        // Проверяем, что все элементы успешно преобразованы
        guard timestamps.count == timestampsArray.count,
              rates.count == ratesArray.count,
              timestamps.count == rates.count else {
            logger.debug("⚠️ Ошибка при преобразовании кэшированных данных для \(base)/\(symbol)")
            return nil
        }
        
        // Восстанавливаем данные
        let points = zip(timestamps, rates).map { 
            HistoryPoint(date: Date(timeIntervalSince1970: $0.0), rate: $0.1)
        }
        return points
    }
    
    /// Сохраняет данные истории в кэш
    func cacheHistoryData(base: String, symbol: String, start: Date, end: Date, points: [HistoryPoint]) {
        // Генерируем уникальный ключ для кэша
        let startStr = inputDateFormatter.string(from: start)
        let endStr = inputDateFormatter.string(from: end)
        let cacheKey = "history_\(base)_\(symbol)_\(startStr)_\(endStr)"
        
        // Сохраняем даты и курсы отдельно для удобства хранения
        let timestamps = points.map { $0.date.timeIntervalSince1970 }
        let rates = points.map { $0.rate }
        
        // Кэшируем через UserDefaults
        UserDefaults.standard.set(timestamps, forKey: "\(cacheKey)_timestamps")
        UserDefaults.standard.set(rates, forKey: "\(cacheKey)_rates")
        
        logger.debug("💾 Кэшировано \(points.count) точек для \(base)/\(symbol)")
    }
    
    /// Histiry date formatter
    private let historyDateFormatter: DateFormatter? = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "yyyy-MM-dd"
        return f
    }()

    // PERFORMANCE: Optimized debounced save with longer delay
    private func debouncedSaveAmounts() {
        saveDebouncer?.cancel()
        saveDebouncer = Just(())
            .delay(for: .milliseconds(500), scheduler: RunLoop.main) // Increased from immediate to 500ms
            .sink { [weak self] _ in
                self?.saveAmounts()
            }
    }
    
    // PERFORMANCE: Optimized save operation
    private func saveAmounts() {
        guard !_amounts.isEmpty else { return }
        
        saveQueue.async { [weak self] in
            guard let self = self else { return }
            
            // Only save non-empty amounts to reduce data size
            let filteredAmounts = self._amounts.filter { !$0.value.isEmpty }
            
            if let encoded = try? JSONEncoder().encode(filteredAmounts) {
                UserDefaults.standard.set(encoded, forKey: "savedAmounts")
            }
        }
    }

    // PERFORMANCE: Optimized load operation
    private func loadSavedAmounts() {
        saveQueue.async { [weak self] in
            guard let self = self else { return }
            
            if let data = UserDefaults.standard.data(forKey: "savedAmounts"),
               let decoded = try? JSONDecoder().decode([String: String].self, from: data) {
                DispatchQueue.main.async {
                    self._amounts = decoded
                    // CRITICAL PERFORMANCE: Don't trigger UI update during initialization
                    // UI will be updated when needed by other methods
                }
            }
        }
    }
    
    // CRITICAL PERFORMANCE: Clear cache periodically to prevent memory issues
    private func clearCacheIfNeeded() {
        if formattedCache.count > 50 { // Reduced cache size from 100 to 50 for better performance
            formattedCache.removeAll()
        }
    }
    
    /// Очищает сохраненные значения amounts
    func clearSavedAmounts() {
        UserDefaults.standard.removeObject(forKey: "savedAmounts")
        _amounts = [:]
        formattedCache.removeAll()
        // CRITICAL PERFORMANCE: Update UI only once
        triggerUIUpdateIfNeeded()
    }

    /// Очищает все суммы во всех валютах и обновляет UI
    func clearAllAmounts() {
        for code in currencies.map({ $0.code }) {
            _amounts[code] = ""
        }
        formattedCache.removeAll()
        triggerUIUpdate()
    }
}
