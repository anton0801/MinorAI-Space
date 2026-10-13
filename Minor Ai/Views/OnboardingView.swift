//
//  OnboardingView.swift
//  Minor Ai
//
//  First launch, a short tour in three steps: a map from any thought, the assistant that
//  changes it on request, and the results (slides, tasks, flashcards). Start goes straight to
//  the assistant; signing in waits until AI is needed, or happens here from "Sign In".
//

import SwiftUI

struct OnboardingView: View {
    var onFinish: () -> Void

    @State private var page = 0
    @State private var showSignIn = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private let theme = AppTheme(sphere: UserDefaults.standard.integer(forKey: "SelectedSphere"))

    private var pages: [(title: String, text: String)] {
        [
            (L("Give Your Thoughts Shape"), L("From a topic, a link or a note to a clear map.")),
            (L("Discuss. Refine. Expand.").replacingOccurrences(of: ". ", with: ".\n"), L("Minor sees your map and changes it when you ask.")),
            (L("From Idea to Result"), L("Slides, tasks and flashcards from your map.")),
        ]
    }
    // Each page's title and text sizes and the room under its words.
    private let titleSizes: [CGFloat] = [38, 38, 34]
    private let textSizes: [CGFloat] = [20, 18, 19]
    private let bottoms: [CGFloat] = [44, 23, 20]
    private var isLast: Bool { page == pages.count - 1 }

    var body: some View {
        ZStack {
            theme.background.ignoresSafeArea()
            VStack {
                Spacer()
                Rectangle().fill(theme.blur).frame(height: 120).blur(radius: 50).opacity(0.5)
            }
            .ignoresSafeArea()
            .allowsHitTesting(false)
            .accessibilityHidden(true)

            if showSignIn {
                SignInView(onFinish: onFinish)
                    .transition(.opacity)
            } else {
                VStack(spacing: 0) {
                    HStack {
                        Text(verbatim: "Minor AI")
                            .minorFont(22, .bold, maxScale: 1.2)
                            .accessibilityHidden(true)
                        Spacer()
                        Button("Skip", action: onFinish)
                            .minorFont(14, maxScale: 1.3)
                            .foregroundColor(MinorColor.textSecondary)
                            .frame(minHeight: 44)
                            .contentShape(Rectangle())
                            .padding(.vertical, -8)   // a full-size target on a slim bar
                            .opacity(isLast ? 0 : 1)
                            .disabled(isLast)
                            .accessibilityHidden(isLast)
                    }
                    .frame(minHeight: 28)
                    .padding(.horizontal, 20)

                    TabView(selection: $page) {
                        ForEach(pages.indices, id: \.self) { index in
                            pageView(index).tag(index)
                        }
                    }
                    .tabViewStyle(.page(indexDisplayMode: .never))

                    HStack(spacing: 10) {
                        ForEach(pages.indices, id: \.self) { index in
                            Circle()
                                .fill(index == page ? MinorColor.accent : Color.white.opacity(0.22))
                                .frame(width: 9, height: 9)
                        }
                    }
                    .animation(.minorMenu, value: page)
                    .padding(.bottom, 26)
                    .accessibilityElement()
                    .accessibilityLabel(Text(L("Page \(page + 1) of \(pages.count)")))

                    Button {
                        if page < pages.count - 1 {
                            withAnimation(reduceMotion ? nil : .minorSheet) { page += 1 }
                        } else {
                            onFinish()
                        }
                    } label: {
                        Text(isLast ? "Get Started" : "Continue")
                            .minorFont(17, .semibold, maxScale: 1.3)
                            .foregroundColor(.black)
                            .frame(maxWidth: .infinity, minHeight: 50)
                            .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(Color.white))
                    }
                    .buttonStyle(PressScale())
                    .padding(.horizontal, 20)

                    Button {
                        withAnimation { showSignIn = true }
                    } label: {
                        (Text("Already have an account?").foregroundColor(MinorColor.textSecondary) + Text(verbatim: " ") + Text("Sign In").bold())
                            .minorFont(15, maxScale: 1.3)
                            .frame(minHeight: 44)
                    }
                    .buttonStyle(.plain)
                    .opacity(isLast ? 1 : 0)
                    .disabled(!isLast)
                    .accessibilityHidden(!isLast)
                    .padding(.top, 4)
                    // Only the last page has the sign-in line; the others keep the button lower.
                    .frame(height: isLast ? 48 : 18, alignment: .top)
                    .clipped()
                }
                .animation(.minorMenu, value: isLast)
            }
        }
        .foregroundColor(MinorColor.textPrimary)
        #if DEBUG
        .onAppear {
            // -onboardingPage 2: open on a page, for screenshots.
            let args = ProcessInfo.processInfo.arguments
            if let i = args.firstIndex(of: "-onboardingPage"), i + 1 < args.count, let n = Int(args[i + 1]) { page = min(max(n, 0), 2) }
        }
        #endif
    }

    // Each page: its scene and its words. The assistant page leads with the words, as a chat does.
    // The scene takes the room the words leave and shrinks only when a short screen needs it.
    private func pageView(_ index: Int) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            if index == 1 {
                words(index).padding(.top, 20)
                GeometryReader { g in
                    scene(index).modifier(FitScale(room: g.size)).frame(width: g.size.width, height: g.size.height)
                }
                .padding(.top, 12)
            } else {
                GeometryReader { g in
                    scene(index).modifier(FitScale(room: g.size)).frame(width: g.size.width, height: g.size.height)
                }
                .background(DotGrid().padding(.horizontal, -20).accessibilityHidden(true))
                .padding(.bottom, 12)
                words(index)
            }
        }
        .padding(.horizontal, 20)
        .padding(.bottom, bottoms[index])
    }

    private func words(_ index: Int) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(pages[index].title)
                .minorFont(titleSizes[index], .heavy, style: .largeTitle, maxScale: 1.2)
                .lineLimit(index == 2 ? 1 : nil)
                .minimumScaleFactor(index == 2 ? 0.6 : 0.7)
                .fixedSize(horizontal: false, vertical: index != 2)
                .accessibilityAddTraits(.isHeader)
            Text(pages[index].text)
                .minorFont(textSizes[index], maxScale: 1.3)
                .foregroundColor(MinorColor.textSecondary)
                .lineSpacing(2)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    @ViewBuilder
    private func scene(_ index: Int) -> some View {
        let active = page == index && !showSignIn
        switch index {
        case 0: ShapeScene(active: active)
        case 1: AssistantScene(active: active)
        default: ResultScene(active: active)
        }
        // The scenes illustrate the words; VoiceOver reads the words.
    }
}

