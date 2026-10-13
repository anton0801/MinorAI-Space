//
//  SystemShare.swift
//  Minor Ai
//
//  The system share sheet, presented from UIKit over whatever is on screen (like DocumentPicker).
//  SwiftUI's ShareLink did nothing in Invite Friends on iOS 26, where that screen is a sheet,
//  sometimes over the Settings sheet.
//

import UIKit

@MainActor
enum SystemShare {
    static func present(text: String, url: URL, subject: String) {
        guard let top = DocumentPicker.topViewController() else { return }
        let controller = UIActivityViewController(activityItems: [Item(text, subject: subject), Item(url, subject: subject)], applicationActivities: nil)
        // iPad shows it as a popover, which needs an anchor: the middle of the screen.
        if let popover = controller.popoverPresentationController {
            popover.sourceView = top.view
            popover.sourceRect = CGRect(x: top.view.bounds.midX, y: top.view.bounds.midY, width: 0, height: 0)
            popover.permittedArrowDirections = []
        }
        top.present(controller, animated: true)
    }

    // A kept file under its own name (originals are stored under their hash).
    static func present(file: URL, name: String) {
        guard let top = DocumentPicker.topViewController() else { return }
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("Share", isDirectory: true)
        try? FileManager.default.removeItem(at: folder)
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let safe = name.replacingOccurrences(of: "/", with: "-")
        let named = folder.appendingPathComponent(safe.isEmpty ? file.lastPathComponent : safe)
        guard (try? FileManager.default.copyItem(at: file, to: named)) != nil else { return }
        let controller = UIActivityViewController(activityItems: [named], applicationActivities: nil)
        if let popover = controller.popoverPresentationController {
            popover.sourceView = top.view
            popover.sourceRect = CGRect(x: top.view.bounds.midX, y: top.view.bounds.midY, width: 0, height: 0)
            popover.permittedArrowDirections = []
        }
        top.present(controller, animated: true)
    }

    // A shared item that also gives Mail its subject.
    private final class Item: NSObject, UIActivityItemSource {
        let value: Any
        let subject: String

        init(_ value: Any, subject: String) {
            self.value = value
            self.subject = subject
        }

        func activityViewControllerPlaceholderItem(_ controller: UIActivityViewController) -> Any { value }

        func activityViewController(_ controller: UIActivityViewController, itemForActivityType type: UIActivity.ActivityType?) -> Any? { value }

        func activityViewController(_ controller: UIActivityViewController, subjectForActivityType type: UIActivity.ActivityType?) -> String { subject }
    }
}
