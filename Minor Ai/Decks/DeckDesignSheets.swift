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

struct ThemePicker: View {
    let deck: Deck
    let theme: AppTheme
    let isPaid: Bool
    var onPick: (ThemeChoice) -> Void
    var onCreate: () -> Void
    var onDescribe: () -> Void

    @Environment(\.dismiss) private var dismiss
    @ObservedObject private var store = LookStore.shared

    private var sample: Slide { deck.slides.first ?? Slide(layout: .cover, title: deck.title) }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    HStack(spacing: 10) {
                        bigButton(L("Own Style"), icon: "paintbrush.pointed.fill") { onCreate() }
                        bigButton(L("Describe a Style"), icon: "sparkles") { onDescribe() }
                    }
                    if !store.looks.isEmpty {
                        title(L("My Themes"))
                        grid(store.looks.map { look in
                            var preview = deck
                            preview.look = look
                            return (look.id.uuidString, look.name, preview, deck.look?.id == look.id, { onPick(.look(look)) }, look.id)
                        })
                    }
                    title(L("Ready-Made"))
                    grid(DeckTheme.allCases.map { choice in
                        var preview = deck
                        preview.theme = choice.rawValue
                        preview.look = nil
                        return (choice.rawValue, choice.name, preview, deck.look == nil && deck.deckTheme == choice, { onPick(.builtIn(choice)) }, nil)
                    })
                }
                .padding(16)
            }
            .background(theme.background.ignoresSafeArea())
            .navigationTitle("Theme")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }.foregroundColor(MinorColor.accent)
                }
            }
        }
        .foregroundColor(MinorColor.textPrimary)
        .preferredColorScheme(.dark)
    }

    private func title(_ text: String) -> some View {
        Text(text.uppercased()).font(.system(size: 12, weight: .semibold)).foregroundColor(MinorColor.textTertiary)
    }

    private func bigButton(_ title: String, icon: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Image(systemName: icon).font(.system(size: 20))
                    Spacer()
                    if !isPaid { PlusBadge() }
                }
                Text(title).font(.system(size: 15, weight: .semibold))
            }
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(RoundedRectangle(cornerRadius: 14).fill(theme.chatRectangle))
            .overlay(RoundedRectangle(cornerRadius: 14).stroke(theme.chatStroke, lineWidth: 1))
        }
        .buttonStyle(.plain)
    }

    private func grid(_ items: [(String, String, Deck, Bool, () -> Void, UUID?)]) -> some View {
        LazyVGrid(columns: [GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12)], spacing: 14) {
            ForEach(items, id: \.0) { item in
                Button {
                    Haptics.selection()
                    item.4()
                } label: {
                    VStack(alignment: .leading, spacing: 6) {
                        SlideCanvas(slide: sample, deck: item.2)
                            .clipShape(RoundedRectangle(cornerRadius: 8))
                            .overlay(RoundedRectangle(cornerRadius: 8).stroke(item.3 ? MinorColor.accent : theme.chatStroke, lineWidth: item.3 ? 2 : 1))
                        Text(item.1).font(.system(size: 13, weight: .medium)).lineLimit(1)
                    }
                }
                .buttonStyle(.plain)
                .accessibilityLabel(item.1)
                .accessibilityAddTraits(item.3 ? .isSelected : [])
                .contextMenu {
                    if let id = item.5 {
                        Button(role: .destructive) { store.delete(id) } label: { Label("Delete Theme", systemImage: "trash") }
                    }
                }
            }
        }
    }
}

// MARK: - Theme editor

struct LookEditor: View {
    let deck: Deck
    let slideIndex: Int
    let theme: AppTheme
    var onApply: (DeckLook) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var look: DeckLook
    @State private var saveToMine = true

    init(deck: Deck, slideIndex: Int, theme: AppTheme, start: DeckLook? = nil, onApply: @escaping (DeckLook) -> Void) {
        self.deck = deck
        self.slideIndex = slideIndex
        self.theme = theme
        self.onApply = onApply
        var initial = start ?? deck.look ?? DeckLook(theme: deck.deckTheme)
        if start == nil && deck.look == nil { initial.name = "" }
        _look = State(initialValue: initial)
    }

    private var preview: Deck {
        var copy = deck
        copy.look = look
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
            .navigationTitle("Own Style")
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
