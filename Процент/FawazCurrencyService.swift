import Foundation
import Combine

// Новый сервис для работы с fawazahmed0 currency API
class FawazCurrencyService {
    static let shared = FawazCurrencyService()
    private let session = URLSession.shared
    private let cache = NSCache<NSString, NSData>()
    
    // Кэш для хранения данных
    private var historicalCache: [String: [HistoricalDataPoint]] = [:]
    private var currentRatesCache: [String: Double] = [:]
    private let cacheQueue = DispatchQueue(label: "fawaz.cache", qos: .utility)
    
    // Контроль частоты запросов
    private let requestQueue = DispatchQueue(label: "fawaz.requests", qos: .utility)
    private let requestSemaphore = DispatchSemaphore(value: 3) // Максимум 3 одновременных запроса
    private var lastRequestTime: Date?
    private let minRequestInterval: TimeInterval = 0.5 // 0.5 секунды между запросами
    
    private let historyDateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        formatter.locale = Locale(identifier: "en_US_POSIX")
        return formatter
    }()
    
    private init() {}
    
    // MARK: - Структуры для парсинга ответов API
    
    private struct FawazCurrentResponse: Decodable {
        let date: String?
        let rates: [String: Double]
        
        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            
            // Проверяем наличие поля date
            if container.contains(.date) {
                date = try container.decode(String.self, forKey: .date)
            } else {
                date = nil
            }
            
            // Получаем все ключи и ищем валютные курсы
            let allKeys = container.allKeys
            var tempRates: [String: Double] = [:]
            
            for key in allKeys {
                if key.stringValue != "date" {
                    if let nestedRates = try? container.decode([String: Double].self, forKey: key) {
                        // Формат: {"usd": {"eur": 0.85, "rub": 75.0}}
                        tempRates = nestedRates
                        break
                    } else if let value = try? container.decode(Double.self, forKey: key) {
                        // Прямой формат: {"eur": 0.85, "rub": 75.0}
                        tempRates[key.stringValue] = value
                    }
                }
            }
            
            rates = tempRates
        }
        
        struct CodingKeys: CodingKey {
            var stringValue: String
            init?(stringValue: String) { self.stringValue = stringValue }
            var intValue: Int? { nil }
            init?(intValue: Int) { return nil }
            static let date = CodingKeys(stringValue: "date")!
        }
    }
    
    // MARK: - Получение текущих курсов валют
    
    func fetchLatestRates(base: String, symbols: [String]? = nil) -> AnyPublisher<[String: Double], Never> {
        let baseLower = base.lowercased()
        
        // Проверяем кэш с временной меткой (кэшируем на 5 минут)
        let cacheKey = "cachedRates_\(base)"
        let cacheTimeKey = "cachedRatesTime_\(base)"
        
        if let data = UserDefaults.standard.data(forKey: cacheKey),
           let cached = try? JSONDecoder().decode([String: Double].self, from: data),
           let cacheTime = UserDefaults.standard.object(forKey: cacheTimeKey) as? Date,
           Date().timeIntervalSince(cacheTime) < 300 { // 5 минут
            print("📚 Использую кэшированные данные для \(base) (возраст: \(Int(Date().timeIntervalSince(cacheTime))) сек)")
            return Just(cached).eraseToAnyPublisher()
        }
        
        // Основной URL для получения курсов
        let primaryURL = "https://cdn.jsdelivr.net/npm/@fawazahmed0/currency-api@latest/v1/currencies/\(baseLower).json"
        
        // Fallback URL
        let fallbackURL = "https://latest.currency-api.pages.dev/v1/currencies/\(baseLower).json"
        
        return fetchRatesFromURL(primaryURL, base: base, symbols: symbols)
            .catch { _ in
                print("⚠️ Основной URL недоступен, пробуем fallback")
                return self.fetchRatesFromURL(fallbackURL, base: base, symbols: symbols)
            }
            .catch { error in
                print("❌ Ошибка при получении данных: \(error.localizedDescription)")
                
                // Пробуем использовать кэшированные данные
                if let data = UserDefaults.standard.data(forKey: cacheKey),
                   let cached = try? JSONDecoder().decode([String: Double].self, from: data) {
                    print("📚 Использую кэшированные данные для \(base) (ошибка сети)")
                    return Just(cached)
                }
                
                return Just([:])
            }
            .eraseToAnyPublisher()
    }
    
    private func fetchRatesFromURL(_ urlString: String, base: String, symbols: [String]?) -> AnyPublisher<[String: Double], Error> {
        guard let url = URL(string: urlString) else {
            return Fail(error: NSError(domain: "FawazCurrencyService", code: 1, userInfo: [NSLocalizedDescriptionKey: "Invalid URL"]))
                .eraseToAnyPublisher()
        }
        
        var request = URLRequest(url: url)
        request.timeoutInterval = 10
        
        return URLSession.shared.dataTaskPublisher(for: request)
            .map(\.data)
            .tryMap { data -> [String: Double] in
                print("📦 Получены данные из \(urlString): \(data.count) байт")
                
                let response = try JSONDecoder().decode(FawazCurrentResponse.self, from: data)
                
                // Приводим ключи к верхнему регистру
                var resultRates = response.rates.mapKeys { $0.uppercased() }
                
                // Фильтруем по запрошенным символам, если указаны
                if let symbols = symbols {
                    resultRates = resultRates.filter { symbols.contains($0.key) }
                }
                
                print("✅ Успешно получены курсы для \(base): \(resultRates.keys.joined(separator: ", "))")
                
                // Кэшируем результат с временной меткой
                let cacheKey = "cachedRates_\(base)"
                let cacheTimeKey = "cachedRatesTime_\(base)"
                if let encodedData = try? JSONEncoder().encode(resultRates) {
                    UserDefaults.standard.set(encodedData, forKey: cacheKey)
                    UserDefaults.standard.set(Date(), forKey: cacheTimeKey)
                }
                
                return resultRates
            }
            .eraseToAnyPublisher()
    }
    
    // MARK: - Получение исторических данных
    
    // Перегрузка для String параметров
    func fetchHistoricalData(from: String, to: String, days: Int) -> AnyPublisher<[HistoricalDataPoint], Error> {
        let fromCurrency = Currency(code: from, name: from, flagName: from.lowercased(), rate: 1.0)
        let toCurrency = Currency(code: to, name: to, flagName: to.lowercased(), rate: 1.0)
        return fetchHistoricalData(from: fromCurrency, to: toCurrency, days: days)
    }
    
    func fetchHistoricalData(from: Currency, to: Currency, days: Int) -> AnyPublisher<[HistoricalDataPoint], Error> {
        // Ограничиваем максимальный период до 365 дней из-за ограничений API
        let limitedDays = min(days, 365)
        if days > 365 {
            print("⚠️ Запрошено \(days) дней, но API поддерживает максимум 365 дней. Ограничиваем до \(limitedDays) дней.")
        }
        
        print("🔄 Начинаем загрузку истории курсов \(from.code)/\(to.code) за \(limitedDays) дней")
        
        // Проверяем кэш
        let cacheKey = "\(from.code)-\(to.code)-\(limitedDays)"
        if let cachedData = historicalCache[cacheKey] {
            print("📚 Использую кэшированные исторические данные для \(from.code)/\(to.code)")
            return Just(cachedData)
                .setFailureType(to: Error.self)
                .eraseToAnyPublisher()
        }
        
        // Используем HistoricalDataManager для получения данных
        return Future<[HistoricalDataPoint], Error> { promise in
            let calendar = Calendar.current
            let endDate = Date()
            guard let startDate = calendar.date(byAdding: .day, value: -limitedDays + 1, to: endDate) else {
                promise(.failure(NSError(domain: "DateError", code: 0, userInfo: [NSLocalizedDescriptionKey: "Не удалось вычислить дату начала истории"])))
                return
            }
            
            HistoricalDataManager.shared.getHistoricalData(
                fromCurrency: from.code,
                toCurrency: to.code,
                startDate: startDate,
                endDate: endDate
            ) { result in
                switch result {
                case .success(let ratesData):
                    // Преобразуем данные в HistoricalDataPoint
                    let sortedData = ratesData.sorted { $0.0 < $1.0 }
                    var points: [HistoricalDataPoint] = []
                    var previousRate: Double?
                    
                    for (date, rate) in sortedData {
                        let change = previousRate != nil ? rate - previousRate! : 0.0
                        let changePercent = previousRate != nil && previousRate! > 0 ? (change / previousRate!) * 100 : 0.0
                        
                        points.append(HistoricalDataPoint(
                            date: date,
                            rate: rate,
                            change: change,
                            changePercent: changePercent
                        ))
                        
                        previousRate = rate
                    }
                    
                    // Кэшируем результат
                    self.historicalCache[cacheKey] = points
                    print("💾 Кэшировано \(points.count) точек для \(cacheKey)")
                    
                    promise(.success(points))
                case .failure(let error):
                    promise(.failure(error))
                }
            }
        }
        .catch { error -> AnyPublisher<[HistoricalDataPoint], Error> in
            print("❌ Ошибка при загрузке исторических данных: \(error.localizedDescription)")
            print("🔄 Переключаемся на демонстрационные данные")
            return self.generateDemoHistoricalData(from: from, to: to, days: limitedDays)
                .setFailureType(to: Error.self)
                .eraseToAnyPublisher()
        }
        .eraseToAnyPublisher()
    }
    
    // Асинхронная версия для последовательной обработки
    public func fetchRateForDateAsync(from: Currency, to: Currency, date: Date) async throws -> (Date, Double)? {
        let dateString = historyDateFormatter.string(from: date)
        let fromLower = from.code.lowercased()
        let toLower = to.code.lowercased()
        
        // Основной URL
        let primaryURL = "https://cdn.jsdelivr.net/npm/@fawazahmed0/currency-api@\(dateString)/v1/currencies/\(fromLower).json"
        
        // Fallback URL
        let fallbackURL = "https://\(dateString).currency-api.pages.dev/v1/currencies/\(fromLower).json"
        
        do {
            return try await fetchRateFromURLAsync(primaryURL, to: toLower, date: date)
        } catch {
            do {
                return try await fetchRateFromURLAsync(fallbackURL, to: toLower, date: date)
            } catch {
                print("⚠️ Не удалось получить курс за \(dateString): \(error.localizedDescription)")
                return nil
            }
        }
    }
    
    // Асинхронная версия для последовательной обработки
    private func fetchRateFromURLAsync(_ urlString: String, to: String, date: Date) async throws -> (Date, Double)? {
        guard let url = URL(string: urlString) else {
            throw NSError(domain: "FawazCurrencyService", code: 1, userInfo: [NSLocalizedDescriptionKey: "Invalid URL"])
        }
        
        var request = URLRequest(url: url)
        request.timeoutInterval = 5 // Уменьшаем таймаут для быстрой обработки
        
        let (data, _) = try await URLSession.shared.data(for: request)
        let response = try JSONDecoder().decode(FawazCurrentResponse.self, from: data)
        
        if let rate = response.rates[to] {
            return (date, rate)
        }
        
        return nil
    }
    
    // MARK: - Генерация демонстрационных данных как fallback
    
    // Публичная перегрузка для String параметров
    func generateDemoHistoricalData(from: String, to: String, days: Int) -> AnyPublisher<[HistoricalDataPoint], Never> {
        let fromCurrency = Currency(code: from, name: from, flagName: from.lowercased(), rate: 1.0)
        let toCurrency = Currency(code: to, name: to, flagName: to.lowercased(), rate: 1.0)
        return generateDemoHistoricalData(from: fromCurrency, to: toCurrency, days: days)
    }
    
    private func generateDemoHistoricalData(from: Currency, to: Currency, days: Int) -> AnyPublisher<[HistoricalDataPoint], Never> {
        return Future<[HistoricalDataPoint], Never> { promise in
            print("🎭 ГЕНЕРАЦИЯ ДЕМОНСТРАЦИОННЫХ ДАННЫХ для \(from.code)/\(to.code)")
            
            let calendar = Calendar.current
            let currentDate = Date()
            
            // Используем текущую дату
            let safeDate = currentDate
            print("📅 Генерируем демо-данные с текущей даты: \(DateFormatter.localizedString(from: safeDate, dateStyle: .medium, timeStyle: .none))")
            
            let endDate = calendar.date(byAdding: .day, value: -1, to: calendar.startOfDay(for: safeDate)) ?? safeDate
            let startDate = calendar.date(byAdding: .day, value: -days, to: endDate) ?? endDate
            
            var demoPoints: [HistoricalDataPoint] = []
            var currentIterationDate = calendar.startOfDay(for: startDate)
            let finalDate = calendar.startOfDay(for: endDate)
            
            // Базовый курс в зависимости от валютной пары
            var currentRate: Double
            if from.code == "USD" && to.code == "EUR" {
                currentRate = 0.85
            } else if from.code == "EUR" && to.code == "USD" {
                currentRate = 1.18
            } else if from.code == "USD" && to.code == "RUB" {
                currentRate = 75.0
            } else if from.code == "RUB" && to.code == "USD" {
                currentRate = 1.0 / 75.0
            } else {
                currentRate = 1.0
            }
            
            // Генерируем точки данных
            while currentIterationDate <= finalDate {
                // Добавляем небольшие случайные колебания
                let variation = Double.random(in: 0.95...1.05)
                let adjustedRate = currentRate * variation
                
                demoPoints.append(HistoricalDataPoint(
                    date: currentIterationDate,
                    rate: adjustedRate,
                    change: 0.0,
                    changePercent: 0.0
                ))
                
                guard let nextDate = calendar.date(byAdding: .day, value: 1, to: currentIterationDate) else { break }
                currentIterationDate = nextDate
            }
            
            // Вычисляем изменения
            for i in 1..<demoPoints.count {
                let previousRate = demoPoints[i-1].rate
                let currentRateValue = demoPoints[i].rate
                let change = currentRateValue - previousRate
                let changePercent = (change / previousRate) * 100
                
                demoPoints[i].change = change
                demoPoints[i].changePercent = changePercent
            }
            
            print("🎭 Сгенерированы демонстрационные данные: \(demoPoints.count) точек для \(from.code)/\(to.code)")
            promise(.success(demoPoints))
        }
        .eraseToAnyPublisher()
    }
    
    // MARK: - Вспомогательные методы
    
    func getCurrentRate(from: String, to: String) -> Double? {
        let cacheKey = "cachedRates_\(from)"
        if let data = UserDefaults.standard.data(forKey: cacheKey),
           let cached = try? JSONDecoder().decode([String: Double].self, from: data) {
            return cached[to.uppercased()]
        }
        return nil
    }
    
    func clearHistoricalDataCache() {
        historicalCache.removeAll()
        print("🗑️ Кэш исторических данных FawazCurrencyService очищен")
    }
    
    func clearCache() {
        historicalCache.removeAll()
        currentRatesCache.removeAll()
        print("🗑️ Кэш FawazCurrencyService очищен")
    }
}

// Вспомогательное расширение для mapKeys
private extension Dictionary {
    func mapKeys<T: Hashable>(_ transform: (Key) -> T) -> [T: Value] {
        var result: [T: Value] = [:]
        for (key, value) in self {
            result[transform(key)] = value
        }
        return result
    }
}