import Foundation
import Darwin
import Vision

guard CommandLine.arguments.count == 3 else {
    fputs("Usage: verify_store_home_title.swift <screenshot.jpg> <expected-app-name>\n", stderr)
    exit(2)
}

let imageURL = URL(fileURLWithPath: CommandLine.arguments[1])
let expectedTitle = CommandLine.arguments[2]
let request = VNRecognizeTextRequest()
request.recognitionLevel = .accurate
request.usesLanguageCorrection = false
request.recognitionLanguages = expectedTitle == "現場ギア" ? ["ja-JP"] : ["en-US"]
request.customWords = [expectedTitle]

do {
    let handler = VNImageRequestHandler(url: imageURL, options: [:])
    try handler.perform([request])
    let recognizedText = (request.results ?? [])
        .compactMap { $0.topCandidates(1).first?.string }
        .joined(separator: " ")
        .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)

    guard recognizedText.localizedCaseInsensitiveContains(expectedTitle) else {
        fputs("Screenshot does not show the expected localized app name ‘\(expectedTitle)’. OCR: \(recognizedText)\n", stderr)
        exit(1)
    }

    print("PASS: App Store home screenshot shows the localized app name ‘\(expectedTitle)’.")
} catch {
    fputs("Could not inspect the localized app name in the screenshot: \(error)\n", stderr)
    exit(1)
}
