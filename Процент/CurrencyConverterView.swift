import Charts
import SwiftUI
import Foundation
import Combine
#if os(iOS)
import UIKit
#endif



enum Period: Identifiable, CaseIterable {
    var id: Self { self }
    case sevenDays, oneMonth, threeMonths, sixMonths, oneYear

    var title: String {
        switch self {
        case .sevenDays: return LocalizationManager.shared.localizedString("7_days")
        case .oneMonth: return LocalizationManager.shared.localizedString("1_month")
        case .threeMonths: return LocalizationManager.shared.localizedString("3_months")
        case .sixMonths: return LocalizationManager.shared.localizedString("6_months")
        case .oneYear: return LocalizationManager.shared.localizedString("1_year")
        }
    }
    
    func calculateStartDate() -> Date {
        let now = Date()
        let calendar = Calendar.current
        let yesterday = calendar.date(byAdding: .day, value: -1, to: calendar.startOfDay(for: now)) ?? now
        switch self {
        case .sevenDays: return Calendar.current.date(byAdding: .day, value: -7, to: yesterday)!
        case .oneMonth: return Calendar.current.date(byAdding: .month, value: -1, to: yesterday)!
        case .threeMonths: return Calendar.current.date(byAdding: .month, value: -3, to: yesterday)!
        case .sixMonths: return Calendar.current.date(byAdding: .month, value: -6, to: yesterday)!
        case .oneYear: return Calendar.current.date(byAdding: .year, value: -1, to: yesterday)!
        }
    }
}

// MARK: - View Extensions
extension View {
    @ViewBuilder
    func conditionalModifier<Content: View>(
        _ condition: Bool,
        transform: (Self) -> Content
    ) -> some View {
        if condition {
            transform(self)
        } else {
            self
        }
    }
}

struct CurrencyConverterView: View {
    @EnvironmentObject private var themeManager: ThemeManager
    @EnvironmentObject private var localizationManager: LocalizationManager
    
    // CRITICAL PERFORMANCE: Use shared ViewModel instead of creating new instance
    @EnvironmentObject private var viewModel: CurrencyConverterViewModel
    @State private var showingPicker = false
    @State private var activeIndex: Int? = nil
    @State private var showingStats = false
    @State private var statsBaseCode: String = "USD"
    @State private var statsCompareCode: String = "EUR"
    @State private var showingStatsBasePicker = false
    @State private var showingStatsComparePicker = false
    @State private var currentPoint: CurrencyConverterViewModel.HistoryPoint? = nil
    @State private var lastRefresh = Date()
    // REMOVED: @State private var refreshID = UUID() // Removed to prevent unnecessary updates
    @State private var showingAddCurrencyPicker = false
    @State private var isEditMode: Bool = false
    @State private var cancellables = Set<AnyCancellable>()
    
    // CRITICAL PERFORMANCE: Use simple @State instead of @AppStorage to reduce updates
    @State private var lastActiveIndex: Int = UserDefaults.standard.integer(forKey: "lastActiveIndex")

    private let buttonSpacing: CGFloat = -12
    private let horizontalPadding: CGFloat = 6
    private let verticalPadding: CGFloat = 4
    private let rowSpacing: CGFloat = -12

    @State private var selectedPeriod: Period = .sevenDays
    
    // Состояния для локального масштабирования графика
    @State private var zoomStartDate: Date?
    @State private var zoomEndDate: Date?
    @State private var zoomMinY: Double?
    @State private var zoomMaxY: Double?
    @State private var isZooming: Bool = false
    @State private var lastMagnification: CGFloat = 1.0
    @AppStorage("showZoomHint") private var showZoomHint: Bool = true
    
    // Состояния для панорамирования
    @State private var isPanning: Bool = false
    @State private var lastPanLocation: CGPoint = .zero
    
    // Состояния для длительного нажатия и горизонтального перемещения
    @State private var isLongPressing: Bool = false
    @State private var longPressStartLocation: CGPoint = .zero
    @State private var isHorizontalDragging: Bool = false
    
    // Показывать ли точки на графике
    private var shouldShowPoints: Bool {
        switch selectedPeriod {
        case .sevenDays, .oneMonth, .threeMonths, .sixMonths:
            return true
        case .oneYear:
            return false  // Не показываем точки для длинного периода
        }
    }
    
    // Вычисляемые свойства для размеров линий и точек в зависимости от периода
    private var lineWidth: CGFloat {
        switch selectedPeriod {
        case .sevenDays, .oneMonth:
            return 2.0
        case .threeMonths, .sixMonths:
            return 1.5
        case .oneYear:
            return 2.0  // Увеличиваем толщину для длинного периода
        }
    }
    
    private var pointSize: CGFloat {
        switch selectedPeriod {
        case .sevenDays, .oneMonth:
            return 20.0
        case .threeMonths, .sixMonths:
            return 8.0
        case .oneYear:
            return 0.0  // Убираем точки для длинного периода
        }
    }
    


    private var headerDateFormatter: DateFormatter {
        return localizationManager.createDateFormatter(format: "d MMM yyyy HH:mm")
    }
    
    private var tooltipDateFormatter: DateFormatter {
        return localizationManager.createDateFormatter(format: "dd.MM.yyyy")
    }

    private var buttonSize: CGFloat {
        #if os(iOS)
        let screenWidth = UIScreen.main.bounds.width
        #else
        let screenWidth = 400.0
        #endif
        let availableWidth = screenWidth - horizontalPadding * 2 + (buttonSpacing * 3)
        return floor(availableWidth / 3.65) // Максимально увеличиваем размер кнопок
    }

    // Добавляем функцию для безопасного доступа к размерам экрана
    private var screenSize: CGSize {
        #if os(iOS)
        return UIScreen.main.bounds.size
        #else
        return CGSize(width: 400, height: 800)
        #endif
    }
    
    // CRITICAL PERFORMANCE: Save lastActiveIndex with throttling
    private func saveLastActiveIndex(_ index: Int) {
        // Only save if value actually changed
        if lastActiveIndex != index {
            lastActiveIndex = index
            // CRITICAL FIX: Remove asyncAfter delay to prevent CPU overload
            // Direct save to UserDefaults without delay
            UserDefaults.standard.set(index, forKey: "lastActiveIndex")
        }
    }

