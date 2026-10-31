import Foundation

public enum LocalizedNumberParser {
    public static func parse(_ text: String, locale: Locale) -> Double? {
        guard let number = parseNumber(text, locale: locale) else { return nil }
        let value = number.doubleValue
        return value.isFinite ? value : nil
    }

    public static func parseInteger(_ text: String, locale: Locale) -> Int? {
        guard let number = parseNumber(text, locale: locale) else { return nil }
        var parsedValue = number.decimalValue
        var roundedValue = Decimal()
        NSDecimalRound(&roundedValue, &parsedValue, 0, .plain)
        guard roundedValue == parsedValue,
              roundedValue >= Decimal(Int64.min),
              roundedValue <= Decimal(Int64.max) else { return nil }
        return Int(exactly: NSDecimalNumber(decimal: roundedValue).int64Value)
    }

    private static func parseNumber(_ text: String, locale: Locale) -> NSNumber? {
        let input = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !input.isEmpty else { return nil }

        let formatter = NumberFormatter()
        formatter.locale = locale
        formatter.numberStyle = .decimal
        formatter.isLenient = false
        formatter.generatesDecimalNumbers = true

        let inputLength = (input as NSString).length
        var parsedObject: AnyObject?
        var parsedRange = NSRange(location: 0, length: inputLength)
        do {
            try formatter.getObjectValue(&parsedObject, for: input, range: &parsedRange)
        } catch {
            return nil
        }
        guard parsedRange.location == 0,
              NSMaxRange(parsedRange) == inputLength,
              let number = parsedObject as? NSNumber else { return nil }
        return number
    }
}
