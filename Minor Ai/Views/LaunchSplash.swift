//
//  LaunchSplash.swift
//  Minor Ai
//
//  The animated splash on a cold start. Sparks and a small mind map are pulled into the
//  middle, the Minor logo assembles there ring by ring and locks with a shockwave, the name
//  decodes under it, then a heptagon portal opens from the logo onto the app while the logo
//  shrinks into the faint logo of the home screen.
//
//  It lives in its own window above the app (onboarding is a full-screen cover), goes up when
//  the scene connects so the app never flashes first, and starts when the scene is active.
//  A tap skips to the portal. Reduce Motion and VoiceOver get a short fade.
//

import SwiftUI
import UIKit

@MainActor
final class LaunchSplash: ObservableObject {
    static let shared = LaunchSplash()

    // False while the splash covers the app: the app zooms in a little as the portal opens.
    @Published private(set) var revealed = true
    @Published private(set) var start: Date?
    private(set) var timeline = SplashTimeline.full
    private var skipped: TimeInterval = 0
    private var window: UIWindow?
    private var observers: [NSObjectProtocol] = []
    private var events: Task<Void, Never>?
    #if DEBUG
    private var frozen: TimeInterval?
    #endif

    static var enabled: Bool {
        if ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil { return false }
        #if DEBUG
        let args = ProcessInfo.processInfo.arguments
        if args.contains("-noSplash") { return false }
        // UI tests and screenshot runs pass "-didOnboard"; "-splash" shows it anyway.
        if args.contains("-didOnboard") && !args.contains("-splash") { return false }
        #endif
        return true
    }

    // Called first thing in didFinishLaunching; the app's scene connects after it.
    func install() {
        guard Self.enabled, observers.isEmpty else { return }
        revealed = false
        // No queue: the block runs while the scene connects, before the app's first frame.
        observers.append(NotificationCenter.default.addObserver(forName: UIScene.willConnectNotification, object: nil, queue: nil) { note in
            guard let scene = note.object as? UIWindowScene else { return }
            MainActor.assumeIsolated { LaunchSplash.shared.present(in: scene) }
        })
    }

    private func present(in scene: UIWindowScene) {
        guard window == nil, start == nil, scene.session.role == .windowApplication else { return }
        var reduced = UIAccessibility.isReduceMotionEnabled || UIAccessibility.isVoiceOverRunning
        #if DEBUG
        if ProcessInfo.processInfo.arguments.contains("-splashReduced") { reduced = true }
        #endif
        timeline = reduced ? .reduced : .full
        if reduced { revealed = true }
        let sphere = UserDefaults.standard.integer(forKey: "SelectedSphere")
        let theme = AppTheme(sphere: sphere == 0 ? nil : sphere)
        let host = UIHostingController(rootView: LaunchSplashView(splash: self, scene: SplashScene(glow: theme.glowSolid, timeline: timeline)))
        host.view.backgroundColor = .clear
        let window = UIWindow(windowScene: scene)
        window.windowLevel = .normal + 1
        window.backgroundColor = .clear
        window.overrideUserInterfaceStyle = .dark
        window.rootViewController = host
        window.isHidden = false
        self.window = window

        #if DEBUG
        // -splashAt 1.2: a still frame of the splash at that second, for checking the design.
        let args = ProcessInfo.processInfo.arguments
        if let i = args.firstIndex(of: "-splashAt"), i + 1 < args.count, let time = Double(args[i + 1]) {
            frozen = time
            start = Date()
            return
        }
        #endif
        if scene.activationState == .foregroundActive {
            begin()
        } else {
            observers.append(NotificationCenter.default.addObserver(forName: UIScene.didActivateNotification, object: scene, queue: .main) { _ in
                MainActor.assumeIsolated { LaunchSplash.shared.begin() }
            })
        }
    }

    // The top safe area: the home screen lays out its faint logo below it.
    var safeTop: CGFloat { window?.safeAreaInsets.top ?? 0 }

    // Seconds into the splash.
    func elapsed(at date: Date) -> TimeInterval {
        #if DEBUG
        if let frozen { return frozen }
        #endif
        guard let start else { return 0 }
        return date.timeIntervalSince(start) + skipped
    }