    var body: some View {
        GeometryReader { geometry in
            let screenSize = geometry.size
            
            // Основной контейнер
            ZStack(alignment: .top) {
                
                // Основное содержимое
                VStack(spacing: 0) {
                    // Шапка с текстурой клавиатуры
                    ZStack {
                        // Текстура для шапки
                        TextureBackgroundView(imageName: themeManager.currentTheme.backgroundTextureName)
                            .ignoresSafeArea(edges: .top)
                        
                        // Содержимое шапки
                        HeaderView(
                            lastRefresh: lastRefresh,
                            isEditMode: $isEditMode,
                            onReload: { reloadAll(base: $0) },
                            viewModel: viewModel,
                            activeIndex: activeIndex
                        )
                        .environmentObject(themeManager)
                        .environmentObject(localizationManager)
                        .padding(.top, -1) // Приподнимаем всю область на один пиксель
                    }
                    .frame(height: 38) // Уменьшаем высоту шапки с 60 до 38 пикселей
                    
                    // Черная разделительная линия
                    Rectangle()
                        .fill(Color.black)
                        .frame(height: 1)
                    
                    // Область списка валют с отдельной текстурой
                    ZStack {
                        // Текстура для списка валют
                        TextureBackgroundView(imageName: themeManager.currentTheme.currencyTextureName)
                            .ignoresSafeArea(edges: .horizontal)
                        
                        // Список валют
                        CurrencyListView(
                            viewModel: viewModel,
                            isEditMode: isEditMode,
                            activeIndex: $activeIndex,
                            lastActiveIndex: $lastActiveIndex,
                            showingPicker: $showingPicker,
                            statsBaseCode: $statsBaseCode,
                            statsCompareCode: $statsCompareCode,
                            showingStats: $showingStats,
                            showingAddCurrencyPicker: $showingAddCurrencyPicker,
                            themeManager: themeManager,
                            onReload: { reloadAll(base: $0) }
                        )
                        .environmentObject(localizationManager)
                    }
                    .frame(height: screenSize.height * 0.55)
                    
                    // Клавиатура с текстурой клавиатуры
                    ZStack {
                        // Клавиатура
                        CustomKeyboardView(
                            onTap: { key in
                                guard let idx = activeIndex, idx < viewModel.currencies.count else { return }
                                let code = viewModel.currencies[idx].code
                                
                                // FIX: Batch updates to reduce redraws
                                viewModel.setActiveField(code)
                                
                                var raw = viewModel.amounts[code]?.cleanedForCalculation() ?? ""
                                
                                if key == "," || key == "." {
                                    raw = raw.isEmpty ? "0." : (raw.contains(".") ? raw : raw + ".")
                                } else {
                                    raw += key
                                }
                                
                                viewModel.updateAmounts(changedCode: code, enteredText: raw)
                            },
                            onBackspace: {
                                guard let idx = activeIndex, idx < viewModel.currencies.count else { return }
                                let code = viewModel.currencies[idx].code
                                
                                viewModel.setActiveField(code)
                                
                                var raw = viewModel.amounts[code]?.cleanedForCalculation() ?? ""
                                if !raw.isEmpty { raw.removeLast() }
                                
                                viewModel.updateAmounts(changedCode: code, enteredText: raw)
                            },
                            onClearAll: {
                                viewModel.clearAllAmounts()
                            },
                            onHistory: {
                                guard let idx = activeIndex, idx < viewModel.currencies.count else { return }
                                
                                let compareIdx = (idx + 1) % viewModel.currencies.count
                                
                                statsBaseCode = viewModel.currencies[idx].code
                                statsCompareCode = viewModel.currencies[compareIdx].code
                                showingStats = true
                            },
                            onRefresh: {
                                if let idx = activeIndex, idx < viewModel.currencies.count {
                                    let baseCurrency = viewModel.currencies[idx].code
                                    viewModel.reloadRates(base: baseCurrency)
                                } else {
                                    viewModel.reloadRates(base: "USD")
                                }
                            }
                        )
                        .environmentObject(themeManager)
                        .environmentObject(localizationManager)
                        .environmentObject(viewModel)
                        .frame(height: screenSize.height * 0.35)
                        .padding(.top, 1)
                    }
                }
            }
        }
        // REMOVED: .id(refreshID) // Removed to prevent unnecessary updates
        .sheet(isPresented: $showingPicker) {
            CurrencyPickerView(
                selectedCode: activeIndex != nil && activeIndex! < viewModel.currencies.count ? viewModel.currencies[activeIndex!].code : viewModel.currencies.first?.code ?? "",
                allCodes: viewModel.trackedCodes
            ) { newCode in
                if let idx = activeIndex, idx < viewModel.currencies.count {
                    viewModel.replaceCode(at: idx, with: newCode)
                }
                showingPicker = false
            }
            .environmentObject(themeManager)
            .environmentObject(localizationManager) // FIX: Pass localizationManager
        }
        .sheet(isPresented: $showingAddCurrencyPicker) {
            CurrencyPickerView(
                selectedCode: "",
                allCodes: viewModel.allCurrencies.filter { currency in
                    !viewModel.visibleCurrencies.contains { $0.code == currency.code }
                }.map { $0.code }
            ) { newCode in
                if !newCode.isEmpty, let currency = viewModel.allCurrencies.first(where: { $0.code == newCode }) {
                    viewModel.addCurrencyToVisible(currency)
                    
                    if viewModel.currencies.count == 1 {
                        activeIndex = 0
                        lastActiveIndex = 0
                    }
                }
                showingAddCurrencyPicker = false
            }
            .environmentObject(themeManager)
            .environmentObject(localizationManager) // FIX: Pass localizationManager
        }
        .sheet(isPresented: $showingStats) {
            historySheet
                .environmentObject(themeManager)
                .environmentObject(localizationManager) // FIX: Pass localizationManager
                .onAppear {
                    loadHistory()
                }
        }
        .onAppear {
            // FIX: Reduce initial setup delay
            activeIndex = lastActiveIndex
            if let idx = activeIndex, idx >= viewModel.currencies.count {
                activeIndex = viewModel.currencies.isEmpty ? nil : 0
                lastActiveIndex = activeIndex ?? 0
            }
            setupInitialState()
            setupNotifications()
            if viewModel.visibleCurrencies.isEmpty {
                // Удалён вызов viewModel.loadDefaultCurrenciesIfNeeded()
                // Теперь автозаполнение валют происходит в init ViewModel
            }
        }
        .onDisappear {
            cancellables.removeAll()
        }
        .onReceive(NotificationCenter.default.publisher(for: NSNotification.Name("LanguageChanged"))) { _ in
            // REMOVED: refreshID = UUID() // Removed to prevent unnecessary updates
            viewModel.updateCurrencyNames()
        }
        .onChange(of: isEditMode) { _, newValue in
            if !newValue {
                UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
            }
        }
        .environment(\.layoutDirection, .leftToRight)
    }

    // MARK: — History Sheet Components
    private var currencySelectionPanel: some View {
        HStack(spacing: 8) {
            Button {
                showingStatsBasePicker = true
            } label: {
                HStack(spacing: 4) {
                    CurrencyFlag(currencyCode: statsBaseCode)
                        .id(statsBaseCode)
                        .frame(width: 40, height: 30)
                    Text(statsBaseCode)
                        .foregroundColor(themeManager.textColor)
                        .font(.system(size: 18, weight: .semibold))
                    Image(systemName: "chevron.down")
                        .foregroundColor(themeManager.textColor.opacity(0.7))
                        .font(.system(size: 16))
                }
            }
            .buttonStyle(BorderlessButtonStyle())
            .sheet(isPresented: $showingStatsBasePicker) {
                CurrencyPickerView(
                    selectedCode: statsBaseCode,
                    allCodes: viewModel.trackedCodes
                ) { newCode in
                    if newCode != statsCompareCode {
                        statsBaseCode = newCode
                        loadHistory()
                    }
                    showingStatsBasePicker = false
                }
                .environmentObject(themeManager)
                .environmentObject(localizationManager)
            }

            Spacer()

            Button {
                let old = statsBaseCode
                statsBaseCode = statsCompareCode
                statsCompareCode = old
                loadHistory()
            } label: {
                Image(systemName: "arrow.left.arrow.right")
                    .foregroundColor(themeManager.textColor)
                    .font(.system(size: 22))
            }
            .buttonStyle(BorderlessButtonStyle())

            Spacer()

            Button {
                showingStatsComparePicker = true
            } label: {
                HStack(spacing: 4) {
                    CurrencyFlag(currencyCode: statsCompareCode)
                        .id(statsCompareCode)
                        .frame(width: 40, height: 30)
                    Text(statsCompareCode)
                        .foregroundColor(themeManager.textColor)
                        .font(.system(size: 18, weight: .semibold))
                    Image(systemName: "chevron.down")
                        .foregroundColor(themeManager.textColor.opacity(0.7))
                        .font(.system(size: 16))
                }
            }
            .buttonStyle(BorderlessButtonStyle())
            .sheet(isPresented: $showingStatsComparePicker) {
                CurrencyPickerView(
                    selectedCode: statsCompareCode,
                    allCodes: viewModel.trackedCodes
                ) { newCode in
                    if newCode != statsBaseCode {
                        statsCompareCode = newCode
                        loadHistory()
                    }
                    showingStatsComparePicker = false
                }
                .environmentObject(themeManager)
                .environmentObject(localizationManager)
            }
        }
        .padding(.vertical, 16)
        .frame(height: 60)
        .background(themeManager.currentTheme.isDark ? Color.black.opacity(0.15) : Color.white.opacity(0.7))
        .cornerRadius(12)
    }
    
