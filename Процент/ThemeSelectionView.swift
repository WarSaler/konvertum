import SwiftUI

struct ThemeSelectionView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var themeManager: ThemeManager
    
    var body: some View {
        NavigationView {
            ScrollView {
                VStack(spacing: 20) {
                    ForEach(ThemeType.allCases) { theme in
                        Button {
                            themeManager.selectTheme(theme)
                            // Закрываем окно выбора темы
                            dismiss()
                        } label: {
                            VStack {
                                // Превью-картинка темы (может быть превью текстуры)
                                Image(theme.previewImageName)
                                    .resizable()
                                    .aspectRatio(contentMode: .fit)
                                    .cornerRadius(8)
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 8)
                                            .stroke(themeManager.currentTheme == theme ? Color.accentColor : Color.clear,
                                                    lineWidth: 3)
                                    )

                                // Отображаемое название темы - используем локализованную строку
                                Text(theme.displayName)
                                    .font(.caption)
                                    .foregroundColor(themeManager.currentTheme == theme ? .accentColor : .primary)
                            }
                        }
                        .buttonStyle(PlainButtonStyle())
                    }
                }
                .padding()
            }
            // Используем локализованную строку вместо хардкода
            .navigationTitle(LocalizationManager.shared.localizedString("theme_selection"))
            .navigationBarTitleDisplayMode(.inline)
        }
    }
}
