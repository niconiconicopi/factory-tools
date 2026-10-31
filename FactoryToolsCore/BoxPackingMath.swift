import Foundation

public struct BoxDimensions: Equatable {
    public let length: Int
    public let width: Int
    public let height: Int

    public init(length: Int, width: Int, height: Int) {
        self.length = length
        self.width = width
        self.height = height
    }

    public var isPositive: Bool {
        length > 0 && width > 0 && height > 0
    }
}

public struct BoxPackingResult: Equatable {
    public let unitsPerBox: Int
    public let unitsAlongLength: Int
    public let unitsAlongWidth: Int
    public let unitsAlongHeight: Int
    public let itemOrientation: BoxDimensions

    public init(unitsPerBox: Int, unitsAlongLength: Int, unitsAlongWidth: Int, unitsAlongHeight: Int, itemOrientation: BoxDimensions) {
        self.unitsPerBox = unitsPerBox
        self.unitsAlongLength = unitsAlongLength
        self.unitsAlongWidth = unitsAlongWidth
        self.unitsAlongHeight = unitsAlongHeight
        self.itemOrientation = itemOrientation
    }
}

public enum BoxPackingOutcome: Equatable {
    case fit(BoxPackingResult)
    case noFit
    case countTooLarge
}

public enum BoxCalculator {
    public static func outcome(item: BoxDimensions, innerBox: BoxDimensions) -> BoxPackingOutcome {
        guard item.isPositive, innerBox.isPositive else { return .noFit }

        let orientations = [
            BoxDimensions(length: item.length, width: item.width, height: item.height),
            BoxDimensions(length: item.length, width: item.height, height: item.width),
            BoxDimensions(length: item.width, width: item.length, height: item.height),
            BoxDimensions(length: item.width, width: item.height, height: item.length),
            BoxDimensions(length: item.height, width: item.length, height: item.width),
            BoxDimensions(length: item.height, width: item.width, height: item.length)
        ]

        var bestResult: BoxPackingResult?
        var hasOverflowingLayout = false
        for orientation in orientations {
            let unitsAlongLength = innerBox.length / orientation.length
            let unitsAlongWidth = innerBox.width / orientation.width
            let unitsAlongHeight = innerBox.height / orientation.height
            guard unitsAlongLength > 0, unitsAlongWidth > 0, unitsAlongHeight > 0 else { continue }

            let (unitsAcrossBase, baseOverflow) = unitsAlongLength.multipliedReportingOverflow(by: unitsAlongWidth)
            guard !baseOverflow else {
                hasOverflowingLayout = true
                continue
            }
            let (unitsPerBox, totalOverflow) = unitsAcrossBase.multipliedReportingOverflow(by: unitsAlongHeight)
            guard !totalOverflow else {
                hasOverflowingLayout = true
                continue
            }

            if unitsPerBox > (bestResult?.unitsPerBox ?? 0) {
                bestResult = BoxPackingResult(
                    unitsPerBox: unitsPerBox,
                    unitsAlongLength: unitsAlongLength,
                    unitsAlongWidth: unitsAlongWidth,
                    unitsAlongHeight: unitsAlongHeight,
                    itemOrientation: orientation
                )
            }
        }
        if let bestResult { return .fit(bestResult) }
        return hasOverflowingLayout ? .countTooLarge : .noFit
    }

    public static func maximumUnits(item: BoxDimensions, innerBox: BoxDimensions) -> BoxPackingResult? {
        guard case let .fit(result) = outcome(item: item, innerBox: innerBox) else { return nil }
        return result
    }
}