// MARK: - Pieces

// Rings that run out of a selected idea a few times, like on a map.
private struct PulseRings: ViewModifier {
    let color: Color
    let trigger: Int
    var radius: CGFloat = 10
    @State private var run = false

    func body(content: Content) -> some View {
        content.overlay(
            RoundedRectangle(cornerRadius: radius, style: .continuous)
                .stroke(color, lineWidth: 2)
                .scaleEffect(run ? 1.4 : 1)
                .opacity(run ? 0 : (trigger > 0 ? 0.9 : 0))
        )
        .onChange(of: trigger) { value in
            run = false
            guard value > 0 else { return }
            withAnimation(.easeOut(duration: 0.85).repeatCount(3, autoreverses: false)) { run = true }
        }
    }
}

private struct NodeAnchors: PreferenceKey {
    static var defaultValue: [String: Anchor<CGRect>] = [:]
    static func reduce(value: inout [String: Anchor<CGRect>], nextValue: () -> [String: Anchor<CGRect>]) {
        value.merge(nextValue()) { $1 }
    }
}

private extension View {
    func node(_ id: String) -> some View {
        anchorPreference(key: NodeAnchors.self, value: .bounds) { [id: $0] }
    }

    // Lines from a node on the left to a node on the right, whichever is the parent.
    func connectorsBetween(_ links: [(from: String, to: String, color: Color, shown: Bool)]) -> some View {
        connectors(links)
    }

