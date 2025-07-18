import SwiftUI
import MessageUI

struct SettingsView: View {
    @EnvironmentObject private var themeManager: ThemeManager
    @EnvironmentObject private var localizationManager: LocalizationManager
    @Environment(\.dismiss) private var dismiss
    @AppStorage("keyboardSoundEnabled") private var soundEnabled: Bool = false
    @AppStorage("keyboardHapticStrength") private var hapticStrength: Int = 1
    @State private var showingLanguageSettings = false
    @State private var showingThemeSettings = false
    @State private var showingFeedback = false
    @State private var feedbackText = ""
    @State private var feedbackTextToSend = ""
    @State private var shouldShowMailComposer = false
    @State private var showMailComposer = false
    @State private var showMailError = false

    var body: some View {
        NavigationView {
            List {
                Section {
                    Button(action: {
                        showingLanguageSettings = true
                    }) {
                        HStack {
                            Image(systemName: "globe")
                                .foregroundColor(.blue)
                            
                            VStack(alignment: .leading) {
                                Text(LocalizationManager.shared.localizedString("languages"))
                                Text(localizationManager.availableLanguages.first { $0.0 == localizationManager.currentLanguage }?.1 ?? "English")
                                    .font(.caption)
                                    .foregroundColor(.gray)
                            }
                            
                            Spacer()
                            
                            Text(localizationManager.availableLanguages.first { $0.0 == localizationManager.currentLanguage }?.2 ?? "🇺🇸")
                                .font(.title2)
                        }
                    }
                    
                    Button(action: {
                        showingThemeSettings = true
                    }) {
                        HStack {
                            Image(systemName: "paintbrush.fill")
                                .foregroundColor(.blue)
                            
                            VStack(alignment: .leading) {
                                Text(LocalizationManager.shared.localizedString("theme"))
                                Text(themeManager.currentTheme.displayName)
                                    .font(.caption)
                                    .foregroundColor(.gray)
                            }
                            
                            Spacer()
                        }
                    }
                }
                
                Section(header: Text(LocalizationManager.shared.localizedString("keyboard"))) {
                    Picker(LocalizationManager.shared.localizedString("haptic_strength"), selection: $hapticStrength) {
                        Text(LocalizationManager.shared.localizedString("weak")).tag(0)
                        Text(LocalizationManager.shared.localizedString("medium")).tag(1)
                        Text(LocalizationManager.shared.localizedString("strong")).tag(2)
                    }
                    Toggle(LocalizationManager.shared.localizedString("keyboard_sound"), isOn: $soundEnabled)
                }
                Section {
                    Button(action: { showingFeedback = true }) {
                        HStack {
                            Image(systemName: "envelope.fill").foregroundColor(.blue)
                            Text("Обратная связь")
                        }
                    }
                }
            }
            .navigationTitle(LocalizationManager.shared.localizedString("settings"))
            .navigationBarItems(trailing: Button(LocalizationManager.shared.localizedString("done")) {
                dismiss()
            })
        }
        .sheet(isPresented: $showingLanguageSettings) {
            LanguageSettingsView()
                .id(localizationManager.currentLanguage)
        }
        .sheet(isPresented: $showingThemeSettings) {
            ThemeSelectionView()
        }
        .sheet(isPresented: $showingFeedback, onDismiss: {
            if shouldShowMailComposer {
                shouldShowMailComposer = false
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                    showMailComposer = true
                }
            }
        }) {
            FeedbackModal(
                feedbackText: $feedbackText,
                appVersion: appVersion,
                appLanguage: localizationManager.currentLanguage,
                onSend: {
                    feedbackTextToSend = feedbackText
                    shouldShowMailComposer = true
                    showingFeedback = false
                },
                onCancel: {
                    showingFeedback = false
                }
            )
        }
        .sheet(isPresented: $showMailComposer) {
            MailView(isShowing: $showMailComposer, result: .constant(nil), subject: "Обратная связь Конвертум", body: feedbackMailBody)
        }
        .alert(isPresented: $showMailError) {
            Alert(title: Text("Ошибка"), message: Text("Не удалось открыть почтовый клиент на этом устройстве."), dismissButton: .default(Text("OK")))
        }
    }

    private var appVersion: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "-"
    }
    private var feedbackMailBody: String {
        let device = UIDevice.current.model
        let system = UIDevice.current.systemName + " " + UIDevice.current.systemVersion
        let region = Locale.current.region?.identifier ?? "-"
        let lang = localizationManager.currentLanguage
        return "Письмо от пользователя:\n\n" + feedbackTextToSend + "\n\n---\nВерсия приложения: \(appVersion)\nМодель: \(device)\nСистема: \(system)\nРегион: \(region)\nЯзык приложения: \(lang)"
    }

    private func sendFeedbackMail() {
        if MailView.canSendMail {
            shouldShowMailComposer = true
            showingFeedback = false
        } else {
            showMailError = true
        }
    }
}

