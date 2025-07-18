import SwiftUI
import UIKit
import Combine

// MARK: - Optimized Flag Loading Manager
class FlagLoadingManager: ObservableObject {
    static let shared = FlagLoadingManager()
    
    // Enhanced cache with size limits and memory management
    private let imageCache = NSCache<NSString, UIImage>()
    private let diskCache = URLCache(memoryCapacity: 10 * 1024 * 1024, diskCapacity: 50 * 1024 * 1024, diskPath: "flag_cache")
    
    // Loading queue to limit concurrent downloads
    private let loadingQueue = DispatchQueue(label: "flag.loading", qos: .userInitiated)
    private let semaphore = DispatchSemaphore(value: 3) // Max 3 concurrent downloads
    private var loadingTasks: [String: URLSessionDataTask] = [:]
    
    // Preloading for visible currencies
    private var preloadedCurrencies: Set<String> = []
    
    private init() {
        setupCache()
        URLSession.shared.configuration.urlCache = diskCache
    }
    
    private func setupCache() {
        imageCache.countLimit = 100 // Max 100 images in memory
        imageCache.totalCostLimit = 20 * 1024 * 1024 // 20MB memory limit
        
        // Clear cache on memory warning
        NotificationCenter.default.addObserver(
            forName: UIApplication.didReceiveMemoryWarningNotification,
            object: nil,
            queue: .main
        ) { _ in
            self.imageCache.removeAllObjects()
        }
    }
    
    func preloadFlags(for currencies: [String]) {
        let newCurrencies = Set(currencies).subtracting(preloadedCurrencies)
        
        for currency in newCurrencies {
            _ = loadFlag(for: currency, priority: .low)
        }
        
        preloadedCurrencies.formUnion(newCurrencies)
    }
    
    func loadFlag(for currencyCode: String, priority: TaskPriority = .medium, retryCount: Int = 0) -> AnyPublisher<UIImage?, Never> {
        let key = currencyCode
        if let cached = imageCache.object(forKey: key as NSString) {
            return Just(cached).eraseToAnyPublisher()
        }
        let country = (CurrencyFlag.map[currencyCode] ?? currencyCode).lowercased()
        // Пробуем сначала Flags/xxx.png, потом просто xxx.png
        if let image = UIImage(named: "Flags/" + country) {
            imageCache.setObject(image, forKey: key as NSString)
            return Just(image).eraseToAnyPublisher()
        } else if let image = UIImage(named: country) {
            imageCache.setObject(image, forKey: key as NSString)
            return Just(image).eraseToAnyPublisher()
        } else if let image = UIImage(named: "Flags/" + currencyCode.lowercased()) {
            imageCache.setObject(image, forKey: key as NSString)
            return Just(image).eraseToAnyPublisher()
        } else if let image = UIImage(named: currencyCode.lowercased()) {
            imageCache.setObject(image, forKey: key as NSString)
            return Just(image).eraseToAnyPublisher()
        } else {
            // Флаг не найден — возвращаем nil, будет fallback-иконка
            return Just(nil).eraseToAnyPublisher()
        }
    }
}

// MARK: - Optimized Currency Flag View
struct CurrencyFlag: View {
    let currencyCode: String
    @StateObject private var flagLoader = FlagLoadingManager.shared
    @State private var uiImage: UIImage?
    @State private var isLoading = false
    @State private var cancellables = Set<AnyCancellable>()
    