    // Draws a curved line from each parent to its child, growing in when `shown` says so.
    // `spread` lets lines leave the parent above or below its middle, toward their child.
    func connectors(_ links: [(from: String, to: String, color: Color, shown: Bool)], spread: CGFloat = 0, width: CGFloat = 2) -> some View {
        backgroundPreferenceValue(NodeAnchors.self) { anchors in
            GeometryReader { geo in
                ForEach(links.indices, id: \.self) { i in
                    let link = links[i]
                    if let a = anchors[link.from], let b = anchors[link.to] {
                        let from = geo[a], to = geo[b]
                        let lift = max(-from.height * 0.3, min(from.height * 0.3, (to.midY - from.midY) * spread))
                        Curve(start: CGPoint(x: from.maxX - (lift == 0 ? 0 : 4), y: from.midY + lift), end: CGPoint(x: to.minX, y: to.midY))
                            .trim(from: 0, to: link.shown ? 1 : 0)
                            .stroke(link.color, style: StrokeStyle(lineWidth: width, lineCap: .round))
                            .animation(.easeOut(duration: 0.45), value: link.shown)
                    }
                }
            }
        }
    }
}

private struct Curve: Shape {
    let start: CGPoint
    let end: CGPoint

    func path(in rect: CGRect) -> Path {
        var path = Path()
        let mid = (start.x + end.x) / 2
        path.move(to: start)
        path.addCurve(to: end, control1: CGPoint(x: mid, y: start.y), control2: CGPoint(x: mid, y: end.y))
        return path
    }
}

// Runs a scene's steps while its page is on screen and starts over when the page comes back.
private struct Steps: ViewModifier {
    let active: Bool
    @Binding var step: Int
    let last: Int
    let delays: [Double]   // seconds before each step
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func body(content: Content) -> some View {
        content.task(id: active) {
            step = 0
            guard active else { return }
            if reduceMotion { step = last; return }
            for (i, delay) in delays.enumerated() {
                try? await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
                guard !Task.isCancelled else { return }
                withAnimation(.spring(response: 0.45, dampingFraction: 0.75)) { step = i + 1 }
            }
        }
    }
}

// MARK: - Page 1: notes, links and ideas become one map

private struct ShapeScene: View {
    let active: Bool
    @State private var step = 0

    private var sources: [(icon: String?, title: String, color: BranchColor)] {
        [(nil, L("Idea"), .mint), ("link", L("Link"), .sky), ("doc.text", L("Note"), .lilac)]
    }
    private let branches: [BranchColor] = [.sun, .pink, .coral]

    var body: some View {
        HStack(spacing: 0) {
            VStack(spacing: 21) {
                ForEach(sources.indices, id: \.self) { i in
                    card(i)
                        .node("s\(i)")
                        .opacity(step > i ? 1 : 0)
                        .offset(x: step > i ? 0 : -10)
                }
            }
            Spacer(minLength: 24)
            Text(L("My Project"))
                .font(.system(size: 17, weight: .bold))
                .foregroundColor(.black)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
                .padding(.horizontal, 14)
                .frame(minWidth: 122, minHeight: 54)
                .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(Color(white: 0.96)))
                .shadow(color: .white.opacity(0.16), radius: 18)
                .fixedSize()
                .node("root")
                .opacity(step >= 4 ? 1 : 0)
                .scaleEffect(step >= 4 ? 1 : 0.7)
            Spacer(minLength: 28)
            VStack(spacing: 48) {
                ForEach(branches.indices, id: \.self) { i in
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(branches[i].color.opacity(0.16))
                        .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).stroke(branches[i].color, lineWidth: 2))
                        .overlay(Capsule().fill(branches[i].color.opacity(0.85)).frame(width: 33, height: 6))
                        .frame(width: 61, height: 33)
                        .node("b\(i)")
                        .opacity(step >= 5 + i ? 1 : 0)
                        .offset(x: step >= 5 + i ? 0 : -10)
                }
            }
        }
        .frame(maxWidth: 360)
        .hubLinks(
            into: sources.indices.map { i in ("s\(i)", sources[i].color.color, step >= 4) },
            out: branches.indices.map { i in ("b\(i)", branches[i].color, step >= 5 + i) }
        )
        .modifier(Steps(active: active, step: $step, last: 7, delays: [0.25, 0.2, 0.2, 0.45, 0.4, 0.18, 0.18]))
    }

    private func card(_ i: Int) -> some View {
        let source = sources[i]
        return VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 11) {
                Group {
                    if let icon = source.icon {
                        Image(systemName: icon).font(.system(size: 19, weight: .medium))
                    } else {
                        PageGlyph()
                    }
                }
                .foregroundColor(source.color.color)
                .frame(width: 24, height: 24)
                Text(source.title).font(.system(size: 15)).lineLimit(1).minimumScaleFactor(0.8)
            }
            Capsule().fill(Color.white.opacity(0.16)).frame(width: 75, height: 5).padding(.top, 14)
            Capsule().fill(Color.white.opacity(0.11)).frame(width: 39, height: 5).padding(.top, 9)
        }
        .padding(.leading, 16)
        .padding(.vertical, 14)
        .frame(width: 116, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 13, style: .continuous).fill(Color.white.opacity(0.05)))
        .overlay(RoundedRectangle(cornerRadius: 13, style: .continuous).stroke(Color.white.opacity(0.12), lineWidth: 1))
    }
}

