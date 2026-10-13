//
//  MenuView.swift
//  Minor Ai
//
//  The screen behind the Menu button on the assistant: four places to go (New Map,
//  Presentation, Today, Library), templates, the last documents and settings. It rises from
//  the bottom over the assistant; its places push onto its own stack and come back to it with the
//  scroll position kept. Opened from the assistant's "Create a Map", the stack starts at New Map
//  and Back goes straight back to the assistant.
//

import SwiftUI

enum MenuDestination: Hashable {
    case newMap
    case library        // the tab is LibraryState's
    case today
    case templates(TemplateLibraryTab)
}

enum LibraryTab: String, Hashable { case maps, decks, chats }
enum TemplateLibraryTab: Hashable { case maps, decks }

struct MenuView<Destination: View>: View {
    let theme: AppTheme
    @Binding var path: [MenuDestination]
    // True while the menu is on screen; the groups come in only when it opens.
    let isOpen: Bool
    var onClose: () -> Void
    var onNewDeck: () -> Void
    var onOpenMap: (UUID) -> Void
    var onOpenDeck: (UUID) -> Void
    var onOpenJob: (UUID) -> Void
    var onSettings: () -> Void
    @ViewBuilder var destination: (MenuDestination) -> Destination

    @ObservedObject private var maps = MapStore.shared
    @ObservedObject private var decks = DeckStore.shared
    @ObservedObject private var recents = RecentDocuments.shared
    @ObservedObject private var generation = GenerationCenter.shared
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @AccessibilityFocusState private var titleFocused: Bool
    @State private var entered = false
    @State private var accent = false
    @State private var thumbnails = false
    // The current value of isOpen for delayed work (a captured `let` would be stale).
    @State private var open = false

    var body: some View {
        NavigationStack(path: $path) {
            root
                .navigationTitle(Text("Menu"))
                .toolbar(.hidden, for: .navigationBar)
                .navigationDestination(for: MenuDestination.self) { place in
                    destination(place)
                        .toolbarBackground(theme.background, for: .navigationBar)
                        .toolbarColorScheme(.dark, for: .navigationBar)
                }
        }
        .tint(.white)
        .onChange(of: isOpen) { value in
            open = value
            if value { enter() } else { leave() }
        }
        .onAppear {
            open = isOpen
            if isOpen { enter() }
        }
    }

    // MARK: - Root