    // Static methods remain the same
    static func isDeprecatedCurrency(_ code: String) -> Bool {
        let deprecatedCurrencies = [
            "DEM", "FRF", "IEP", "PTE", "LTL", "LVL", "EEK", "ESP", "GRD", "ATS", "BEF", "CYP", "FIM", "ITL", "LUF", "SKK", "SIT",
            "ROL", "SRG", "VEB", "VEF", "MGF", "ZMK", "GHC", "BYR", "MRO", "STD", "SLL", "ZWD", "ZWG",
            "AZM", "TMM", "MZM", "CSD", "YUM", "YUD", "YUN", "ZWL", "ZWN", "ZWR", "VEF", "BYR", "LTT", "LVR", "EEK", "MRO", "GHC", "TPE",
            "AFA", "AOR", "ARL", "ARM", "ARP", "ATS", "BEF", "BGL", "BOP", "BRB", "BRC", "BRE", "BRN", "BRR", "BUK", "CSK", "CYP", "DDM",
            "DEM", "ECS", "ESA", "ESB", "ESP", "FIM", "FRF", "GHC", "GRD", "GWP", "IEP", "ILP", "ITL", "LUF", "MGF", "MLF", "MTL", "MTP",
            "NLG", "PEI", "PES", "PLZ", "PTE", "RUR", "SDD", "SDP", "SIT", "SKK", "SUR", "UAK", "UGS", "UYP", "UYN", "XEU", "XFO", "XFU",
            "YUD", "YUM", "YUN", "ZAL", "ZMK", "ZRN", "ZRZ", "ZWC", "ZWD", "ZWN", "ZWR",
            "TRL", "CUC", "HT", "GT"
        ]
        return deprecatedCurrencies.contains(code)
    }
    
    static let map: [String: String] = [
        // Americas
        "USD":"us", "CAD":"ca", "MXN":"mx", "BSD":"bs", "BMD":"bm",
        "BRL":"br", "ARS":"ar", "CLP":"cl", "COP":"co", "VES":"ve",
        "PEN":"pe", "UYU":"uy", "PYG":"py", "BOB":"bo", "CRC":"cr",
        "JMD":"jm", "TTD":"tt", "BBD":"bb", "BZD":"bz", "DOP":"do",
        "HTG":"ht", "GTQ":"gt", "HNL":"hn", "NIO":"ni", "PAB":"pa",
        "SRD":"sr", "AWG":"aw", "ANG":"cw", "GYD":"gy", "MXV":"mx",
        "CUP":"cu", "KYD":"ky", // Кубинское песо и доллар островов Кайман
        
        // Europe
        "EUR":"eu", "GBP":"gb", "CHF":"ch", "SEK":"se", "NOK":"no",
        "DKK":"dk", "CZK":"cz", "PLN":"pl", "RON":"ro", "HUF":"hu",
        "BGN":"bg", "HRK":"hr", "RSD":"rs", "BYN":"by", "MDL":"md",
        "ISK":"is", "MKD":"mk", "ALL":"al", "BAM":"ba", "GIP":"gi",
        "JEP":"je", "IMP":"im", "FOK":"fo", "GGP":"gg", "FKP":"fk",
        "TRY":"tr", // Турецкая лира
        
        // CIS & Eastern Europe
        "RUB":"ru", "UAH":"ua", "KZT":"kz", "AZN":"az", "AMD":"am",
        "GEL":"ge", "TJS":"tj", "KGS":"kg", "UZS":"uz", "TMT":"tm",
        "KUD":"kw", // Кувейтский динар (код KUD)
        
        // Asia
        "JPY":"jp", "CNY":"cn", "KRW":"kr", "INR":"in", "IDR":"id",
        "PHP":"ph", "SGD":"sg", "THB":"th", "MYR":"my", "VND":"vn",
        "HKD":"hk", "TWD":"tw", "PKR":"pk", "BDT":"bd", "LKR":"lk",
        "NPR":"np", "MMK":"mm", "LAK":"la", "KHR":"kh", "BND":"bn",
        "MNT":"mn", "MVR":"mv", "BTN":"bt", "MOP":"mo",
        "KPW":"kp", "AFN":"af",
        
        // Oceania
        "AUD":"au", "NZD":"nz", "FJD":"fj", "PGK":"pg", "SBD":"sb",
        "TOP":"to", "VUV":"vu", "WST":"ws",
        "TVD":"tv", // Доллар Тувалу
        
        // Africa
        "ZAR":"za", "EGP":"eg", "NGN":"ng", "KES":"ke", "TZS":"tz",
        "UGX":"ug", "GHS":"gh", "MAD":"ma", "DZD":"dz", "TND":"tn",
        "XOF":"sn", "XAF":"cm", "ZMW":"zm", "RWF":"rw", "ETB":"et",
        "GMD":"gm", "GNF":"gn", "MGA":"mg", "MWK":"mw", "MUR":"mu",
        "NAD":"na", "SCR":"sc", "SLL":"sl", "SZL":"sz", "LSL":"ls",
        "CVE":"cv", "CDF":"cd", "KMF":"km", "LRD":"lr", "LYD":"ly",
        "SDG":"sd", "STN":"st", "MRU":"mr", "MZN":"mz",
        "AOA":"ao", "BIF":"bi", "BWP":"bw", "DJF":"dj",
        "ERN":"er", "SOS":"so",
        "SLE":"sl", // Леоне Сьерра-Леоне
        
        // Middle East & Others
        "AED":"ae", "SAR":"sa", "QAR":"qa", "OMR":"om", "KWD":"kw",
        "BHD":"bh", "IQD":"iq", "ILS":"il", "JOD":"jo", "LBP":"lb",
        "SYP":"sy", "YER":"ye", "IRR":"ir",
        
        // Custom mappings for non-standard currency codes

        "CNH": "cn", // Offshore Chinese Yuan
        "STD": "st", // São Tomé & Príncipe Dobra (old code)
        "SVC": "sv", // Salvadoran Colón
        "XCD": "ag", // East Caribbean Dollar (Antigua & Barbuda)
        "XPF": "pf", // CFP Franc (French Polynesia)
        
        // Криптовалюты используют уникальные иконки вместо флагов
        // (их коды удалены из этой карты)
    ]

