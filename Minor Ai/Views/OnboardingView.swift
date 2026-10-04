//
//  OnboardingView.swift
//  Minor Ai
//
//  Four first-launch pages, then Sign in. Each page plays a short scene of the real thing:
//  a topic grows into a map, the sources, Expand with AI, tasks and presentations.
//

import SwiftUI

struct OnboardingView: View {
    var onFinish: () -> Void

    @State private var page = 0
    @State private var showSignIn = false

    private let theme = AppTheme(sphere: UserDefaults.standard.integer(forKey: "SelectedSphere"))

    private var pages: [(title: String, text: String)] {
        [
            (L("Give Your Thoughts Shape"), L("Type a topic, and Minor builds a map you can grow — in seconds.")),
            (L("Start From Anything"), L("A document, a link, a YouTube video, your voice or a photo of your notes.")),
            (L("Go Deeper"), L("Tap an idea and Expand: AI adds examples and explanations. The assistant knows all your maps.")),
            (L("Turn Ideas Into Action"), L("Tasks with dates, the Today screen, reminders and presentations from any map.")),
        ]
    }

    var body: some View {
        ZStack {
            theme.background.ignoresSafeArea()
            VStack {
                Spacer()
                Rectangle().fill(theme.blur).frame(height: 120).blur(radius: 50).opacity(0.5)
            }
            .ignoresSafeArea()
            .allowsHitTesting(false)

            if showSignIn {
                SignInView(onFinish: onFinish)
                    .transition(.opacity)
            } else {
                VStack(spacing: 0) {
                    HStack {
                        Spacer()
                        Button("Skip") { withAnimation { showSignIn = true } }
                            .font(.system(size: 17))
                            .foregroundColor(MinorColor.textSecondary)
                            .frame(height: 44)
                    }
                    .padding(.horizontal, 20)

                    TabView(selection: $page) {
                        ForEach(pages.indices, id: \.self) { index in
                            VStack(spacing: 0) {
                                scene(index)
                                    .frame(height: 340)
                                    .frame(maxWidth: .infinity)
                                    .accessibilityHidden(true)
                                Text(pages[index].title)
                                    .font(.system(size: 26, weight: .bold))
                                    .multilineTextAlignment(.center)
                                    .padding(.top, 28)
                                    .padding(.horizontal, 24)
                                Text(pages[index].text)
                                    .font(.system(size: 16))
                                    .foregroundColor(MinorColor.textSecondary)
                                    .multilineTextAlignment(.center)
                                    .fixedSize(horizontal: false, vertical: true)
                                    .padding(.top, 10)
                                    .padding(.horizontal, 36)
                                Spacer(minLength: 0)
                            }
                            .tag(index)
                        }
                    }
                    .tabViewStyle(.page(indexDisplayMode: .never))

                    HStack(spacing: 8) {
                        ForEach(pages.indices, id: \.self) { index in
                            Capsule()
                                .fill(index == page ? Color.white : theme.chatStroke)
                                .frame(width: index == page ? 22 : 7, height: 7)
                        }
                    }
                    .animation(.minorMenu, value: page)
                    .padding(.bottom, 24)
                    .accessibilityHidden(true)

                    Button {
                        if page < pages.count - 1 {
                            withAnimation(.minorSheet) { page += 1 }
                        } else {
                            withAnimation { showSignIn = true }
                        }
                    } label: {
                        Text(page < pages.count - 1 ? "Continue" : "Get Started")
                            .font(.system(size: 17, weight: .semibold))
                            .foregroundColor(.black)
                            .frame(maxWidth: .infinity)
                            .frame(height: 50)
                            .background(Capsule().fill(MinorColor.sendFill))
                    }
                    .padding(.horizontal, 16)
                    .padding(.bottom, 12)
                }
            }
        }
        .foregroundColor(MinorColor.textPrimary)
    }

    @ViewBuilder
    private func scene(_ index: Int) -> some View {
        let active = page == index && !showSignIn
        switch index {
        case 0: GrowScene(active: active)
        case 1: SourcesScene(active: active)
        case 2: ExpandScene(active: active)
        default: ActionScene(active: active)
        }
    }
}