    private var root: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: 0) {
                header
                    .stage(entered, delay: 0.07, duration: 0.12, rise: 8, reduceMotion: reduceMotion)

                LazyVGrid(columns: [GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12)], spacing: 12) {
                    tile("point.3.connected.trianglepath.dotted", "New Map", L("From a topic or material")) { go(.newMap) }
                    tile("rectangle.on.rectangle.angled", "Presentation", L("From a map or from scratch")) {
                        guard path.isEmpty else { return }
                        onNewDeck()
                    }
                    tile("calendar", "Today", todayDetail, highlight: dueCount > 0) { go(.today) }
                    tile("books.vertical", "Library", L("Maps, slides and chats")) { go(.library) }
                }
                .padding(.top, 20)
                .stage(entered, delay: 0.10, duration: 0.14, rise: 12, reduceMotion: reduceMotion)

                templatesRow
                    .padding(.top, 12)
                    .stage(entered, delay: 0.135, duration: 0.14, rise: 10, reduceMotion: reduceMotion)

                VStack(alignment: .leading, spacing: 0) {
                    continueSection
                    settingsRow.padding(.top, 28)
                }
                .stage(entered, delay: 0.17, duration: 0.13, rise: 10, reduceMotion: reduceMotion)
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 24)
        }
        .background(theme.background.ignoresSafeArea())
        .overlay(alignment: .top) {
            // A faint mint wash along the top edge as the menu arrives, then gone.
            LinearGradient(colors: [MinorColor.accent.opacity(0.5), .clear], startPoint: .top, endPoint: .bottom)
                .frame(height: 120)
                .opacity(accent ? 0.06 / 0.5 : 0)
                .ignoresSafeArea(edges: .top)
                .allowsHitTesting(false)
                .accessibilityHidden(true)
        }
        .foregroundColor(MinorColor.textPrimary)
    }

    private var header: some View {
        HStack(alignment: .center) {
            Text("Menu")
                .minorFont(34, .bold, style: .largeTitle, maxScale: 1.3)
                .accessibilityAddTraits(.isHeader)
                .accessibilityFocused($titleFocused)
            Spacer(minLength: 12)
            Button(action: onClose) {
                Image(systemName: "xmark")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundColor(.white)
                    .frame(width: 34, height: 34)
                    .background(Circle().fill(theme.chatRectangle))
                    .overlay(Circle().stroke(theme.chatStroke, lineWidth: 1))
                    .frame(width: 44, height: 44)
                    .contentShape(Rectangle())
            }
            .accessibilityLabel("Back to Assistant")
        }
        .padding(.top, 8)
    }

    private func tile(_ icon: String, _ title: LocalizedStringKey, _ detail: String, highlight: Bool = false, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 10) {
                Image(systemName: icon)
                    .font(.system(size: 20))
                    .foregroundColor(highlight ? MinorColor.accent : .white)
                    .frame(height: 24, alignment: .leading)
                VStack(alignment: .leading, spacing: 3) {
                    Text(title)
                        .minorFont(16, .semibold, maxScale: 1.4)
                        .fixedSize(horizontal: false, vertical: true)
                    Text(detail)
                        .minorFont(13, style: .footnote, maxScale: 1.4)
                        .foregroundColor(highlight ? MinorColor.accent : MinorColor.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 0)
            }
            .frame(maxWidth: .infinity, minHeight: 104, alignment: .topLeading)
            .padding(14)
            .background(RoundedRectangle(cornerRadius: 16).fill(theme.chatRectangle))
            .overlay(RoundedRectangle(cornerRadius: 16).stroke(highlight ? MinorColor.accent.opacity(0.6) : theme.chatStroke, lineWidth: 1))
            .contentShape(RoundedRectangle(cornerRadius: 16))
        }
        .buttonStyle(PressScale())
        .accessibilityElement(children: .combine)
    }

    private var templatesRow: some View {
        Button { go(.templates(.maps)) } label: {
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 3) {
                    Text("Templates").minorFont(16, .semibold, maxScale: 1.4)
                    Text("Ready structures for maps and slides")
                        .minorFont(13, style: .footnote, maxScale: 1.4)
                        .foregroundColor(MinorColor.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 8)
                HStack(spacing: 6) {
                    StructurePreview(kind: .tree)
                    StructurePreview(kind: .balanced)
                    StructurePreview(kind: .slides)
                }
                .accessibilityHidden(true)
                Image(systemName: "chevron.right").font(.system(size: 13, weight: .semibold)).foregroundColor(MinorColor.textTertiary)
            }
            .padding(14)
            .background(RoundedRectangle(cornerRadius: 16).fill(theme.chatRectangle))
            .overlay(RoundedRectangle(cornerRadius: 16).stroke(theme.chatStroke, lineWidth: 1))
            .contentShape(RoundedRectangle(cornerRadius: 16))
        }
        .buttonStyle(PressScale())
        .accessibilityElement(children: .combine)
    }

    // At most two real documents, and the map being built if there is one. No documents, no section.
    @ViewBuilder
    private var continueSection: some View {
        let latest = recents.latest(2, maps: maps.maps, decks: decks.decks)
        let job = generation.running.first
        if !latest.isEmpty || job != nil {
            Text("Continue")
                .textCase(.uppercase)
                .minorFont(13, .semibold, style: .footnote, maxScale: 1.3)
                .foregroundColor(MinorColor.textTertiary)
                .padding(.top, 28)
                .padding(.bottom, 10)
                .accessibilityAddTraits(.isHeader)
            VStack(spacing: 8) {
                if let job {
                    Button { onOpenJob(job.id) } label: { BuildingCardView(job: job) }
                        .buttonStyle(PressScale())
                }
                ForEach(latest) { entry in
                    continueRow(entry)
                }
            }
        }
    }

    @ViewBuilder
    private func continueRow(_ entry: RecentDocuments.Entry) -> some View {
        switch entry.kind {
        case .map:
            if let map = maps.map(entry.id) {
                Button { onOpenMap(map.id) } label: {
                    DocumentRow(title: map.title, detail: L("Map · \(map.nodeCount) nodes"), date: entry.openedAt) {
                        MapThumbnail(map: map)
                    }
                }
                .buttonStyle(PressScale())
            }
        case .deck:
            if let deck = decks.deck(entry.id) {
                Button { onOpenDeck(deck.id) } label: {
                    DocumentRow(title: deck.title, detail: L("Presentation · \(deck.slides.count) slides"), date: entry.openedAt) {
                        DeckThumbnail(deck: deck, rendered: thumbnails)
                    }
                }
                .buttonStyle(PressScale())
            }
        }
    }

    private var settingsRow: some View {
        Button(action: onSettings) {
            HStack(spacing: 12) {
                Image(systemName: "gearshape").font(.system(size: 17)).frame(width: 24)
                Text("Settings").minorFont(16, maxScale: 1.4)
                Spacer()
                Image(systemName: "chevron.right").font(.system(size: 13, weight: .semibold)).foregroundColor(MinorColor.textTertiary)
            }
            .foregroundColor(MinorColor.textPrimary)
            .padding(.horizontal, 14)
            .frame(minHeight: 50)
            .background(RoundedRectangle(cornerRadius: 12).fill(MinorColor.fillRow))
            .contentShape(Rectangle())
        }
        .buttonStyle(PressScale())
    }

    // MARK: - Data

    private var dueCount: Int { TaskAgenda.dueCount(in: maps.maps) }

    private var todayDetail: String {
        dueCount > 0 ? L("\(dueCount) tasks due") : L("Tasks and reminders")
    }

    // MARK: - Navigation and motion

    // One place at a time: a second tap during the push doesn't stack another screen.
    private func go(_ place: MenuDestination) {
        guard path.isEmpty else { return }
        path.append(place)
    }

    private func enter() {
        thumbnails = false
        if reduceMotion {
            var quiet = Transaction()
            quiet.disablesAnimations = true
            withTransaction(quiet) { entered = true }
        } else if !entered {
            entered = true
            withAnimation(.easeOut(duration: 0.13).delay(0.04)) { accent = true }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.17) {
                withAnimation(.easeOut(duration: 0.13)) { accent = false }
            }
        }
        // Previews render after the first frame, in place, so they never hold the slide-in.
        DispatchQueue.main.async { thumbnails = true }
        DispatchQueue.main.asyncAfter(deadline: .now() + (reduceMotion ? 0.15 : 0.32)) {
            if open && path.isEmpty { titleFocused = true }
        }
    }

    // The groups stay as they are while the menu slides away; they reset only once it is gone,
    // so a reopen mid-way continues instead of replaying the cascade.
    private func leave() {
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
            guard !open else { return }
            var quiet = Transaction()
            quiet.disablesAnimations = true
            withTransaction(quiet) {
                entered = false
                accent = false
            }
        }
    }
}