    private func begin() {
        guard start == nil, window != nil else { return }
        start = Date()
        schedule()
    }

    // A tap jumps straight to the portal.
    func skip() {
        guard start != nil, window != nil else { return }
        let now = elapsed(at: Date())
        guard now < timeline.portal else { return }
        skipped += timeline.portal - now
        schedule()
    }

    private func schedule() {
        events?.cancel()
        let timeline = timeline
        var steps: [(time: TimeInterval, action: () -> Void)] = []
        if timeline.motion {
            steps.append((timeline.ignite, { UIImpactFeedbackGenerator(style: .light).impactOccurred(intensity: 0.7) }))
            steps.append((timeline.lock, { UIImpactFeedbackGenerator(style: .soft).impactOccurred() }))
        }
        steps.append((timeline.portal, { LaunchSplash.shared.reveal() }))
        steps.append((timeline.end, { LaunchSplash.shared.finish() }))
        events = Task { @MainActor in
            for step in steps {
                let left = step.time - LaunchSplash.shared.elapsed(at: Date())
                // Haptics a skip jumped over stay silent.
                if left < -0.05 && step.time < timeline.portal { continue }
                if left > 0 { try? await Task.sleep(nanoseconds: UInt64(left * 1_000_000_000)) }
                if Task.isCancelled { return }
                step.action()
            }
        }
    }

    private func reveal() {
        guard !revealed else { return }
        withAnimation(.timingCurve(0.3, 0, 0.2, 1, duration: timeline.end - timeline.portal)) { revealed = true }
    }

    private func finish() {
        events?.cancel()
        events = nil
        observers.forEach { NotificationCenter.default.removeObserver($0) }
        observers = []
        revealed = true
        window?.isHidden = true
        window = nil
        UIAccessibility.post(notification: .screenChanged, argument: nil)
    }
}

// The app under the splash zooms in slightly as the portal opens.
struct LaunchReveal: ViewModifier {
    @ObservedObject private var splash = LaunchSplash.shared

    func body(content: Content) -> some View {
        content.scaleEffect(splash.revealed ? 1 : 1.06)
    }
}

struct SplashTimeline {
    var ignite: TimeInterval    // the core of the logo appears
    var lock: TimeInterval      // the last ring closes
    var portal: TimeInterval    // the portal starts opening
    var end: TimeInterval
    var motion: Bool            // false: Reduce Motion or VoiceOver, a plain fade

    static let full = SplashTimeline(ignite: 0.8, lock: 1.42, portal: 1.84, end: 2.42, motion: true)
    static let reduced = SplashTimeline(ignite: 0, lock: 0, portal: 0.6, end: 0.95, motion: false)
}

struct LaunchSplashView: View {
    @ObservedObject var splash: LaunchSplash
    let scene: SplashScene

    var body: some View {
        TimelineView(.animation(minimumInterval: nil, paused: splash.start == nil)) { timeline in
            let t = splash.elapsed(at: timeline.date)
            let top = splash.safeTop
            Canvas { context, size in
                scene.draw(&context, size: size, safeTop: top, t: t)
            }
        }
        .ignoresSafeArea()
        .contentShape(Rectangle())
        .onTapGesture { splash.skip() }
        .accessibilityHidden(true)
    }
}

// Draws one frame of the splash for a time in seconds.
struct SplashScene {
    let glow: Color
    let timeline: SplashTimeline
    private let particles: [Particle]
    private let branches: [Branch]

    static let background = Color(red: 18 / 255, green: 18 / 255, blue: 18 / 255)

    // The Minor logo, measured from the artwork: three heptagon rings and a filled center.
    // Radii and widths are in units of the outer ring's radius (along its center line);
    // corners in units of each ring's own radius.
    struct Ring {
        let radius: CGFloat
        let width: CGFloat
        let corner: CGFloat
    }
    static let rings = [
        Ring(radius: 1, width: 0.1185, corner: 0.22),
        Ring(radius: 0.7997, width: 0.096, corner: 0.34),
        Ring(radius: 0.5822, width: 0.096, corner: 0.18),
    ]
    static let coreRadius: CGFloat = 0.3707
    static let coreCorner: CGFloat = 0.31
    // The faint logo on the home screen (110 pt artwork) has its outer ring at 34.4 pt.
    static let homeRadius: CGFloat = 34.37

