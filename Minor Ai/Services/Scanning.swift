//
//  Scanning.swift
//  Minor Ai
//
//  Text from photos and scans (notes, lecture slides, a whiteboard), recognized on the iPhone
//  with Vision, and the system document camera.
//

import SwiftUI
import Vision
import VisionKit

enum TextRecognizer {
    // A recognized line: its text, its box on the page (0…1 from the top left) and how sure Vision was.
    struct Line: Equatable {
        let text: String
        let box: CGRect
        let confidence: Double
    }

    // Text of every page, in reading order, pages separated by a blank line. One page at a time,
    // off the main thread: reading them all at once could run out of memory.
    static func text(from images: [UIImage]) async -> String {
        await lines(from: images).map { $0.map(\.text).joined(separator: "\n") }.filter { !$0.isEmpty }.joined(separator: "\n\n")
    }

    // The lines of every page with where they are, for quoting a scan with its place.
    static func lines(from images: [UIImage]) async -> [[Line]] {
        await Task.detached(priority: .userInitiated) {
            images.map { image in autoreleasepool { recognize(image) } }
        }.value
    }

    private static func recognize(_ image: UIImage) -> [Line] {
        guard let cgImage = image.cgImage else { return [] }
        let request = VNRecognizeTextRequest()
        request.recognitionLevel = .accurate
        request.usesLanguageCorrection = true
        request.recognitionLanguages = ["ru-RU", "en-US"]
        let handler = VNImageRequestHandler(cgImage: cgImage, orientation: CGImagePropertyOrientation(image.imageOrientation))
        try? handler.perform([request])
        return (request.results ?? []).compactMap { observation in
            guard let best = observation.topCandidates(1).first else { return nil }
            let text = best.string.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !text.isEmpty else { return nil }
            // Vision measures from the bottom left; pages are drawn from the top left.
            let box = observation.boundingBox
            return Line(text: text, box: CGRect(x: box.minX, y: 1 - box.maxY, width: box.width, height: box.height), confidence: Double(best.confidence))
        }
    }
}

extension CGImagePropertyOrientation {
    init(_ orientation: UIImage.Orientation) {
        switch orientation {
        case .up: self = .up
        case .down: self = .down
        case .left: self = .left
        case .right: self = .right
        case .upMirrored: self = .upMirrored
        case .downMirrored: self = .downMirrored
        case .leftMirrored: self = .leftMirrored
        case .rightMirrored: self = .rightMirrored
        @unknown default: self = .up
        }
    }
}

// The system document camera: finds the page edges and straightens each scan.
struct DocumentScanner: UIViewControllerRepresentable {
    var onFinish: ([UIImage]) -> Void

    static var isAvailable: Bool { VNDocumentCameraViewController.isSupported }

    func makeUIViewController(context: Context) -> VNDocumentCameraViewController {
        let controller = VNDocumentCameraViewController()
        controller.delegate = context.coordinator
        return controller
    }

    func updateUIViewController(_ controller: VNDocumentCameraViewController, context: Context) {}

    func makeCoordinator() -> Coordinator { Coordinator(onFinish: onFinish) }

    final class Coordinator: NSObject, VNDocumentCameraViewControllerDelegate {
        let onFinish: ([UIImage]) -> Void
        init(onFinish: @escaping ([UIImage]) -> Void) { self.onFinish = onFinish }

        // At most 30 pages, each made smaller as it's taken, so a long scan can't exhaust memory.
        func documentCameraViewController(_ controller: VNDocumentCameraViewController, didFinishWith scan: VNDocumentCameraScan) {
            onFinish((0..<min(scan.pageCount, 30)).map { index in
                autoreleasepool { Attachments.downsampled(scan.imageOfPage(at: index), maxPixels: 2_500) }
            })
        }

        func documentCameraViewControllerDidCancel(_ controller: VNDocumentCameraViewController) {
            onFinish([])
        }

        func documentCameraViewController(_ controller: VNDocumentCameraViewController, didFailWithError error: Error) {
            onFinish([])
        }
    }
}
