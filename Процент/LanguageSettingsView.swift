import SwiftUI

struct LanguageSettingsView: View {
    @EnvironmentObject private var localizationManager: LocalizationManager
    @Environment(\.dismiss) private var dismiss
    
    var body: some View {
        NavigationView {
            List {
                ForEach(localizationManager.availableLanguages, id: \.0) { language in
                    Button(action: {
                        localizationManager.currentLanguage = language.0
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                            dismiss()
                        }
                    }) {
                        HStack {
                            Text(language.2) // Flag
                                .font(.title2)
                            Text(language.1) // Language name
                                .foregroundColor(.primary)
                            Spacer()
                            if localizationManager.currentLanguage == language.0 {
                                Image(systemName: "checkmark")
                                    .foregroundColor(.blue)
                            }
                        }
                    }
                }
            }
            .navigationTitle(LocalizationManager.shared.localizedString("languages"))
            .navigationBarItems(trailing: Button(LocalizationManager.shared.localizedString("done")) {
                dismiss()
            })
        }
        .id(localizationManager.currentLanguage) // Форсируем пересоздание view при смене языка
    }
} 