    // MARK: — History Sheet
    var historySheet: some View {
        NavigationView {
            ZStack {
                // FIX: Single background layer
                themeManager.currentTheme.backgroundColor
                    .ignoresSafeArea()
                
                // FIX: Single texture instance
                TextureBackgroundView(imageName: themeManager.currentTheme.currencyTextureName)
                    .ignoresSafeArea()
                
                ScrollView {
                    VStack(spacing: 28) {
                        // Title
                        Text(localizationManager.localizedString("currency_history"))
                            .font(.system(size: 24, weight: .bold))
                            .foregroundColor(themeManager.textColor)
                            .padding(.top, 16)
                            .padding(.bottom, 8)

                        // Currency selection panel
                        currencySelectionPanel

                        // Period picker
                        Picker("Период", selection: $selectedPeriod) {
                            ForEach(Period.allCases) { period in
                                Text(period.title).tag(period)
                            }
                        }
                        .pickerStyle(SegmentedPickerStyle())
                        .padding(.horizontal, 0)
                        .background(themeManager.buttonBG.opacity(0.2))
                        .cornerRadius(10)
                        #if swift(>=5.9) && canImport(OSLog)
                        .onChange(of: selectedPeriod) { _, newValue in 
                            loadHistory() 
                        }
                        #else
                        .onChange(of: selectedPeriod) { _ in loadHistory() }
                        #endif

                        // Подсказка о масштабировании
                        if showZoomHint {
                            HStack {
                                Image(systemName: "hand.pinch")
                                    .foregroundColor(.orange)
                                Text(localizationManager.localizedString("zoom_hint"))
                                    .font(.caption)
                                    .foregroundColor(themeManager.textColor.opacity(0.8))
                                Spacer()
                                Button("✕") {
                                    showZoomHint = false
                                }
                                .foregroundColor(themeManager.textColor.opacity(0.6))
                            }
                            .padding(.horizontal, 16)
                            .padding(.vertical, 8)
                            .background(Color.orange.opacity(0.1))
                            .cornerRadius(8)
                            .padding(.horizontal, 16)
                        }
                        
                        // Chart
                        if #available(iOS 16.0, *) {
                            ZStack {
                                RoundedRectangle(cornerRadius: 20, style: .continuous)
                                    .fill(themeManager.currentTheme.isDark ? Color.black.opacity(0.7) : Color.white.opacity(0.7))
                                chartView
                                    .padding(.vertical, 12)
                                    .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
                                    .onTapGesture(count: 2) {
                                        // Двойное нажатие для сброса масштаба
                                        withAnimation(.easeInOut(duration: 0.3)) {
                                            resetZoom()
                                        }
                                    }
                                    .simultaneousGesture(
                                        MagnificationGesture()
                                            .onChanged { value in
                                                if !isZooming {
                                                    isZooming = true
                                                }
                                                let magnificationDelta = value / lastMagnification
                                                lastMagnification = value
                                                applyFocusedZoom(magnificationDelta: magnificationDelta)
                                            }
                                            .onEnded { value in
                                                lastMagnification = 1.0
                                                isZooming = false
                                            }
                                    )
                                    .simultaneousGesture(
                                        DragGesture(minimumDistance: 10)
                                            .onChanged { value in
                                                if !isPanning {
                                                    isPanning = true
                                                    lastPanLocation = value.location
                                                }
                                                let deltaX = value.location.x - lastPanLocation.x
                                                lastPanLocation = value.location
                                                if zoomStartDate != nil || zoomEndDate != nil {
                                                    applyPanning(deltaX: deltaX)
                                                }
                                            }
                                            .onEnded { _ in
                                                isPanning = false
                                            }
                                    )
                                    .simultaneousGesture(
                                        LongPressGesture(minimumDuration: 0.5)
                                            .onChanged { pressing in
                                                if pressing && !isLongPressing {
                                                    isLongPressing = true
                                                    let impactFeedback = UIImpactFeedbackGenerator(style: .medium)
                                                    impactFeedback.prepare()
                                                    impactFeedback.impactOccurred()
                                                }
                                            }
                                            .onEnded { _ in
                                                // Long press ended
                                            }
                                    )
                                    .simultaneousGesture(
                                        DragGesture()
                                            .onChanged { value in
                                                if isLongPressing {
                                                    if !isHorizontalDragging {
                                                        isHorizontalDragging = true
                                                        longPressStartLocation = value.location
                                                    } else {
                                                        let deltaX = value.location.x - longPressStartLocation.x
                                                        longPressStartLocation = value.location
                                                        applyHorizontalDrag(deltaX: deltaX)
                                                    }
                                                }
                                            }
                                            .onEnded { _ in
                                                if isLongPressing {
                                                    isLongPressing = false
                                                    isHorizontalDragging = false
                                                    longPressStartLocation = .zero
                                                }
                                            }
                                    )
                            }
                            .frame(minWidth: 0, maxWidth: .infinity, minHeight: 350, maxHeight: 550, alignment: .bottom)
                            .shadow(color: themeManager.currentTheme.isDark ? Color.black.opacity(0.3) : Color.gray.opacity(0.1), radius: 12, x: 0, y: 4)
                        } else {
                            Text("График недоступен")
                                .foregroundColor(themeManager.textColor)
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 12)
                    .frame(maxHeight: .infinity, alignment: .bottom)
                }
                .frame(maxHeight: .infinity)
                .edgesIgnoringSafeArea(.bottom)
            }
        }
        .navigationTitle(localizationManager.localizedString("currency_history"))
        .navigationBarTitleDisplayMode(.inline)
        .navigationBarItems(trailing: Button(localizationManager.localizedString("close")) {
            showingStats = false
        })
        .background(Color.clear)
        // REMOVED: .id(refreshID) // Removed to prevent unnecessary updates
        .preferredColorScheme(themeManager.colorScheme)
        #if swift(>=5.9) && canImport(OSLog)
        .onChange(of: viewModel.history) { _, newHistory in
            if !newHistory.isEmpty {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                    setupDefaultZoom()
                }
            }
        }
        #else
        .onChange(of: viewModel.history) { newHistory in
            if !newHistory.isEmpty {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                    setupDefaultZoom()
                }
            }
        }
        #endif
    }

    func reloadAll(base: String) {
        viewModel.reloadRates(base: base)
        // CRITICAL PERFORMANCE: Only update if enough time has passed
        if Date().timeIntervalSince(lastRefresh) > 2 {
            lastRefresh = Date()
        }
    }

    func loadHistory() {
        guard !statsBaseCode.isEmpty, !statsCompareCode.isEmpty else { return }
        // Проверка на системную дату из будущего
        let calendar = Calendar.current
        let currentDate = Date()
        let currentYear = calendar.component(.year, from: currentDate)
        
        // Используем вчерашний день вместо текущей даты
        let yesterday = calendar.date(byAdding: .day, value: -1, to: calendar.startOfDay(for: currentDate)) ?? currentDate
        
        if currentYear > 2030 {
            print("⚠️ Системная дата из будущего: \(currentYear).")
            // Уведомляем пользователя о проблеме с датой
            let alertTitle = localizationManager.localizedString("error")
            let alertMessage = localizationManager.localizedString("future_date_alert")
            
            // Создаем UIAlertController для отображения предупреждения
            #if os(iOS)
            let alertController = UIAlertController(title: alertTitle, message: alertMessage, preferredStyle: .alert)
            alertController.addAction(UIAlertAction(title: localizationManager.localizedString("ok"), style: .default))
            
            // Получаем UIViewController для представления алерта
            if let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
               let rootViewController = windowScene.windows.first?.rootViewController {
                DispatchQueue.main.async {
                    rootViewController.present(alertController, animated: true)
                }
            }
            #else
            // Для не-iOS платформ (например, macOS или тестов) просто логируем ошибку
            print("⚠️ \(alertTitle): \(alertMessage)")
            #endif
        }
        
        // Безопасно получаем индексы
        guard !statsBaseCode.isEmpty, !statsCompareCode.isEmpty else {
            print("⚠️ Индексы не установлены")
            return
        }
        
        // Сбрасываем масштабирование перед загрузкой новых данных
        resetZoom()
        
        viewModel.fetchTimeSeriesHistory(
            base: statsBaseCode,
            symbol: statsCompareCode,
            start: selectedPeriod.calculateStartDate(),
            end: yesterday // Используем вчерашний день вместо сегодняшнего
        )
    }

    @available(iOS 16.0, *)
    var chartView: some View {
        VStack {
            if viewModel.isLoading {
                // Показываем индикатор загрузки
                VStack {
                    ProgressView()
                        .progressViewStyle(CircularProgressViewStyle())
                        .padding()
                    Text(localizationManager.localizedString("loading_data"))
                        .font(.subheadline)
                        .foregroundColor(themeManager.textColor)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal)
                }
            } else if viewModel.history.isEmpty {
                // Показываем пустое состояние
                VStack(spacing: 10) {
                    Image(systemName: "exclamationmark.triangle")
                        .font(.largeTitle)
                        .foregroundColor(.orange)
                    Text(localizationManager.localizedString("no_data_available"))
                        .font(.headline)
                        .multilineTextAlignment(.center)
                    
                    if let errorMsg = viewModel.errorMessage {
                        Text(errorMsg)
                            .font(.subheadline)
                            .foregroundColor(themeManager.textColor.opacity(0.7))
                            .multilineTextAlignment(.center)
                    } else {
                        Text(localizationManager.localizedString("api_unavailable"))
                            .font(.subheadline)
                            .foregroundColor(themeManager.textColor.opacity(0.7))
                            .multilineTextAlignment(.center)
                    }
                    
                    Button(localizationManager.localizedString("try_again")) {
                        loadHistory()
                    }
                    .padding(.horizontal, 20)
                    .padding(.vertical, 8)
                    .background(Color.blue)
                    .foregroundColor(.white)
                    .cornerRadius(8)
                    .padding(.top, 5)
                }
                .padding()
                .frame(height: 250)
            } else {
                // Показываем график с данными
                ChartDataView(
                    history: viewModel.history,
                    currentPoint: $currentPoint,
                    errorMessage: viewModel.errorMessage,
                    baseCurrency: statsBaseCode,
                    compareCurrency: statsCompareCode,
                    dateFormatter: tooltipDateFormatter,
                    selectedPeriod: selectedPeriod,
                    shouldShowPoints: shouldShowPoints,
                    zoomStartDate: zoomStartDate,
                    zoomEndDate: zoomEndDate,
                    zoomMinY: zoomMinY,
                    zoomMaxY: zoomMaxY
                )
            }
        }
    }

    private func setupInitialState() {
        // Устанавливаем активный индекс из сохраненного значения
        if lastActiveIndex < viewModel.currencies.count {
            activeIndex = lastActiveIndex
        } else {
            activeIndex = 0
            saveLastActiveIndex(0)
        }
        
        // Загружаем курсы валют
        if let idx = activeIndex, idx < viewModel.currencies.count {
            let baseCurrency = viewModel.currencies[idx].code
            viewModel.reloadRates(base: baseCurrency)
        }
        
        // PERFORMANCE: Preload flags for visible currencies
        let visibleCurrencies = viewModel.currencies.map { $0.code }
        FlagLoadingManager.shared.preloadFlags(for: visibleCurrencies)
        
        // CRITICAL PERFORMANCE: Initial refresh only
        lastRefresh = Date()
    }
    
    private func setupNotifications() {
        // CRITICAL PERFORMANCE: Minimize UI updates to prevent CPU overload
        // Подписываемся на уведомления о смене языка с очень сильным throttling
        NotificationCenter.default.publisher(for: NSNotification.Name("LanguageChanged"))
            .throttle(for: .seconds(3), scheduler: RunLoop.main, latest: true)
            .receive(on: DispatchQueue.main)
            .sink { _ in
                // Принудительно обновляем UI при смене языка только при необходимости
                if Date().timeIntervalSince(lastRefresh) > 3 {
                    lastRefresh = Date()
                }
            }
            .store(in: &cancellables)
        
        // CRITICAL PERFORMANCE: Remove lastUpdate subscription to reduce CPU load
        // Since lastUpdate is no longer @Published, we don't need this subscription
        // UI will be updated through other mechanisms
    }

    // --- КНОПКА ДОБАВИТЬ ВАЛЮТУ ---
    private var addCurrencyButton: some View {
        Button {
            showingAddCurrencyPicker = true
        } label: {
            HStack(spacing: 8) {
                Image(systemName: "plus.circle.fill")
                    .font(.system(size: 18))
                    .foregroundColor(.white)
                Text(localizationManager.localizedString("add_currency"))
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(.white)
            }
            .padding(.vertical, 8)
            .padding(.horizontal, 12)
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(
                        LinearGradient(
                            gradient: Gradient(colors: [
                                Color(red: 0.3, green: 0.5, blue: 0.8),
                                Color(red: 0.2, green: 0.4, blue: 0.7)
                            ]),
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 8)
                            .stroke(Color.white.opacity(0.3), lineWidth: 1)
                    )
            )
            .shadow(color: Color.black.opacity(0.3), radius: 3, x: 0, y: 2)
        }
        .frame(maxWidth: .infinity, alignment: .center)
    }
    
    // MARK: - Методы масштабирования
    
    private func applyFocusedZoom(magnificationDelta: CGFloat) {
        guard !viewModel.history.isEmpty else { return }
        
        // Если это первое масштабирование, устанавливаем начальные границы
        if zoomStartDate == nil || zoomEndDate == nil {
            let sortedData = viewModel.history.sorted { $0.date < $1.date }
            zoomStartDate = sortedData.first?.date
            zoomEndDate = sortedData.last?.date
            
            let values = viewModel.history.map { $0.rate }
            zoomMinY = values.min()
            zoomMaxY = values.max()
        }
        
        guard let startDate = zoomStartDate,
              let endDate = zoomEndDate,
              let minY = zoomMinY,
              let maxY = zoomMaxY else { return }
        
        // Определяем точку фокуса для масштабирования
        let focusDate: Date
        if let selectedPoint = currentPoint {
            // Если есть выбранная точка, используем её как центр масштабирования
            focusDate = selectedPoint.date
        } else {
            // Иначе используем центр текущего диапазона
            let centerTime = startDate.timeIntervalSince1970 + endDate.timeIntervalSince(startDate) / 2
            focusDate = Date(timeIntervalSince1970: centerTime)
        }
        
        // Вычисляем новый диапазон времени с фокусом на выбранной точке
        let currentRange = endDate.timeIntervalSince(startDate)
        let newRange = max(currentRange / Double(magnificationDelta), 3600) // Минимум 1 час
        
        let focusTime = focusDate.timeIntervalSince1970
        let focusRatio = (focusTime - startDate.timeIntervalSince1970) / currentRange
        
        let newStartTime = focusTime - newRange * focusRatio
        let newEndTime = focusTime + newRange * (1 - focusRatio)
        
        let newStartDate = Date(timeIntervalSince1970: newStartTime)
        let newEndDate = Date(timeIntervalSince1970: newEndTime)
        
        zoomStartDate = newStartDate
        zoomEndDate = newEndDate
        
        // Автоматически подстраиваем Y-диапазон под видимые данные
        updateYRangeForVisibleData(startDate: newStartDate, endDate: newEndDate)
    }
    
    private func applyPanning(deltaX: CGFloat) {
        guard let startDate = zoomStartDate,
              let endDate = zoomEndDate,
              !viewModel.history.isEmpty else { return }
        
        let sortedData = viewModel.history.sorted { $0.date < $1.date }
        guard let dataStartDate = sortedData.first?.date,
              let dataEndDate = sortedData.last?.date else { return }
        
        // Вычисляем смещение времени на основе deltaX
        let currentRange = endDate.timeIntervalSince(startDate)
        let timeShift = currentRange * Double(deltaX) / 300.0 // Чувствительность панорамирования
        
        let newStartTime = startDate.timeIntervalSince1970 - timeShift
        let newEndTime = endDate.timeIntervalSince1970 - timeShift
        
        // Ограничиваем панорамирование границами данных
        let dataStartTime = dataStartDate.timeIntervalSince1970
        let dataEndTime = dataEndDate.timeIntervalSince1970
        
        let constrainedStartTime = max(newStartTime, dataStartTime)
        let constrainedEndTime = min(newEndTime, dataEndTime)
        
        // Проверяем, что новый диапазон не выходит за границы
        if constrainedEndTime - constrainedStartTime >= currentRange * 0.5 {
            let newStartDate = Date(timeIntervalSince1970: constrainedStartTime)
            let newEndDate = Date(timeIntervalSince1970: constrainedEndTime)
            
            // Обновляем временной диапазон
            zoomStartDate = newStartDate
            zoomEndDate = newEndDate
            
            // Автоматически подстраиваем Y-диапазон под видимые данные
            updateYRangeForVisibleData(startDate: newStartDate, endDate: newEndDate)
        }
    }
    
    private func updateYRangeForVisibleData(startDate: Date, endDate: Date) {
        // Фильтруем данные в видимом временном диапазоне
        let visibleData = viewModel.history.filter { point in
            point.date >= startDate && point.date <= endDate
        }
        
        guard !visibleData.isEmpty else { return }
        
        // Находим минимальные и максимальные значения в видимом диапазоне
        let visibleValues = visibleData.map { $0.rate }
        guard let minValue = visibleValues.min(),
              let maxValue = visibleValues.max() else { return }
        
        // Добавляем небольшой отступ для лучшей визуализации
        let yRange = maxValue - minValue
        let yPadding = max(yRange * 0.1, yRange == 0 ? 0.001 : 0) // Минимальный отступ если данные одинаковые
        
        zoomMinY = minValue - yPadding
        zoomMaxY = maxValue + yPadding
    }
    
    private func applyHorizontalDrag(deltaX: CGFloat) {
        guard !viewModel.history.isEmpty else { 
            return 
        }
        
        let sortedData = viewModel.history.sorted { $0.date < $1.date }
        guard let dataStartDate = sortedData.first?.date,
              let dataEndDate = sortedData.last?.date else { 
            return 
        }
        
        // Если график не увеличен, устанавливаем умеренное увеличение
        if zoomStartDate == nil || zoomEndDate == nil {
            setupDefaultZoom()
        }
        
        guard let startDate = zoomStartDate,
              let endDate = zoomEndDate else { 
            return 
        }
        
        // Вычисляем смещение времени на основе deltaX
        let currentRange = endDate.timeIntervalSince(startDate)
        let timeShift = currentRange * Double(deltaX) / 400.0 // Чувствительность горизонтального перемещения
        
        let newStartTime = startDate.timeIntervalSince1970 - timeShift
        let newEndTime = endDate.timeIntervalSince1970 - timeShift
        
        // Ограничиваем перемещение границами данных
        let dataStartTime = dataStartDate.timeIntervalSince1970
        let dataEndTime = dataEndDate.timeIntervalSince1970
        
        let constrainedStartTime = max(newStartTime, dataStartTime)
        let constrainedEndTime = min(newEndTime, dataEndTime)
        
        // Проверяем, что новый диапазон не выходит за границы
        if constrainedEndTime - constrainedStartTime >= currentRange * 0.8 {
            let newStartDate = Date(timeIntervalSince1970: constrainedStartTime)
            let newEndDate = Date(timeIntervalSince1970: constrainedEndTime)
            
            // Обновляем временной диапазон
            zoomStartDate = newStartDate
            zoomEndDate = newEndDate
            
            // Автоматически подстраиваем Y-диапазон под видимые данные
            updateYRangeForVisibleData(startDate: newStartDate, endDate: newEndDate)
        }
    }
    
    private func setupDefaultZoom() {
        guard !viewModel.history.isEmpty else { return }
        
        let sortedData = viewModel.history.sorted { $0.date < $1.date }
        guard let firstDate = sortedData.first?.date,
              let lastDate = sortedData.last?.date else { return }
        
        let values = viewModel.history.map { $0.rate }
        guard let minValue = values.min(),
              let maxValue = values.max() else { return }
        
        // Устанавливаем умеренное увеличение по умолчанию (показываем 70% данных)
        let totalRange = lastDate.timeIntervalSince(firstDate)
        let zoomRange = totalRange * 0.7
        let centerTime = firstDate.timeIntervalSince1970 + totalRange / 2
        
        zoomStartDate = Date(timeIntervalSince1970: centerTime - zoomRange / 2)
        zoomEndDate = Date(timeIntervalSince1970: centerTime + zoomRange / 2)
        
        // Добавляем небольшой отступ по Y
        let yRange = maxValue - minValue
        let yPadding = yRange * 0.1
        zoomMinY = minValue - yPadding
        zoomMaxY = maxValue + yPadding
    }
    
    private func resetZoom() {
        zoomStartDate = nil
        zoomEndDate = nil
        zoomMinY = nil
        zoomMaxY = nil
        isZooming = false
        lastMagnification = 1.0
    }
}