    private struct Particle {
        let distance: Double    // where it starts, in reaches from the center
        let angle: Double
        let swirl: Double
        let delay: Double
        let duration: Double
        let size: Double
        let white: Bool
    }

    private struct Twig {
        let angle: Double
        let length: Double
        let bend: Double
    }

    private struct Branch {
        let angle: Double
        let length: Double      // in shorter screen sides
        let bend: Double
        let color: Color
        let delay: Double
        let twigs: [Twig]
    }

    // SplitMix64, seeded: the same sky on every launch.
    private struct Seeded {
        var state: UInt64
        mutating func next() -> Double {
            state &+= 0x9E37_79B9_7F4A_7C15
            var z = state
            z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
            z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
            z ^= z >> 31
            return Double(z >> 11) / Double(UInt64(1) << 53)
        }
        mutating func range(_ lower: Double, _ upper: Double) -> Double { lower + (upper - lower) * next() }
        mutating func sign() -> Double { next() < 0.5 ? -1 : 1 }
    }

    init(glow: Color, timeline: SplashTimeline) {
        self.glow = glow
        self.timeline = timeline
        var random = Seeded(state: 2026)
        var particles: [Particle] = []
        for _ in 0..<56 {
            particles.append(Particle(distance: random.range(0.55, 1.05), angle: random.range(0, 2 * .pi),
                                      swirl: random.range(0.5, 1.3) * random.sign(), delay: random.range(0, 0.3),
                                      duration: random.range(0.5, 0.68), size: random.range(0.8, 1.8), white: random.next() < 0.3))
        }
        self.particles = particles
        let colors: [BranchColor] = [.mint, .sky, .lilac, .pink, .sun, .coral, .teal]
        var branches: [Branch] = []
        for i in 0..<7 {
            let angle = -Double.pi / 2 + Double(i) * 2 * .pi / 7 + random.range(-0.12, 0.12)
            let length = random.range(0.3, 0.36)
            let twigs = [-1.0, 1.0].map { side in
                Twig(angle: angle + side * random.range(0.2, 0.32), length: length + random.range(0.1, 0.16), bend: random.range(-0.08, 0.08))
            }
            branches.append(Branch(angle: angle, length: length, bend: random.range(-0.1, 0.1), color: colors[i].color,
                                   delay: 0.06 + 0.035 * Double(i), twigs: twigs))
        }
        self.branches = branches
    }

    // MARK: Frame

    func draw(_ context: inout GraphicsContext, size: CGSize, safeTop: CGFloat, t: Double) {
        // Where the faint logo sits on the home screen; the splash logo lands right on it.
        let center = CGPoint(x: size.width / 2, y: safeTop + size.height / 2.5)
        let side = min(size.width, size.height)
        let radius = side * 0.17
        let dx = max(center.x, size.width - center.x), dy = max(center.y, size.height - center.y)
        let reach = sqrt(dx * dx + dy * dy)

        if !timeline.motion {
            drawReduced(&context, size: size, center: center, radius: radius, t: t)
            return
        }

        let portal = Self.progress(t, timeline.portal, timeline.end - timeline.portal)
        var background = Path(CGRect(origin: .zero, size: size))
        var hole: CGFloat = 0
        if portal > 0 {
            let from = radius * 1.12
            let to = reach / CGFloat(cos(Double.pi / 7)) + 24
            hole = from + (to - from) * CGFloat(pow(portal, 2.2))
            background.addPath(Self.heptagon(center, radius: hole, corner: hole * 0.22))
        }
        context.fill(background, with: .color(Self.background), style: FillStyle(eoFill: true))

        context.drawLayer { layer in
            if hole > 0 { layer.clip(to: background, style: FillStyle(eoFill: true)) }
            layer.blendMode = .plusLighter
            drawGrid(&layer, size: size, center: center, radius: radius, reach: reach, t: t)
            drawNetwork(&layer, center: center, side: side, t: t)
            drawParticles(&layer, center: center, reach: reach, t: t)
            drawShockwave(&layer, center: center, radius: radius, t: t)
        }
        context.drawLayer { layer in
            layer.blendMode = .plusLighter
            drawCore(&layer, center: center, radius: radius, t: t, fade: 1 - portal)
        }
        drawLogo(&context, center: center, radius: radius, t: t, portal: portal)
        drawWordmark(&context, center: center, radius: radius, t: t)

        if portal > 0, portal < 1 {
            let rim = Self.heptagon(center, radius: hole, corner: hole * 0.22)
            let alpha = 0.9 * (1 - portal)
            context.stroke(rim, with: .color(glow.opacity(0.16 * alpha)), lineWidth: 18)
            context.stroke(rim, with: .color(glow.opacity(0.6 * alpha)), lineWidth: 2.5)
            context.stroke(rim, with: .color(.white.opacity(0.5 * alpha)), lineWidth: 1)
        }
    }

