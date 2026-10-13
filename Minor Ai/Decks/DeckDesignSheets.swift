//
//  DeckDesignSheets.swift
//  Minor Ai
//
//  Sheets for how a presentation looks: themes (ready-made, saved, own, from a description),
//  the theme editor, the brand, one slide's background and motion, and the AI designer.
//  Own looks, brand, slide backgrounds and most motion are part of Minor Plus.
//

import PhotosUI
import SwiftUI

// MARK: - Saved looks

@MainActor
final class LookStore: ObservableObject {
    static let shared = LookStore()
    @Published private(set) var looks: [DeckLook] = []
    private let key = "deck.myLooks"

    private init() {
        if let data = UserDefaults.standard.data(forKey: key), let saved = try? JSONDecoder().decode([DeckLook].self, from: data) {
            looks = saved
        }
    }

    var imageIDs: [UUID] { looks.compactMap(\.background.image) }

    func save(_ look: DeckLook) {
        var look = look
        if look.name.isEmpty { look.name = L("My Theme") }
        looks.removeAll { $0.id == look.id }
        looks.insert(look, at: 0)
        looks = Array(looks.prefix(30))
        persist()
    }

    func delete(_ id: UUID) {
        looks.removeAll { $0.id == id }
        persist()
    }

    private func persist() {
        if let data = try? JSONEncoder().encode(looks) { UserDefaults.standard.set(data, forKey: key) }
    }
}

// A small "Plus" mark on features that need it.
struct PlusBadge: View {
    var body: some View {
        Text(verbatim: "Plus")
            .font(.system(size: 10, weight: .bold))
            .foregroundColor(.black)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(Capsule().fill(MinorColor.accent))
            .accessibilityLabel(L("Part of Minor Plus"))
    }
}

// MARK: - Themes

enum ThemeChoice {
    case builtIn(DeckTheme)
    case look(DeckLook)
}

// The presentation's style, or (Plus) one slide's own: ready-made themes, saved ones, your own
// style or one described to the AI. Changing the style never changes text, numbers or order.
struct ThemePicker: View {
    enum Scope: Hashable { case deck, slide }

    let deck: Deck
    let slideIndex: Int
    let theme: AppTheme
    let isPaid: Bool
    var onPick: (_ choice: ThemeChoice, _ forSlide: Bool) -> Void
    var onResetSlide: () -> Void
    var onCreate: (_ forSlide: Bool) -> Void
    var onDescribe: () -> Void
    var onUpgrade: () -> Void

    @Environment(\.dismiss) private var dismiss
    @ObservedObject private var store = LookStore.shared
    @State private var scope: Scope = .deck

    private var slide: Slide? { deck.slides.indices.contains(slideIndex) ? deck.slides[slideIndex] : nil }
    private var slideHasOwn: Bool { slide?.look != nil || slide?.theme != nil }
    private var ownStyleCount: Int { deck.slides.filter { $0.look != nil || $0.theme != nil }.count }

    // The slide on screen, drawn with a choice: as it would look for the whole deck, or for itself.
    private func preview(_ choice: ThemeChoice) -> (Deck, Slide) {
        var copy = deck
        var sample = slide ?? Slide(layout: .cover, title: deck.title)
        switch (scope, choice) {
        case (.deck, .builtIn(let ready)):
            copy.theme = ready.rawValue
            copy.look = nil
            sample.look = nil
            sample.theme = nil
        case (.deck, .look(let look)):
            copy.look = look
            sample.look = nil
            sample.theme = nil
        case (.slide, .builtIn(let ready)):
            sample.look = nil
            sample.theme = ready.rawValue
        case (.slide, .look(let look)):
            sample.look = look
            sample.theme = nil
        }
        if copy.slides.indices.contains(slideIndex) { copy.slides[slideIndex] = sample }
        return (copy, sample)
    }

    private func isCurrent(_ choice: ThemeChoice) -> Bool {
        switch (scope, choice) {
        case (.deck, .builtIn(let ready)): return deck.look == nil && deck.deckTheme == ready
        case (.deck, .look(let look)): return deck.look?.id == look.id
        case (.slide, .builtIn(let ready)): return slide?.look == nil && slide?.theme == ready.rawValue
        case (.slide, .look(let look)): return slide?.look?.id == look.id
        }
    }

