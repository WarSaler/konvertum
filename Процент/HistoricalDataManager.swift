import Foundation
import os.log

/// Менеджер для работы с предзагруженными и динамическими историческими данными
class HistoricalDataManager {
    static let shared = HistoricalDataManager()
    private let logger = Logger(subsystem: "com.Procent.Procent", category: "HistoricalDataManager")
    
    // Дата окончания предзагруженных данных (15 июля 2025)
    private let preloadedDataEndDate = Calendar.current.date(from: DateComponents(year: 2025, month: 7, day: 15))!
    
    // Кэш для предзагруженных данных
    private var preloadedData: [String: [String: Double]] = [:]
    private var isPreloadedDataLoaded = false
    private let currencyService = FawazCurrencyService.shared
    private let dateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        return formatter
    }()
    
    private init() {
        loadPreloadedData()
    }
    
    /// Загружает предзагруженные данные из JSON файла
    private func loadPreloadedData() {
        guard let path = Bundle.main.path(forResource: "preloaded_historical_data", ofType: "json"),
              let data = NSData(contentsOfFile: path) else {
            print("⚠️ Не удалось найти файл preloaded_historical_data.json")
            return
        }
        
        do {
            if let json = try JSONSerialization.jsonObject(with: data as Data, options: []) as? [String: [String: Double]] {
                preloadedData = json
                print("✅ Предзагруженные данные загружены: \(preloadedData.keys.count) дат, \(preloadedData.values.first?.keys.count ?? 0) валют")
            }
        } catch {
            print("❌ Ошибка парсинга предзагруженных данных: \(error)")
        }
    }
    
    /// Получает исторические данные для указанного периода
    /// - Parameters:
    ///   - fromCurrency: Базовая валюта
    ///   - toCurrency: Целевая валюта
    ///   - startDate: Начальная дата
    ///   - endDate: Конечная дата
    ///   - completion: Callback с результатом
    func getHistoricalData(
        fromCurrency: String,
        toCurrency: String,
        startDate: Date,
        endDate: Date,
        completion: @escaping (Result<[(Date, Double)], Error>) -> Void
    ) {
        let calendar = Calendar.current
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyy-MM-dd"
        
        var result: [(Date, Double)] = []
        var missingDates: [Date] = []
        
        // Генерируем список всех дат в диапазоне
        var currentDate = startDate
        while currentDate <= endDate {
            let dateString = dateFormatter.string(from: currentDate)
            
            // Проверяем, есть ли данные в предзагруженном кэше
            if currentDate <= preloadedDataEndDate,
               let dayData = preloadedData[dateString],
               let rate = calculateRate(from: fromCurrency, to: toCurrency, dayData: dayData) {
                result.append((currentDate, rate))
                logger.debug("Использованы предзагруженные данные для \(dateString): \(fromCurrency)/\(toCurrency) = \(rate)")
            } else {
                // Данные отсутствуют, нужно загрузить через API
                missingDates.append(currentDate)
            }
            
            currentDate = calendar.date(byAdding: .day, value: 1, to: currentDate) ?? currentDate
        }
        
        print("📊 Найдено в предзагруженных данных: \(result.count) дат")
        print("🔄 Нужно загрузить через API: \(missingDates.count) дат")
        
        // Если все данные есть в кэше, возвращаем результат
        if missingDates.isEmpty {
            logger.info("Все данные найдены в предзагруженном кэше для \(fromCurrency)/\(toCurrency)")
            completion(.success(result.sorted { $0.0 < $1.0 }))
            return
        }
        
        // Загружаем недостающие данные через API
        logger.info("Загружаем \(missingDates.count) недостающих дат через API для \(fromCurrency)/\(toCurrency)")
        print("📊 Период: \(dateFormatter.string(from: startDate)) - \(dateFormatter.string(from: endDate))")
        print("📊 Предзагружено: \(result.count) точек, загружаем через API: \(missingDates.count) точек")
        
        loadMissingDataFromAPI(
            fromCurrency: fromCurrency,
            toCurrency: toCurrency,
            missingDates: missingDates
        ) { [weak self] apiResult in
            switch apiResult {
            case .success(let apiData):
                result.append(contentsOf: apiData)
                completion(.success(result.sorted { $0.0 < $1.0 }))
            case .failure(let error):
                self?.logger.error("Ошибка загрузки данных через API: \(error.localizedDescription)")
                // Возвращаем хотя бы предзагруженные данные
                if !result.isEmpty {
                    completion(.success(result.sorted { $0.0 < $1.0 }))
                } else {
                    completion(.failure(error))
                }
            }
        }
    }
    
    /// Вычисляет курс между двумя валютами на основе данных за день
    private func calculateRate(from: String, to: String, dayData: [String: Double]) -> Double? {
        // Если это одна и та же валюта
        if from == to {
            return 1.0
        }
        
        // Если базовая валюта USD
        if from == "USD" {
            return dayData[to]
        }
        
        // Если целевая валюта USD
        if to == "USD" {
            if let fromRate = dayData[from] {
                return 1.0 / fromRate
            }
        }
        
        // Кросс-курс через USD
        if let fromRate = dayData[from], let toRate = dayData[to] {
            return toRate / fromRate
        }
        
        return nil
    }
    
    /// Загружает недостающие данные через API
    private func loadMissingDataFromAPI(
        fromCurrency: String,
        toCurrency: String,
        missingDates: [Date],
        completion: @escaping (Result<[(Date, Double)], Error>) -> Void
    ) {
        guard !missingDates.isEmpty else {
            completion(.success([]))
            return
        }
        
        print("🔄 Загружаем \(missingDates.count) дат через API для пары \(fromCurrency)/\(toCurrency)")
        
        Task {
            var allResults: [(Date, Double)] = []
            var hasError = false
            
            // Создаем объекты Currency для API
            let fromCurrencyObj = Currency(code: fromCurrency, name: fromCurrency, flagName: fromCurrency.lowercased(), rate: 1.0)
            let toCurrencyObj = Currency(code: toCurrency, name: toCurrency, flagName: toCurrency.lowercased(), rate: 1.0)
            
            for date in missingDates {
                do {
                    if let result = try await self.currencyService.fetchRateForDateAsync(from: fromCurrencyObj, to: toCurrencyObj, date: date) {
                        allResults.append(result)
                        let dateString = self.dateFormatter.string(from: date)
                        print("✅ Загружен курс для \(dateString): \(result.1)")
                    } else {
                        let dateString = self.dateFormatter.string(from: date)
                        print("❌ Не удалось загрузить курс для \(dateString)")
                        hasError = true
                    }
                } catch {
                    let dateString = self.dateFormatter.string(from: date)
                    print("❌ Ошибка при загрузке курса для \(dateString): \(error.localizedDescription)")
                    hasError = true
                }
            }
            
            DispatchQueue.main.async {
                print("🎉 API загрузка завершена: \(allResults.count) курсов")
                if hasError && allResults.isEmpty {
                    completion(.failure(NSError(domain: "HistoricalDataManager", code: 1, userInfo: [NSLocalizedDescriptionKey: "Не удалось загрузить данные через API"])))
                } else {
                    completion(.success(allResults))
                }
            }
        }
    }
    
    /// Группирует последовательные даты в диапазоны
    private func groupConsecutiveDates(_ dates: [Date]) -> [(start: Date, end: Date)] {
        guard !dates.isEmpty else { return [] }
        
        let sortedDates = dates.sorted()
        var ranges: [(start: Date, end: Date)] = []
        var currentStart = sortedDates[0]
        var currentEnd = sortedDates[0]
        
        for i in 1..<sortedDates.count {
            let date = sortedDates[i]
            let daysBetween = Calendar.current.dateComponents([.day], from: currentEnd, to: date).day!
            
            if daysBetween == 1 {
                // Последовательная дата
                currentEnd = date
            } else {
                // Разрыв в последовательности
                ranges.append((start: currentStart, end: currentEnd))
                currentStart = date
                currentEnd = date
            }
        }
        
        ranges.append((start: currentStart, end: currentEnd))
        return ranges
    }
}

// MARK: - Расширение для интеграции с существующим кодом
extension HistoricalDataManager {
    /// Метод для совместимости с существующим FawazCurrencyService
    func fetchHistoricalDataCompatible(
        fromCurrency: String,
        toCurrency: String,
        days: Int,
        endDate: Date = Date(),
        completion: @escaping (Result<[(Date, Double)], Error>) -> Void
    ) {
        let calendar = Calendar.current
        let startDate = calendar.date(byAdding: .day, value: -days + 1, to: endDate) ?? endDate
        
        getHistoricalData(
            fromCurrency: fromCurrency,
            toCurrency: toCurrency,
            startDate: startDate,
            endDate: endDate,
            completion: completion
        )
    }
}