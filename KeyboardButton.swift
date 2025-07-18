import SwiftUI
import AudioToolbox

struct KeyboardButton: View {
    let key: String
    let size: CGFloat
    let themeManager: ThemeManager
    let action: () -> Void
    
    var body: some View {
        FastPressButton(
            key: key,
            size: size,
            isModern: themeManager.themeType == .modern,
            action: action
        )
    }
}