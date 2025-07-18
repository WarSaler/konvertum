import Foundation
import Combine

// Модель для исторических данных
struct HistoricalDataPoint {
    let date: Date
    let rate: Double
    var change: Double
    var changePercent: Double
}

class CurrencyService {
    static let shared = CurrencyService()
    private let fawazService = FawazCurrencyService.shared

    func fetchLatestRates(base: String, symbols: [String]? = nil) -> AnyPublisher<[String: Double], Never> {
        return fawazService.fetchLatestRates(base: base, symbols: symbols)
    }

    func fetchRealHistoryUSD(for currency: String, days: Int) -> AnyPublisher<[HistoricalDataPoint], Never> {
        return fawazService.fetchHistoricalData(from: "USD", to: currency, days: days)
            .catch { _ in
                return self.generateDemoHistoricalData(from: "USD", to: currency, days: days)
            }
            .eraseToAnyPublisher()
    }

    func fetchHistoryRange(from: String, to: String, start: Date, end: Date) -> AnyPublisher<[HistoricalDataPoint], Never> {
        let calendar = Calendar.current
        let days = calendar.dateComponents([.day], from: start, to: end).day ?? 7
        return fawazService.fetchHistoricalData(from: from, to: to, days: days)
            .catch { _ in
                return self.generateDemoHistoricalData(from: from, to: to, days: days)
            }
            .eraseToAnyPublisher()
    }
    
    func fetchHistoricalData(from: String, to: String, days: Int) -> AnyPublisher<[HistoricalDataPoint], Never> {
        return fawazService.fetchHistoricalData(from: from, to: to, days: days)
            .catch { _ in
                return self.generateDemoHistoricalData(from: from, to: to, days: days)
            }
            .eraseToAnyPublisher()
    }
    
    // MARK: - Генерация демонстрационных данных как fallback
    
    // Этот метод теперь делегируется в FawazCurrencyService
    private func generateDemoHistoricalData(from: String, to: String, days: Int) -> AnyPublisher<[HistoricalDataPoint], Never> {
        return fawazService.generateDemoHistoricalData(from: from, to: to, days: days)
    }
    
    // Метод для очистки кэша исторических данных
    func clearHistoricalDataCache() {
        fawazService.clearHistoricalDataCache()
    }

    // Метод для получения текущего курса из кэша
    func getCurrentRate(from: String, to: String) -> Double? {
        return fawazService.getCurrentRate(from: from, to: to)
    }
}