    // The style the chosen scope shows now: the slide's own, or the presentation's.
    private var current: SlideStyle {
        if scope == .slide, let slide { return deck.style(for: slide) }
        return deck.style
    }

    // The look "Save My Style" keeps: the scope's own look, or the ready-made theme as a look.
    private var currentLook: DeckLook {
        if scope == .slide, let slide {
            if let look = slide.look { return look }
            if let ready = slide.theme.flatMap(DeckTheme.init(rawValue:)) { return DeckLook(theme: ready) }
        }
        return deck.look ?? DeckLook(theme: deck.deckTheme)
    }

    @State private var savedNote = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                EditorSheetHeader(title: L("Presentation Style")) { dismiss() }
                MinorSegments(
                    items: [(Scope.deck, "Whole Presentation", nil), (.slide, "This Slide", isPaid ? nil : "lock.fill")],
                    selection: Binding(get: { scope }, set: { value in
                        if value == .slide && !isPaid { return onUpgrade() }
                        scope = value
                    }),
                    height: 30
                )
                .padding(.top, 10)

                themes.padding(.top, 10)

                VStack(spacing: 0) {
                    row("paintpalette", L("Palette")) {
                        HStack(spacing: 6) {
                            ForEach(Array(current.palette.prefix(4).enumerated()), id: \.offset) { _, color in
                                Circle().fill(color).frame(width: 18, height: 18)
                            }
                        }
                    }
                    divider
                    row("textformat", L("Headings")) { value("\(current.titleFont.name) Bold") }
                    divider
                    row("textformat", L("Body Text")) { value(current.bodyFont.name) }
                    divider
                    row("rectangle.portrait", L("Background")) {
                        HStack(spacing: 8) {
                            value(backgroundName(current.background))
                            Circle()
                                .fill(LinearGradient(colors: [current.background.first, current.background.last], startPoint: .topLeading, endPoint: .bottomTrailing))
                                .overlay(Circle().stroke(Color.white.opacity(0.25), lineWidth: 1))
                                .frame(width: 18, height: 18)
                        }
                    }
                }
                .padding(.top, 8)

