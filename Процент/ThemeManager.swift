import SwiftUI
import UIKit

// Типы доступных тем
enum ThemeType: String, CaseIterable, Identifiable {
    case classic, modern
    var id: String { rawValue }

    /// Отображаемое имя темы - теперь использует локализацию вместо хардкода
    var displayName: String {
        switch self {
        case .classic: return LocalizationManager.shared.localizedString("classic")
        case .modern:  return LocalizationManager.shared.localizedString("modern")
        }
    }

    /// Имя превью-картинки (для списка выбора)
    var previewImageName: String {
        switch self {
        case .classic: return "classic_preview"
        case .modern:  return "modern_preview"
        }
    }

    /// Название текстуры фона (как в ассетах)
    var backgroundTextureName: String {
        switch self {
        case .classic: return "classic_keyboard_bg_texture"
        case .modern:  return "modern_keyboard_bg_texture"
        }
    }
    
    /// Имя текстуры для области валют
    var currencyTextureName: String {
        switch self {
        case .classic: return "classic_currency_bg_texture"
        case .modern: return "modern_currency_bg_texture"
        }
    }

    /// Цвет текста (чёрный для светлой, белый для тёмной)
    var textColor: Color {
        switch self {
        case .classic: return .black
        case .modern:  return .white
        }
    }

    /// Является ли тема тёмной
    var isDark: Bool {
        self == .modern
    }
    
    var backgroundColor: Color {
        switch self {
        case .classic: return Color(UIColor.systemBackground)
        case .modern:  return Color(red: 0.12, green: 0.12, blue: 0.12)
        }
    }
    
    var textFieldBG: Color {
        switch self {
        case .classic: return Color(UIColor.secondarySystemBackground)
        case .modern:  return Color(red: 0.10, green: 0.15, blue: 0.25)
        }
    }
    
    var buttonBG: Color {
        switch self {
        case .classic: return Color(red: 0.90, green: 0.90, blue: 0.90)
        case .modern:  return Color(red: 0.16, green: 0.32, blue: 0.54)
        }
    }
    
    var keyboardBG: Color {
        switch self {
        case .modern: return Color(red: 0.25, green: 0.25, blue: 0.25)
        case .classic: return Color(red: 0.90, green: 0.90, blue: 0.90)
        }
    }
}

final class ThemeManager: ObservableObject {
    @Published var currentTheme: ThemeType
    @Published var isChangingTheme: Bool = false

    private let key = "selectedTheme"

    init() {
        // Загрузка ранее сохранённой темы или выбор по умолчанию
        let saved = UserDefaults.standard.string(forKey: key) ?? ThemeType.classic.rawValue
        currentTheme = ThemeType(rawValue: saved) ?? .classic
    }

    /// Возвращает ColorScheme для SwiftUI (.light или .dark)
    var colorScheme: ColorScheme {
        currentTheme.isDark ? .dark : .light
    }

    /// Переключение темы: сохраняет выбор, сигнализирует о начале и конце смены
    func selectTheme(_ theme: ThemeType) {
        guard currentTheme != theme else { return }

        print("[ThemeManager] 🎨 Переключение темы: \(currentTheme.rawValue) → \(theme.rawValue)")
        
        // Начало смены темы
        isChangingTheme = true

        // Обновляем тему и сохраняем в UserDefaults
        currentTheme = theme
        UserDefaults.standard.set(theme.rawValue, forKey: key)
        UserDefaults.standard.synchronize() // Принудительно сохраняем
        
        print("[ThemeManager] ✅ Тема изменена на: \(currentTheme.rawValue)")
        print("[ThemeManager] 📁 backgroundTexture: \(currentTheme.backgroundTextureName)")
        print("[ThemeManager] 📁 currencyTexture: \(currentTheme.currencyTextureName)")

        // Через 0.5 секунды скрываем баннер "Изменение темы..." с анимацией
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            withAnimation {
                self.isChangingTheme = false
            }
        }
    }
    
    // Проксирующие свойства для удобного доступа к свойствам текущей темы
    var background: Color { currentTheme.backgroundColor }
    var textFieldBG: Color { currentTheme.textFieldBG }
    var textColor: Color { currentTheme.textColor }
    var buttonBG: Color { currentTheme.buttonBG }
    var keyboardBG: Color { currentTheme.keyboardBG }
    var currencyTextureName: String { currentTheme.currencyTextureName }
    
    var buttonText: Color { currentTheme.textColor }
    var keyboardText: Color { buttonText }
}