    // MARK: Background: the map canvas dot grid, lit by a scanning wave and the shockwave

    private func drawGrid(_ context: inout GraphicsContext, size: CGSize, center: CGPoint, radius: CGFloat, reach: CGFloat, t: Double) {
        let pitch: CGFloat = 22
        let scan = reach * CGFloat(Self.easeOut(Self.progress(t, 0, 1)))
        let scanFade = 1 - Self.progress(t, 0.7, 0.4)
        let shock = Self.progress(t, timeline.lock, 0.9)
        let shockRadius = radius + (reach - radius) * CGFloat(Self.easeOut(shock))
        var base = Path()
        var lit = [Path](repeating: Path(), count: 9)
        let columns = Int(size.width / 2 / pitch) + 1
        let rows = Int(max(center.y, size.height - center.y) / pitch) + 1
        for i in -columns...columns {
            for j in -rows...rows {
                let x = center.x + CGFloat(i) * pitch, y = center.y + CGFloat(j) * pitch
                guard x >= 0, x <= size.width, y >= 0, y <= size.height else { continue }
                let d = sqrt((x - center.x) * (x - center.x) + (y - center.y) * (y - center.y))
                guard d < scan else { continue }
                let dot = CGRect(x: x - 1, y: y - 1, width: 2, height: 2)
                base.addEllipse(in: dot)
                var light = 0.35 * Self.crest(d, scan, 36) * scanFade
                if shock > 0, shock < 1 { light += 0.55 * Self.crest(d, shockRadius, 44) * (1 - shock) }
                let level = min(8, Int((light * 16).rounded()))
                if level > 0 { lit[level].addEllipse(in: dot.insetBy(dx: -0.4, dy: -0.4)) }
            }
        }
        let fade = 1 - Self.progress(t, timeline.portal, 0.3)
        context.fill(base, with: .color(.white.opacity(0.05 * fade)))
        for level in 1..<lit.count where !lit[level].isEmpty {
            context.fill(lit[level], with: .color(glow.opacity(Double(level) / 16 * fade)))
        }
    }

    // MARK: A mind map that grows out of the center, then folds back into it