// MARK: - Header View
struct HeaderView: View {
    let lastRefresh: Date
    @Binding var isEditMode: Bool
    let onReload: (String) -> Void
    let viewModel: CurrencyConverterViewModel
    let activeIndex: Int?
    
    @EnvironmentObject private var themeManager: ThemeManager
    @EnvironmentObject private var localizationManager: LocalizationManager
    
    private var dateFormatter: DateFormatter {
        return localizationManager.createDateFormatter(format: "d MMM yyyy HH:mm")
    }
    
    var body: some View {
        ZStack {
            // Содержимое заголовка - оптимизированная структура
            HStack {
                // Левая часть - кнопка редактирования
                Button {
                                                // CRITICAL PERFORMANCE: Remove withAnimation to prevent CPU overload
                            isEditMode.toggle()
                } label: {
                    Text(isEditMode ? localizationManager.localizedString("done") : localizationManager.localizedString("edit"))
                        .font(.system(size: 14, weight: .medium))
                        .foregroundColor(.white)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .background(
                            ZStack {
                                RoundedRectangle(cornerRadius: 8)
                                    .fill(themeManager.currentTheme.isDark ?
                                        LinearGradient(
                                            gradient: Gradient(colors: [
                                                Color(red: 0.3, green: 0.5, blue: 0.8),
                                                Color(red: 0.2, green: 0.4, blue: 0.7)
                                            ]),
                                            startPoint: .top,
                                            endPoint: .bottom
                                        ) :
                                        LinearGradient(
                                            gradient: Gradient(colors: [
                                                Color(red: 0.2, green: 0.4, blue: 0.7),
                                                Color(red: 0.1, green: 0.3, blue: 0.6)
                                            ]),
                                            startPoint: .top,
                                            endPoint: .bottom
                                        )
                                    )
                                
                                RoundedRectangle(cornerRadius: 8)
                                    .stroke(Color.white.opacity(0.3), lineWidth: 1)
                            }
                        )
                        .shadow(color: themeManager.currentTheme.isDark ?
                                Color.black.opacity(0.4) : Color.black.opacity(0.25),
                                radius: 2, x: 0, y: 1)
                }
                .padding(.leading, 16)
                
                Spacer()
                
                // Центральная часть - вертикальное расположение названия и даты
                VStack(spacing: 1) {
                    // Название приложения сверху
                    Text(localizationManager.localizedString("converter"))
                        .font(.system(size: 22, weight: .bold))
                        .foregroundColor(themeManager.currentTheme.textColor)
                    
                    // Дата обновления под названием
                    Text("\(localizationManager.localizedString("last_update")) \(dateFormatter.string(from: lastRefresh))")
                        .font(.system(size: 11))
                        .foregroundColor(themeManager.currentTheme.textColor.opacity(0.8))
                }
                .padding(.top, -6) // Поднимаем текст на 6 пикселей вверх
                .padding(.bottom, 8) // Компенсируем отступ снизу
                
                Spacer()
                
                // Пустое пространство справа для симметрии
                Color.clear
                    .frame(width: 60)
                    .padding(.trailing, 16)
            }
            .padding(.top, 4)
        }
        .frame(height: 38) // Уменьшаем высоту для компактности
        .background(Color.clear) // Делаем фон прозрачным
    }
}