                if scope == .slide && slideHasOwn {
                    divider
                    Button(action: onResetSlide) {
                        HStack(spacing: 12) {
                            Image(systemName: "arrow.uturn.backward").font(.system(size: 15)).frame(width: 24)
                            Text("Use the Presentation’s Style").minorFont(14, maxScale: 1.3)
                            Spacer()
                        }
                        .frame(minHeight: 40)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }

                HStack(spacing: 8) {
                    footerButton(savedNote ? L("Saved") : L("Save My Style"), icon: savedNote ? "checkmark" : "square.and.arrow.down") {
                        guard isPaid else { return onUpgrade() }
                        LookStore.shared.save(currentLook)
                        Haptics.success()
                        withAnimation(.minorMenu) { savedNote = true }
                    }
                    if scope == .deck {
                        footerButton(L("AI: Describe a Style"), icon: "sparkles") { onDescribe() }
                    }
                }
                .padding(.top, 10)

                if scope == .slide || ownStyleCount > 0 {
                    Text(footnote)
                        .minorFont(12, style: .caption1, maxScale: 1.4)
                        .foregroundColor(MinorColor.textTertiary)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.top, 10)
                }
            }
            .padding(.horizontal, 14)
            .padding(.top, 12)
            .padding(.bottom, 22)
        }
        .ignoresSafeArea(.container, edges: .bottom)
        .foregroundColor(MinorColor.textPrimary)
        .background(MinorColor.editorSheet.ignoresSafeArea())
        .preferredColorScheme(.dark)
        .onChange(of: scope) { _ in savedNote = false }
    }

    private var footnote: String {
        if scope == .slide { return L("Only this slide changes. Its text, numbers and order stay the same.") }
        if ownStyleCount > 0 { return L("Text, numbers and order stay the same. Slides with their own style keep it: \(ownStyleCount).") }
        return L("Text, numbers and order stay the same.")
    }

    private var divider: some View {
        Rectangle().fill(Color.white.opacity(0.08)).frame(height: 1)
    }

    private func value(_ text: String) -> some View {
        Text(text).minorFont(13, maxScale: 1.3).foregroundColor(MinorColor.textSecondary).lineLimit(1)
    }

    private func backgroundName(_ background: SlideBackground) -> String {
        switch background.kind {
        case .solid: return L("Color")
        case .gradient: return L("Gradient")
        case .image: return L("Photo")
        }
    }

    // A setting of the style; all of them open the style editor (Plus).
    private func row<Value: View>(_ icon: String, _ title: String, @ViewBuilder value: () -> Value) -> some View {
        Button { onCreate(scope == .slide) } label: {
            HStack(spacing: 12) {
                Image(systemName: icon).font(.system(size: 16)).foregroundColor(MinorColor.textSecondary).frame(width: 24)
                Text(title).minorFont(14, maxScale: 1.3).foregroundColor(MinorColor.textPrimary)
                Spacer(minLength: 8)
                value()
                Image(systemName: "chevron.right").font(.system(size: 12, weight: .semibold)).foregroundColor(MinorColor.textTertiary)
            }
            .frame(minHeight: 42)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private func footerButton(_ title: String, icon: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 8) {
                Image(systemName: icon).font(.system(size: 14))
                Text(title).minorFont(13, .medium, maxScale: 1.3).lineLimit(1).minimumScaleFactor(0.8)
            }
            .frame(maxWidth: .infinity, minHeight: 36)
            .background(RoundedRectangle(cornerRadius: 10).fill(Color.white.opacity(0.06)))
            .overlay(RoundedRectangle(cornerRadius: 10).stroke(Color.white.opacity(0.1), lineWidth: 1))
        }
        .buttonStyle(PressScale())
    }

    // My themes first, then the ready-made ones; three fill the row and the rest scroll.
    private var themes: some View {
        let items: [(String, String, ThemeChoice, UUID?)] =
            store.looks.map { ($0.id.uuidString, $0.name, ThemeChoice.look($0), $0.id) }
            + DeckTheme.allCases.map { ($0.rawValue, $0.name, ThemeChoice.builtIn($0), nil) }
        return GeometryReader { geo in
            let width = (geo.size.width - 2 * 8) / 3
            ScrollViewReader { reader in
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(alignment: .top, spacing: 8) {
                        ForEach(items, id: \.0) { item in
                            let selected = isCurrent(item.2)
                            let (previewDeck, sample) = preview(item.2)
                            Button {
                                Haptics.selection()
                                onPick(item.2, scope == .slide)
                            } label: {
                                VStack(spacing: 6) {
                                    SlideCanvas(slide: sample, deck: previewDeck, index: slideIndex)
                                        .frame(width: width)
                                        .clipShape(RoundedRectangle(cornerRadius: 8))
                                        .overlay(RoundedRectangle(cornerRadius: 8).stroke(selected ? MinorColor.accent : Color.white.opacity(0.1), lineWidth: selected ? 2 : 1))
                                    Text(item.1)
                                        .minorFont(12, selected ? .semibold : .regular, maxScale: 1.2)
                                        .foregroundColor(selected ? MinorColor.textPrimary : MinorColor.textSecondary)
                                        .lineLimit(1)
                                        .frame(width: width)
                                }
                                .padding(.vertical, 1)
                            }
                            .buttonStyle(.plain)
                            .id(item.0)
                            .accessibilityLabel(item.1)
                            .accessibilityAddTraits(selected ? .isSelected : [])
                            .contextMenu {
                                if let id = item.3 {
                                    Button(role: .destructive) { store.delete(id) } label: { Label("Delete Theme", systemImage: "trash") }
                                }
                            }
                        }
                    }
                }
                .onAppear {
                    if let chosen = items.first(where: { isCurrent($0.2) }) { reader.scrollTo(chosen.0, anchor: .center) }
                }
            }
        }
        .frame(height: 90)
    }
}

