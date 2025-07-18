import SwiftUI
import AudioToolbox
import Foundation
#if os(iOS)
import UIKit
#endif
import Combine // Added for Combine subscriptions

struct CustomKeyboardView: View {
    @EnvironmentObject private var localizationManager: LocalizationManager // Было: @ObservedObject private var localizationManager = LocalizationManager.shared
    @EnvironmentObject private var themeManager: ThemeManager
    @AppStorage("keyboardSoundEnabled") private var soundEnabled: Bool = false
    @AppStorage("keyboardHapticStrength") private var hapticStrength: Int = 1
    @State private var showingCalculator = false

    // MARK: — Constants
    private let buttonSpacing: CGFloat = -12
    private let horizontalPadding: CGFloat = 6
    private let verticalPadding: CGFloat = 4
    private let rowSpacing: CGFloat = -12
    private let bottomPaddingAdjustment: CGFloat = 45
    private let keyboardTopPadding: CGFloat = 0

    private let keys: [[String]] = [
        ["7", "8", "9", "⌫"],
        ["4", "5", "6", ","],
        ["1", "2", "3", "C"],
        ["r", "0", "h", "k"]
    ]

    private var buttonSize: CGFloat {
        let screenWidth = UIScreen.main.bounds.width
        let availableWidth = screenWidth - horizontalPadding * 2 + (buttonSpacing * 3)
        return floor(availableWidth / 3.65) // Размер как в калькуляторе
    }



    var onTap: (String) -> Void
    var onBackspace: () -> Void
    var onClearAll: () -> Void
    var onHistory: () -> Void // Изменено с onRefresh на onHistory
    var onRefresh: () -> Void

    var body: some View {
        ZStack {
            // FIX: Use optimized TextureBackgroundView instead of direct Image tiling
            TextureBackgroundView(imageName: themeManager.currentTheme.backgroundTextureName)
                .ignoresSafeArea(edges: .bottom)
                .zIndex(1)
            
            // Используем VStack для кнопок
            let overlayOpacity = themeManager.isChangingTheme ? 0.3 : 1.0
            
            VStack(spacing: 0) {
                // Контент клавиатуры
                VStack(spacing: 0) {
                    VStack(spacing: rowSpacing) {
                        rowView(at: 0)
                        rowView(at: 1)
                        rowView(at: 2)
                        rowView(at: 3)
                    }
                    .opacity(overlayOpacity)
                    .padding(.horizontal, horizontalPadding)
                    .padding(.top, 2)
                    .padding(.bottom, verticalPadding)
                    #if os(iOS)
                    .padding(.bottom, max(0, (UIApplication.shared.connectedScenes
                        .compactMap { $0 as? UIWindowScene }
                        .first?.keyWindow?.safeAreaInsets.bottom ?? 0) - bottomPaddingAdjustment))
                    #else
                    .padding(.bottom, 0)
                    #endif
                }
            }
            .zIndex(10) // Высокий zIndex для контента
        }
        .frame(maxWidth: .infinity)
        // Убираем дополнительный фон, так как теперь используем TextureBackgroundView
        .edgesIgnoringSafeArea(.bottom)


        .sheet(isPresented: $showingCalculator) {
            CalculatorView()
                .environmentObject(themeManager)
                .presentationDetents([.large])
                .presentationDragIndicator(.visible)
        }
        .onAppear {
            // Keyboard is ready
        }
        .environment(\.layoutDirection, .leftToRight) // Принудительно устанавливаем LTR направление
    }

    @ViewBuilder
    private func rowView(at index: Int) -> some View {
        HStack(spacing: buttonSpacing) {
            ForEach(keys[index], id: \.self) { key in
                keyButton(key)
            }
        }
    }

    private func keyButton(_ key: String) -> some View {
        FastPressButton(
            key: key,
            size: buttonSize,
            isModern: themeManager.currentTheme == .modern
        ) {
            handle(key)
        }
    }

    private func handle(_ key: String) {
        // Haptic feedback based on strength
        switch hapticStrength {
        case 0:
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
        case 1:
            UIImpactFeedbackGenerator(style: .medium).impactOccurred()
        case 2:
            UIImpactFeedbackGenerator(style: .heavy).impactOccurred()
        default:
            break
        }
        // Optional sound feedback
        if soundEnabled {
            AudioServicesPlaySystemSound(SystemSoundID(1104))
        }

        switch key {
        case "⌫": onBackspace()
        case "C":  onClearAll()
        case "r":  onRefresh()
        case "h":  onHistory()
        case "k":  showingCalculator = true
        default:   onTap(key)
        }
    }
    


}

// Расширение для безопасного доступа к элементам массива
extension Array {
    subscript(safe index: Index) -> Element? {
        return indices.contains(index) ? self[index] : nil
    }
}
