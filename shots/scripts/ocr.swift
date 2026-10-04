import Foundation
import Vision
import ImageIO

// Read-only OCR QA: retains text and normalized bounding boxes for each real capture.
let root = URL(fileURLWithPath: CommandLine.arguments[1], isDirectory: true)
let output = URL(fileURLWithPath: CommandLine.arguments[2])
let files = FileManager.default.enumerator(at: root, includingPropertiesForKeys: nil)!.compactMap { $0 as? URL }.filter { $0.pathExtension == "png" }.sorted { $0.path < $1.path }
var reports: [[String: Any]] = []
for file in files {
    let request = VNRecognizeTextRequest()
    request.recognitionLevel = .accurate
    request.recognitionLanguages = ["en-US", "ru-RU"]
    request.usesLanguageCorrection = false
    try VNImageRequestHandler(url: file).perform([request])
    let rows: [[String: Any]] = (request.results ?? []).compactMap { item in
        guard let text = item.topCandidates(1).first else { return nil }
        return ["text": text.string, "confidence": text.confidence,
                "bounds": [item.boundingBox.minX,item.boundingBox.minY,item.boundingBox.width,item.boundingBox.height]]
    }
    reports.append(["file": file.path, "text": rows])
}
let data = try JSONSerialization.data(withJSONObject: reports, options: [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes])
try data.write(to: output)
print("OCR checked \(files.count) images")
