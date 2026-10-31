import Foundation

public enum ProductionProgressMath {
    public static func fraction(currentCount: Int, targetCount: Int) -> Double {
        guard targetCount > 0 else { return 0 }
        return min(Double(max(0, currentCount)) / Double(targetCount), 1)
    }

}