// Красивое модальное окно для обратной связи с версией и языком приложения, быстрый отклик
struct FeedbackModal: View {
    @Binding var feedbackText: String
    var appVersion: String
    var appLanguage: String
    var onSend: () -> Void
    var onCancel: () -> Void
    @FocusState private var isFocused: Bool
    var body: some View {
        NavigationView {
            VStack(alignment: .leading, spacing: 16) {
                Text("Ваше сообщение")
                    .font(.headline)
                FeedbackTextView(text: $feedbackText)
                    .frame(height: 140)
                    .padding(8)
                    .background(Color(.secondarySystemBackground))
                    .cornerRadius(10)
                Text("Версия приложения: \(appVersion)\nЯзык приложения: \(appLanguage)")
                    .font(.footnote)
                    .foregroundColor(.gray)
                Spacer()
                HStack {
                    Button("Отмена", action: onCancel)
                        .foregroundColor(.red)
                    Spacer()
                    Button("Отправить", action: onSend)
                        .disabled(feedbackText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
            .padding()
            .navigationTitle("Обратная связь")
            .navigationBarTitleDisplayMode(.inline)
        }
    }
}

// Быстрый UIKit TextView для мгновенного отклика
import UIKit
struct FeedbackTextView: UIViewRepresentable {
    @Binding var text: String
    func makeUIView(context: Context) -> UITextView {
        let tv = UITextView()
        tv.font = UIFont.systemFont(ofSize: 17)
        tv.backgroundColor = UIColor.clear
        tv.delegate = context.coordinator
        tv.isScrollEnabled = true
        tv.text = text
        tv.autocorrectionType = .yes
        tv.autocapitalizationType = .sentences
        tv.returnKeyType = .default
        tv.becomeFirstResponder()
        return tv
    }
    func updateUIView(_ uiView: UITextView, context: Context) {
        if uiView.text != text {
            uiView.text = text
        }
    }
    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }
    class Coordinator: NSObject, UITextViewDelegate {
        var parent: FeedbackTextView
        init(_ parent: FeedbackTextView) { self.parent = parent }
        func textViewDidChange(_ textView: UITextView) {
            parent.text = textView.text
        }
    }
}

// Вью для отправки письма через стандартный mail composer
struct MailView: UIViewControllerRepresentable {
    @Binding var isShowing: Bool
    @Binding var result: Result<MFMailComposeResult, Error>?
    var subject: String
    var body: String
    static var canSendMail: Bool { MFMailComposeViewController.canSendMail() }
    func makeCoordinator() -> Coordinator { Coordinator(self) }
    func makeUIViewController(context: Context) -> MFMailComposeViewController {
        let vc = MFMailComposeViewController()
        vc.setToRecipients(["testgithab@gmail.com"])
        vc.setSubject(subject)
        vc.setMessageBody(body, isHTML: false)
        vc.mailComposeDelegate = context.coordinator
        return vc
    }
    func updateUIViewController(_ uiViewController: MFMailComposeViewController, context: Context) {}
    class Coordinator: NSObject, MFMailComposeViewControllerDelegate {
        let parent: MailView
        init(_ parent: MailView) { self.parent = parent }
        func mailComposeController(_ controller: MFMailComposeViewController, didFinishWith result: MFMailComposeResult, error: Error?) {
            parent.isShowing = false
            if let error = error {
                parent.result = .failure(error)
            } else {
                parent.result = .success(result)
            }
        }
    }
}