    private func drawNetwork(_ context: inout GraphicsContext, center: CGPoint, side: CGFloat, t: Double) {
        let collapse = Self.easeIn(Self.progress(t, 0.6, 0.32))
        guard collapse < 1 else { return }
        let fade = 1 - Self.progress(collapse, 0.75, 0.25)
        let swirl = 0.5 * collapse
        func place(_ angle: Double, _ length: Double) -> CGPoint {
            let r = CGFloat(length * (1 - collapse)) * side
            let a = angle + swirl
            return CGPoint(x: center.x + r * CGFloat(cos(a)), y: center.y + r * CGFloat(sin(a)))
        }
        let lineAlpha = (0.5 + 0.4 * collapse) * fade
        for branch in branches {
            let grow = Self.easeOut(Self.progress(t, branch.delay, 0.22))
            guard grow > 0 else { continue }
            let node = place(branch.angle, branch.length)
            let stem = Self.curve(center, node, bend: branch.bend)
            context.stroke(grow < 1 ? stem.trimmedPath(from: 0, to: grow) : stem,
                           with: .color(branch.color.opacity(lineAlpha)), style: StrokeStyle(lineWidth: 1.5, lineCap: .round))
            for twig in branch.twigs {
                let reach = Self.easeOut(Self.progress(t, branch.delay + 0.17, 0.2))
                guard reach > 0 else { continue }
                let end = place(twig.angle, twig.length)
                let path = Self.curve(node, end, bend: twig.bend)
                context.stroke(reach < 1 ? path.trimmedPath(from: 0, to: reach) : path,
                               with: .color(branch.color.opacity(lineAlpha * 0.75)), style: StrokeStyle(lineWidth: 1, lineCap: .round))
                let pop = Self.progress(t, branch.delay + 0.37, 0.16)
                if pop > 0 { drawNode(&context, end, radius: 2.6 * CGFloat(Self.backOut(pop)), color: branch.color, alpha: fade) }
                // A spark of data running from the twig to its branch.
                let run = Self.progress(t, branch.delay + 0.42, 0.2)
                if run > 0, run < 1 { drawSpark(&context, Self.point(node, end, bend: twig.bend, at: 1 - Self.easeIn(run)), color: branch.color, alpha: fade, size: 4) }
            }
            let pop = Self.progress(t, branch.delay + 0.2, 0.16)
            if pop > 0 { drawNode(&context, node, radius: 4.2 * CGFloat(Self.backOut(pop)), color: branch.color, alpha: fade) }
            // And from the branch into the core.
            let run = Self.progress(t, branch.delay + 0.3, 0.3)
            if run > 0, run < 1 { drawSpark(&context, Self.point(center, node, bend: branch.bend, at: 1 - Self.easeIn(run)), color: branch.color, alpha: fade, size: 5.5) }
        }
    }

    private func drawNode(_ context: inout GraphicsContext, _ point: CGPoint, radius: CGFloat, color: Color, alpha: Double) {
        guard radius > 0.1 else { return }
        let halo = radius * 3.5
        context.fill(Path(ellipseIn: CGRect(x: point.x - halo, y: point.y - halo, width: halo * 2, height: halo * 2)),
                     with: .radialGradient(Gradient(colors: [color.opacity(0.35 * alpha), color.opacity(0)]), center: point, startRadius: 0, endRadius: halo))
        context.fill(Path(ellipseIn: CGRect(x: point.x - radius, y: point.y - radius, width: radius * 2, height: radius * 2)), with: .color(color.opacity(alpha)))
    }

    private func drawSpark(_ context: inout GraphicsContext, _ point: CGPoint, color: Color, alpha: Double, size: CGFloat) {
        context.fill(Path(ellipseIn: CGRect(x: point.x - size, y: point.y - size, width: size * 2, height: size * 2)),
                     with: .radialGradient(Gradient(colors: [Color.white.opacity(alpha), color.opacity(0.6 * alpha), color.opacity(0)]),
                                           center: point, startRadius: 0, endRadius: size))
    }

    // MARK: Sparks pulled in from the edges

    private func drawParticles(_ context: inout GraphicsContext, center: CGPoint, reach: CGFloat, t: Double) {
        for particle in particles {
            let x = (t - particle.delay) / particle.duration
            guard x > 0, x < 1 else { continue }
            func at(_ x: Double) -> CGPoint {
                let e = pow(max(x, 0), 2.2)
                let r = CGFloat(particle.distance * (1 - e)) * reach
                let a = particle.angle + particle.swirl * e
                return CGPoint(x: center.x + r * CGFloat(cos(a)), y: center.y + r * CGFloat(sin(a)))
            }
            let alpha = min(1, x / 0.15) * (1 - Self.progress(x, 0.88, 0.12))
            let color = particle.white ? Color.white : glow
            // A streak that thickens toward the head.
            var previous = at(x - 0.14)
            for k in 1...5 {
                let point = at(x - 0.14 + 0.028 * Double(k))
                var segment = Path()
                segment.move(to: previous)
                segment.addLine(to: point)
                context.stroke(segment, with: .color(color.opacity(alpha * Double(k) / 5 * 0.7)),
                               style: StrokeStyle(lineWidth: CGFloat(particle.size * Double(k) / 5), lineCap: .round))
                previous = point
            }
            let halo = CGFloat(particle.size) * 4
            context.fill(Path(ellipseIn: CGRect(x: previous.x - halo, y: previous.y - halo, width: halo * 2, height: halo * 2)),
                         with: .radialGradient(Gradient(colors: [color.opacity(0.5 * alpha), color.opacity(0)]), center: previous, startRadius: 0, endRadius: halo))
        }
    }

