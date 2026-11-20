import Foundation
import Darwin
import Vision

guard CommandLine.arguments.count == 2 else {
    fputs("Usage: verify_watch_screenshot.swift <screenshot.jpg>\n", stderr)
    exit(2)
}

let imageURL = URL(fileURLWithPath: CommandLine.arguments[1])
let request = VNRecognizeTextRequest()
request.recognitionLevel = .accurate
request.usesLanguageCorrection = false
request.recognitionLanguages = ["en-US"]
request.customWords = ["286", "300"]

do {
    let handler = VNImageRequestHandler(url: imageURL, options: [:])
    try handler.perform([request])
    let recognizedText = (request.results ?? [])
        .compactMap { $0.topCandidates(1).first?.string }
        .joined(separator: " ")
    let recognizedNumbers = recognizedText
        .split { !$0.isNumber }
        .map(String.init)

    let missingValues = ["286", "300"].filter { !recognizedNumbers.contains($0) }
    guard missingValues.isEmpty else {
        fputs(
            "Apple Watch screenshot is missing expected demo values: \(missingValues.joined(separator: ", ")). OCR: \(recognizedText)\n",
            stderr
        )
        exit(1)
    }

    print("PASS: Apple Watch screenshot visibly contains counter 286 and target 300.")
} catch {
    fputs("Could not inspect Apple Watch screenshot text: \(error)\n", stderr)
    exit(1)
}