    var body: some View {
        Group {
            if isLoading {
                ProgressView()
                    .frame(width: 32, height: 24)
            } else if let uiImage = uiImage {
                flagImage(uiImage)
            } else if currencyCode == "TRY" {
                // После 3 неудачных попыток — специальный значок
                Image(systemName: "flag.slash.fill")
                    .resizable()
                    .frame(width: 32, height: 24)
                    .foregroundColor(.gray)
            } else {
                fallbackIcon
            }
        }
        .onAppear {
            if uiImage == nil && !isLoading {
                loadImageAsync()
            }
        }
        .id(currencyCode)
    }
    
    private var fallbackIcon: some View {
        Group {
            switch currencyCode {
            case "KYD":
                iconCircle(color: .blue, text: "KY")
            case "TVD":
                iconCircle(color: .cyan, text: "TV$", fontSize: 9)
            case "SLE":
                iconCircle(color: .green, text: "Le")
            case "CUP":
                iconCircle(color: .red, text: "₱", fontSize: 14)
            case _ where Self.isDeprecatedCurrency(currencyCode):
                deprecatedIcon
            default:
                defaultIcon
            }
        }
    }
    
    private func iconCircle(color: Color, text: String, fontSize: CGFloat = 10) -> some View {
        ZStack {
            Circle()
                .fill(color.opacity(0.8))
                .frame(width: 32, height: 24)
            Text(text)
                .font(.system(size: fontSize, weight: .bold))
                .foregroundColor(.white)
        }
    }
    
    private var deprecatedIcon: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 6)
                .fill(Color.gray.opacity(0.3))
                .frame(width: 32, height: 24)
            Text(currencyCode.prefix(2))
                .font(.system(size: 10, weight: .bold))
                .foregroundColor(.gray)
        }
    }
    
    private var defaultIcon: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 6)
                .fill(Color.gray.opacity(0.2))
                .frame(width: 32, height: 24)
                .overlay(
                    RoundedRectangle(cornerRadius: 6)
                        .stroke(Color.gray.opacity(0.3), lineWidth: 1)
                )
            Text(currencyCode.prefix(3))
                .font(.system(size: 10, weight: .bold))
                .foregroundColor(.gray)
        }
    }
    
    private func flagImage(_ image: UIImage) -> some View {
        Image(uiImage: image)
            .resizable()
            .aspectRatio(contentMode: .fit)
            .frame(width: 32, height: 24)
            .clipShape(RoundedRectangle(cornerRadius: 4))
            .overlay(
                RoundedRectangle(cornerRadius: 4)
                    .stroke(Color.gray.opacity(0.2), lineWidth: 0.5)
            )
    }
    
    private func loadImageAsync() {
        isLoading = true
        flagLoader.loadFlag(for: currencyCode)
            .receive(on: DispatchQueue.main)
            .sink { image in
                self.uiImage = image // всегда обновлять @State
                self.isLoading = false
            }
            .store(in: &cancellables)
    }
}
