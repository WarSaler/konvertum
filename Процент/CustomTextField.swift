// CustomTextField.swift
import SwiftUI
import Combine

struct CustomTextField: View {
    @EnvironmentObject private var localizationManager: LocalizationManager
    @Binding var text: String
    let placeholder: String
    let isFirstResponder: Bool
    let backgroundColor: Color
    let textColor: Color
    let onEditingBegin: () -> Void

    // PERFORMANCE: caret blinking state
    @State private var caretVisible = true
    @State private var caretTimer: AnyCancellable? = nil

    var body: some View {
        HStack(spacing: 0) {
            // PERFORMANCE: Simplified text display logic
            if text.isEmpty && !isFirstResponder {
                // Placeholder only when not focused and empty
                Text(placeholder)
                    .font(.system(size: 22, weight: .regular))
                    .foregroundColor(Color.gray)
                    .padding(.leading, 8)
                    .frame(minHeight: 46, alignment: .leading)
                    .multilineTextAlignment(.trailing)
                    .frame(maxWidth: .infinity, alignment: .trailing)
            } else {
                // Actual text value
                Text(text)
                    .font(.system(size: 22, weight: .regular))
                    .foregroundColor(textColor)
                    .padding(.leading, 8)
                    .frame(minHeight: 46, alignment: .leading)
                    .multilineTextAlignment(.trailing)
                    .frame(maxWidth: .infinity, alignment: .trailing)
                    // PERFORMANCE: Disable text animations
                    .animation(nil, value: text)
            }

            Spacer()

            // PERFORMANCE: Simplified caret with conditional rendering
            if isFirstResponder {
                Rectangle()
                    .fill(textColor)
                    .frame(width: 2, height: 24)
                    .opacity(caretVisible ? 1 : 0)
                    .padding(.trailing, 8)
            }
        }
        .background(backgroundColor)
        .cornerRadius(5)
        .contentShape(Rectangle())
        .onTapGesture {
            onEditingBegin()
        }
        // PERFORMANCE: Context menu only when there's content
        .contextMenu {
            if !text.isEmpty {
                Button(localizationManager.localizedString("copy")) {
                    UIPasteboard.general.string = text
                }
            }
        }
        .onChange(of: isFirstResponder) { _, newValue in
            if newValue {
                // Запускаем таймер мигания через Combine
                caretTimer?.cancel()
                caretTimer = Timer.publish(every: 0.5, on: .main, in: .common)
                    .autoconnect()
                    .sink { _ in
                        withAnimation(.linear(duration: 0.1)) {
                            caretVisible.toggle()
                        }
                    }
            } else {
                caretTimer?.cancel()
                caretVisible = true
            }
        }
        .onDisappear {
            caretTimer?.cancel()
        }
    }
}
