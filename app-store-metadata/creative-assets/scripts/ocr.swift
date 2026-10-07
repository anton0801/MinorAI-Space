import Foundation
import Vision
import ImageIO

// Read-only OCR of the six final files; previews and sources are excluded.
let root = URL(fileURLWithPath: CommandLine.arguments[1], isDirectory: true)
var reports: [[String: Any]] = []
for language in ["en-US", "ru"] {
    for name in ["header.jpg", "header.png", "search.jpg"] {
        let file = root.appendingPathComponent(language).appendingPathComponent(name)
        let request = VNRecognizeTextRequest()
        request.recognitionLevel = .accurate
        request.recognitionLanguages = ["en-US", "ru-RU"]
        request.usesLanguageCorrection = false
        try VNImageRequestHandler(url: file).perform([request])
        let rows: [[String: Any]] = (request.results ?? []).compactMap { item in
            guard let text = item.topCandidates(1).first else { return nil }
            return ["text": text.string, "confidence": text.confidence,
                    "bounds": [item.boundingBox.minX, item.boundingBox.minY, item.boundingBox.width, item.boundingBox.height]]
        }
        reports.append(["file": "\(language)/\(name)", "text": rows])
    }
}
let data = try JSONSerialization.data(withJSONObject: reports, options: [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes])
try data.write(to: root.appendingPathComponent("ocr-report.json"))
print("OCR checked \(reports.count) final files")
