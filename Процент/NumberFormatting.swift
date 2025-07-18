import Foundation

// MARK: – PERFORMANCE: Centralized number formatting with thin-space separators
extension Double {
    /// Fast formatting with thin-space separators and comma decimal
    /// Formats numbers like: 1 234 567,89 (using thin space U+2009)
    func formattedWithThousandsSeparator() -> String {
        // Handle special cases
        if self.isNaN || self.isInfinite {
            return "0"
        }
        
        // Convert to string with appropriate decimal places
        let str = String(format: "%.2f", self)
        
        // Split by decimal point
        let parts = str.split(separator: ".")
        guard parts.count == 2 else { 
            return formatIntegerPart(String(parts.first ?? "0")) + ",00"
        }
        
        let integerPart = String(parts[0])
        let decimalPart = String(parts[1])
        
        // Format integer part with thin spaces
        let formattedInteger = formatIntegerPart(integerPart)
        
        // Combine with decimal part using comma
        return formattedInteger + "," + decimalPart
    }
    
    /// Format for calculator display (up to 8 decimal places, no trailing zeros)
    func formattedForCalculator() -> String {
        // Handle special cases
        if self.isNaN || self.isInfinite {
            return "0"
        }
        
        // Remove trailing zeros and unnecessary decimal point
        let formatter = NumberFormatter()
        formatter.minimumFractionDigits = 0
        formatter.maximumFractionDigits = 8
        formatter.numberStyle = .decimal
        formatter.groupingSeparator = "\u{2009}" // Thin space
        formatter.decimalSeparator = ","
        formatter.usesGroupingSeparator = true
        
        return formatter.string(from: NSNumber(value: self)) ?? "0"
    }
    
    /// Private helper to format integer part with thin spaces
    private func formatIntegerPart(_ integerPart: String) -> String {
        var result = ""
        let reversed = integerPart.reversed()
        
        for (index, char) in reversed.enumerated() {
            if index > 0 && index % 3 == 0 {
                result = "\u{2009}" + result // Thin space U+2009
            }
            result = String(char) + result
        }
        
        return result
    }
}

extension String {
    /// Fast string formatting for display with thin-space separators
    func formattedWithThousandsSeparator() -> String {
        // Quick check - avoid re-formatting if already contains thin space
        if self.contains("\u{2009}") {
            return self
        }
        
        // Remove existing spaces and convert comma to dot for parsing
        let cleaned = self
            .replacingOccurrences(of: " ", with: "")
            .replacingOccurrences(of: "\u{2009}", with: "") // Remove thin spaces
            .replacingOccurrences(of: ",", with: ".")
        
        // Try to parse as double
        guard let value = Double(cleaned) else { return self }
        
        // Use the fast formatter
        return value.formattedWithThousandsSeparator()
    }
    
    /// Clean input string for calculation (removes formatting)
    func cleanedForCalculation() -> String {
        return self
            .replacingOccurrences(of: " ", with: "")
            .replacingOccurrences(of: "\u{2009}", with: "") // Remove thin spaces
            .replacingOccurrences(of: ",", with: ".")
    }
    
    /// Check if string represents a valid number
    var isValidNumber: Bool {
        let cleaned = self.cleanedForCalculation()
        return Double(cleaned) != nil
    }
}