// MARK: - Chart Supporting Views
@available(iOS 16.0, *)
struct ChartLoadingView: View {
    let errorMessage: String?
    let textColor: Color
    
    var body: some View {
        VStack {
            ProgressView()
                .progressViewStyle(CircularProgressViewStyle())
                .padding()
            Text(errorMessage ?? "Загрузка данных...")
                .font(.subheadline)
                .foregroundColor(textColor)
                .multilineTextAlignment(.center)
                .padding(.horizontal)
        }
    }
}

@available(iOS 16.0, *)
struct ChartEmptyView: View {
    let errorMessage: String?
    let textColor: Color
    let onReload: () -> Void
    
    @EnvironmentObject private var localizationManager: LocalizationManager
    
    var body: some View {
        VStack(spacing: 10) {
            Image(systemName: "exclamationmark.triangle")
                .font(.largeTitle)
                .foregroundColor(.orange)
            Text(localizationManager.localizedString("no_data_available"))
                .font(.headline)
                .multilineTextAlignment(.center)
            if let errorMsg = errorMessage {
                Text(errorMsg)
                    .font(.subheadline)
                    .foregroundColor(textColor.opacity(0.7))
                    .multilineTextAlignment(.center)
            } else {
                Text(localizationManager.localizedString("api_unavailable"))
                    .font(.subheadline)
                    .foregroundColor(textColor.opacity(0.7))
                    .multilineTextAlignment(.center)
            }
            Button(action: onReload) {
                Text(localizationManager.localizedString("try_again"))
                    .padding(.horizontal, 20)
                    .padding(.vertical, 8)
                    .background(Color.blue)
                    .foregroundColor(.white)
                    .cornerRadius(8)
            }
            .padding(.top, 5)
        }
        .padding()
        .frame(height: 250)
    }
}

@available(iOS 16.0, *)
struct ChartDataView: View {
    let history: [CurrencyConverterViewModel.HistoryPoint]
    @Binding var currentPoint: CurrencyConverterViewModel.HistoryPoint?
    let errorMessage: String?
    let baseCurrency: String?
    let compareCurrency: String?
    let dateFormatter: DateFormatter
    let selectedPeriod: Period
    let shouldShowPoints: Bool
    let zoomStartDate: Date?
    let zoomEndDate: Date?
    let zoomMinY: Double?
    let zoomMaxY: Double?
    
    var body: some View {
        ZStack(alignment: .top) {
            ZStack(alignment: .bottom) {
                ChartContentView(
                    history: history,
                    currentPoint: $currentPoint,
                    baseCurrency: baseCurrency,
                    compareCurrency: compareCurrency,
                    dateFormatter: dateFormatter,
                    selectedPeriod: selectedPeriod,
                    shouldShowPoints: shouldShowPoints,
                    zoomStartDate: zoomStartDate,
                    zoomEndDate: zoomEndDate,
                    zoomMinY: zoomMinY,
                    zoomMaxY: zoomMaxY
                )
                .frame(maxWidth: .infinity, minHeight: 520, maxHeight: 700)
                .background(Color.black)
            }
            // Верхняя и нижняя полоски
            VStack {
                Rectangle()
                    .fill(Color.white.opacity(0.3))
                    .frame(height: 1.5)
                    .padding(.horizontal, 8)
                    .cornerRadius(0.75)
                Spacer()
                Rectangle()
                    .fill(Color.white.opacity(0.3))
                    .frame(height: 1.5)
                    .padding(.horizontal, 8)
                    .cornerRadius(0.75)
                    .padding(.bottom, 10)
            }
        }
    }
}

@available(iOS 16.0, *)
struct ChartContentView: View {
    let history: [CurrencyConverterViewModel.HistoryPoint]
    @Binding var currentPoint: CurrencyConverterViewModel.HistoryPoint?
    let baseCurrency: String?
    let compareCurrency: String?
    let dateFormatter: DateFormatter
    let selectedPeriod: Period
    let shouldShowPoints: Bool
    let zoomStartDate: Date?
    let zoomEndDate: Date?
    let zoomMinY: Double?
    let zoomMaxY: Double?
    
    @EnvironmentObject private var localizationManager: LocalizationManager
    
    // FIX: Add localized date formatter for axis labels
    private var axisDateFormatter: DateFormatter {
        return localizationManager.createDateFormatter(format: "d MMM")
    }
    
    // Вычисляемые свойства для размеров линий и точек в зависимости от периода
    private var lineWidth: CGFloat {
        switch selectedPeriod {
        case .sevenDays, .oneMonth:
            return 2.0
        case .threeMonths, .sixMonths:
            return 1.5
        case .oneYear:
            return 2.0  // Увеличиваем толщину для длинного периода
        }
    }
    
