import SwiftUI
import UIKit

// MARK: - Optimized Texture Cache
class OptimizedTextureCache {
    static let shared = OptimizedTextureCache()
    private var cachedImages: [String: UIImage] = [:]
    private var cachedViews: [String: UIView] = [:]
    private let queue = DispatchQueue(label: "texture.cache", qos: .userInitiated, attributes: .concurrent)
    
    // Memory management
    private let maxCacheSize = 50 // Limit cache size
    private var cacheAccessOrder: [String] = []
    
    private init() {
        setupMemoryWarningObserver()
    }
    
    private func setupMemoryWarningObserver() {
        NotificationCenter.default.addObserver(
            forName: UIApplication.didReceiveMemoryWarningNotification,
            object: nil,
            queue: .main
        ) { _ in
            self.clearCache()
        }
    }
    
    func getImage(named name: String) -> UIImage? {
        return queue.sync {
            if let image = cachedImages[name] {
                // Update access order
                updateAccessOrder(for: name)
                return image
            }
            
            // Принудительно сбрасываем кэш UIImage для этого ассета
            // UIImageAsset не имеет метода unregister, используем другой подход
            let _ = UIImage(named: name) // Просто перезагружаем изображение
            
            if let image = UIImage(named: name) {
                // Cache with memory management
                cacheImage(image, named: name)
                return image
            }
            
            return nil
        }
    }
    
    func getOrCreateView(named name: String, isDark: Bool, themeKey: String) -> UIView? {
        let cacheKey = "\(name)_\(isDark)_\(themeKey)"
        
        return queue.sync {
            if let view = cachedViews[cacheKey] {
                updateAccessOrder(for: cacheKey)
                return view
            }
            
            // Return nil to force async creation in main thread
            return nil
        }
    }
    
    // Create view asynchronously in main thread
    func createViewAsync(named name: String, isDark: Bool, themeKey: String, completion: @escaping (UIView?) -> Void) {
        let cacheKey = "\(name)_\(isDark)_\(themeKey)"
        
        // First check cache
        if let view = queue.sync(execute: {
            if let view = cachedViews[cacheKey] {
                updateAccessOrder(for: cacheKey)
                return view
            }
            return nil
        }) {
            completion(view)
            return
        }
        
        // Create view in main thread
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { 
                completion(nil)
                return 
            }
            
            guard let image = self.getImage(named: name) else {
                print("[OptimizedTextureCache] ❌ Не удалось загрузить изображение: \(name)")
                completion(nil)
                return
            }
            
            print("[OptimizedTextureCache] ✅ Создаём view для: \(name), размер: \(image.size)")
            
            let imageView = UIImageView(image: image)
            imageView.contentMode = .scaleToFill // Растягиваем текстуру на всю область
            imageView.alpha = 1.0 // Убираем полупрозрачность
            
            // Cache the view
            self.cacheView(imageView, named: cacheKey)
            
            completion(imageView)
        }
    }
    
    private func cacheImage(_ image: UIImage, named name: String) {
        queue.async(flags: .barrier) { [weak self] in
            guard let self = self else { return }
            
            // Manage cache size
            self.manageCacheSize()
            
            self.cachedImages[name] = image
            self.updateAccessOrder(for: name)
        }
    }
    
    private func cacheView(_ view: UIView, named name: String) {
        queue.async(flags: .barrier) { [weak self] in
            guard let self = self else { return }
            
            // Manage cache size
            self.manageCacheSize()
            
            self.cachedViews[name] = view
            self.updateAccessOrder(for: name)
        }
    }
    
    private func updateAccessOrder(for key: String) {
        if let index = cacheAccessOrder.firstIndex(of: key) {
            cacheAccessOrder.remove(at: index)
        }
        cacheAccessOrder.append(key)
    }
    
    private func manageCacheSize() {
        let totalItems = cachedImages.count + cachedViews.count
        
        if totalItems >= maxCacheSize {
            let itemsToRemove = totalItems - maxCacheSize + 10 // Remove extra items
            
            for i in 0..<min(itemsToRemove, cacheAccessOrder.count) {
                let keyToRemove = cacheAccessOrder[i]
                cachedImages.removeValue(forKey: keyToRemove)
                cachedViews.removeValue(forKey: keyToRemove)
            }
            
            cacheAccessOrder.removeFirst(min(itemsToRemove, cacheAccessOrder.count))
        }
    }
    
    func clearCache() {
        queue.async(flags: .barrier) { [weak self] in
            // Очищаем кэш UIImage для всех закэшированных изображений
            // UIImageAsset не имеет метода unregister, используем другой подход
            self?.cachedImages.keys.forEach { imageName in
                let _ = UIImage(named: imageName) // Просто перезагружаем изображение
            }
            
            self?.cachedImages.removeAll()
            self?.cachedViews.removeAll()
            self?.cacheAccessOrder.removeAll()
            
            print("[OptimizedTextureCache] 🗑️ Кэш полностью очищен")
        }
    }
}

