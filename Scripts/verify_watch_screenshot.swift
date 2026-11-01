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
    let recognizedText = (request.results ?? [])
        .compactMap { $0.topCandidates(1).first?.string }
    let recognizedDigits = recognizedText.joined().filter(\.isNumber)
    let missingValues = expectedValues.filter { !recognizedDigits.contains($0) }
    guard missingValues.isEmpty else {
        fputs(
            "Watch screenshot is missing visible counter values \(missingValues.joined(separator: ", ")). "
                + "Recognized text: \(recognizedText.joined(separator: " | "))\n",
            stderr
        )
        exit(1)
    }

    print("Visible Watch counter values confirmed: \(expectedValues.joined(separator: ", ")).")
} catch {
    fputs("Watch screenshot text recognition failed: \(error)\n", stderr)
    exit(1)
}