    // MARK: The light in the middle: gathering, the flash of ignition, the glow behind the logo

    private func drawCore(_ context: inout GraphicsContext, center: CGPoint, radius: CGFloat, t: Double, fade: Double) {
        func glowDisc(_ r: CGFloat, _ inner: Color, _ outer: Color) {
            guard r > 0.5 else { return }
            context.fill(Path(ellipseIn: CGRect(x: center.x - r, y: center.y - r, width: r * 2, height: r * 2)),
                         with: .radialGradient(Gradient(colors: [inner, outer, outer.opacity(0)]), center: center, startRadius: 0, endRadius: r))
        }
        if t < timeline.ignite + 0.1 {
            let gather = Self.easeIn(Self.progress(t, 0.25, timeline.ignite - 0.25))
            let size = 6 + 34 * CGFloat(gather)
            glowDisc(size, Color.white.opacity(0.35 + 0.6 * gather), glow.opacity(0.25 * gather))
        }
        if t >= timeline.ignite {
            let since = t - timeline.ignite
            let flash = min(1, since / 0.05) * exp(-since / 0.2)
            let spread = radius * CGFloat(1.2 + 2.2 * (1 - exp(-since / 0.15)))
            glowDisc(spread, Color.white.opacity(0.7 * flash), glow.opacity(0.35 * flash))
            let ping = t >= timeline.lock ? exp(-(t - timeline.lock) / 0.3) : 0
            let ambient = (0.16 + 0.3 * ping) * min(1, since / 0.3) * fade
            glowDisc(radius * 2.6, glow.opacity(ambient), glow.opacity(ambient * 0.35))
        }
    }

    // MARK: The logo

    private func drawLogo(_ context: inout GraphicsContext, center: CGPoint, radius base: CGFloat, t: Double, portal: Double) {
        let radius = base + (Self.homeRadius - base) * CGFloat(Self.easeInOut(portal))
        let alpha = 1 - Self.easeIn(portal)
        guard alpha > 0 else { return }

        let coreX = Self.progress(t, timeline.ignite, 0.5)
        if coreX > 0 {
            let r = radius * Self.coreRadius * CGFloat(Self.springOut(coreX))
            let turn = -(Double.pi / 7) * (1 - Self.easeOut(coreX))
            let core = Self.heptagon(center, radius: r, corner: r * Self.coreCorner, rotation: turn)
            context.fill(core, with: .color(glow.opacity(0.25 * alpha * (1 - portal))))
            context.fill(core, with: .color(.white.opacity(alpha)))
        }

        for (k, ring) in Self.rings.enumerated() {
            // Inner ring first; each one closes from the top down both sides.
            let start = timeline.ignite + 0.08 + 0.09 * Double(2 - k)
            let x = Self.progress(t, start, 0.36)
            guard x > 0 else { continue }
            let drawn = Self.easeInOut(x)
            let settle = Self.progress(t, start, 0.55)
            let scale = CGFloat(0.84 + 0.16 * Self.backOut(settle))
            let turn = (k == 1 ? -1.0 : 1.0) * (Double.pi / 7) * (1 - Self.easeOut(settle))
            let r = radius * ring.radius * scale
            let width = radius * ring.width * scale
            let path = Self.heptagon(center, radius: r, corner: r * ring.corner, rotation: turn)
            let piece = drawn < 1 ? path.trimmedPath(from: 0.5 - drawn / 2, to: 0.5 + drawn / 2) : path
            // After the lock a ping runs out through the rings.
            let pingAt = timeline.lock + 0.07 * Double(2 - k)
            let ping = t >= pingAt ? exp(-(t - pingAt) / 0.2) : 0
            let bloom = (0.6 + 1.4 * ping) * alpha * (1 - portal)
            let round = StrokeStyle(lineWidth: width, lineCap: .round, lineJoin: .round)
            var wide = round
            wide.lineWidth = width * 3.2
            context.stroke(piece, with: .color(glow.opacity(0.14 * bloom)), style: wide)
            wide.lineWidth = width * 1.9
            context.stroke(piece, with: .color(glow.opacity(0.22 * bloom)), style: wide)
            context.stroke(piece, with: .color(.white.opacity(alpha)), style: round)
            if drawn > 0, drawn < 1 {
                for end in [0.5 - drawn / 2, 0.5 + drawn / 2] {
                    guard let head = path.trimmedPath(from: 0, to: end).currentPoint else { continue }
                    drawSpark(&context, head, color: glow, alpha: 1, size: width * 1.6)
                }
            }
        }
    }

