import Foundation
import Vision

guard CommandLine.arguments.count >= 3 else {
    fputs("Usage: verify_simulator_home_screenshot.swift <image> <required-value>...\n", stderr)
    exit(2)
}

let imageURL = URL(fileURLWithPath: CommandLine.arguments[1])
let expectedValues = Array(CommandLine.arguments.dropFirst(2))
let request = VNRecognizeTextRequest()
request.recognitionLevel = .accurate
request.usesLanguageCorrection = false

do {
    try VNImageRequestHandler(url: imageURL).perform([request])
    let observations = (request.results ?? []).compactMap { observation in
        observation.topCandidates(1).first.map { (text: $0.string, confidence: $0.confidence) }
    }
    let missingValues = expectedValues.filter { expected in
        let escapedValue = NSRegularExpression.escapedPattern(for: expected)
        let pattern = "(?<![0-9])\(escapedValue)(?![0-9])"
        return !observations.contains { observation in
            observation.confidence >= 0.5
                && observation.text.range(of: pattern, options: .regularExpression) != nil
        }
    }
    let observationSummary = observations.map {
        "\($0.text) [confidence=\(String(format: "%.2f", $0.confidence))]"
    }.joined(separator: " | ")

    guard missingValues.isEmpty else {
        fputs(
            "Simulator home screenshot is missing visible values \(missingValues.joined(separator: ", ")). "
                + "Recognized text: \(observationSummary)\n",
            stderr
        )
        exit(1)
    }

    print("Visible simulator home values confirmed: \(expectedValues.joined(separator: ", ")).")
    print("Simulator screenshot OCR: \(observationSummary)")
} catch {
    fputs("Simulator home screenshot text recognition failed: \(error)\n", stderr)
    exit(1)
}
