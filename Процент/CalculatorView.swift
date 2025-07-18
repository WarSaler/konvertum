import SwiftUI
import AudioToolbox

struct CalculatorButton: View {
    let key: String
    let size: CGFloat
    let isModern: Bool
    let action: () -> Void
    
    @State private var isPressed = false
    
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
            Image(key)
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
}

struct CalculatorView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var themeManager: ThemeManager
    @AppStorage("keyboardHapticStrength") private var hapticStrength: Int = 1
    @AppStorage("keyboardSoundEnabled") private var soundEnabled: Bool = false
    
    // Используем селектор обратной связи для системных настроек
    private let feedbackGenerator = UISelectionFeedbackGenerator()
    
    @State private var display = "0"
    @State private var currentNumber = ""
    @State private var currentOperation: Operation? = nil
    @State private var previousNumber: Double? = nil
    @State private var shouldResetDisplay = false
    @State private var calculationHistory = ""
    
    // Константы из CustomKeyboardView
    private let buttonSpacing: CGFloat = -12
    private let horizontalPadding: CGFloat = 6
    private let verticalPadding: CGFloat = 4
    private let rowSpacing: CGFloat = -12
    
    private var buttonSize: CGFloat {
        let screenWidth = UIScreen.main.bounds.width
        let availableWidth = screenWidth - horizontalPadding * 2 + (buttonSpacing * 3)
        return floor(availableWidth / 3.65)
    }
    
    enum Operation {
        case add, subtract, multiply, divide, percent
    }
    
    private let keys: [[String]] = [
        ["percent", "backspace", "divide", "multiply"],
        ["7", "8", "9", "minus"],
        ["4", "5", "6", "plus"],
        ["1", "2", "3", "equals"],
        ["0", "dot", "C"]
    ]
    
    @State private var isPressed = false
    
    var body: some View {
        ZStack {
            // Фоновый слой с текстурой
            Color(themeManager.currentTheme.isDark ? .black : .white)
                .edgesIgnoringSafeArea(.all)
                .zIndex(-20)
                
            // Добавляем текстуру только когда не происходит смена темы
            if !themeManager.isChangingTheme {
                if let image = UIImage(named: themeManager.currentTheme.backgroundTextureName) {
                    Image(uiImage: image)
                        .resizable(resizingMode: .tile)
                        .opacity(0.85)
                        .edgesIgnoringSafeArea(.all)
                        .zIndex(-10)
                }
            }
            
            VStack(spacing: 0) {
                // Заголовок
                Text("Калькулятор")
                    .font(.system(size: 30, weight: .medium))
                    .foregroundColor(themeManager.textColor)
                    .padding(.top, 16)
                    .padding(.bottom, 8)

                // Дисплей с историей
                VStack(alignment: .trailing, spacing: 4) {
                    if !calculationHistory.isEmpty {
                        Text(calculationHistory)
                            .font(.system(size: 20))
                            .foregroundColor(.gray)
                            .lineLimit(1)
                            .frame(maxWidth: .infinity, alignment: .trailing)
                            .padding(.horizontal, 16)
                            .padding(.top, 8)
                    }
                    
                    Text(display)
                        .font(.system(size: 56, weight: .bold))
                        .foregroundColor(themeManager.textColor)
                        .lineLimit(1)
                        .minimumScaleFactor(0.5)
                        .frame(maxWidth: .infinity, alignment: .trailing)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 8)
                }
                .frame(height: 150)  // Увеличиваем высоту с 120 до 150
                .background(Color(red: 150/255, green: 200/255, blue: 230/255))
                .cornerRadius(8)
                .padding(.horizontal, 8)  // Уменьшаем горизонтальные отступы для большей ширины
                
                Spacer()
                
                // Клавиатура
                VStack(spacing: rowSpacing) {
                    ForEach(0..<keys.count, id: \.self) { rowIndex in
                        if rowIndex == keys.count - 1 {
                            // Последний ряд - центрируем
                            HStack(spacing: buttonSpacing) {
                                Spacer()
                                ForEach(keys[rowIndex], id: \.self) { key in
                                    keyButton(key)
                                }
                                Spacer()
                            }
                        } else {
                            rowView(at: rowIndex)
                        }
                    }
                }
                .padding(.horizontal, horizontalPadding)
                .padding(.top, 2)
                .padding(.bottom, verticalPadding)
            }
            .zIndex(10) // Высокий z-index для контента
        }
        .presentationDetents([.medium])
        .presentationDragIndicator(.visible)
    }
    
    @ViewBuilder
    private func rowView(at index: Int) -> some View {
        HStack(spacing: buttonSpacing) {
            ForEach(keys[index], id: \.self) { key in
                keyButton(key)
            }
            if index == keys.count - 1 {
                Spacer()
            }
        }
    }
    
    private func keyButton(_ key: String) -> some View {
        CalculatorButton(
            key: key,
            size: buttonSize,
            isModern: themeManager.currentTheme == .modern
        ) {
            // Применяем вибрацию в зависимости от настроек
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
            
            // Воспроизводим звук если включен
            if soundEnabled {
                AudioServicesPlaySystemSound(1104)
            }
            
            buttonPressed(key)
        }
    }
    
    private func buttonPressed(_ button: String) {
        switch button {
        case "C":
            display = "0"
            currentNumber = ""
            currentOperation = nil
            previousNumber = nil
            shouldResetDisplay = false
            calculationHistory = ""  // Очищаем историю
            
        case "backspace":
            if currentNumber.count > 1 {
                currentNumber.removeLast()
                display = currentNumber
            } else {
                currentNumber = "0"
                display = "0"
            }
            
        case "percent":
            if let value = Double(display) {
                let percentValue = value / 100
                // CRITICAL FIX: Check for NaN before formatting
                if percentValue.isNaN || percentValue.isInfinite {
                    display = "0"
                } else {
                    display = formatResult(percentValue)
                }
                shouldResetDisplay = true
            }
            
        case "plus":
            setOperation(.add)
        case "minus":
            setOperation(.subtract)
        case "multiply":
            setOperation(.multiply)
        case "divide":
            setOperation(.divide)
            
        case "equals":
            calculate()
            
        case "dot":
            if !display.contains(".") {
                display += "."
            }
            
        default:
            if shouldResetDisplay {
                display = button
                shouldResetDisplay = false
            } else {
                display = display == "0" ? button : display + button
            }
            currentNumber = display
        }
    }
    
    private func setOperation(_ operation: Operation) {
        if let number = Double(currentNumber) {
            if previousNumber != nil {
                calculate()
            }
            previousNumber = number
            currentOperation = operation
            shouldResetDisplay = true
            
            // Обновляем историю при установке операции
            calculationHistory = "\(formatResult(number)) \(getOperationSymbol(operation))"
        }
    }
    
    private func getOperationSymbol(_ operation: Operation) -> String {
        switch operation {
        case .add: return "+"
        case .subtract: return "-"
        case .multiply: return "×"
        case .divide: return "÷"
        case .percent: return "%"
        }
    }
    
    private func calculate() {
        guard let previous = previousNumber,
              let current = Double(currentNumber),
              let operation = currentOperation else { return }
        
        var result: Double = 0
        
        switch operation {
        case .add:
            result = previous + current
        case .subtract:
            result = previous - current
        case .multiply:
            result = previous * current
        case .divide:
            if current != 0 {
                result = previous / current
                // CRITICAL FIX: Additional check for division result
                if result.isNaN || result.isInfinite {
                    result = 0
                }
            } else {
                result = 0
            }
        case .percent:
            result = previous * (current / 100)
        }
        
        // Обновляем историю с полным выражением
        calculationHistory = "\(formatResult(previous)) \(getOperationSymbol(operation)) \(formatResult(current)) ="
        
        display = formatResult(result)
        currentNumber = display
        previousNumber = nil
        currentOperation = nil
        shouldResetDisplay = true
    }
    
    private func formatResult(_ number: Double) -> String {
        // CRITICAL FIX: Handle NaN and Infinite values to prevent CoreGraphics errors
        if number.isNaN || number.isInfinite {
            return "0"
        }
        
        let formatter = NumberFormatter()
        formatter.minimumFractionDigits = 0
        formatter.maximumFractionDigits = 8
        formatter.numberStyle = .decimal
        
        return formatter.string(from: NSNumber(value: number)) ?? "0"
    }
} 