    // MARK: The shockwave when the logo locks

    private func drawShockwave(_ context: inout GraphicsContext, center: CGPoint, radius: CGFloat, t: Double) {
        for (delay, strength) in [(0.0, 1.0), (0.1, 0.45)] {
            let s = Self.progress(t, timeline.lock + delay, 0.8)
            guard s > 0, s < 1 else { continue }
            let r = radius * (1.1 + 4.2 * CGFloat(Self.easeOut(s)))
            let ring = Self.heptagon(center, radius: r, corner: r * 0.22)
            let fade = (1 - s) * strength
            context.stroke(ring, with: .color(glow.opacity(0.12 * fade)), lineWidth: 14 * CGFloat(1 - s) + 2)
            context.stroke(ring, with: .color(glow.opacity(0.55 * fade)), lineWidth: 2.5 * CGFloat(1 - s) + 0.5)
        }
    }

    // MARK: The name, decoded letter by letter

    private func drawWordmark(_ context: inout GraphicsContext, center: CGPoint, radius: CGFloat, t: Double) {
        let start = 1.08
        guard t > start else { return }
        let leave = Self.progress(t, timeline.portal, 0.3)
        let alpha = 1 - leave
        guard alpha > 0 else { return }
        let word = Array("Minor AI")
        let spacing = CGFloat(2.5 + 6 * (1 - Self.easeOut(Self.progress(t, start, 0.6))) + 10 * Self.easeIn(leave))
        let font = Font.system(size: 26, weight: .semibold)
        let finals = word.map { context.resolve(Text(String($0)).font(font).foregroundColor(.white.opacity(alpha))) }
        let widths = finals.map { $0.measure(in: CGSize(width: 200, height: 100)).width }
        let total = widths.reduce(0, +) + spacing * CGFloat(word.count - 1)
        let y = center.y + radius * 1.05 + 44 - CGFloat(leave) * 12
        let pool = Array("01<>/{}[]#*+=~%&ΔΣΛΞ")
        var x = center.x - total / 2
        for (i, character) in word.enumerated() {
            let middle = CGPoint(x: x + widths[i] / 2, y: y)
            x += widths[i] + spacing
            let appear = start + 0.03 * Double(i)
            let resolve = start + 0.12 + 0.055 * Double(i)
            guard t >= appear, character != " " else { continue }
            if t < resolve {
                let glyph = pool[(Int(t * 28) * 7 + i * 13) % pool.count]
                let scrambled = Text(String(glyph)).font(.system(size: 22, weight: .medium, design: .monospaced)).foregroundColor(glow.opacity(0.85 * alpha))
                context.draw(context.resolve(scrambled), at: middle)
            } else {
                let flash = 1 - Self.progress(t, resolve, 0.18)
                if flash > 0 {
                    context.fill(Path(ellipseIn: CGRect(x: middle.x - 16, y: middle.y - 16, width: 32, height: 32)),
                                 with: .radialGradient(Gradient(colors: [glow.opacity(0.4 * flash * alpha), glow.opacity(0)]), center: middle, startRadius: 0, endRadius: 16))
                }
                context.draw(finals[i], at: middle)
            }
        }
        // A thin line opening from the middle under the name.
        let open = Self.easeOut(Self.progress(t, start + 0.15, 0.5))
        if open > 0 {
            let half = total / 2 * CGFloat(open)
            let left = CGPoint(x: center.x - half, y: y + 24), right = CGPoint(x: center.x + half, y: y + 24)
            var line = Path()
            line.move(to: left)
            line.addLine(to: right)
            context.stroke(line, with: .linearGradient(Gradient(colors: [glow.opacity(0), glow.opacity(0.7 * alpha), glow.opacity(0)]), startPoint: left, endPoint: right), lineWidth: 1)
        }
    }

    // MARK: Reduce Motion: the logo fades in and the splash fades out