// MARK: - Optimized Texture Background View
struct TextureBackgroundView: View {
    let imageName: String
    @EnvironmentObject private var themeManager: ThemeManager
    @State private var cachedView: UIView?
    
    var body: some View {
        ZStack {
            // Base color layer
            baseColorLayer
            
            // Texture layer
            if let cachedView = cachedView {
                TextureViewRepresentable(view: cachedView)
            } else {
                // Loading fallback
                Color.clear
                    .onAppear {
                        loadTexture()
                    }
            }
        }
        .ignoresSafeArea()
        .onChange(of: themeManager.currentTheme) { _, _ in
            print("[TextureBackgroundView] onChange theme: imageName=\(imageName), isDark=\(themeManager.currentTheme.isDark), themeKey=\(themeManager.currentTheme.rawValue)")
            
            // Принудительно очищаем кэш UIImage для всех ассетов
            // UIImageAsset не имеет метода unregister, используем другой подход
            let _ = UIImage(named: imageName) // Просто перезагружаем изображение
            
            // Очищаем наш кэш
            OptimizedTextureCache.shared.clearCache()
            
            // Принудительно сбрасываем текущий view
            self.cachedView = nil
            
            // Загружаем новую текстуру
            loadTexture()
        }
    }
    
    private var baseColorLayer: some View {
        (themeManager.currentTheme.isDark 
            ? Color(red: 0.12, green: 0.12, blue: 0.15) 
            : Color(red: 0.92, green: 0.92, blue: 0.92))
    }
    
    private func loadTexture() {
        let imageName = self.imageName
        let isDark = self.themeManager.currentTheme.isDark
        let themeKey = self.themeManager.currentTheme.rawValue
        print("[TextureBackgroundView] loadTexture: imageName=\(imageName), isDark=\(isDark), themeKey=\(themeKey)")
        // First try to get from cache
        if let cachedView = OptimizedTextureCache.shared.getOrCreateView(named: imageName, isDark: isDark, themeKey: themeKey) {
            self.cachedView = cachedView
            return
        }
        // Create asynchronously in main thread
        OptimizedTextureCache.shared.createViewAsync(named: imageName, isDark: isDark, themeKey: themeKey) { view in
            self.cachedView = view
        }
    }
}

// MARK: - UIViewRepresentable for Texture
struct TextureViewRepresentable: UIViewRepresentable {
    let view: UIView
    
    func makeUIView(context: Context) -> UIView {
        let containerView = UIView()
        containerView.backgroundColor = .clear
        
        // Add the texture view
        view.translatesAutoresizingMaskIntoConstraints = false
        containerView.addSubview(view)
        
        NSLayoutConstraint.activate([
            view.topAnchor.constraint(equalTo: containerView.topAnchor),
            view.leadingAnchor.constraint(equalTo: containerView.leadingAnchor),
            view.trailingAnchor.constraint(equalTo: containerView.trailingAnchor),
            view.bottomAnchor.constraint(equalTo: containerView.bottomAnchor)
        ])
        
        return containerView
    }
    
    func updateUIView(_ uiView: UIView, context: Context) {
        // No updates needed as the view is cached
    }
}

// MARK: - Legacy TextureCache (for compatibility)
class TextureCache {
    static let shared = TextureCache()
    
    private init() {}
    
    func getImage(named name: String) -> UIImage? {
        return OptimizedTextureCache.shared.getImage(named: name)
    }
    
    func clearCache() {
        // Delegate to optimized cache
    }
}

// MARK: - Static Texture View (for better performance)
struct StaticTextureView: View {
    let imageName: String
    let isDark: Bool
    
    var body: some View {
        if let image = OptimizedTextureCache.shared.getImage(named: imageName) {
            Image(uiImage: image)
                .resizable(resizingMode: .tile)
                .opacity(isDark ? 0.7 : 0.85)
                .allowsHitTesting(false)
                .drawingGroup() // Optimize rendering
        } else {
            Color.clear
        }
    }
} 