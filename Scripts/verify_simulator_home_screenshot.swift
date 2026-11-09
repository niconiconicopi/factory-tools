import Foundation
import Vision

guard CommandLine.arguments.count >= 3 else {
    fputs("Usage: verify_simulator_home_screenshot.swift <image> <required-value>... [--required-label <text>]... [--language <locale>] [--counter-row]\n", stderr)
    exit(2)
}

let imageURL = URL(fileURLWithPath: CommandLine.arguments[1])
let verifierArguments = Array(CommandLine.arguments.dropFirst(2))
var expectedValues: [String] = []
var requiredLabels: [String] = []
var requiresCounterRow = false
var recognitionLanguage: String?
var argumentIndex = 0
while argumentIndex < verifierArguments.count {
    switch verifierArguments[argumentIndex] {
    case "--counter-row":
        requiresCounterRow = true
        argumentIndex += 1
    case "--language", "--required-label":
        guard verifierArguments.indices.contains(argumentIndex + 1) else {
            fputs("Missing a value after \(verifierArguments[argumentIndex]).\n", stderr)
            exit(2)
        }
        let option = verifierArguments[argumentIndex]
        let value = verifierArguments[argumentIndex + 1]
        if option == "--language" {
            recognitionLanguage = value
        } else {
            requiredLabels.append(value)
        }
        argumentIndex += 2
    default:
        expectedValues.append(verifierArguments[argumentIndex])
        argumentIndex += 1
    }
}
guard !expectedValues.isEmpty else {
    fputs("At least one required visible value must be supplied.\n", stderr)
    exit(2)
}
let recognitionLanguages = recognitionLanguage == "ja-JP"
    ? ["ja-JP", "en-US"]
    : [recognitionLanguage ?? "en-US"]
let requests = recognitionLanguages.map { language in
    let request = VNRecognizeTextRequest()
    request.recognitionLevel = .accurate
    request.usesLanguageCorrection = false
    request.recognitionLanguages = [language]
    return request
}

do {
    try VNImageRequestHandler(url: imageURL).perform(requests)
    let observations = requests.enumerated().flatMap { requestIndex, request in
        (request.results ?? []).enumerated().compactMap { index, observation in
            observation.topCandidates(1).first.map {
                (
                    index: requestIndex * 1_000 + index,
                    language: recognitionLanguages[requestIndex],
                    text: $0.string,
                    confidence: $0.confidence,
                    bounds: observation.boundingBox
                )
            }
        }
    }
    let missingValues = expectedValues.filter { expected in
        let escapedValue = NSRegularExpression.escapedPattern(for: expected)
        let pattern = "(?<![0-9])\(escapedValue)(?![0-9])"
        return !observations.contains { observation in
            observation.confidence >= 0.5
                && observation.text.range(of: pattern, options: .regularExpression) != nil
        }
    }
    let missingLabels = requiredLabels.filter { expected in
        let escapedLabel = NSRegularExpression.escapedPattern(for: expected)
        return !observations.contains { observation in
            observation.confidence >= 0.25
                && observation.text.range(of: escapedLabel, options: .regularExpression) != nil
        }
    }
    let observationSummary = observations.map {
        "[\($0.language)] \($0.text)@\(String(format: "%.2f", $0.bounds.midY)) [confidence=\(String(format: "%.2f", $0.confidence))]"
    }.joined(separator: " | ")

    let containsToken: (String, String) -> Bool = { value, text in
        let escapedValue = NSRegularExpression.escapedPattern(for: value)
        let pattern = "(?<![0-9])\(escapedValue)(?![0-9])"
        return text.range(of: pattern, options: .regularExpression) != nil
    }
    let hasCountAndTargetOnSameRow: Bool = {
        guard requiresCounterRow else { return true }
        guard expectedValues.count >= 2 else { return false }
        let currentCount = expectedValues[0]
        let targetCount = expectedValues[1]
        let plausibleCounterRow: (CGRect) -> Bool = { (0.15...0.95).contains($0.midY) }
        let sameObservation = observations.contains { observation in
            guard observation.confidence >= 0.5, plausibleCounterRow(observation.bounds),
                  let currentRange = observation.text.range(of: "(?<![0-9])\(NSRegularExpression.escapedPattern(for: currentCount))(?![0-9])", options: .regularExpression),
                  let targetRange = observation.text.range(of: "(?<![0-9])\(NSRegularExpression.escapedPattern(for: targetCount))(?![0-9])", options: .regularExpression)
            else { return false }
            return currentRange.lowerBound < targetRange.lowerBound
        }
        if sameObservation { return true }

        let currentObservations = observations.filter {
            $0.confidence >= 0.5 && plausibleCounterRow($0.bounds) && containsToken(currentCount, $0.text)
        }
        let targetObservations = observations.filter {
            $0.confidence >= 0.5 && plausibleCounterRow($0.bounds) && containsToken(targetCount, $0.text)
        }
        return currentObservations.contains { current in
            targetObservations.contains { target in
                current.index != target.index
                    && abs(current.bounds.midY - target.bounds.midY) <= 0.06
                    && current.bounds.minX < target.bounds.minX
            }
        }
    }()

    guard missingValues.isEmpty, missingLabels.isEmpty, hasCountAndTargetOnSameRow else {
        let details = [
            missingValues.isEmpty ? nil : "Missing values: \(missingValues.joined(separator: ", ")).",
            missingLabels.isEmpty ? nil : "Missing labels: \(missingLabels.joined(separator: ", ")).",
            !hasCountAndTargetOnSameRow ? "Counter and target values were recognized but not together on the counter row." : nil,
        ].compactMap { $0 }.joined(separator: " ")
        fputs(
            "Simulator screenshot does not show the required visible content. \(details) "
                + "Recognized text: \(observationSummary)\n",
            stderr
        )
        exit(1)
    }

    print("Visible simulator screenshot values confirmed: \(expectedValues.joined(separator: ", ")).")
    if !requiredLabels.isEmpty {
        print("Visible simulator screenshot labels confirmed: \(requiredLabels.joined(separator: ", ")).")
    }
    print("Simulator screenshot OCR: \(observationSummary)")
} catch {
    fputs("Simulator home screenshot text recognition failed: \(error)\n", stderr)
    exit(1)
}
