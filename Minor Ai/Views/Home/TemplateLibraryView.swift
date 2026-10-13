//
//  TemplateLibraryView.swift
//  Minor Ai
//
//  Templates for both kinds of documents. A map template is a starting structure made on the
//  phone; a presentation template is a plan of slides with its design, filled by AI or by hand
//  on the New Presentation screen.
//

import SwiftUI

struct TemplateLibraryView: View {
    let theme: AppTheme
    @State var tab: TemplateLibraryTab
    var onPickMap: (MapTemplate) -> Void
    var onPickDeck: (DeckTemplate) -> Void

    enum Shelf: Hashable { case all, work, study, mine }

    @ObservedObject private var saved = TemplateStore.shared
    @State private var shelf: Shelf = .all

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                MinorSegments(items: [(.maps, "Maps", "point.3.connected.trianglepath.dotted"), (.decks, "Presentations", "rectangle.on.rectangle.angled")], selection: $tab)
                    .padding(.top, 4)
                if tab == .maps { mapTemplates } else { deckTemplates }
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 24)
        }
        .background(theme.background.ignoresSafeArea())
        .foregroundColor(MinorColor.textPrimary)
        .navigationTitle(Text("Templates"))
        .navigationBarTitleDisplayMode(.large)
    }

    // MARK: - Maps

    private var mapTemplates: some View {
        LazyVGrid(columns: [GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12)], spacing: 12) {
            ForEach(MapTemplate.all) { template in
                Button {
                    Haptics.selection()
                    onPickMap(template)
                } label: {
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Text(template.icon).font(.system(size: 26))
                            Spacer()
                            HStack(spacing: -5) {
                                ForEach(Array(template.palette.colors.prefix(4).enumerated()), id: \.offset) { _, color in
                                    Circle().fill(color.color).frame(width: 12, height: 12)
                                        .overlay(Circle().stroke(theme.chatRectangle, lineWidth: 1.5))
                                }
                            }
                            .accessibilityHidden(true)
                        }
                        Text(template.title)
                            .minorFont(16, .semibold, maxScale: 1.3)
                            .fixedSize(horizontal: false, vertical: true)
                        Text(template.summary)
                            .minorFont(13, style: .footnote, maxScale: 1.3)
                            .foregroundColor(MinorColor.textSecondary)
                            .fixedSize(horizontal: false, vertical: true)
                        Text("\(template.branches.count) branches")
                            .minorFont(12, style: .caption1, maxScale: 1.3)
                            .foregroundColor(MinorColor.textTertiary)
                        Spacer(minLength: 0)
                    }
                    .multilineTextAlignment(.leading)
                    .frame(maxWidth: .infinity, minHeight: 150, alignment: .topLeading)
                    .padding(14)
                    .background(RoundedRectangle(cornerRadius: 16).fill(theme.chatRectangle))
                    .overlay(RoundedRectangle(cornerRadius: 16).stroke(theme.chatStroke, lineWidth: 1))
                    .contentShape(RoundedRectangle(cornerRadius: 16))
                }
                .buttonStyle(PressScale())
                .accessibilityElement(children: .combine)
                .accessibilityHint(Text("Creates a map with this structure"))
            }
        }
    }

    // MARK: - Presentations

    private var deckTemplates: some View {
        VStack(alignment: .leading, spacing: 14) {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    chip("All", .all)
                    chip("Work", .work)
                    chip("Study", .study)
                    chip("Mine", .mine)
                }
            }
            let list = shelfTemplates
            if list.isEmpty {
                VStack(spacing: 8) {
                    Image(systemName: "square.on.square").font(.system(size: 30)).foregroundColor(MinorColor.textSecondary)
                    Text("No saved templates yet").minorFont(16, .semibold, maxScale: 1.3)
                    Text("Save one from a presentation: More → Save as Template.")
                        .minorFont(14, maxScale: 1.3)
                        .foregroundColor(MinorColor.textSecondary)
                        .multilineTextAlignment(.center)
                }
                .frame(maxWidth: .infinity)
                .padding(.top, 40)
            } else {
                ForEach(list) { template in
                    Button {
                        Haptics.selection()
                        onPickDeck(template)
                    } label: {
                        VStack(alignment: .leading, spacing: 8) {
                            // The cover, with the next slides laid over its lower edge.
                            if let first = template.deck.slides.first {
                                SlideCanvas(slide: first, deck: template.deck)
                                    .clipShape(RoundedRectangle(cornerRadius: 8))
                                    .overlay(alignment: .bottomTrailing) {
                                        HStack(spacing: 5) {
                                            ForEach(Array(template.deck.slides.dropFirst().prefix(3))) { slide in
                                                SlideCanvas(slide: slide, deck: template.deck)
                                                    .frame(width: 84)
                                                    .clipShape(RoundedRectangle(cornerRadius: 4))
                                                    .overlay(RoundedRectangle(cornerRadius: 4).stroke(Color.white.opacity(0.25), lineWidth: 0.5))
                                                    .shadow(color: .black.opacity(0.35), radius: 4, y: 2)
                                            }
                                        }
                                        .padding(7)
                                    }
                                    .accessibilityHidden(true)
                            }
                            HStack(alignment: .center) {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(template.name).minorFont(16, .semibold, maxScale: 1.3)
                                    Text(outline(template))
                                        .minorFont(12, style: .caption1, maxScale: 1.3)
                                        .foregroundColor(MinorColor.textSecondary)
                                        .lineLimit(1)
                                }
                                Spacer()
                                Image(systemName: "chevron.right").font(.system(size: 13, weight: .semibold)).foregroundColor(MinorColor.textTertiary)
                            }
                            .padding(.horizontal, 2)
                        }
                        .padding(8)
                        .background(RoundedRectangle(cornerRadius: 14).fill(theme.chatRectangle))
                        .overlay(RoundedRectangle(cornerRadius: 14).stroke(theme.chatStroke, lineWidth: 1))
                        .contentShape(RoundedRectangle(cornerRadius: 14))
                    }
                    .buttonStyle(PressScale())
                    .accessibilityElement(children: .combine)
                    .accessibilityHint(Text("Opens New Presentation with this template"))
                    .contextMenu {
                        if shelf == .mine || saved.templates.contains(where: { $0.id == template.id }) {
                            Button(role: .destructive) {
                                if let id = UUID(uuidString: template.id) { saved.delete(id) }
                            } label: { Label("Delete Template", systemImage: "trash") }
                        }
                    }
                }
                Text("Your own template can be saved from any presentation.")
                    .minorFont(12, style: .caption1, maxScale: 1.3)
                    .foregroundColor(MinorColor.textTertiary)
                    .frame(maxWidth: .infinity)
            }
        }
    }

    // "8 slides · Problem, Solution, Plan": how many and what the first ones are about.
    private func outline(_ template: DeckTemplate) -> String {
        let count = L("\(template.deck.slides.count) slides")
        let topics = template.deck.slides.dropFirst().prefix(3).map(\.title).filter { !$0.isEmpty }
        return topics.isEmpty ? count : "\(count) · \(topics.joined(separator: ", "))"
    }

    private func chip(_ title: LocalizedStringKey, _ value: Shelf) -> some View {
        Button {
            Haptics.selection()
            shelf = value
        } label: {
            Text(title)
                .minorFont(13, .medium, maxScale: 1.3)
                .foregroundColor(shelf == value ? .black : MinorColor.textPrimary)
                .padding(.horizontal, 14)
                .frame(minHeight: 30)
                .background(Capsule().fill(shelf == value ? MinorColor.accent : theme.chatRectangle))
                .overlay(Capsule().stroke(shelf == value ? Color.clear : theme.chatStroke, lineWidth: 1))
        }
        .buttonStyle(.plain)
        .frame(minHeight: 44)
        .accessibilityAddTraits(shelf == value ? .isSelected : [])
    }

    // Built-in templates sorted onto shelves by what they are for; Mine are the saved ones.
    private var shelfTemplates: [DeckTemplate] {
        let work: Set<String> = ["pitch", "project", "report", "launch"]
        let study: Set<String> = ["lecture", "study"]
        switch shelf {
        case .all: return DeckTemplates.all + saved.templates
        case .work: return DeckTemplates.all.filter { work.contains($0.id) }
        case .study: return DeckTemplates.all.filter { study.contains($0.id) }
        case .mine: return saved.templates
        }
    }
}
