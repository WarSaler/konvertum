import SwiftUI

struct ContentView: View {
    @EnvironmentObject private var themeManager: ThemeManager
    @EnvironmentObject private var localizationManager: LocalizationManager
    @State private var showingSettings = false
    
    var body: some View {
        NavigationView {
            ZStack {
                // Полноэкранный фон с базовым цветом
                Color(themeManager.currentTheme.isDark ? .black : .white)
                    .edgesIgnoringSafeArea(.all)
                
                // Полноэкранная текстура - убеждаемся, что она покрывает все части экрана
                TextureBackgroundView(imageName: themeManager.currentTheme.backgroundTextureName)
                    .opacity(0.7)
                    .edgesIgnoringSafeArea(.all)
                
                // Контент
                CurrencyConverterView()
                    .navigationBarTitle("", displayMode: .inline)
                    .navigationBarItems(trailing:
                        Button(action: { showingSettings = true }) {
                            Image(systemName: "gearshape")
                                .foregroundColor(themeManager.currentTheme.textColor)
                                .font(.system(size: 22))
                        }
                    )
                
                // Баннер при смене темы
                if themeManager.isChangingTheme {
                    Color.black.opacity(themeManager.currentTheme.isDark ? 0.4 : 0.2)
                        .edgesIgnoringSafeArea(.all)
                    
                    VStack {
                        Text(LocalizationManager.shared.localizedString("changing_theme"))
                            .font(.headline)
                            .foregroundColor(themeManager.currentTheme.textColor)
                            .padding(.all, 12)
                            .background(
                                RoundedRectangle(cornerRadius: 10)
                                    .fill(themeManager.currentTheme.isDark ? Color.white.opacity(0.2) : Color.black.opacity(0.1))
                            )
                    }
                    .transition(.opacity)
                }
            }
        }
        .navigationViewStyle(StackNavigationViewStyle())
        .sheet(isPresented: $showingSettings) {
            SettingsView()
                .onDisappear {
                    // Принудительное обновление при закрытии настроек
                    // Это может помочь с обновлением фона
                    if !themeManager.isChangingTheme {
                        withAnimation {
                            // Пустой блок для принудительного обновления View
                        }
                    }
                }
        }
        .preferredColorScheme(themeManager.colorScheme)
    }
}