    private var pointSize: CGFloat {
        switch selectedPeriod {
        case .sevenDays, .oneMonth:
            return 20.0
        case .threeMonths, .sixMonths:
            return 8.0
        case .oneYear:
            return 0.0  // Убираем точки для длинного периода
        }
    }
    

    
    var body: some View {
        if history.isEmpty {
                                Text(localizationManager.localizedString("no_data"))
                .foregroundColor(.gray)
                .frame(height: 300)
        } else {
            // Используем параметры масштабирования или значения по умолчанию
            let minY = zoomMinY ?? (history.map(\.rate).min() ?? 0)
            let maxY = zoomMaxY ?? (history.map(\.rate).max() ?? 1)
            let startDate = zoomStartDate ?? (history.min(by: { $0.date < $1.date })?.date ?? Date())
            let endDate = zoomEndDate ?? (history.max(by: { $0.date < $1.date })?.date ?? Date())
            
            // Уменьшаем отступы для более компактного отображения
            let yPadding = max((maxY - minY) * 0.05, 0.005)
            ZStack(alignment: .top) {
                Chart {
                    ForEach(history) { point in
                        // Создаем линейный график как на втором скриншоте
                        LineMark(
                            x: .value("Дата", point.date),
                            y: .value("Курс", point.rate)
                        )
                        .foregroundStyle(Color.orange)
                        .lineStyle(StrokeStyle(lineWidth: lineWidth))
                        .interpolationMethod(.catmullRom)
                        
                        // Добавляем точки на линии только для коротких периодов
                        if shouldShowPoints {
                            PointMark(
                                x: .value("Дата", point.date),
                                y: .value("Курс", point.rate)
                            )
                            .foregroundStyle(Color.orange)
                            .symbolSize(pointSize)
                        }
                    }
                }
                .chartLegend(.hidden)
                .chartYScale(domain: (minY - yPadding)...(maxY + yPadding))
                .chartXScale(domain: startDate...endDate)
                .chartBackground { _ in
                    Color.black
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .clipped()
                .chartXAxis {
                    AxisMarks(position: .bottom, values: .automatic(desiredCount: 4)) { value in
                        AxisGridLine(stroke: StrokeStyle(lineWidth: 0.3))
                            .foregroundStyle(Color.gray.opacity(0.2))
                        AxisTick(stroke: StrokeStyle(lineWidth: 0.3))
                            .foregroundStyle(Color.white)
                        AxisValueLabel {
                            // FIX: Use localized date formatter for axis labels
                            if let date = value.as(Date.self) {
                                Text(axisDateFormatter.string(from: date))
                                    .foregroundStyle(Color.white)
                                    .font(.system(size: 10))
                            }
                        }
                    }
                }
                .chartYAxis {
                    AxisMarks(position: .leading, values: .automatic(desiredCount: 4)) { value in
                        AxisGridLine(stroke: StrokeStyle(lineWidth: 0.3))
                            .foregroundStyle(Color.gray.opacity(0.2))
                        AxisTick(stroke: StrokeStyle(lineWidth: 0.3))
                            .foregroundStyle(Color.white)
                        AxisValueLabel()
                            .foregroundStyle(Color.white)
                            .font(.system(size: 10))
                    }
                }
                .chartOverlay { proxy in
                    GeometryReader { geo in
                        ZStack {
                            Rectangle()
                                .fill(Color.clear)
                                .contentShape(Rectangle())
                                .gesture(
                                    DragGesture(minimumDistance: 0)
                                        .onChanged { value in
                                            #if swift(>=5.9)
                                            let plotFrameAnchorOpt = proxy.plotFrame
                                            #else
                                            let plotFrameAnchorOpt = proxy.plotAreaFrame
                                            #endif
                                            if let plotFrameAnchor = plotFrameAnchorOpt {
                                                let frame = geo[plotFrameAnchor]
                                                let xPos = value.location.x - frame.origin.x
                                                guard let date = proxy.value(atX: xPos, as: Date.self) else { return }
                                                if !history.isEmpty {
                                                    let nearestPoint = history.min { pointA, pointB in
                                                        let distA = abs(pointA.date.timeIntervalSince(date))
                                                        let distB = abs(pointB.date.timeIntervalSince(date))
                                                        return distA < distB
                                                    }
                                                    currentPoint = nearestPoint
                                                }
                                            }
                                        }
                                        .onEnded { _ in 
                                            // Убираем сброс currentPoint при отпускании пальца
                                            // currentPoint = nil 
                                        }
                                )
                            // Вертикальная линия
                            if let current = currentPoint {
                                // Получаем X-координату для выбранной даты
                                #if swift(>=5.9)
                                let plotFrameAnchorOpt = proxy.plotFrame
                                #else
                                let plotFrameAnchorOpt = proxy.plotAreaFrame
                                #endif
                                if let plotFrameAnchor = plotFrameAnchorOpt {
                                    let frame = geo[plotFrameAnchor]
                                    if let xPosition = proxy.position(forX: current.date) {
                                        let lineX = frame.origin.x + xPosition
                                        Rectangle()
                                            .fill(Color.white.opacity(0.3))
                                            .frame(width: 2, height: frame.height)
                                            .position(x: lineX, y: frame.midY)
                                        // Точка пересечения с графиком
                                        if let yPosition = proxy.position(forY: current.rate) {
                                            let pointY = frame.origin.y + yPosition
                                            
                                            // Отображаем точку
                                            Circle()
                                                .strokeBorder(Color.orange, lineWidth: 3)
                                                .background(Circle().fill(Color.white))
                                                .frame(width: 16, height: 16)
                                                .position(x: lineX, y: pointY)
                                            
                                            // Добавляем информационное окно как отдельное представление
                                            InfoTooltipView(
                                                current: current,
                                                firstRate: history.first?.rate,
                                                dateFormatter: dateFormatter,
                                                pointPosition: (x: lineX, y: pointY),
                                                frameWidth: frame.width
                                            )
                                        }
                                    }
                                }
                            }
                        }
                    }
                }
                // Надписи "Мин" и "Макс" в верхних углах
                HStack {
                    if let min = history.map(\ .rate).min() {
                        Text(String(format: localizationManager.localizedString("min"), String(format: "%.2f", min)))
                            .foregroundColor(.white)
                            .font(.subheadline)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(Color.black.opacity(0.7))
                            .cornerRadius(6)
                            .padding(.leading, 8)
                            .padding(.top, 8)
                    }
                    Spacer()
                    if let max = history.map(\ .rate).max() {
                        Text(String(format: localizationManager.localizedString("max"), String(format: "%.2f", max)))
                            .foregroundColor(.white)
                            .font(.subheadline)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(Color.black.opacity(0.7))
                            .cornerRadius(6)
                            .padding(.trailing, 8)
                            .padding(.top, 8)
                    }
                }
                .zIndex(1)
            }
        }
    }
}

// Отдельное представление для информационного окна
@available(iOS 16.0, *)
struct InfoTooltipView: View {
    let current: CurrencyConverterViewModel.HistoryPoint
    let firstRate: Double?
    let dateFormatter: DateFormatter
    let pointPosition: (x: CGFloat, y: CGFloat)
    let frameWidth: CGFloat
    
    var body: some View {
        Group {
            if let firstRate = firstRate {
                let delta = current.rate - firstRate
                
                // Определяем оптимальное положение информационного окна
                let infoBoxHeight: CGFloat = 80
                let infoBoxWidth: CGFloat = 100
                let lineX = pointPosition.x
                let pointY = pointPosition.y
                
                // Проверяем близость к верхнему краю
                let isNearTop = pointY < infoBoxHeight + 20
                let isNearLeft = lineX < infoBoxWidth/2 + 20
                let isNearRight = lineX > frameWidth - infoBoxWidth/2 - 20
                
                // Рассчитываем смещение для позиционирования
                let offsetY: CGFloat = isNearTop ? 60 : -60
                let offsetX: CGFloat = isNearLeft ? 50 : (isNearRight ? -50 : 0)
                
                VStack(alignment: .center, spacing: 2) {
                    Text(String(format: "%.4f", current.rate))
                        .font(.headline)
                        .bold()
                        .foregroundColor(.white)
                    Text(dateFormatter.string(from: current.date))
                        .font(.caption)
                        .foregroundColor(.gray)
                    Text(String(format: "%@%.4f", delta >= 0 ? "+" : "", delta))
                        .font(.caption)
                        .foregroundColor(delta >= 0 ? .green : .red)
                }
                .padding(6)
                .background(Color.black.opacity(0.8))
                .cornerRadius(8)
                .shadow(color: .black.opacity(0.5), radius: 4, x: 0, y: 2)
                .position(x: lineX + offsetX, y: pointY + offsetY)
            }
        }
    }
}

// Добавить вспомогательную структуру для скругления только верхних углов
struct RoundedCorner: Shape {
    var radius: CGFloat = .infinity
    var corners: UIRectCorner = .allCorners
    func path(in rect: CGRect) -> Path {
        let path = UIBezierPath(roundedRect: rect, byRoundingCorners: corners, cornerRadii: CGSize(width: radius, height: radius))
        return Path(path.cgPath)
    }
}

// MARK: - Drag and Drop Delegate
struct DropViewDelegate: DropDelegate {
    let item: Int
    @Binding var items: [Currency]
    @Binding var draggedItem: Int?
    var onMoveCompleted: ((Int, Int) -> Void)?
    
    func dropUpdated(info: DropInfo) -> DropProposal? {
        return DropProposal(operation: .move)
    }
    
