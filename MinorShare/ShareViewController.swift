//
//  ShareViewController.swift
//  MinorShare
//
//  "Minor" in the share sheet: a page from Safari or text from any app is kept in the app
//  group's inbox; the next time Minor opens it offers to build a map from it.
//

import SwiftUI
import UIKit
import UniformTypeIdentifiers

final class ShareViewController: UIViewController {
    override func viewDidLoad() {
        super.viewDidLoad()
        let model = ShareModel(context: extensionContext)
        let host = UIHostingController(rootView: ShareView(model: model))
        host.view.backgroundColor = .clear
        addChild(host)
        host.view.frame = view.bounds
        host.view.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        view.addSubview(host.view)
        host.didMove(toParent: self)
        Task { await model.load() }
    }
}

@MainActor
final class ShareModel: ObservableObject {
    @Published var item = SharedItem()
    @Published var loading = true
    @Published var saved = false
    @Published var failed = false

    private weak var context: NSExtensionContext?

    init(context: NSExtensionContext?) {
        self.context = context
    }

    var ru: Bool { Locale.preferredLanguages.first?.hasPrefix("ru") == true }

    func load() async {
        defer { loading = false }
        let items = context?.inputItems.compactMap { $0 as? NSExtensionItem } ?? []
        for extensionItem in items {
            if item.title == nil, let title = extensionItem.attributedContentText?.string, !title.isEmpty {
                item.title = String(title.prefix(200))
            }
            for provider in extensionItem.attachments ?? [] {
                if item.url == nil, provider.hasItemConformingToTypeIdentifier(UTType.url.identifier),
                   let url = try? await provider.loadItem(forTypeIdentifier: UTType.url.identifier) as? URL,
                   url.scheme?.hasPrefix("http") == true {
                    item.url = url.absoluteString
                } else if item.text == nil, provider.hasItemConformingToTypeIdentifier(UTType.plainText.identifier),
                          let text = try? await provider.loadItem(forTypeIdentifier: UTType.plainText.identifier) as? String {
                    // A link shared as text is still a link.
                    let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
                    if item.url == nil, let url = URL(string: trimmed), url.scheme?.hasPrefix("http") == true, !trimmed.contains(" ") {
                        item.url = trimmed
                    } else {
                        item.text = String(trimmed.prefix(200_000))
                    }
                }
            }
        }
        failed = item.url == nil && (item.text ?? "").isEmpty
    }

    func save() {
        do {
            try item.save()
            saved = true
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) { [weak self] in
                self?.context?.completeRequest(returningItems: nil)
            }
        } catch {
            failed = true
        }
    }

    func cancel() {
        context?.cancelRequest(withError: CocoaError(.userCancelled))
    }
}

struct ShareView: View {
    @ObservedObject var model: ShareModel
    private let accent = Color(red: 47 / 255, green: 1, blue: 158 / 255)

    var body: some View {
        VStack {
            Spacer()
            VStack(alignment: .leading, spacing: 14) {
                HStack {
                    Text(model.ru ? "Карта в Minor" : "Map in Minor")
                        .font(.system(size: 18, weight: .bold))
                    Spacer()
                    Button(model.ru ? "Отмена" : "Cancel") { model.cancel() }
                        .foregroundColor(.white.opacity(0.7))
                }
                if model.loading {
                    ProgressView().tint(.white)
                } else if model.saved {
                    Label(model.ru ? "Сохранено. Откройте Minor — карта построится в один тап." : "Saved. Open Minor to build the map in one tap.",
                          systemImage: "checkmark.circle.fill")
                        .foregroundColor(accent)
                        .font(.system(size: 15, weight: .medium))
                } else if model.failed {
                    Text(model.ru ? "Здесь нет ссылки или текста, из которых можно сделать карту." : "There’s no link or text here to make a map from.")
                        .font(.system(size: 15))
                        .foregroundColor(.white.opacity(0.7))
                } else {
                    VStack(alignment: .leading, spacing: 4) {
                        if let title = model.item.title {
                            Text(title).font(.system(size: 15, weight: .semibold)).lineLimit(2)
                        }
                        if let url = model.item.url {
                            Text(URL(string: url)?.host ?? url).font(.system(size: 13)).foregroundColor(.white.opacity(0.55)).lineLimit(1)
                        } else if let text = model.item.text {
                            Text(text).font(.system(size: 13)).foregroundColor(.white.opacity(0.7)).lineLimit(4)
                        }
                    }
                    Button { model.save() } label: {
                        Text(model.ru ? "Сделать карту" : "Make a Map")
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundColor(.black)
                            .frame(maxWidth: .infinity)
                            .frame(height: 48)
                            .background(Capsule().fill(accent))
                    }
                }
            }
            .foregroundColor(.white)
            .padding(20)
            .background(RoundedRectangle(cornerRadius: 22).fill(Color(red: 0.11, green: 0.11, blue: 0.12)))
            .padding(12)
        }
        .preferredColorScheme(.dark)
    }
}