// A page with lines of text, the Idea card's mark.
private struct PageGlyph: View {
    var body: some View {
        RoundedRectangle(cornerRadius: 4, style: .continuous)
            .stroke(lineWidth: 2)
            .frame(width: 18, height: 22)
            .overlay(
                VStack(alignment: .leading, spacing: 3.5) {
                    Capsule().frame(width: 9, height: 2)
                    Capsule().frame(width: 9, height: 2)
                    Capsule().frame(width: 6, height: 2)
                }
            )
    }
}

private extension View {
    // Lines from the cards into the topic and from the topic out to its branches, with a dot where
    // each line meets a card or a branch. A line that isn't level with the topic bends into its top
    // or bottom edge, as on the map.
    func hubLinks(into: [(id: String, color: Color, shown: Bool)], out: [(id: String, color: Color, shown: Bool)]) -> some View {
        backgroundPreferenceValue(NodeAnchors.self) { anchors in
            GeometryReader { geo in
                if let r = anchors["root"].map({ geo[$0] }) {
                    ForEach(into.indices, id: \.self) { i in
                        if let a = anchors[into[i].id].map({ geo[$0] }) {
                            HubCurve(edge: CGPoint(x: a.maxX, y: a.minY + a.height * 0.43), hub: r, outward: false)
                                .trim(from: 0, to: into[i].shown ? 1 : 0)
                                .stroke(into[i].color, style: StrokeStyle(lineWidth: 2.5, lineCap: .round))
                                .animation(.easeOut(duration: 0.45), value: into[i].shown)
                        }
                    }
                    ForEach(out.indices, id: \.self) { i in
                        if let b = anchors[out[i].id].map({ geo[$0] }) {
                            HubCurve(edge: CGPoint(x: b.minX, y: b.midY), hub: r, outward: true)
                                .trim(from: 0, to: out[i].shown ? 1 : 0)
                                .stroke(out[i].color, style: StrokeStyle(lineWidth: 2.5, lineCap: .round))
                                .animation(.easeOut(duration: 0.45), value: out[i].shown)
                        }
                    }
                }
            }
        }
        .overlayPreferenceValue(NodeAnchors.self) { anchors in
            GeometryReader { geo in
                ForEach(into.indices, id: \.self) { i in
                    if let a = anchors[into[i].id].map({ geo[$0] }) {
                        Circle().fill(into[i].color).frame(width: 9, height: 9)
                            .position(x: a.maxX, y: a.minY + a.height * 0.43)
                            .opacity(into[i].shown ? 1 : 0)
                    }
                }
                ForEach(out.indices, id: \.self) { i in
                    if let b = anchors[out[i].id].map({ geo[$0] }) {
                        Circle().fill(out[i].color).frame(width: 9, height: 9)
                            .position(x: b.minX, y: b.midY)
                            .opacity(out[i].shown ? 1 : 0)
                    }
                }
            }
            .allowsHitTesting(false)
        }
    }
}

// A line between a point beside the topic and the topic itself. Level with the topic it runs
// straight in; above or below, it leaves the point flat and turns into the topic's edge.
private struct HubCurve: Shape {
    let edge: CGPoint
    let hub: CGRect
    let outward: Bool   // drawn from the topic out to the point

