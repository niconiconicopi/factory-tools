import Foundation
import Vision

guard CommandLine.arguments.count == 4 else {
    fputs("Usage: verify_watch_screenshot.swift <image> <scenario> <ja|en>\n", stderr)
    exit(2)
}

let imageURL = URL(fileURLWithPath: CommandLine.arguments[1])
let scenario = CommandLine.arguments[2]
let language = CommandLine.arguments[3]
guard ["counter", "cycle-time", "production-progress"].contains(scenario),
      ["ja", "en"].contains(language) else {
    fputs("Unsupported Watch screenshot scenario or language.\n", stderr)
    exit(2)
}

let expectedTitle: String?
switch (scenario, language) {
case ("cycle-time", "ja"): expectedTitle = "サイクルタイム"
case ("cycle-time", "en"): expectedTitle = "Cycle Time"
case ("production-progress", "ja"): expectedTitle = "生産進捗"
case ("production-progress", "en"): expectedTitle = "Production Progress"
default: expectedTitle = nil
}

let request = VNRecognizeTextRequest()
request.recognitionLevel = .accurate
request.usesLanguageCorrection = false
request.recognitionLanguages = language == "ja" ? ["ja-JP"] : ["en-US"]

func normalized(_ value: String) -> String {
    value.lowercased().filter { $0.isLetter || $0.isNumber }
}

do {
    try VNImageRequestHandler(url: imageURL).perform([request])
    let observations = request.results ?? []
    let recognizedText = observations.compactMap { observation in
        observation.topCandidates(3).map { candidate in
            (text: candidate.string, bounds: observation.boundingBox)
        }
    }.flatMap { $0 }
    let numericChecks: [(expected: String, range: ClosedRange<CGFloat>)]
    switch scenario {
    case "counter":
        numericChecks = [("286", 0.36...0.84), ("300", 0.08...0.52)]
    case "production-progress":
        // The target value is intentionally shown near the bottom edge of the
        // compact progress view, so Vision reports a low normalized midY.
        numericChecks = [("286", 0.36...0.84), ("300", 0.0...0.52)]
    case "cycle-time":
        numericChecks = [("278", 0.20...0.82)]
    default:
        numericChecks = []
    }
    let missingValues = numericChecks.compactMap { check -> String? in
        let isVisible = recognizedText.contains { item in
            item.text.filter(\.isNumber) == check.expected && check.range.contains(item.bounds.midY)
        }
        return isVisible ? nil : check.expected
    }
    let titleIsVisible = expectedTitle.map { expected in
        recognizedText.contains { normalized($0.text).contains(normalized(expected)) }
    } ?? true
    let observationSummary = recognizedText.map {
        "\($0.text)@\(String(format: "%.2f", Double($0.bounds.midY)))"
    }.joined(separator: " | ")
    guard missingValues.isEmpty, titleIsVisible else {
        let missingTitle = titleIsVisible ? "" : "localized title \(expectedTitle ?? "")"
        let missingCount = missingValues.isEmpty ? "" : "numeric content \(missingValues.joined(separator: ", "))"
        fputs(
            "Watch \(scenario) screenshot is missing \(missingTitle) \(missingCount). "
                + "Recognized text with vertical positions: \(observationSummary)\n",
            stderr
        )
        exit(1)
    }

    print("Visible Watch \(scenario) screen confirmed in \(language).")
    print("Watch screenshot OCR: \(observationSummary)")
} catch {
    fputs("Watch screenshot text recognition failed: \(error)\n", stderr)
    exit(1)
}
