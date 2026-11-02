import Foundation
import Vision

guard CommandLine.arguments.count == 4 else {
    fputs("Usage: verify_watch_screenshot.swift <image> <current-count> <target-count>\n", stderr)
    exit(2)
}

let imageURL = URL(fileURLWithPath: CommandLine.arguments[1])
let expectedValues = Array(CommandLine.arguments.dropFirst(2))
let request = VNRecognizeTextRequest()
request.recognitionLevel = .accurate
request.usesLanguageCorrection = false

do {
    try VNImageRequestHandler(url: imageURL).perform([request])
    let observations = request.results ?? []
    let recognizedText = observations.compactMap { observation in
        observation.topCandidates(1).first.map { (text: $0.string, bounds: observation.boundingBox) }
    }
    let missingValues = expectedValues.enumerated().compactMap { index, expected -> String? in
        let requiredVerticalRange: ClosedRange<CGFloat> = index == 0 ? 0.40...0.75 : 0.10...0.42
        let isVisible = recognizedText.contains { item in
            item.text.filter(\.isNumber) == expected && requiredVerticalRange.contains(item.bounds.midY)
        }
        return isVisible ? nil : expected
    }
    let observationSummary = recognizedText.map {
        "\($0.text)@\(String(format: "%.2f", $0.bounds.midY))"
    }.joined(separator: " | ")
    guard missingValues.isEmpty else {
        fputs(
            "Watch screenshot is missing visible counter values \(missingValues.joined(separator: ", ")). "
                + "Recognized text with vertical positions: \(observationSummary)\n",
            stderr
        )
        exit(1)
    }

    print("Visible Watch counter values confirmed: \(expectedValues.joined(separator: ", ")).")
    print("Watch screenshot OCR: \(observationSummary)")
} catch {
    fputs("Watch screenshot text recognition failed: \(error)\n", stderr)
    exit(1)
}