    func performDrop(info: DropInfo) -> Bool {
        if let draggedItem = self.draggedItem {
            let fromIndex = draggedItem
            let toIndex = item
            
            if fromIndex != toIndex {
                // CRITICAL PERFORMANCE: Remove withAnimation to prevent CPU overload
                let item = items.remove(at: fromIndex)
                items.insert(item, at: toIndex)
                
                // Вызываем обработчик, если он задан
                onMoveCompleted?(fromIndex, toIndex)
            }
            
            // Сбрасываем перетаскиваемый элемент
            self.draggedItem = nil
            return true
        }
        
        return false
    }
}

// MARK: - Optimized Currency List View
struct CurrencyListView: View {
    let viewModel: CurrencyConverterViewModel
    let isEditMode: Bool
    @Binding var activeIndex: Int?
    @Binding var lastActiveIndex: Int
    @Binding var showingPicker: Bool
    @Binding var statsBaseCode: String
    @Binding var statsCompareCode: String
    @Binding var showingStats: Bool
    @Binding var showingAddCurrencyPicker: Bool
    let themeManager: ThemeManager
    let onReload: (String) -> Void
    
    @EnvironmentObject private var localizationManager: LocalizationManager
    @StateObject private var flagManager = FlagLoadingManager.shared
    @State private var draggedItem: Int?
    @State private var globalDragOffset = CGSize.zero
    @State private var isDraggingGlobal = false
    
    // CRITICAL PERFORMANCE: Limit visible items to prevent CPU overload
    private let visibleItemsLimit = 10
    
    var body: some View {
        ScrollView {
            LazyVStack(spacing: 0) {
                // Edit mode hint
                if isEditMode {
                    editModeHint
                        .padding(.top, 8)
                        .padding(.bottom, 12)
                        .transition(.opacity.combined(with: .move(edge: .top)))
                }
                
                // Currency rows - CRITICAL: Only render limited items to reduce CPU
                ForEach(Array(viewModel.currencies.prefix(visibleItemsLimit).enumerated()), id: \.1.code) { index, currency in
                    CurrencyRowWrapper(
                        currency: currency,
                        index: index,
                        isEditMode: isEditMode,
                        activeIndex: $activeIndex,
                        lastActiveIndex: $lastActiveIndex,
                        viewModel: viewModel,
                        showingPicker: $showingPicker,
                        statsBaseCode: $statsBaseCode,
                        statsCompareCode: $statsCompareCode,
                        showingStats: $showingStats,
                        themeManager: themeManager,
                        onReload: onReload,
                        draggedItem: $draggedItem,
                        globalDragOffset: $globalDragOffset,
                        isDraggingGlobal: $isDraggingGlobal,
                        visibleItemsLimit: visibleItemsLimit,
                        preloadNearbyFlags: preloadNearbyFlags
                    )
                }
                
                // Add currency button
                addCurrencyButton
                    .padding(.top, 16)
                    .padding(.horizontal, 70)
                // Bottom spacing для видимости кнопки и последней валюты
                Color.clear.frame(height: 60)
            }
            .padding(.horizontal, 16)
        }
        .scrollContentBackground(.hidden)
        .background(Color.clear)
        .refreshable {
            if let firstCurrency = viewModel.currencies.first {
                onReload(firstCurrency.code)
            }
        }
        .onAppear {
            // Preload flags for all visible currencies
            let codes = viewModel.currencies.map { $0.code }
            flagManager.preloadFlags(for: codes)
        }
    }
    
    private var editModeHint: some View {
        HStack {
            Spacer()
            Text(localizationManager.localizedString("edit_mode_hint"))
                .font(.system(size: 13))
                .foregroundColor(themeManager.textColor.opacity(0.7))
                .padding(.vertical, 8)
                .padding(.horizontal, 16)
                .background(
                    RoundedRectangle(cornerRadius: 8)
                        .fill(Color.black.opacity(0.1))
                )
            Spacer()
        }
    }
    
    private func preloadNearbyFlags(currentIndex: Int) {
        let startIndex = max(0, currentIndex - 2)
        let endIndex = min(viewModel.currencies.count - 1, currentIndex + 5)
        
        let nearbyFlags = Array(viewModel.currencies[startIndex...endIndex]).map { $0.code }
        flagManager.preloadFlags(for: nearbyFlags)
    }
    
    private var addCurrencyButton: some View {
        Button {
            showingAddCurrencyPicker = true
        } label: {
            HStack(spacing: 8) {
                Image(systemName: "plus.circle.fill")
                    .font(.system(size: 18))
                    .foregroundColor(.white)
                Text(localizationManager.localizedString("add_currency"))
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(.white)
            }
            .padding(.vertical, 8)
            .padding(.horizontal, 12)
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(
                        LinearGradient(
                            gradient: Gradient(colors: [
                                Color(red: 0.3, green: 0.5, blue: 0.8),
                                Color(red: 0.2, green: 0.4, blue: 0.7)
                            ]),
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 8)
                            .stroke(Color.white.opacity(0.3), lineWidth: 1)
                    )
            )
            .shadow(color: Color.black.opacity(0.3), radius: 3, x: 0, y: 2)
        }
        .frame(maxWidth: .infinity, alignment: .center)
    }
}

// MARK: - Currency Row Wrapper
struct CurrencyRowWrapper: View {
    let currency: Currency
    let index: Int
    let isEditMode: Bool
    @Binding var activeIndex: Int?
    @Binding var lastActiveIndex: Int
    let viewModel: CurrencyConverterViewModel
    @Binding var showingPicker: Bool
    @Binding var statsBaseCode: String
    @Binding var statsCompareCode: String
    @Binding var showingStats: Bool
    let themeManager: ThemeManager
    let onReload: (String) -> Void
    @Binding var draggedItem: Int?
    @Binding var globalDragOffset: CGSize
    @Binding var isDraggingGlobal: Bool
    let visibleItemsLimit: Int
    let preloadNearbyFlags: (Int) -> Void
    
    @State private var dragOffset = CGSize.zero
    @State private var isDragging = false
    @State private var dropTargetIndex: Int? = nil
    
    var body: some View {
        baseCurrencyRow
            .background(dragBackgroundColor)
            .overlay(dropIndicator, alignment: .top)
            .scaleEffect(isDragging && draggedItem == index ? 1.02 : 1.0)
            .shadow(color: isDragging && draggedItem == index ? Color.black.opacity(0.2) : Color.clear, radius: isDragging && draggedItem == index ? 4 : 0, x: 0, y: isDragging && draggedItem == index ? 2 : 0)
            .animation(.smooth(duration: 0.25), value: isDragging)
            .animation(.smooth(duration: 0.25), value: draggedItem)
            .onChange(of: isDraggingGlobal) { _, newValue in
                if !newValue {
                    withAnimation(.smooth(duration: 0.2)) {
                        dragOffset = .zero
                    }
                }
            }
    }
    
    private var baseCurrencyRow: some View {
        OptimizedCurrencyRowView(
            currency: currency,
            index: index,
            isEditMode: isEditMode,
            activeIndex: $activeIndex,
            lastActiveIndex: $lastActiveIndex,
            viewModel: viewModel,
            showingPicker: $showingPicker,
            statsBaseCode: $statsBaseCode,
            statsCompareCode: $statsCompareCode,
            showingStats: $showingStats,
            themeManager: themeManager,
            onReload: onReload,
            draggedItem: $draggedItem,
            isDragging: $isDragging,
            globalDragOffset: $globalDragOffset,
            isDraggingGlobal: $isDraggingGlobal,
            visibleItemsLimit: visibleItemsLimit
        )
        .background(
            activeIndex == index ? 
            Color.black.opacity(0.15) : 
            Color.clear
        )
        .offset(y: isDragging && draggedItem == index ? dragOffset.height : 0)
        .onAppear {
            preloadNearbyFlags(index)
        }
    }
    
    private var dragBackgroundColor: Color {
        if isDragging && draggedItem == index {
            return Color.blue.opacity(0.2)
        }
        return Color.clear
    }
    
    private var dropIndicator: some View {
        Group {
            if let draggedIndex = draggedItem, draggedIndex != index {
                let rowHeight: CGFloat = 80
                let targetOffset = Int(round(globalDragOffset.height / rowHeight))
                let targetIndex = max(0, min(viewModel.currencies.count - 1, draggedIndex + targetOffset))
                
                if targetIndex == index {
                    Rectangle()
                        .fill(Color.blue)
                        .frame(height: 3)
                        .animation(.easeInOut(duration: 0.2), value: targetIndex)
                }
            }
        }
    }
}



// MARK: - View Extension
extension View {
    @ViewBuilder
    func conditionalModifier<T: ViewModifier>(_ condition: Bool, modifier: (Self) -> ModifiedContent<Self, T>) -> some View {
        if condition {
            modifier(self)
        } else {
            self
        }
    }
}

// MARK: - Optimized Currency Row View
struct OptimizedCurrencyRowView: View {
    let currency: Currency
    let index: Int
    let isEditMode: Bool
    @Binding var activeIndex: Int?
    @Binding var lastActiveIndex: Int
    let viewModel: CurrencyConverterViewModel
    @Binding var showingPicker: Bool
    @Binding var statsBaseCode: String
    @Binding var statsCompareCode: String
    @Binding var showingStats: Bool
    let themeManager: ThemeManager
    let onReload: (String) -> Void
    @Binding var draggedItem: Int?
    @Binding var isDragging: Bool
    @Binding var globalDragOffset: CGSize
    @Binding var isDraggingGlobal: Bool
    let visibleItemsLimit: Int
    
    @State private var cachedDisplayText: String = ""
    @State private var isActive: Bool = false
    @State private var dragOffset: CGSize = .zero
    