// MARK: - Theme editor

struct LookEditor: View {
    let deck: Deck
    let slideIndex: Int
    let theme: AppTheme
    var forSlide = false            // the slide's own style instead of the presentation's
    var onApply: (DeckLook) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var look: DeckLook
    @State private var saveToMine = true

    init(deck: Deck, slideIndex: Int, theme: AppTheme, start: DeckLook? = nil, forSlide: Bool = false, onApply: @escaping (DeckLook) -> Void) {
        self.deck = deck
        self.slideIndex = slideIndex
        self.theme = theme
        self.forSlide = forSlide
        self.onApply = onApply
        let slide = deck.slides.indices.contains(slideIndex) ? deck.slides[slideIndex] : nil
        let current = forSlide
            ? (slide?.look ?? slide?.theme.flatMap(DeckTheme.init(rawValue:)).map(DeckLook.init(theme:)) ?? deck.look)
            : deck.look
        var initial = start ?? current ?? DeckLook(theme: deck.deckTheme)
        if start == nil && current == nil { initial.name = "" }
        _look = State(initialValue: initial)
    }

    private var preview: Deck {
        var copy = deck
        if forSlide, copy.slides.indices.contains(slideIndex) {
            copy.slides[slideIndex].look = look
            copy.slides[slideIndex].theme = nil
        } else {
            copy.look = look
            // The slide on screen shows the presentation's style while it is edited.
            if copy.slides.indices.contains(slideIndex) {
                copy.slides[slideIndex].look = nil
                copy.slides[slideIndex].theme = nil
            }
        }
        return copy
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                if preview.slides.indices.contains(slideIndex) {
                    SlideCanvas(slide: preview.slides[slideIndex], deck: preview, index: slideIndex)
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                        .overlay(RoundedRectangle(cornerRadius: 12).stroke(theme.chatStroke, lineWidth: 1))
                        .padding(.horizontal, 16)
                        .padding(.vertical, 10)
                        .animation(.easeInOut(duration: 0.2), value: look)
                }
                Form {
                    Section("Background") { BackgroundEditor(background: $look.background) }
                    Section("Colors") {
                        ColorPicker("Accent", selection: Binding(get: { Color(hex: look.accent) }, set: {
                            look.accent = UIColor($0).hexString
                            look.palette = DeckLook.palette(from: look.accent)
                        }), supportsOpacity: false)
                        HStack(spacing: 8) {
                            ForEach(look.palette.indices, id: \.self) { i in
                                ColorPicker("", selection: Binding(get: { Color(hex: look.palette[i]) }, set: { look.palette[i] = UIColor($0).hexString }), supportsOpacity: false)
                                    .labelsHidden()
                            }
                        }
                        Picker("Text", selection: Binding(get: { look.textColor == nil ? "auto" : (SlideBackground.luminance(look.textColor!) > 0.5 ? "light" : "dark") }, set: {
                            look.textColor = $0 == "auto" ? nil : ($0 == "light" ? "#FFFFFF" : "#18171B")
                        })) {
                            Text("Automatic").tag("auto")
                            Text("Light").tag("light")
                            Text("Dark").tag("dark")
                        }
                    }
                    Section("Fonts") {
                        fontPicker(L("Titles"), selection: $look.titleFont)
                        fontPicker(L("Text"), selection: $look.bodyFont)
                    }
                    Section {
                        Toggle("Soft Glow", isOn: $look.glow)
                        TextField("Theme name", text: $look.name)
                        Toggle("Save to My Themes", isOn: $saveToMine)
                    }
                }
                .scrollContentBackground(.hidden)
            }
            .background(theme.background.ignoresSafeArea())
            .navigationTitle(forSlide ? Text("This Slide’s Style") : Text("Own Style"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Apply") {
                        if saveToMine { LookStore.shared.save(look) }
                        onApply(look)
                        dismiss()
                    }
                    .foregroundColor(MinorColor.accent)
                }
            }
        }
        .preferredColorScheme(.dark)
    }

    private func fontPicker(_ title: String, selection: Binding<DeckFont>) -> some View {
        Picker(title, selection: selection) {
            ForEach(DeckFont.allCases) { font in
                Text(font.name).font(font.font(17, .semibold)).tag(font)
            }
        }
        .pickerStyle(.navigationLink)
    }
}

