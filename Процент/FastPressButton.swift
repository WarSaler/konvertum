import SwiftUI
import AudioToolbox
#if os(iOS)
import UIKit
#endif

struct FastPressButton: View {
    let key: String
    let size: CGFloat
    let isModern: Bool
    let action: () -> Void
    
    @State private var isPressed = false
    @AppStorage("keyboardSoundEnabled") private var soundEnabled: Bool = false
    @AppStorage("keyboardHapticStrength") private var hapticStrength: Int = 1
    
    var body: some View {
        Button(action: {
            // CRITICAL PERFORMANCE: Remove withAnimation to prevent CPU overload
            // Мгновенное нажатие при тапе
            isPressed = true
            
            // Выполняем действие сразу
            action()
            
            // Быстрый возврат в исходное состояние
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                isPressed = false
            }
        }) {
            // Используем точно такой же подход, как в CalculatorButton
            Image(getImageName(for: key))
                .resizable()
                .renderingMode(.original)
                .aspectRatio(contentMode: .fit)
                .frame(width: size - 0.5, height: size - 0.5)
                .rotation3DEffect(
                    .degrees(isPressed ? 6.5 : 0),
                    axis: (x: 1, y: 0, z: 0),
                    anchor: .center,
                    anchorZ: 0,
                    perspective: 0.2
                )
                .scaleEffect(isPressed ? 0.935 : 1.0)
                .offset(y: isPressed ? 3 : 0)
                .shadow(
                    color: isModern ? .black.opacity(0.3) : .gray.opacity(0.3),
                    radius: isPressed ? 2 : 4,
                    x: 0,
                    y: isPressed ? 1 : 3
                )
                // CRITICAL PERFORMANCE: Remove .animation to prevent CPU overload
        }
        .buttonStyle(PlainButtonStyle())
    }
    
    private func getImageName(for key: String) -> String {
        switch key {
        case "⌫":
            return "backspace"
        case ",":
            return "dot"
        default:
            return key
        }
    }
} 