    var body: some View {
        HStack {
            // Delete button in edit mode
            if isEditMode {
                deleteButton
            }
            
            // Currency picker button
            currencyPickerButton
                .frame(width: 100, alignment: .leading)
            
            Spacer()
            
            // Amount text field
            optimizedTextField
                .frame(maxWidth: .infinity)
                .frame(minWidth: 120)
            
            Spacer()
            
            // Chart button
            chartButton
                .padding(.trailing, isEditMode ? 8 : 8)
            
            // Drag handle in edit mode
            if isEditMode {
                dragHandle
                    .padding(.trailing, 8)
            }
        }
        .padding(.vertical, 4)
        .padding(.horizontal)
        .background(
            isActive ? Color(red: 43/255, green: 51/255, blue: 53/255).opacity(0.8) : 
            (isDraggingGlobal && draggedItem == index ? Color.blue.opacity(0.15) : Color.clear)
        )
        .overlay(alignment: .top) {
            dropIndicator
        }
        .offset(y: calculateRowOffset())
        .scaleEffect(draggedItem == index ? 1.02 : 1.0)
        .shadow(color: draggedItem == index ? Color.black.opacity(0.15) : Color.clear, radius: draggedItem == index ? 3 : 0, x: 0, y: draggedItem == index ? 1 : 0)
        .zIndex(draggedItem == index ? 1000 : 0)
        .animation(.smooth(duration: 0.3), value: calculateRowOffset())
        .animation(.smooth(duration: 0.25), value: draggedItem == index)
        .onAppear {
            updateCachedText()
            isActive = activeIndex == index
        }
        .onChange(of: activeIndex) { newValue in
            isActive = newValue == index
            if isActive && newValue != index {
                viewModel.setActiveField(nil)
            }
        }
        .onChange(of: viewModel.amounts[currency.code]) { _, _ in
            updateCachedText()
        }
    }
    
    private var deleteButton: some View {
        Button {
            // CRITICAL PERFORMANCE: Remove withAnimation to prevent CPU overload
            viewModel.removeCurrencyFromVisible(currency.code)
            updateActiveIndex()
        } label: {
            ZStack {
                Circle()
                    .fill(Color.red)
                    .frame(width: 24, height: 24)
                Image(systemName: "minus")
                    .font(.system(size: 16, weight: .bold))
                    .foregroundColor(.white)
            }
        }
        .buttonStyle(PlainButtonStyle())
        .padding(.leading, 4)
        .padding(.trailing, 8)
        .transition(.scale.combined(with: .opacity))
    }
    
    private var currencyPickerButton: some View {
        Button {
            activeIndex = index
            lastActiveIndex = index
            showingPicker = true
        } label: {
            HStack(spacing: 4) {
                CurrencyFlag(currencyCode: currency.code)
                    .id(currency.code)
                    .frame(width: 32, height: 24)
                Text(currency.code)
                    .foregroundColor(themeManager.textColor)
                    .font(.system(size: 16, weight: .medium))
                Image(systemName: "chevron.down")
                    .foregroundColor(themeManager.textColor.opacity(0.7))
                    .font(.system(size: 14))
            }
        }
        .buttonStyle(BorderlessButtonStyle())
        .padding(.leading, isEditMode ? 4 : 0)
    }
    
    private var optimizedTextField: some View {
        CustomTextField(
            text: Binding(
                get: { cachedDisplayText },
                set: { newValue in
                    let cleaned = newValue.cleanedForCalculation()
                    viewModel.updateAmounts(changedCode: currency.code, enteredText: cleaned)
                }
            ),
            placeholder: "0",
            isFirstResponder: isActive,
            backgroundColor: isActive
                ? Color(red: 100/255, green: 180/255, blue: 240/255)
                : Color(red: 150/255, green: 200/255, blue: 230/255),
            textColor: themeManager.textColor
        ) {
            activeIndex = index
            lastActiveIndex = index
            viewModel.setActiveField(currency.code)
        }
        .cornerRadius(8)
        .frame(height: 46)
    }
    
    private var chartButton: some View {
        Button {
            statsBaseCode = "USD"
            statsCompareCode = currency.code
            showingStats = true
        } label: {
            Image(systemName: "chart.line.uptrend.xyaxis")
                .foregroundColor(themeManager.textColor)
        }
        .buttonStyle(PlainButtonStyle())
    }
    
    private var dragHandle: some View {
        Image(systemName: "line.3.horizontal")
            .foregroundColor(themeManager.textColor.opacity(isDragging ? 1.0 : 0.6))
            .font(.system(size: 18, weight: .medium))
            .frame(width: 24, height: 24)
            .scaleEffect(isDragging ? 1.1 : 1.0)
            .gesture(
                DragGesture(minimumDistance: 5, coordinateSpace: .global)
                    .onChanged { value in
                        if !isDragging {
                            withAnimation(.interactiveSpring(response: 0.3, dampingFraction: 0.7)) {
                                isDragging = true
                                draggedItem = index
                            }
                            #if os(iOS)
                            let impactFeedback = UIImpactFeedbackGenerator(style: .medium)
                            impactFeedback.impactOccurred()
                            #endif
                        }
                        
                        // Обновляем dragOffset для всех строк через родительский компонент
                        updateDragOffset(value.translation)
                        globalDragOffset = value.translation
                        isDraggingGlobal = true
                    }
                    .onEnded { value in
                        withAnimation(.smooth(duration: 0.4)) {
                            handleDragEnd(translation: value.translation.height)
                        }
                    }
            )
    }
    
    private func handleDragEnd(translation: CGFloat) {
        let rowHeight: CGFloat = 70
        let threshold: CGFloat = rowHeight / 2
        
        // Плавный возврат в исходное положение
        withAnimation(.smooth(duration: 0.3)) {
            updateDragOffset(.zero)
            globalDragOffset = .zero
            isDragging = false
            isDraggingGlobal = false
            draggedItem = nil
        }
        
        if abs(translation) > threshold {
            let targetOffset = Int(round(translation / rowHeight))
            let maxIndex = viewModel.currencies.count - 1
            let targetIndex = max(0, min(maxIndex, index + targetOffset))
            
            if targetIndex != index && targetIndex >= 0 && targetIndex < viewModel.currencies.count {
                // Тактильная обратная связь при успешном перемещении
                #if os(iOS)
                let successFeedback = UINotificationFeedbackGenerator()
                successFeedback.notificationOccurred(.success)
                #endif
                
                DispatchQueue.main.async {
                    viewModel.moveCurrency(from: index, to: targetIndex)
                }
            } else {
                // Тактильная обратная связь при неудачном перемещении
                #if os(iOS)
                let errorFeedback = UINotificationFeedbackGenerator()
                errorFeedback.notificationOccurred(.error)
                #endif
            }
        } else {
            // Тактильная обратная связь при отмене
            #if os(iOS)
            let errorFeedback = UINotificationFeedbackGenerator()
            errorFeedback.notificationOccurred(.error)
            #endif
        }
    }
    
    private func updateDragOffset(_ translation: CGSize) {
        dragOffset = translation
    }
    
    // Простое вычисление смещения для каждой строки при перетаскивании
    private func calculateRowOffset() -> CGFloat {
        guard let draggedIndex = draggedItem, isDraggingGlobal else {
            return 0
        }
        
        // Если это перетаскиваемая строка, используем dragOffset
        if index == draggedIndex {
            return dragOffset.height
        }
        
        let rowHeight: CGFloat = 70
        let translation = globalDragOffset.height
        
        // Простое вытеснение только ближайших элементов
        if abs(translation) > rowHeight / 3 {
            let targetIndex = draggedIndex + Int(round(translation / rowHeight))
            
            if draggedIndex < targetIndex && index > draggedIndex && index <= targetIndex {
                return -rowHeight // Сдвигаем вверх
            } else if draggedIndex > targetIndex && index < draggedIndex && index >= targetIndex {
                return rowHeight // Сдвигаем вниз
            }
        }
        
        return 0
    }
    
    // Вычисляемое свойство для определения целевой позиции
    private var dropTargetIndex: Int? {
        guard isDraggingGlobal, let draggedIndex = draggedItem else { return nil }
        
        let translation = globalDragOffset.height
        let rowHeight: CGFloat = 70 // Высота строки с отступами
        let targetOffset = Int(round(translation / rowHeight))
        let targetIndex = draggedIndex + targetOffset
        
        return max(0, min(targetIndex, viewModel.currencies.count - 1))
    }
    
    // Индикатор места вставки
    private var dropIndicator: some View {
        EmptyView()
    }
    

    
    private func updateCachedText() {
        let rawText = viewModel.amounts[currency.code] ?? ""
        cachedDisplayText = rawText.formattedWithThousandsSeparator()
    }
    
    private func updateActiveIndex() {
        if activeIndex == index {
            activeIndex = viewModel.currencies.isEmpty ? nil : 0
            lastActiveIndex = activeIndex ?? 0
        } else if let activeIdx = activeIndex, activeIdx > index {
            activeIndex = activeIdx - 1
            lastActiveIndex = activeIndex ?? 0
        }
    }
}
