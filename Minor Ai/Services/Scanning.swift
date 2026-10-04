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
    // Text of every page, in reading order, pages separated by a blank line. One page at a time,
    // off the main thread: reading them all at once could run out of memory.
    static func text(from images: [UIImage]) async -> String {
        await Task.detached(priority: .userInitiated) {
            images.map { recognize($0) }.filter { !$0.isEmpty }.joined(separator: "\n\n")
        }.value
    }

    private static func recognize(_ image: UIImage) -> String {
        guard let cgImage = image.cgImage else { return "" }
        let request = VNRecognizeTextRequest()
        request.recognitionLevel = .accurate
        request.usesLanguageCorrection = true
        request.recognitionLanguages = ["ru-RU", "en-US"]
        let handler = VNImageRequestHandler(cgImage: cgImage, orientation: CGImagePropertyOrientation(image.imageOrientation))
        try? handler.perform([request])
        let lines = (request.results ?? []).compactMap { $0.topCandidates(1).first?.string }
        return lines.joined(separator: "\n")
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
