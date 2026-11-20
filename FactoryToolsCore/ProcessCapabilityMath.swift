import Foundation

public struct ProcessCapabilityResult: Equatable, Sendable {
    public let cp: Double
    public let cpk: Double

    public init(cp: Double, cpk: Double) {
        self.cp = cp
        self.cpk = cpk
    }
}

public enum ProcessCapabilityMath {
    /// Calculates Cp and Cpk from specification limits, process mean, and the
    /// process standard deviation supplied by the user (σ).
    public static func calculate(
        lowerSpecLimit: Double,
        upperSpecLimit: Double,
        processMean: Double,
        standardDeviation: Double
    ) -> ProcessCapabilityResult? {
        guard lowerSpecLimit.isFinite,
              upperSpecLimit.isFinite,
              processMean.isFinite,
              standardDeviation.isFinite,
              lowerSpecLimit < upperSpecLimit,
              standardDeviation > 0 else { return nil }

        let cp = (upperSpecLimit - lowerSpecLimit) / (6 * standardDeviation)
        let cpu = (upperSpecLimit - processMean) / (3 * standardDeviation)
        let cpl = (processMean - lowerSpecLimit) / (3 * standardDeviation)
        let cpk = min(cpu, cpl)
        guard cp.isFinite, cpk.isFinite else { return nil }
        return ProcessCapabilityResult(cp: cp, cpk: cpk)
    }
}