    func path(in rect: CGRect) -> Path {
        var path = Path()
        let inset = hub.width * 0.2
        if abs(edge.y - hub.midY) < 10 {
            let end = CGPoint(x: outward ? hub.maxX - 1 : hub.minX + 1, y: edge.y)
            path.move(to: outward ? end : edge)
            path.addLine(to: outward ? edge : end)
            return path
        }
        let inner = CGPoint(x: outward ? hub.maxX - inset : hub.minX + inset, y: hub.midY)
        let flat = CGPoint(x: edge.x + (inner.x - edge.x) * 0.55, y: edge.y)
        let turn = CGPoint(x: inner.x, y: edge.y + (inner.y - edge.y) * 0.4)
        if outward {
            path.move(to: inner)
            path.addCurve(to: edge, control1: turn, control2: flat)
        } else {
            path.move(to: edge)
            path.addCurve(to: inner, control1: flat, control2: turn)
        }
        return path
    }
}

// Shrinks a scene to the room it has (a short screen or a large text size), never grows it.
private struct FitScale: ViewModifier {
    let room: CGSize
    @State private var natural: CGSize = .zero

    func body(content: Content) -> some View {
        let scale = natural.width > 0 && natural.height > 0
            ? min(1, room.width / natural.width, room.height / natural.height) : 1
        content
            .fixedSize(horizontal: false, vertical: true)
            // The scene's own size, read where it is laid out (before it is scaled).
            .background(
                GeometryReader { g in
                    Color.clear
                        .onAppear { natural = g.size }
                        .onChange(of: g.size) { natural = $0 }
                }
            )
            .scaleEffect(scale)
    }
}

// MARK: - Page 2: the assistant changes the map on request

private struct AssistantScene: View {
    let active: Bool
    @State private var step = 0
    @State private var pulse = 0

    private var ideas: [(title: String, color: BranchColor)] {
        [(L("Story"), .sky), (L("Interview"), .lilac), (L("Breakdown"), .pink)]
    }