// Color, gradient or photo.
struct BackgroundEditor: View {
    @Binding var background: SlideBackground
    @State private var photoItem: PhotosPickerItem?
    @State private var showPhotos = false

    var body: some View {
        Picker("Background", selection: $background.kind) {
            Text("Color").tag(SlideBackground.Kind.solid)
            Text("Gradient").tag(SlideBackground.Kind.gradient)
            Text("Photo").tag(SlideBackground.Kind.image)
        }
        .pickerStyle(.segmented)
        switch background.kind {
        case .solid:
            ColorPicker("Color", selection: color(0), supportsOpacity: false)
        case .gradient:
            ColorPicker("From", selection: color(0), supportsOpacity: false)
            ColorPicker("To", selection: color(1), supportsOpacity: false)
            VStack(alignment: .leading) {
                Text("Direction").font(.system(size: 14)).foregroundColor(MinorColor.textSecondary)
                Slider(value: $background.angle, in: 0...360, step: 15)
            }
        case .image:
            Button { showPhotos = true } label: {
                Label(background.image == nil ? "Choose Photo" : "Replace Photo", systemImage: "photo")
            }
            .photosPicker(isPresented: $showPhotos, selection: $photoItem, matching: .images)
            .onChange(of: photoItem) { item in
                guard let item else { return }
                Task {
                    if let data = try? await item.loadTransferable(type: Data.self), let picture = MapStore.shared.storeImage(data, isAI: false) {
                        background.image = picture.id
                    }
                    photoItem = nil
                }
            }
            VStack(alignment: .leading) {
                Text("Darken the photo").font(.system(size: 14)).foregroundColor(MinorColor.textSecondary)
                Slider(value: $background.dim, in: 0...0.8)
            }
        }
    }

    private func color(_ i: Int) -> Binding<Color> {
        Binding(
            get: { Color(hex: background.colors.indices.contains(i) ? background.colors[i] : (background.colors.first ?? "#121014")) },
            set: { value in
                while background.colors.count <= i { background.colors.append(background.colors.last ?? "#121014") }
                background.colors[i] = UIColor(value).hexString
            }
        )
    }
}

// MARK: - Brand

struct BrandSheet: View {
    let deck: Deck
    let theme: AppTheme
    var onSave: (DeckBrand?) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var brand: DeckBrand
    @State private var photoItem: PhotosPickerItem?
    @State private var showPhotos = false

    init(deck: Deck, theme: AppTheme, onSave: @escaping (DeckBrand?) -> Void) {
        self.deck = deck
        self.theme = theme
        self.onSave = onSave
        _brand = State(initialValue: deck.brand ?? DeckBrand())
    }

