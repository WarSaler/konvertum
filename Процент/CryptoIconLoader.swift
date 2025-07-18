import SwiftUI
import Combine
import UIKit

/// Загружает и кэширует иконки криптовалют
class CryptoIconLoader: ObservableObject {
    @Published var image: UIImage? = nil
    private var cancellable: AnyCancellable?
    private static let cache = NSCache<NSString, UIImage>()
    
    // URL API для загрузки иконок криптовалют
    private static let baseURL = "https://cryptoicons.org/api"
    
    private let currencyCode: String
    private let size: Int
    private let style: String
    
    init(currencyCode: String, size: Int = 60, style: String = "color") {
        self.currencyCode = currencyCode.lowercased()
        self.size = size
        self.style = style
    }
    
    private var cacheKey: NSString {
        return "\(style)_\(currencyCode)_\(size)" as NSString
    }
    
    func load() {
        // Проверяем кэш сначала
        if let cachedImage = Self.cache.object(forKey: cacheKey) {
            self.image = cachedImage
            return
        }
        
        // Формируем URL запроса
        guard let url = URL(string: "\(Self.baseURL)/\(style)/\(currencyCode)/\(size)") else {
            return
        }
        
        let request = URLRequest(url: url, cachePolicy: .returnCacheDataElseLoad, timeoutInterval: 60)
        
        // Иначе загружаем из сети
        cancellable = URLSession.shared.dataTaskPublisher(for: request)
            .map { data, response -> UIImage? in
                if let http = response as? HTTPURLResponse,
                   200...299 ~= http.statusCode,
                   let image = UIImage(data: data) {
                    // Сохраняем в кэш
                    Self.cache.setObject(image, forKey: self.cacheKey)
                    return image
                }
                return nil
            }
            .replaceError(with: nil)
            .receive(on: DispatchQueue.main)
            .assign(to: \.image, on: self)
    }
    
    // Альтернативный метод получения иконок из разных источников
    // Можно попробовать несколько API, если основной не работает
    static func fallbackLoad(currencyCode: String, completion: @escaping (UIImage?) -> Void) {
        // Список API для получения иконок криптовалют
        let apis = [
            "https://cryptoicons.org/api/color/\(currencyCode.lowercased())/60",
            "https://raw.githubusercontent.com/ErikThiart/cryptocurrency-icons/master/16/\(currencyCode.lowercased()).png",
            "https://s2.coinmarketcap.com/static/img/coins/64x64/\(currencyCode.lowercased()).png"
        ]
        
        // Пробуем загрузить из первого API
        guard let url = URL(string: apis[0]) else {
            completion(nil)
            return
        }
        
        URLSession.shared.dataTask(with: url) { data, response, error in
            if let data = data, let image = UIImage(data: data) {
                DispatchQueue.main.async {
                    completion(image)
                }
            } else {
                // Если первый API не работает, пробуем следующий
                guard let url = URL(string: apis[1]) else {
                    completion(nil)
                    return
                }
                
                URLSession.shared.dataTask(with: url) { data, response, error in
                    if let data = data, let image = UIImage(data: data) {
                        DispatchQueue.main.async {
                            completion(image)
                        }
                    } else {
                        // Если второй API не работает, пробуем последний
                        guard let url = URL(string: apis[2]) else {
                            completion(nil)
                            return
                        }
                        
                        URLSession.shared.dataTask(with: url) { data, response, error in
                            if let data = data, let image = UIImage(data: data) {
                                DispatchQueue.main.async {
                                    completion(image)
                                }
                            } else {
                                DispatchQueue.main.async {
                                    completion(nil)
                                }
                            }
                        }.resume()
                    }
                }.resume()
            }
        }.resume()
    }
}

/// SwiftUI View для отображения иконки криптовалюты
struct CryptoIconView: View {
    let currencyCode: String
    let size: CGFloat
    
    @StateObject private var loader: CryptoIconLoader
    @State private var fallbackImage: UIImage? = nil
    
    init(currencyCode: String, size: CGFloat = 32) {
        self.currencyCode = currencyCode
        self.size = size
        _loader = StateObject(wrappedValue: CryptoIconLoader(currencyCode: currencyCode, size: Int(size), style: "color"))
    }
    
    var body: some View {
        Group {
            if let image = loader.image {
                Image(uiImage: image)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(width: size, height: size)
            } else if let fallbackImage = fallbackImage {
                Image(uiImage: fallbackImage)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(width: size, height: size)
            } else {
                Circle()
                    .fill(Color.gray.opacity(0.3))
                    .frame(width: size, height: size)
                    .overlay(
                        Text(currencyCode.prefix(1))
                            .font(.system(size: size * 0.5, weight: .bold))
                            .foregroundColor(.white)
                    )
            }
        }
        .onAppear {
            loader.load()
            
            // Если основной загрузчик не сработает, пробуем запасной вариант
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                if loader.image == nil {
                    CryptoIconLoader.fallbackLoad(currencyCode: currencyCode) { image in
                        self.fallbackImage = image
                    }
                }
            }
        }
    }
} 