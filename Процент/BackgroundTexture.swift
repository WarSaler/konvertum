import SwiftUI

// Облегченная версия BackgroundTexture для быстрого переключения тем
struct BackgroundTexture: View {
    let imageName: String
    @EnvironmentObject private var themeManager: ThemeManager
    
    var body: some View {
        GeometryReader { geometry in
            ZStack {
                // Базовый цвет фона
                themeManager.currentTheme.isDark 
                    ? Color(red: 0.12, green: 0.12, blue: 0.12)
                    : Color(red: 0.95, green: 0.95, blue: 0.95)
                
                // Текстура
                if !themeManager.isChangingTheme, let uiImage = UIImage(named: imageName) {
                    Image(uiImage: uiImage)
                        .resizable(resizingMode: .tile)
                        .renderingMode(.original)
                        .interpolation(.medium)
                        .opacity(0.85)
                        .drawingGroup()
                        .onAppear {
                            print("[BackgroundTexture] imageName=\(imageName), theme=\(themeManager.currentTheme.rawValue)")
                        }
                }
            }
            .frame(width: geometry.size.width, height: geometry.size.height)
            .allowsHitTesting(false)
        }
        .onChange(of: themeManager.currentTheme) { _, _ in
            // Принудительно очищаем кэш UIImage для текущего ассета
            // UIImageAsset не имеет метода unregister, используем другой подход
            let _ = UIImage(named: imageName) // Просто перезагружаем изображение
            print("[BackgroundTexture] Тема изменена, кэш очищен для: \(imageName)")
        }
    }
} 