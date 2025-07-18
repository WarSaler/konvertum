import SwiftUI

@main
struct ProcentApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    @StateObject private var localizationManager = LocalizationManager.shared
    @StateObject private var themeManager = ThemeManager()
    // CRITICAL PERFORMANCE: Single global ViewModel instance for entire app
    @StateObject private var currencyViewModel = CurrencyConverterViewModel()
    
    init() {
        print("🚀 ProcentApp: Приложение запускается")
        print("🚀 ProcentApp: Приложение запускается (print)")
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(localizationManager)
                .environmentObject(themeManager)
                .environmentObject(currencyViewModel)
                // preferedColorScheme берётся из ThemeManager (light/dark)
                .preferredColorScheme(themeManager.colorScheme)
        }
    }
}

class AppDelegate: NSObject, UIApplicationDelegate {
    func application(_ application: UIApplication,
                     didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil) -> Bool {
        return true
    }

    func application(_ application: UIApplication,
                     supportedInterfaceOrientationsFor window: UIWindow?) -> UIInterfaceOrientationMask {
        .portrait
    }
}
