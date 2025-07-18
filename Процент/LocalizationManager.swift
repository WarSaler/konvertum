import SwiftUI
import Foundation
import ObjectiveC

class LocalizationManager: ObservableObject {
    @Published var currentLanguage: String {
        didSet {
            UserDefaults.standard.set(currentLanguage, forKey: "AppLanguage")
            UserDefaults.standard.synchronize()
            
            // Обновляем bundle
            if let bundlePath = Bundle.main.path(forResource: currentLanguage, ofType: "lproj"),
               let bundle = Bundle(path: bundlePath) {
                self.currentBundle = bundle
            } else {
                self.currentBundle = Bundle.main
            }
            
            // Уведомляем об изменении языка
            objectWillChange.send()
            NotificationCenter.default.post(name: NSNotification.Name("LanguageChanged"), object: nil)
        }
    }
    
    private var currentBundle: Bundle = Bundle.main
    
    static let shared = LocalizationManager()
    
    let availableLanguages = [
        ("en", "English", "🇺🇸"),
        ("ar", "العربية", "🇸🇦"),
        ("cs", "Čeština", "🇨🇿"),
        ("da", "Dansk", "🇩🇰"),
        ("de", "Deutsch", "🇩🇪"),
        ("el", "Ελληνικά", "🇬🇷"),
        ("es", "Español", "🇪🇸"),
        ("fi", "Suomi", "🇫🇮"),
        ("fil", "Filipino", "🇵🇭"),
        ("fr", "Français", "🇫🇷"),
        ("he", "עברית", "🇮🇱"),
        ("hi", "हिन्दी", "🇮🇳"),
        ("hu", "Magyar", "🇭🇺"),
        ("id", "Bahasa Indonesia", "🇮🇩"),
        ("it", "Italiano", "🇮🇹"),
        ("ja", "日本語", "🇯🇵"),
        ("jv", "Basa Jawa", "🇮🇩"),
        ("ko", "한국어", "🇰🇷"),
        ("nb", "Norsk bokmål", "🇳🇴"),
        ("nl", "Nederlands", "🇳🇱"),
        ("pl", "Polski", "🇵🇱"),
        ("pt", "Português", "🇵🇹"),
        ("pt-BR", "Português (Brasil)", "🇧🇷"),
        ("ro", "Română", "🇷🇴"),
        ("ru", "Русский", "🇷🇺"),
        ("sv", "Svenska", "🇸🇪"),
        ("th", "ไทย", "🇹🇭"),
        ("tr", "Türkçe", "🇹🇷"),
        ("vi", "Tiếng Việt", "🇻🇳"),
        ("zh-Hans", "简体中文", "🇨🇳"),
        ("zh-Hant", "繁體中文", "🇹🇼")
    ]
    
    init() {
        // Получаем сохраненный язык или системный язык
        if let savedLanguage = UserDefaults.standard.string(forKey: "AppLanguage") {
            self.currentLanguage = savedLanguage
        } else {
            // Получаем системный язык
            let systemLanguage = Locale.preferredLanguages[0]
            let languageCode = systemLanguage.components(separatedBy: "-")[0]
            
            // Проверяем, поддерживается ли системный язык
            if availableLanguages.contains(where: { $0.0 == languageCode }) {
                self.currentLanguage = languageCode
            } else {
                // Если язык не поддерживается, используем английский
                self.currentLanguage = "en"
            }
        }
        
        // Инициализируем bundle
        if let bundlePath = Bundle.main.path(forResource: currentLanguage, ofType: "lproj"),
           let bundle = Bundle(path: bundlePath) {
            self.currentBundle = bundle
        }
    }
    
    func localizedString(_ key: String) -> String {
        return NSLocalizedString(key, tableName: nil, bundle: currentBundle, value: key, comment: "")
    }
    