    private var preview: Deck {
        var copy = deck
        copy.brand = brand
        return copy
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                if let slide = preview.slides.dropFirst().first ?? preview.slides.first {
                    SlideCanvas(slide: slide, deck: preview, index: preview.slides.count > 1 ? 1 : 0)
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                        .padding(.horizontal, 16)
                        .padding(.vertical, 10)
                }
                Form {
                    Section("Logo") {
                        Button { showPhotos = true } label: { Label(brand.logo == nil ? "Add Logo" : "Replace Logo", systemImage: "photo") }
                        if brand.logo != nil {
                            Picker("Corner", selection: $brand.corner) {
                                Image(systemName: "arrow.up.left").tag(DeckBrand.Corner.topLeft)
                                Image(systemName: "arrow.up.right").tag(DeckBrand.Corner.topRight)
                                Image(systemName: "arrow.down.left").tag(DeckBrand.Corner.bottomLeft)
                                Image(systemName: "arrow.down.right").tag(DeckBrand.Corner.bottomRight)
                            }
                            .pickerStyle(.segmented)
                            VStack(alignment: .leading) {
                                Text("Size").font(.system(size: 14)).foregroundColor(MinorColor.textSecondary)
                                Slider(value: $brand.size, in: 32...140)
                            }
                            Toggle("On the Cover Too", isOn: $brand.onCover)
                            Button("Remove Logo", role: .destructive) { brand.logo = nil }
                        }
                    }
                    Section("Footer") {
                        TextField(deck.title, text: $brand.footer)
                        Toggle("Slide Numbers", isOn: $brand.showNumbers)
                    }
                }
                .scrollContentBackground(.hidden)
            }
            .background(theme.background.ignoresSafeArea())
            .navigationTitle("Brand")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") {
                        onSave(brand == DeckBrand() ? nil : brand)
                        dismiss()
                    }
                    .foregroundColor(MinorColor.accent)
                }
            }
            .photosPicker(isPresented: $showPhotos, selection: $photoItem, matching: .images)
            .onChange(of: photoItem) { item in
                guard let item else { return }
                Task {
                    if let data = try? await item.loadTransferable(type: Data.self), let picture = MapStore.shared.storeImage(data, isAI: false, keepTransparency: true) {
                        brand.logo = picture.id
                    }
                    photoItem = nil
                }
            }
        }
        .preferredColorScheme(.dark)
    }
}

// MARK: - One slide's look and motion

struct SlideDesignSheet: View {
    let deck: Deck
    let index: Int
    let theme: AppTheme
    let isPaid: Bool
    var onSave: (Slide, _ transitionForAll: Bool) -> Void
    var onUpgrade: () -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var slide: Slide
    @State private var ownBackground: Bool
    @State private var transition: SlideTransition
    @State private var forAll = false
    @State private var reveal: Int?

    init(deck: Deck, index: Int, theme: AppTheme, isPaid: Bool, onSave: @escaping (Slide, Bool) -> Void, onUpgrade: @escaping () -> Void) {
        self.deck = deck
        self.index = index
        self.theme = theme
        self.isPaid = isPaid
        self.onSave = onSave
        self.onUpgrade = onUpgrade
        let slide = deck.slides[index]
        _slide = State(initialValue: slide)
        _ownBackground = State(initialValue: slide.background != nil)
        _transition = State(initialValue: slide.transition ?? deck.transition)
    }

    private var preview: Deck {
        var copy = deck
        copy.slides[index] = slide
        return copy
    }

    private var steps: Int { Deck.buildSteps(slide) }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                SlideCanvas(slide: slide, deck: preview, index: index, reveal: reveal)
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                    .overlay(alignment: .bottomTrailing) {
                        if steps > 0 {
                            Button(action: play) {
                                Label("Preview", systemImage: "play.fill")
                                    .font(.system(size: 13, weight: .semibold))
                                    .padding(.horizontal, 10)
                                    .frame(height: 30)
                                    .background(Capsule().fill(Color.black.opacity(0.6)))
                            }
                            .buttonStyle(.plain)
                            .padding(8)
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 10)
                Form {
                    Section {
                        Toggle(isOn: Binding(get: { ownBackground }, set: { on in
                            guard isPaid || !on else { return onUpgrade() }
                            ownBackground = on
                            slide.background = on ? (slide.background ?? deck.style.background) : nil
                        })) {
                            HStack { Text("Own Background"); if !isPaid { PlusBadge() } }
                        }
                        if ownBackground, slide.background != nil {
                            BackgroundEditor(background: Binding(get: { slide.background ?? SlideBackground() }, set: { slide.background = $0 }))
                        }
                    } header: { Text("Background") }
                    Section {
                        Picker("Transition", selection: Binding(get: { transition }, set: { value in
                            guard isPaid || value == .none || value == .fade else { return onUpgrade() }
                            transition = value
                        })) {
                            ForEach(SlideTransition.allCases) { item in
                                Text(item.name + (isPaid || item == .none || item == .fade ? "" : " · Plus")).tag(item)
                            }
                        }
                        Toggle("For All Slides", isOn: $forAll)
                    } header: { Text("Transition") }
                    if slide.layout.buildable {
                        Section {
                            Picker("Points Come In", selection: Binding(get: { slide.buildBullets }, set: { value in
                                guard isPaid || value == .none || value == .fade else { return onUpgrade() }
                                slide.buildBullets = value
                            })) {
                                ForEach(BuildEffect.allCases) { effect in
                                    Label(effect.name + (isPaid || effect == .none || effect == .fade ? "" : " · Plus"), systemImage: effect.icon).tag(effect)
                                }
                            }
                        } header: { Text("One by One") } footer: {
                            Text("While presenting, each tap brings in the next point. PowerPoint plays the same.")
                        }
                    }
                }
                .scrollContentBackground(.hidden)
            }
            .background(theme.background.ignoresSafeArea())
            .navigationTitle("Slide Design")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") {
                        var result = slide
                        result.transition = forAll ? nil : (transition == deck.transition ? nil : transition)
                        if forAll { result.transition = transition }
                        onSave(result, forAll)
                        dismiss()
                    }
                    .foregroundColor(MinorColor.accent)
                }
            }
        }
        .preferredColorScheme(.dark)
    }

    // Plays the slide's steps in the preview.
    private func play() {
        Task {
            for step in 0...steps {
                withAnimation { reveal = step }
                try? await Task.sleep(nanoseconds: 650_000_000)
            }
            try? await Task.sleep(nanoseconds: 500_000_000)
            reveal = nil
        }
    }
}