    var body: some View {
        VStack(spacing: 0) {
            message
                .node("ask")
                .frame(maxWidth: .infinity, alignment: .trailing)
                .opacity(step >= 1 ? 1 : 0)
                .offset(y: step >= 1 ? 0 : 8)
            answer
                .node("answer")
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.top, 16)
                .opacity(step >= 2 ? 1 : 0)
                .offset(y: step >= 2 ? 0 : 10)
            composer
                .padding(.top, 18)
                .padding(.horizontal, -13)
        }
        .frame(maxWidth: 353)
        // The answer hangs off the request, like a reply in a thread.
        .backgroundPreferenceValue(NodeAnchors.self) { anchors in
            GeometryReader { geo in
                if let a = anchors["ask"].map({ geo[$0] }), let b = anchors["answer"].map({ geo[$0] }) {
                    Path { path in
                        let x = b.minX + 75, y = a.midY, r: CGFloat = 12
                        path.move(to: CGPoint(x: a.minX, y: y))
                        path.addLine(to: CGPoint(x: x + r, y: y))
                        path.addQuadCurve(to: CGPoint(x: x, y: y + r), control: CGPoint(x: x, y: y))
                        path.addLine(to: CGPoint(x: x, y: b.minY))
                    }
                    .stroke(BranchColor.mint.color.opacity(0.85), lineWidth: 1.5)
                    .opacity(step >= 2 ? 1 : 0)
                }
            }
        }
        .modifier(Steps(active: active, step: $step, last: 6, delays: [0.3, 0.6, 0.35, 0.3, 0.18, 0.18]))
        .onChange(of: step) { value in if value == 3 { pulse += 1 } }
    }

    private var message: some View {
        HStack(alignment: .top, spacing: 10) {
            VStack(alignment: .trailing, spacing: 4) {
                Text(L("Add ideas for the first episode"))
                    .font(.system(size: 15))
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
                HStack(spacing: 4) {
                    Text(verbatim: "9:41").font(.system(size: 11).monospacedDigit()).foregroundColor(MinorColor.textTertiary)
                    ZStack {
                        Image(systemName: "checkmark").offset(x: -3)
                        Image(systemName: "checkmark").offset(x: 2)
                    }
                    .font(.system(size: 9, weight: .bold))
                    .foregroundColor(BranchColor.mint.color)
                }
            }
            Image(systemName: "person.fill")
                .font(.system(size: 14))
                .foregroundColor(MinorColor.textSecondary)
                .frame(width: 32, height: 32)
                .background(Circle().fill(Color.white.opacity(0.12)))
        }
        .padding(.leading, 16)
        .padding(.trailing, 8)
        .padding(.vertical, 10)
        .frame(width: 251)
        .background(RoundedRectangle(cornerRadius: 18, style: .continuous).fill(Color.white.opacity(0.08)))
        .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).stroke(Color.white.opacity(0.1), lineWidth: 1))
    }

    private var answer: some View {
        let shape = RoundedRectangle(cornerRadius: 18, style: .continuous)
        return VStack(spacing: 0) {
            HStack(spacing: 12) {
                Image(systemName: "waveform")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundColor(MinorColor.accent)
                    .frame(width: 32, height: 32)
                    .background(Circle().fill(BranchColor.mint.color.opacity(0.12)))
                Text(L("Added 3 ideas")).font(.system(size: 15.5))
                Spacer(minLength: 0)
                Text(verbatim: "9:41").font(.system(size: 11).monospacedDigit()).foregroundColor(MinorColor.textTertiary)
            }
            .padding(.horizontal, 10)
            .frame(height: 49)
            .background(Color.white.opacity(0.035))

            HStack(spacing: 41) {
                Text(L("Podcast launch"))
                    .font(.system(size: 15.5))
                    .multilineTextAlignment(.center)
                    .lineLimit(2)
                    .minimumScaleFactor(0.8)
                    .frame(width: 92)
                    .frame(width: 110, height: 51)
                    .background(Capsule().fill(Color(hex: "#0E1A15")))
                    .overlay(Capsule().stroke(BranchColor.mint.color, lineWidth: 2.5))
                    .modifier(PulseRings(color: BranchColor.mint.color, trigger: pulse, radius: 25.5))
                    .node("root")
                VStack(alignment: .leading, spacing: 15) {
                    ForEach(ideas.indices, id: \.self) { i in
                        Text(ideas[i].title)
                            .font(.system(size: 15.5))
                            .lineLimit(1)
                            .padding(.horizontal, 24)
                            .frame(height: 35)
                            .background(Capsule().fill(ideas[i].color.color.opacity(0.1)))
                            .overlay(Capsule().stroke(ideas[i].color.color, lineWidth: 2.5))
                            .node("n\(i)")
                            .opacity(step >= 4 + i ? 1 : 0)
                            .offset(x: step >= 4 + i ? 0 : -10)
                    }
                }
            }
            .connectors(ideas.indices.map { i in ("root", "n\(i)", ideas[i].color.color, step >= 4 + i) }, spread: 0.3, width: 2.5)
            .padding(.leading, 35)
            .frame(maxWidth: .infinity, alignment: .leading)
            .frame(height: 162)
            .background(DotGrid().accessibilityHidden(true))
        }
        .frame(width: 341)
        .background(shape.fill(Color.white.opacity(0.05)))
        .clipShape(shape)
        .overlay(shape.stroke(Color.white.opacity(0.1), lineWidth: 1))
    }

    private var composer: some View {
        HStack(spacing: 10) {
            Image(systemName: "plus")
                .font(.system(size: 17, weight: .regular))
                .foregroundColor(MinorColor.textSecondary)
                .frame(width: 40, height: 40)
                .background(Circle().fill(Color.white.opacity(0.08)))
            Text(L("Message Minor AI"))
                .font(.system(size: 15.5))
                .foregroundColor(MinorColor.textTertiary)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
                .padding(.horizontal, 14)
                .frame(maxWidth: .infinity, minHeight: 40, alignment: .leading)
                .background(Capsule().fill(Color.white.opacity(0.05)))
            Image(systemName: "mic.fill")
                .font(.system(size: 15))
                .foregroundColor(MinorColor.textSecondary)
                .frame(width: 40, height: 40)
                .background(Circle().fill(Color.white.opacity(0.08)))
            Image(systemName: "arrow.up")
                .font(.system(size: 17, weight: .semibold))
                .foregroundColor(.black)
                .frame(width: 41, height: 41)
                .background(Circle().fill(Color.white))
        }
        .padding(.horizontal, 10)
        .frame(height: 65)
        .background(RoundedRectangle(cornerRadius: 24, style: .continuous).fill(Color.white.opacity(0.06)))
        .overlay(RoundedRectangle(cornerRadius: 24, style: .continuous).stroke(Color.white.opacity(0.1), lineWidth: 1))
    }
}

