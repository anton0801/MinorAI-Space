//
//  MapMentions.swift
//  Minor Ai
//
//  "@" in a message attaches one of the person's maps: a list of maps appears above the field,
//  and the picked map's outline goes to the assistant with the message. Also the card the chat
//  shows when the assistant changed, opened or illustrated a map.
//

import SwiftUI

enum Mentions {
    // The text after the last "@" that starts a word, while it can still name a map; nil when there
    // is no mention being typed (or it is one already picked).
    static func query(in text: String, picked: [MapMention]) -> String? {
        guard let at = text.lastIndex(of: "@") else { return nil }
        if at != text.startIndex, !text[text.index(before: at)].isWhitespace { return nil }
        let query = String(text[text.index(after: at)...])
        guard query.count <= 40, !query.contains("\n") else { return nil }
        if picked.contains(where: { query.hasPrefix($0.title) }) { return nil }
        return query
    }

    // Maps whose titles contain the query (all of them for a bare "@"), at most five.
    static func matches(_ query: String, in maps: [MindMap]) -> [MindMap] {
        let wanted = query.trimmingCharacters(in: .whitespaces).lowercased()
        let found = wanted.isEmpty ? maps : maps.filter { $0.title.lowercased().contains(wanted) }
        let ordered = found.filter(\.isPinned) + found.filter { !$0.isPinned }
        return Array(ordered.prefix(5))
    }

    // Replaces the mention being typed with "@Title ".
    static func insert(_ map: MindMap, into text: String) -> String {
        guard let at = text.lastIndex(of: "@") else { return text + "@\(map.title) " }
        return String(text[..<at]) + "@\(map.title) "
    }

    // Picked maps that are still mentioned in the text.
    static func used(_ picked: [MapMention], in text: String) -> [MapMention] {
        picked.filter { text.contains("@" + $0.title) }
    }
}

struct MentionSuggestions: View {
    let maps: [MindMap]
    let theme: AppTheme
    var onPick: (MindMap) -> Void

    var body: some View {
        VStack(spacing: 0) {
            ForEach(maps) { map in
                Button { onPick(map) } label: {
                    HStack(spacing: 10) {
                        Image(systemName: map.isPinned ? "pin.fill" : "point.3.connected.trianglepath.dotted")
                            .font(.system(size: 14))
                            .foregroundColor(MinorColor.accent)
                            .frame(width: 22)
                        Text(map.title)
                            .font(.system(size: 16))
                            .foregroundColor(.white)
                            .lineLimit(1)
                        Spacer(minLength: 8)
                        Text(L("\(map.nodeCount) ideas"))
                            .font(.system(size: 13))
                            .foregroundColor(MinorColor.textTertiary)
                    }
                    .padding(.horizontal, 14)
                    .frame(minHeight: 44)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Attach map \(map.title)")
                if map.id != maps.last?.id {
                    Divider().overlay(theme.chatStroke).padding(.leading, 46)
                }
            }
        }
        .padding(.vertical, 4)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(theme.chatRectangle)
                .overlay(RoundedRectangle(cornerRadius: 16).stroke(theme.chatStroke, lineWidth: 1))
        )
        .padding(.horizontal, 16)
        .padding(.bottom, 8)
        .transition(.move(edge: .bottom).combined(with: .opacity))
    }
}

// What the assistant did in a map, with Open, Undo or Create Images.
struct ActionCard: View {
    let action: ChatAction
    let theme: AppTheme
    let canUndo: Bool
    let mapExists: Bool
    var onOpen: () -> Void
    var onUndo: () -> Void
    var onCreateImages: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top, spacing: 10) {
                Image(systemName: icon)
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundColor(MinorColor.accent)
                    .frame(width: 24, height: 24)
                VStack(alignment: .leading, spacing: 3) {
                    Text(headline)
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundColor(.white)
                    Text(detail)
                        .font(.system(size: 13))
                        .foregroundColor(MinorColor.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            HStack(spacing: 8) {
                if action.kind == .images, action.imagesDone == nil {
                    pill(L("Create \(action.imageNodes?.count ?? 0) Images"), primary: true, action: onCreateImages)
                }
                if action.kind == .images, let done = action.imagesDone, done < (action.imageNodes?.count ?? 0), action.imagesFailed != true {
                    ProgressView().tint(.white).padding(.horizontal, 4)
                }
                if mapExists {
                    pill(L("Open"), primary: false, action: onOpen)
                }
                if canUndo {
                    pill(L("Undo"), primary: false, action: onUndo)
                }
            }
        }
        .padding(14)
        .frame(maxWidth: 320, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(theme.chatRectangle)
                .overlay(RoundedRectangle(cornerRadius: 16).stroke(theme.chatStroke, lineWidth: 1))
        )
        .accessibilityElement(children: .contain)
    }

    private var icon: String {
        switch action.kind {
        case .edited: return action.undone == true ? "arrow.uturn.backward" : "wand.and.stars"
        case .images: return "photo.on.rectangle.angled"
        case .opened: return "point.3.connected.trianglepath.dotted"
        case .deckCreated, .deckOpened: return "rectangle.on.rectangle.angled"
        case .deckEdited: return action.undone == true ? "arrow.uturn.backward" : "rectangle.stack.badge.plus"
        }
    }

    private var headline: String {
        switch action.kind {
        case .edited: return action.undone == true ? L("Change undone") : L("Map updated")
        case .opened: return L("Opened map")
        case .deckCreated: return L("Presentation ready")
        case .deckEdited: return action.undone == true ? L("Change undone") : L("Presentation updated")
        case .deckOpened: return L("Opened presentation")
        case .images:
            let total = action.imageNodes?.count ?? 0
            guard let done = action.imagesDone else { return L("Pictures for \(total) ideas?") }
            if action.imagesFailed == true { return L("Stopped after \(done) pictures") }
            return done < total ? L("Creating pictures: \(done) of \(total)") : L("Added \(done) pictures")
        }
    }

    private var detail: String {
        let title = "“\(action.mapTitle)”"
        switch action.kind {
        case .edited where action.undone != true && !action.summary.isEmpty,
             .deckEdited where action.undone != true && !action.summary.isEmpty,
             .deckCreated where !action.summary.isEmpty:
            return "\(title) · \(action.summary)"
        case .images where action.imagesDone == nil:
            return L("In \(title). Each uses one of your monthly AI images.")
        default:
            return mapExists ? title : L("\(title) was deleted")
        }
    }

    private func pill(_ title: String, primary: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 14, weight: .semibold))
                .foregroundColor(primary ? .black : .white)
                .padding(.horizontal, 14)
                .frame(minHeight: 34)
                .background(Capsule().fill(primary ? MinorColor.accent : Color.clear))
                .overlay(Capsule().stroke(primary ? Color.clear : theme.chatStroke, lineWidth: 1))
                .contentShape(Capsule())
        }
        .buttonStyle(.plain)
    }
}