extension SlideLayout {
    // Layouts whose points can come in one by one.
    var buildable: Bool { [.bullets, .imageText, .twoColumns, .timeline, .diagram, .table].contains(self) }
}

// MARK: - The AI designer

struct DesignPromptSheet: View {
    enum Mode { case style, elements }
    let mode: Mode
    let theme: AppTheme
    var onSubmit: (String) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var text = ""
    @FocusState private var focused: Bool

    private var examples: [String] {
        mode == .style
            ? [L("Calm: navy and gold"), L("Bright startup, purple and coral"), L("Minimal black and white"), L("Warm, like autumn"), L("Neon on dark")]
            : [L("A chart: Jan 12, Feb 18, Mar 25"), L("A badge “New” in the corner"), L("Three cards with icons for our values"), L("A timeline of 4 steps"), L("A QR code to minorai.site")]
    }

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 16) {
                Text(mode == .style ? "Describe the look you want: mood, colors, fonts." : "Describe what to add to this slide. Numbers become a chart.")
                    .font(.system(size: 15))
                    .foregroundColor(MinorColor.textSecondary)
                TextField("", text: $text, axis: .vertical)
                    .placeholder(when: text.isEmpty) { Text(mode == .style ? "Calm: navy and gold" : "A chart: Jan 12, Feb 18, Mar 25").foregroundColor(theme.placeholderText) }
                    .lineLimit(2...5)
                    .focused($focused)
                    .padding(14)
                    .background(RoundedRectangle(cornerRadius: 14).fill(theme.chatRectangle))
                    .overlay(RoundedRectangle(cornerRadius: 14).stroke(theme.chatStroke, lineWidth: 1))
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(examples, id: \.self) { example in
                            Button(example) { text = example }
                                .font(.system(size: 13))
                                .padding(.horizontal, 12)
                                .frame(height: 32)
                                .overlay(Capsule().stroke(theme.chatStroke, lineWidth: 1))
                                .buttonStyle(.plain)
                        }
                    }
                }
                Spacer()
            }
            .padding(20)
            .foregroundColor(MinorColor.textPrimary)
            .background(theme.background.ignoresSafeArea())
            .navigationTitle(mode == .style ? "Describe a Style" : "Add with AI")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Create") {
                        let prompt = text.trimmingCharacters(in: .whitespacesAndNewlines)
                        guard !prompt.isEmpty else { return }
                        onSubmit(prompt)
                        dismiss()
                    }
                    .foregroundColor(MinorColor.accent)
                    .disabled(text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
            .onAppear { focused = true }
        }
        .preferredColorScheme(.dark)
    }
}