    private func drawReduced(_ context: inout GraphicsContext, size: CGSize, center: CGPoint, radius: CGFloat, t: Double) {
        let alpha = 1 - Self.progress(t, timeline.portal, timeline.end - timeline.portal)
        context.fill(Path(CGRect(origin: .zero, size: size)), with: .color(Self.background.opacity(alpha)))
        // The logo goes before the background so it doesn't double the home screen's logo.
        let logo = Self.progress(t, 0, 0.25) * (1 - Self.progress(t, timeline.portal - 0.15, 0.15))
        let core = radius * Self.coreRadius
        context.fill(Self.heptagon(center, radius: core, corner: core * Self.coreCorner), with: .color(.white.opacity(logo)))
        for ring in Self.rings {
            let r = radius * ring.radius
            context.stroke(Self.heptagon(center, radius: r, corner: r * ring.corner), with: .color(.white.opacity(logo)), lineWidth: radius * ring.width)
        }
        let name = Text(verbatim: "Minor AI").font(.system(size: 26, weight: .semibold)).kerning(2.5).foregroundColor(.white.opacity(logo))
        context.draw(context.resolve(name), at: CGPoint(x: center.x, y: center.y + radius * 1.05 + 44))
    }

    // MARK: Geometry

    // A rounded heptagon with a vertex on top. It starts in the middle of the flat bottom edge,
    // so the top is halfway along the path and trimming around 0.5 draws from the top down.
    static func heptagon(_ center: CGPoint, radius: CGFloat, corner: CGFloat, rotation: Double = 0) -> Path {
        let vertices = (0..<7).map { i -> CGPoint in
            let a = -Double.pi / 2 + rotation + Double(i) * 2 * .pi / 7
            return CGPoint(x: center.x + radius * CGFloat(cos(a)), y: center.y + radius * CGFloat(sin(a)))
        }
        var path = Path()
        path.move(to: CGPoint(x: (vertices[3].x + vertices[4].x) / 2, y: (vertices[3].y + vertices[4].y) / 2))
        for i in 4..<11 {
            path.addArc(tangent1End: vertices[i % 7], tangent2End: vertices[(i + 1) % 7], radius: corner)
        }
        path.closeSubpath()
        return path
    }

    // A gently bent connector, like the branches of a map.
    private static func curve(_ a: CGPoint, _ b: CGPoint, bend: Double) -> Path {
        var path = Path()
        path.move(to: a)
        path.addQuadCurve(to: b, control: control(a, b, bend: bend))
        return path
    }

    private static func control(_ a: CGPoint, _ b: CGPoint, bend: Double) -> CGPoint {
        CGPoint(x: (a.x + b.x) / 2 - (b.y - a.y) * CGFloat(bend), y: (a.y + b.y) / 2 + (b.x - a.x) * CGFloat(bend))
    }

    private static func point(_ a: CGPoint, _ b: CGPoint, bend: Double, at s: Double) -> CGPoint {
        let c = control(a, b, bend: bend)
        let u = CGFloat(1 - s), v = CGFloat(s)
        return CGPoint(x: u * u * a.x + 2 * u * v * c.x + v * v * b.x, y: u * u * a.y + 2 * u * v * c.y + v * v * b.y)
    }

    // MARK: Easing

    static func progress(_ t: Double, _ start: Double, _ duration: Double) -> Double {
        duration <= 0 ? (t >= start ? 1 : 0) : min(max((t - start) / duration, 0), 1)
    }
    static func easeOut(_ x: Double) -> Double { 1 - pow(1 - x, 3) }
    static func easeIn(_ x: Double) -> Double { x * x * x }
    static func easeInOut(_ x: Double) -> Double { x < 0.5 ? 4 * x * x * x : 1 - pow(-2 * x + 2, 3) / 2 }
    static func backOut(_ x: Double) -> Double { 1 + 2.70158 * pow(x - 1, 3) + 1.70158 * pow(x - 1, 2) }
    static func springOut(_ x: Double) -> Double { x <= 0 ? 0 : 1 - exp(-6 * x) * cos(9 * x) }
    static func crest(_ d: CGFloat, _ front: CGFloat, _ width: CGFloat) -> Double { Double(max(0, 1 - abs(d - front) / width)) }
}