// MARK: - Page 3: slides, tasks and flashcards from the map

private struct ResultScene: View {
    let active: Bool
    @State private var step = 0

    private var branches: [(icon: String, title: String, color: BranchColor)] {
        [("doc.text", L("Idea and format"), .mint), ("person.2", L("Audience"), .sky), ("mic", L("Equipment"), .lilac),
         ("list.bullet", L("Episode plan"), .sun), ("waveform", L("Promotion"), .pink), ("checkmark.circle", L("Tasks"), .coral)]
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 0) {
                VStack(spacing: 15) {
                    ForEach(0..<3, id: \.self) { i in pill(i).node("l\(i)") }
                }
                Spacer(minLength: 16)
                Text(L("Podcast launch"))
                    .font(.system(size: 13, weight: .semibold))
                    .multilineTextAlignment(.center)
                    .lineLimit(2)
                    .minimumScaleFactor(0.8)
                    .padding(.horizontal, 8)
                    .frame(width: 98, height: 50)
                    .background(RoundedRectangle(cornerRadius: 13, style: .continuous).fill(Color(hex: "#0E1A15")))
                    .overlay(RoundedRectangle(cornerRadius: 13, style: .continuous).stroke(BranchColor.mint.color, lineWidth: 2))
                    .shadow(color: BranchColor.mint.color.opacity(0.45), radius: 12)
                    .node("root")
                    .opacity(step >= 1 ? 1 : 0)
                Spacer(minLength: 16)
                VStack(spacing: 15) {
                    ForEach(3..<6, id: \.self) { i in pill(i).node("r\(i)") }
                }
            }
            .connectorsBetween(
                (0..<3).map { i in ("l\(i)", "root", branches[i].color.color, step >= 2) }
                + (3..<6).map { i in ("root", "r\(i)", branches[i].color.color, step >= 2) }
            )

            // From the map down to the slide.
            VStack(spacing: 0) {
                Rectangle().fill(BranchColor.mint.color).frame(width: 2, height: 80)
                Image(systemName: "chevron.down")
                    .font(.system(size: 13, weight: .bold))
                    .foregroundColor(BranchColor.mint.color)
                    .padding(.top, -7)
            }
            .shadow(color: BranchColor.mint.color.opacity(0.6), radius: 6)
            .opacity(step >= 3 ? 1 : 0)
            .padding(.top, -51)