    // Возвращает корректный Locale для текущего языка
    func currentLocale() -> Locale {
        switch currentLanguage {
        case "ar":
            return Locale(identifier: "ar-SA")
        case "he":
            return Locale(identifier: "he-IL")
        case "zh-Hans": 
            return Locale(identifier: "zh-Hans-CN")
        case "zh-Hant": 
            return Locale(identifier: "zh-Hant-TW")
        case "pt-BR": 
            return Locale(identifier: "pt-BR")
        case "pt":
            return Locale(identifier: "pt-PT")
        case "nb":
            return Locale(identifier: "nb-NO")
        case "fil":
            return Locale(identifier: "fil-PH")
        case "jv":
            return Locale(identifier: "jv-ID")
        case "cs":
            return Locale(identifier: "cs-CZ")
        case "da":
            return Locale(identifier: "da-DK")
        case "de":
            return Locale(identifier: "de-DE")
        case "el":
            return Locale(identifier: "el-GR")
        case "es":
            return Locale(identifier: "es-ES")
        case "fi":
            return Locale(identifier: "fi-FI")
        case "fr":
            return Locale(identifier: "fr-FR")
        case "hi":
            return Locale(identifier: "hi-IN")
        case "hu":
            return Locale(identifier: "hu-HU")
        case "id":
            return Locale(identifier: "id-ID")
        case "it":
            return Locale(identifier: "it-IT")
        case "ja":
            return Locale(identifier: "ja-JP")
        case "ko":
            return Locale(identifier: "ko-KR")
        case "nl":
            return Locale(identifier: "nl-NL")
        case "pl":
            return Locale(identifier: "pl-PL")
        case "ro":
            return Locale(identifier: "ro-RO")
        case "ru":
            return Locale(identifier: "ru-RU")
        case "sv":
            return Locale(identifier: "sv-SE")
        case "th":
            return Locale(identifier: "th-TH")
        case "tr":
            return Locale(identifier: "tr-TR")
        case "vi":
            return Locale(identifier: "vi-VN")
        case "en":
            return Locale(identifier: "en-US")
        default: 
            return Locale(identifier: "en-US")
        }
    }
    
    // Специальный метод для получения локализованных названий месяцев и дат
    func getLocalizedDateFormatter(format: String) -> DateFormatter {
        let formatter = DateFormatter()
        formatter.locale = currentLocale()
        formatter.dateFormat = format
        return formatter
    }

    // Вспомогательный метод для получения локализованного формата даты
    func localizedDateFormatter(format: String) -> DateFormatter {
        let formatter = DateFormatter()
        formatter.locale = currentLocale()
        formatter.dateFormat = format
        return formatter
    }
    
    // Новый метод для создания динамического форматтера дат (обновляется при смене языка)
    func createDateFormatter(format: String) -> DateFormatter {
        return getLocalizedDateFormatter(format: format)
    }
    
    // Определяет направление текста для текущего языка
    func isRTL() -> Bool {
        return currentLanguage == "ar" || currentLanguage == "he"
    }
    
    // Возвращает правильное выравнивание текста
    func textAlignment() -> TextAlignment {
        return isRTL() ? .trailing : .leading
    }
    
    // Возвращает правильное выравнивание для HStack
    func horizontalAlignment() -> HorizontalAlignment {
        return isRTL() ? .trailing : .leading
    }
}

// Расширение для Bundle для поддержки динамической локализации
private var bundleKey: UInt8 = 0

extension Bundle {
    var localizedBundle: Bundle? {
        get {
            return objc_getAssociatedObject(self, &bundleKey) as? Bundle
        }
        set {
            objc_setAssociatedObject(self, &bundleKey, newValue, .OBJC_ASSOCIATION_RETAIN_NONATOMIC)
        }
    }
    
    func loadAndSetLocalizationBundle(for language: String) {
        guard let bundlePath = Bundle.main.path(forResource: language, ofType: "lproj"),
              let bundle = Bundle(path: bundlePath) else {
            self.localizedBundle = nil
            return
        }
        self.localizedBundle = bundle
    }
}

// Расширение для Bundle для поддержки смены языка
extension Bundle {
    private static var bundle: Bundle?
    
    static func setLanguage(_ language: String) {
        let path = Bundle.main.path(forResource: language, ofType: "lproj")
        bundle = path != nil ? Bundle(path: path!) : Bundle.main
    }
    
    static func localizedString(for key: String, comment: String = "") -> String {
        let defaultValue = NSLocalizedString(key, comment: comment)
        guard let bundle = bundle else { return defaultValue }
        return bundle.localizedString(forKey: key, value: defaultValue, table: nil)
    }
} 