// A group of the menu fading and rising in once, with its own delay.
private struct Stage: ViewModifier {
    let shown: Bool
    let delay: Double
    let duration: Double
    let rise: CGFloat
    let reduceMotion: Bool

    func body(content: Content) -> some View {
        content
            .opacity(shown ? 1 : 0)
            .offset(y: shown || reduceMotion ? 0 : rise)
            .animation(reduceMotion ? nil : .easeOut(duration: duration).delay(delay), value: shown)
    }
}

private extension View {
    func stage(_ shown: Bool, delay: Double, duration: Double, rise: CGFloat, reduceMotion: Bool) -> some View {
        modifier(Stage(shown: shown, delay: delay, duration: duration, rise: rise, reduceMotion: reduceMotion))
    }
}

// Buttons shrink a little while pressed.
struct PressScale: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.97 : 1)
            .animation(.easeOut(duration: 0.1), value: configuration.isPressed)
    }
}

// A map or presentation row: preview, title, kind and date.
struct DocumentRow<Preview: View>: View {
    let title: String
    let detail: String
    var date: Date? = nil
    var shared = false
    var pinned = false
    var plain = false   // a list row with a line under it instead of a filled card
    @ViewBuilder var preview: () -> Preview

    var body: some View {
        HStack(spacing: plain ? 14 : 12) {
            preview()
            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .minorFont(16, plain ? .semibold : .medium, maxScale: 1.4)
                    .foregroundColor(MinorColor.textPrimary)
                    .lineLimit(2)
                if shared {
                    Label("Shared", systemImage: "person.2")
                        .labelStyle(.titleAndIcon)
                        .minorFont(12, style: .caption1, maxScale: 1.4)
                        .foregroundColor(MinorColor.textSecondary)
                }
                Text(date.map { "\(detail) · \(MapCardView.relative($0))" } ?? detail)
                    .minorFont(12, style: .caption1, maxScale: 1.4)
                    .foregroundColor(MinorColor.textTertiary)
                    .lineLimit(2)
            }
            Spacer(minLength: 8)
            if pinned {
                Image(systemName: "pin.fill")
                    .font(.system(size: 11))
                    .foregroundColor(MinorColor.textTertiary)
                    .accessibilityLabel("Pinned")
            }
            if !plain {
                Image(systemName: "chevron.right").font(.system(size: 13, weight: .semibold)).foregroundColor(MinorColor.textTertiary)
            }
        }
        .padding(.leading, plain ? 0 : 10)
        .padding(.trailing, plain ? 0 : 12)
        .padding(.vertical, 10)
        .background(RoundedRectangle(cornerRadius: 12).fill(plain ? Color.clear : MinorColor.fillRow))
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
    }
}