            slide
                .padding(.top, 16)
                // Room for the rest of the deck behind it, so nothing reaches the words below.
                .padding(.bottom, 14)
                .padding(.leading, 10)
                .opacity(step >= 4 ? 1 : 0)
                .offset(y: step >= 4 ? 0 : 16)
        }
        .frame(maxWidth: 356)
        .modifier(Steps(active: active, step: $step, last: 4, delays: [0.25, 0.35, 0.45, 0.35]))
    }

    // A slide made from the same map, on top of the rest of the deck.
    private var slide: some View {
        let shape = RoundedRectangle(cornerRadius: 12, style: .continuous)
        return HStack(alignment: .center, spacing: 0) {
            VStack(alignment: .leading, spacing: 0) {
                Text(verbatim: "Minor AI").font(.system(size: 8, weight: .semibold)).foregroundColor(.black.opacity(0.5))
                Spacer(minLength: 10)
                Text(L("Podcast launch"))
                    .font(.system(size: 30, weight: .heavy))
                    .foregroundColor(.black)
                    .lineLimit(2)
                    .minimumScaleFactor(0.6)
                    .fixedSize(horizontal: false, vertical: true)
                Text(L("Ideas. Plan. Recording. Promotion. Growth."))
                    .font(.system(size: 9.5))
                    .foregroundColor(.black.opacity(0.55))
                    .lineLimit(2)
                    .padding(.top, 8)
                Spacer(minLength: 10)
                HStack(spacing: 6) {
                    ZStack(alignment: .leading) {
                        Capsule().fill(Color.black.opacity(0.12)).frame(width: 28, height: 2)
                        Capsule().fill(Color.black.opacity(0.7)).frame(width: 9, height: 2)
                    }
                    Text(verbatim: "01 / 12").font(.system(size: 7.5, weight: .medium).monospacedDigit()).foregroundColor(.black.opacity(0.45))
                }
            }
            .frame(width: 160, alignment: .leading)
            Spacer(minLength: 0)
            ZStack {
                HStack(spacing: 2.5) {
                    bars([8, 16, 26, 40, 22, 52, 34, 18, 44, 26])
                    Color.clear.frame(width: 44)
                    bars([30, 48, 20, 38, 14, 26, 10])
                }
                Microphone()
            }
            .frame(height: 150)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
        .frame(width: 344, height: 194)
        .background(shape.fill(Color(hex: "#F3F0EA")))
        .overlay(alignment: .topTrailing) {
            Image(systemName: "ellipsis").font(.system(size: 10, weight: .bold)).foregroundColor(.black.opacity(0.45)).padding(12)
        }
        .background(
            ZStack {
                shape.fill(Color(white: 0.24)).rotationEffect(.degrees(-3.5)).offset(x: -9, y: 9)
                shape.fill(Color(white: 0.34)).rotationEffect(.degrees(-1.8)).offset(x: -4, y: 4)
            }
        )
        .background(
            Ellipse().fill(BranchColor.mint.color.opacity(0.22)).frame(width: 260, height: 60).blur(radius: 30).offset(y: -96)
        )
        .rotationEffect(.degrees(step >= 4 ? -1.2 : 3))
    }

    private func bars(_ heights: [CGFloat]) -> some View {
        HStack(alignment: .center, spacing: 2.5) {
            ForEach(heights.indices, id: \.self) { i in
                Capsule().fill(Color(hex: "#3DDC97").opacity(0.9)).frame(width: 2.5, height: heights[i])
            }
        }
    }

    private func pill(_ i: Int) -> some View {
        let title = branches[i].title
        return HStack(spacing: 7) {
            Image(systemName: branches[i].icon)
                .font(.system(size: 13, weight: .medium))
                .foregroundColor(branches[i].color.color)
                .frame(width: 17)
            Text(title)
                .font(.system(size: 10.5, weight: .medium))
                .lineLimit(title.contains(" ") ? 2 : 1)
                .minimumScaleFactor(0.6)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 8)
        .frame(width: 106, height: 41)
        .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(branches[i].color.color.opacity(0.08)))
        .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).stroke(branches[i].color.color, lineWidth: 1.5))
        .opacity(step >= 2 ? 1 : 0)
    }
}

// A studio microphone on its stand, drawn for the slide.
private struct Microphone: View {
    var body: some View {
        VStack(spacing: 0) {
            ZStack {
                Capsule().fill(LinearGradient(colors: [Color(white: 0.32), Color(white: 0.04)], startPoint: .leading, endPoint: .trailing))
                    .frame(width: 38, height: 66)
                VStack(spacing: 3.5) {
                    ForEach(0..<8, id: \.self) { _ in Capsule().fill(Color.white.opacity(0.1)).frame(width: 30, height: 1.5) }
                }
                .padding(.bottom, 12)
            }
            .overlay(alignment: .bottom) {
                // The cradle around the microphone.
                RoundedRectangle(cornerRadius: 11).stroke(Color(white: 0.1), lineWidth: 3.5).frame(width: 50, height: 30).offset(y: 7).mask(Rectangle().frame(height: 26).offset(y: 12))
            }
            Rectangle().fill(Color(white: 0.1)).frame(width: 4.5, height: 34).padding(.top, 8)
            Capsule().fill(LinearGradient(colors: [Color(white: 0.25), Color(white: 0.04)], startPoint: .top, endPoint: .bottom)).frame(width: 56, height: 9)
        }
        .shadow(color: .black.opacity(0.25), radius: 4, y: 3)
    }
}

// The faint dot grid of the map canvas, behind the scenes.
private struct DotGrid: View {
    var body: some View {
        Canvas { context, size in
            var dots = Path()
            var y: CGFloat = 8
            while y < size.height {
                var x: CGFloat = 8
                while x < size.width {
                    dots.addEllipse(in: CGRect(x: x - 1, y: y - 1, width: 2, height: 2))
                    x += 22
                }
                y += 22
            }
            context.fill(dots, with: .color(.white.opacity(0.06)))
        }
        .mask(LinearGradient(colors: [.clear, .white, .white, .clear], startPoint: .top, endPoint: .bottom))
    }
}