// MARK: - Pieces

// A node as it looks on a map.
private struct Chip: View {
    let title: String
    var color: BranchColor? = nil
    var badge: String? = nil
    var selected = false
    var glowing = false
    var sparkle = false

    var body: some View {
        let root = color == nil
        let shape = RoundedRectangle(cornerRadius: root ? 13 : 10, style: .continuous)
        HStack(spacing: 6) {
            if sparkle {
                Image(systemName: "sparkle").font(.system(size: 10, weight: .bold)).foregroundColor(color?.color)
            }
            Text(title)
                .font(.system(size: root ? 15 : 13.5, weight: root ? .bold : .semibold))
                .lineLimit(1)
        }
        .foregroundColor(root ? .black : .white)
        .padding(.horizontal, root ? 15 : 11)
        .padding(.vertical, root ? 10 : 7)
        .background(shape.fill(root ? Color(white: 0.95) : color!.tint))
        .overlay(shape.stroke(root ? Color.clear : color!.line, lineWidth: 1))
        .overlay(shape.stroke(color?.color ?? .white, lineWidth: 2).opacity(selected ? 1 : 0))
        .shadow(color: (color?.color ?? .white).opacity(glowing ? 0.7 : (root ? 0.18 : 0)), radius: glowing ? 14 : 18)
        .overlay(alignment: .trailing) {
            if let badge {
                Text(badge)
                    .font(.system(size: 10, weight: .semibold))
                    .padding(.horizontal, 5)
                    .padding(.vertical, 2)
                    .overlay(Capsule().stroke(color?.line ?? .white, lineWidth: 1))
                    .fixedSize()
                    .offset(x: 30)
            }
        }
    }
}

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

    // Draws a curved line from each parent to its child, growing in when `shown` says so.
    func connectors(_ links: [(from: String, to: String, color: Color, shown: Bool)]) -> some View {
        backgroundPreferenceValue(NodeAnchors.self) { anchors in
            GeometryReader { geo in
                ForEach(links.indices, id: \.self) { i in
                    let link = links[i]
                    if let a = anchors[link.from], let b = anchors[link.to] {
                        let from = geo[a], to = geo[b]
                        Curve(start: CGPoint(x: from.maxX, y: from.midY), end: CGPoint(x: to.minX, y: to.midY))
                            .trim(from: 0, to: link.shown ? 1 : 0)
                            .stroke(link.color, style: StrokeStyle(lineWidth: 2, lineCap: .round))
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

// MARK: - Page 1: a topic grows into a map

private struct GrowScene: View {
    let active: Bool
    @State private var step = 0
    @State private var typed = ""
    @State private var pulse = 0
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var topic: String { L("Project launch") }
    private var branches: [(title: String, color: BranchColor, count: Int)] {
        [(L("Audience"), .mint, 3), (L("Product"), .lilac, 4), (L("Marketing"), .pink, 3), (L("Launch"), .sun, 2)]
    }

    var body: some View {
        VStack(spacing: 34) {
            HStack(spacing: 8) {
                Group {
                    if typed.isEmpty {
                        Text(L("Map any topic or paste a link")).foregroundColor(MinorColor.textTertiary)
                    } else {
                        Text(typed) + Text("|").foregroundColor(MinorColor.accent)
                    }
                }
                .font(.system(size: 15))
                .lineLimit(1)
                Spacer(minLength: 0)
                Image(systemName: "arrow.up")
                    .font(.system(size: 13, weight: .bold))
                    .foregroundColor(step >= 1 ? .black : MinorColor.textTertiary)
                    .frame(width: 30, height: 30)
                    .background(Circle().fill(step >= 1 ? Color.white : Color.white.opacity(0.12)))
            }
            .padding(.leading, 16)
            .padding(.trailing, 6)
            .frame(width: 300, height: 44)
            .background(Capsule().fill(Color.white.opacity(0.06)))
            .overlay(Capsule().stroke(typed.isEmpty ? Color.white.opacity(0.14) : MinorColor.accent.opacity(0.6), lineWidth: 1))

            HStack(spacing: 48) {
                Chip(title: topic)
                    .node("root")
                    .opacity(step >= 2 ? 1 : 0)
                    .scaleEffect(step >= 2 ? 1 : 0.7)
                VStack(alignment: .leading, spacing: 14) {
                    ForEach(branches.indices, id: \.self) { i in
                        let branch = branches[i]
                        let isLaunch = i == branches.count - 1
                        Chip(title: branch.title, color: branch.color, badge: "+\(branch.count)", selected: isLaunch && step >= 7)
                            .modifier(PulseRings(color: branch.color.color, trigger: isLaunch ? pulse : 0))
                            .node("b\(i)")
                            .opacity(step >= 3 + i ? 1 : 0)
                            .offset(x: step >= 3 + i ? 0 : -12)
                    }
                }
                .padding(.trailing, 30)
            }
            .connectors(branches.indices.map { i in ("root", "b\(i)", branches[i].color.line, step >= 3 + i) })
        }
        .task(id: active) {
            typed = ""
            pulse = 0
            guard active else { return }
            if reduceMotion { typed = topic; return }
            try? await Task.sleep(nanoseconds: 450_000_000)
            for count in 1...topic.count {
                guard !Task.isCancelled else { return }
                typed = String(topic.prefix(count))
                try? await Task.sleep(nanoseconds: 55_000_000)
            }
        }
        .modifier(Steps(active: active, step: $step, last: 7,
                        delays: [0.45 + Double(topic.count) * 0.055 + 0.3, 0.5, 0.45, 0.2, 0.2, 0.2, 0.7]))
        .onChange(of: step) { value in if value == 7 { pulse += 1 } }
    }
}

// MARK: - Page 2: the sources

private struct SourcesScene: View {
    let active: Bool
    @State private var step = 0
    @State private var selected = 0

    private var tiles: [(icon: String, title: String, caption: String)] {
        [
            ("textformat", L("Topic"), L("Type any subject")),
            ("doc.text", L("Document"), L("PDF, TXT or RTF")),
            ("link", L("Link"), L("Article or web page")),
            ("play.rectangle", L("YouTube"), L("Video transcript")),
            ("mic", L("Voice"), L("Talk it through")),
            ("doc.viewfinder", L("Scan"), L("Notes, slides, a whiteboard")),
        ]
    }

    var body: some View {
        LazyVGrid(columns: [GridItem(.fixed(160), spacing: 10), GridItem(.fixed(160), spacing: 10)], spacing: 10) {
            ForEach(tiles.indices, id: \.self) { i in
                let tile = tiles[i]
                VStack(alignment: .leading, spacing: 4) {
                    Image(systemName: tile.icon).font(.system(size: 20))
                    Spacer(minLength: 10)
                    Text(tile.title).font(.system(size: 15, weight: .semibold))
                    Text(tile.caption).font(.system(size: 11)).foregroundColor(MinorColor.textTertiary).lineLimit(1)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 12)
                .padding(.vertical, 12)
                .frame(height: 100)
                .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(Color.white.opacity(0.04)))
                .overlay(
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .stroke(selected == i && step >= tiles.count ? MinorColor.accent : Color.white.opacity(0.14), lineWidth: selected == i && step >= tiles.count ? 1.5 : 1)
                )
                .shadow(color: MinorColor.accent.opacity(selected == i && step >= tiles.count ? 0.25 : 0), radius: 14)
                .opacity(step > i ? 1 : 0)
                .scaleEffect(step > i ? 1 : 0.85)
            }
        }
        .modifier(Steps(active: active, step: $step, last: tiles.count, delays: [0.25] + Array(repeating: 0.12, count: tiles.count - 1)))
        .task(id: active) {
            selected = 0
            guard active else { return }
            // The highlight moves across a few sources, as if picking one.
            try? await Task.sleep(nanoseconds: 1_300_000_000)
            for next in [1, 5, 3, 4, 2, 0].cycled() {
                guard !Task.isCancelled else { return }
                withAnimation(.easeInOut(duration: 0.35)) { selected = next }
                try? await Task.sleep(nanoseconds: 1_100_000_000)
            }
        }
    }
}

private extension Array {
    // The same items again and again, for as long as the caller keeps asking.
    func cycled() -> AnySequence<Element> {
        AnySequence { () -> AnyIterator<Element> in
            var index = 0
            return AnyIterator {
                guard !self.isEmpty else { return nil }
                defer { index = (index + 1) % self.count }
                return self[index]
            }
        }
    }
}

// MARK: - Page 3: Expand with AI

private struct ExpandScene: View {
    let active: Bool
    @State private var step = 0
    @State private var pulse = 0

    private var ideas: [String] { [L("Free plan"), L("Monthly and yearly"), L("Student discount")] }

    var body: some View {
        VStack(spacing: 40) {
            HStack(spacing: 46) {
                Chip(title: L("Pricing"), color: .sky, selected: step >= 1, glowing: step == 4)
                    .modifier(PulseRings(color: BranchColor.sky.color, trigger: pulse))
                    .node("idea")
                    .opacity(step >= 1 ? 1 : 0)
                VStack(alignment: .leading, spacing: 12) {
                    ForEach(ideas.indices, id: \.self) { i in
                        Chip(title: ideas[i], color: .sky, sparkle: true)
                            .node("n\(i)")
                            .opacity(step >= 5 + i ? 1 : 0)
                            .offset(x: step >= 5 + i ? 0 : -12)
                    }
                }
            }
            .frame(height: 140)
            .connectors(ideas.indices.map { i in ("idea", "n\(i)", BranchColor.sky.line, step >= 5 + i) })

            HStack(spacing: 4) {
                Label(L("Expand"), systemImage: "sparkles")
                    .font(.system(size: 14, weight: .semibold))
                    .lineLimit(1)
                    .fixedSize()
                    .foregroundColor(.black)
                    .padding(.horizontal, 13)
                    .frame(height: 34)
                    .background(Capsule().fill(MinorColor.accent))
                    .scaleEffect(step == 3 ? 0.9 : 1)
                    .shadow(color: MinorColor.accent.opacity(step == 3 ? 0.6 : 0), radius: 10)
                ForEach([L("Ask"), L("Edit"), L("Style")], id: \.self) { title in
                    Text(title)
                        .font(.system(size: 14))
                        .lineLimit(1)
                        .fixedSize()
                        .padding(.horizontal, 9)
                        .frame(height: 34)
                }
            }
            .padding(4)
            .background(Capsule().fill(Color.white.opacity(0.06)))
            .overlay(Capsule().stroke(Color.white.opacity(0.14), lineWidth: 1))
            .opacity(step >= 2 ? 1 : 0)
            .offset(y: step >= 2 ? 0 : 12)
        }
        .modifier(Steps(active: active, step: $step, last: 8, delays: [0.3, 0.7, 0.9, 0.25, 0.8, 0.18, 0.18, 0.5]))
        .onChange(of: step) { value in if value == 1 || value == 8 { pulse += 1 } }
        .task(id: active) { if !active { pulse = 0 } }
    }
}

// MARK: - Page 4: tasks, Today and presentations

private struct ActionScene: View {
    let active: Bool
    @State private var step = 0

    private var tasks: [(title: String, time: String)] {
        [(L("Lecture notes"), ""), (L("Review flashcards"), "9:00"), (L("Practice test"), L("Fri"))]
    }
    private var done: Int { step >= 4 ? 2 : 1 }

    var body: some View {
        ZStack(alignment: .topTrailing) {
            VStack(alignment: .leading, spacing: 10) {
                HStack(alignment: .firstTextBaseline) {
                    Text(L("Today")).font(.system(size: 20, weight: .bold))
                    Spacer()
                    Text(L("\(done) of \(tasks.count) done"))
                        .font(.system(size: 12))
                        .foregroundColor(MinorColor.textTertiary)
                        .contentTransition(.numericText())
                }
                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        Capsule().fill(Color.white.opacity(0.08))
                        Capsule().fill(MinorColor.accent).frame(width: geo.size.width * CGFloat(done) / CGFloat(tasks.count))
                    }
                }
                .frame(height: 6)
                .padding(.bottom, 2)
                ForEach(tasks.indices, id: \.self) { i in
                    let checked = i == 0 || (i == 1 && step >= 4)
                    HStack(spacing: 10) {
                        Image(systemName: checked ? "checkmark.circle.fill" : "circle")
                            .font(.system(size: 18))
                            .foregroundColor(checked ? BranchColor.sky.color : MinorColor.textTertiary)
                        Text(tasks[i].title)
                            .font(.system(size: 14.5))
                            .strikethrough(checked, color: MinorColor.textTertiary)
                            .foregroundColor(checked ? MinorColor.textTertiary : .white)
                        Spacer()
                        Text(tasks[i].time).font(.system(size: 12)).foregroundColor(MinorColor.textTertiary)
                    }
                    .padding(.horizontal, 10)
                    .frame(height: 40)
                    .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Color.white.opacity(0.05)))
                    .opacity(step >= 1 + i ? 1 : 0)
                    .offset(y: step >= 1 + i ? 0 : 8)
                }
            }
            .padding(16)
            .frame(width: 290)
            .background(RoundedRectangle(cornerRadius: 22, style: .continuous).fill(Color(white: 0.1)))
            .overlay(RoundedRectangle(cornerRadius: 22, style: .continuous).stroke(Color.white.opacity(0.14), lineWidth: 1))
            .padding(.top, 60)

            // A slide made from the same map.
            VStack(alignment: .leading, spacing: 5) {
                Capsule().fill(MinorColor.accent).frame(width: 18, height: 3)
                Text(L("Launch plan")).font(.system(size: 13, weight: .bold)).foregroundColor(.white)
                ForEach([0.9, 0.7, 0.8], id: \.self) { width in
                    Capsule().fill(Color.white.opacity(0.25)).frame(width: 96 * width, height: 4)
                }
            }
            .padding(12)
            .frame(width: 150, height: 86, alignment: .topLeading)
            .background(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(LinearGradient(colors: [Color(hex: "#1B2140"), Color(hex: "#3A2463")], startPoint: .topLeading, endPoint: .bottomTrailing))
            )
            .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).stroke(Color.white.opacity(0.18), lineWidth: 1))
            .overlay(alignment: .bottomTrailing) {
                Text(verbatim: "PowerPoint · PDF")
                    .font(.system(size: 9, weight: .semibold))
                    .padding(.horizontal, 6)
                    .padding(.vertical, 3)
                    .background(Capsule().fill(Color.black.opacity(0.45)))
                    .padding(6)
            }
            .shadow(color: .black.opacity(0.4), radius: 16, y: 8)
            .rotationEffect(.degrees(step >= 5 ? 6 : 14))
            .offset(x: step >= 5 ? 14 : 60, y: step >= 5 ? -20 : -30)
            .opacity(step >= 5 ? 1 : 0)

            // The reminder.
            HStack(spacing: 8) {
                Image(systemName: "bell.fill").font(.system(size: 13)).foregroundColor(BranchColor.sun.color)
                Text(L("Practice test is due on Friday")).font(.system(size: 12.5))
            }
            .padding(.horizontal, 12)
            .frame(height: 36)
            .background(Capsule().fill(Color(white: 0.18)))
            .overlay(Capsule().stroke(Color.white.opacity(0.14), lineWidth: 1))
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
            .offset(y: step >= 6 ? 0 : 14)
            .opacity(step >= 6 ? 1 : 0)
        }
        .frame(width: 320)
        .modifier(Steps(active: active, step: $step, last: 6, delays: [0.3, 0.15, 0.15, 0.9, 0.6, 0.6]))
    }
}
