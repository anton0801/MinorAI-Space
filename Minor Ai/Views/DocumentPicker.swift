//
//  DocumentPicker.swift
//  Minor Ai
//
//  The system file picker, presented from UIKit. SwiftUI's .fileImporter silently does nothing
//  when several screens that are on at once declare one (home, chat, new map), so they all use this.
//

import UIKit
import UniformTypeIdentifiers

@MainActor
enum DocumentPicker {
    // What Attachments.readDocument can read.
    static let documentTypes: [UTType] = [.pdf, .plainText, .rtf, .text]

    // Kept while the picker is open (the picker holds its delegate weakly).
    private static var delegate: Delegate?

    static func present(_ types: [UTType] = documentTypes, onPick: @escaping (URL) -> Void) {
        guard let top = topViewController() else { return }
        // A copy in the app's temporary folder, readable without security scoping.
        let picker = UIDocumentPickerViewController(forOpeningContentTypes: types, asCopy: true)
        let delegate = Delegate(onPick: onPick)
        picker.delegate = delegate
        picker.allowsMultipleSelection = false
        self.delegate = delegate
        top.present(picker, animated: true)
    }

    @MainActor
    private final class Delegate: NSObject, UIDocumentPickerDelegate {
        let onPick: (URL) -> Void
        init(onPick: @escaping (URL) -> Void) { self.onPick = onPick }

        func documentPicker(_ controller: UIDocumentPickerViewController, didPickDocumentsAt urls: [URL]) {
            if let url = urls.first { onPick(url) }
            DocumentPicker.delegate = nil
        }

        func documentPickerWasCancelled(_ controller: UIDocumentPickerViewController) {
            DocumentPicker.delegate = nil
        }
    }

    // The screen on top, to present system controllers from (also used by SystemShare).
    static func topViewController() -> UIViewController? {
        let scenes = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
        let scene = scenes.first { $0.activationState == .foregroundActive } ?? scenes.first
        var top = (scene?.windows.first { $0.isKeyWindow } ?? scene?.windows.first)?.rootViewController
        while let presented = top?.presentedViewController, !presented.isBeingDismissed { top = presented }
        return top
    }
}