// The first slide in a 64×48 frame; a plain card until it is drawn.
struct DeckThumbnail: View {
    let deck: Deck
    var rendered = true

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 8).fill(Color.black.opacity(0.35))
            if rendered, let first = deck.slides.first {
                SlideCanvas(slide: first, deck: deck)
                    .frame(width: 64, height: 36)
                    .clipShape(RoundedRectangle(cornerRadius: 4))
            } else {
                Image(systemName: "rectangle.on.rectangle.angled").font(.system(size: 14)).foregroundColor(MinorColor.textTertiary)
            }
        }
        .frame(width: 64, height: 48)
        .accessibilityHidden(true)
    }
}

// Small drawings of what a template gives: a tree, a two-sided map or slides.
struct StructurePreview: View {
    enum Kind { case tree, balanced, slides }
    let kind: Kind

    var body: some View {
        Canvas { context, size in
            let line = GraphicsContext.Shading.color(.white.opacity(0.5))
            switch kind {
            case .tree, .balanced:
                let root = CGRect(x: kind == .tree ? 3 : size.width / 2 - 5, y: size.height / 2 - 3, width: 10, height: 6)
                let colors = [BranchColor.mint, .sky, .lilac, .pink]
                let sides: [CGFloat] = kind == .tree ? [1, 1, 1] : [1, 1, -1, -1]
                for (i, side) in sides.enumerated() {
                    let y = kind == .tree ? 6 + CGFloat(i) * 9 : (i % 2 == 0 ? 8 : 22)
                    let start = CGPoint(x: side > 0 ? root.maxX : root.minX, y: root.midY)
                    let end = CGPoint(x: side > 0 ? start.x + 12 : start.x - 12, y: y)
                    var path = Path()
                    path.move(to: start)
                    path.addCurve(to: end, control1: CGPoint(x: (start.x + end.x) / 2, y: start.y), control2: CGPoint(x: (start.x + end.x) / 2, y: end.y))
                    context.stroke(path, with: .color(colors[i % colors.count].color), lineWidth: 1)
                    let pill = CGRect(x: side > 0 ? end.x : end.x - 8, y: y - 1.5, width: 8, height: 3)
                    context.fill(Path(roundedRect: pill, cornerRadius: 1.5), with: .color(colors[i % colors.count].color.opacity(0.8)))
                }
                context.fill(Path(roundedRect: root, cornerRadius: 2), with: .color(.white))
            case .slides:
                for i in 0..<2 {
                    let rect = CGRect(x: 4 + CGFloat(i) * 4, y: 6 + CGFloat(i) * 4, width: size.width - 14, height: size.height - 16)
                    context.fill(Path(roundedRect: rect, cornerRadius: 2), with: .color(Color(white: i == 0 ? 0.3 : 0.85)))
                }
                context.stroke(Path(CGRect(x: 12, y: 16, width: 10, height: 1.5)), with: line, lineWidth: 1.5)
            }
        }
        .frame(width: 36, height: 30)
        .background(RoundedRectangle(cornerRadius: 6).fill(Color.black.opacity(0.35)))
    }
}
