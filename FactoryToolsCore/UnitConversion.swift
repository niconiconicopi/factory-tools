import Foundation

public enum UnitCategory: String, CaseIterable, Identifiable {
    case length
    case mass
    case volume
    case temperature

    public var id: String { rawValue }

    public var titleKey: String {
        "unitConverter.category.\(rawValue)"
    }

    public var units: [MeasurementUnit] {
        switch self {
        case .length: [.millimeter, .centimeter, .meter, .kilometer, .inch, .foot]
        case .mass: [.gram, .kilogram, .ounce, .pound]
        case .volume: [.milliliter, .liter, .usFluidOunce, .usGallon]
        case .temperature: [.celsius, .fahrenheit, .kelvin]
        }
    }
}

public enum MeasurementUnit: String, CaseIterable, Identifiable {
    case millimeter
    case centimeter
    case meter
    case kilometer
    case inch
    case foot
    case gram
    case kilogram
    case ounce
    case pound
    case milliliter
    case liter
    case usFluidOunce
    case usGallon
    case celsius
    case fahrenheit
    case kelvin

    public var id: String { rawValue }

    public var category: UnitCategory {
        switch self {
        case .millimeter, .centimeter, .meter, .kilometer, .inch, .foot: .length
        case .gram, .kilogram, .ounce, .pound: .mass
        case .milliliter, .liter, .usFluidOunce, .usGallon: .volume
        case .celsius, .fahrenheit, .kelvin: .temperature
        }
    }

    public var titleKey: String {
        "unitConverter.unit.\(rawValue)"
    }

    public var symbol: String {
        switch self {
        case .millimeter: "mm"
        case .centimeter: "cm"
        case .meter: "m"
        case .kilometer: "km"
        case .inch: "in"
        case .foot: "ft"
        case .gram: "g"
        case .kilogram: "kg"
        case .ounce: "oz"
        case .pound: "lb"
        case .milliliter: "mL"
        case .liter: "L"
        case .usFluidOunce: "US fl oz"
        case .usGallon: "US gal"
        case .celsius: "°C"
        case .fahrenheit: "°F"
        case .kelvin: "K"
        }
    }

    fileprivate var factorToBase: Double? {
        switch self {
        case .millimeter: 0.001
        case .centimeter: 0.01
        case .meter: 1
        case .kilometer: 1_000
        case .inch: 0.0254
        case .foot: 0.3048
        case .gram: 0.001
        case .kilogram: 1
        case .ounce: 0.028349523125
        case .pound: 0.45359237
        case .milliliter: 0.001
        case .liter: 1
        case .usFluidOunce: 0.0295735295625
        case .usGallon: 3.785411784
        case .celsius, .fahrenheit, .kelvin: nil
        }
    }
}

public enum UnitConversion {
    public static func convert(_ value: Double, from source: MeasurementUnit, to target: MeasurementUnit) -> Double? {
        guard value.isFinite, source.category == target.category else { return nil }

        if source.category == .temperature {
            let celsius: Double
            switch source {
            case .celsius: celsius = value
            case .fahrenheit: celsius = (value - 32) * 5 / 9
            case .kelvin: celsius = value - 273.15
            default: return nil
            }
            guard celsius.isFinite, celsius >= -273.15 - 1e-9 else { return nil }
            let validCelsius = max(celsius, -273.15)

            let converted: Double
            switch target {
            case .celsius: converted = validCelsius
            case .fahrenheit: converted = validCelsius * 9 / 5 + 32
            case .kelvin: converted = validCelsius + 273.15
            default: return nil
            }
            return converted.isFinite ? converted : nil
        }

        guard value >= 0,
              let sourceFactor = source.factorToBase,
              let targetFactor = target.factorToBase else { return nil }
        let baseValue = value * sourceFactor
        let converted = baseValue / targetFactor
        guard baseValue.isFinite, converted.isFinite else { return nil }
        return converted
    }
}
