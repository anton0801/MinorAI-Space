//
//  DeckPresenterView.swift
//  Minor Ai
//
//  Presenting: on the phone, the slide full screen (turn the phone sideways) or the presenter
//  view with the next slide, notes and a timer. With a TV or display connected (AirPlay or a
//  cable), the slides go there and the phone keeps the presenter view. Drag on the slide for a
//  laser pointer.
//

import Combine
import SwiftUI
import UIKit

// What the external display shows, shared with its scene.
@MainActor
final class PresentationScreen: ObservableObject {
    static let shared = PresentationScreen()
    @Published var deck: Deck?
    @Published var index = 0
    @Published var reveal: Int?             // build steps shown on the current slide
    @Published var pointer: CGPoint?        // 0…1 in slide coordinates
    @Published var connected = false
}

final class ExternalDisplayDelegate: UIResponder, UIWindowSceneDelegate {
    var window: UIWindow?
    private var watch: AnyCancellable?

    func scene(_ scene: UIScene, willConnectTo session: UISceneSession, options connectionOptions: UIScene.ConnectionOptions) {
        guard let windowScene = scene as? UIWindowScene else { return }
        let window = UIWindow(windowScene: windowScene)
        window.rootViewController = UIHostingController(rootView: ExternalSlideView())
        self.window = window
        Task { @MainActor in
            PresentationScreen.shared.connected = true
            // The TV shows slides only while presenting; otherwise the window hides, so Screen
            // Mirroring shows the app as usual.
            watch = PresentationScreen.shared.$deck
                .map { $0 == nil }
                .removeDuplicates()
                .sink { [weak window] hidden in window?.isHidden = hidden }
        }
    }

    func sceneDidDisconnect(_ scene: UIScene) {
        watch = nil
        window = nil
        Task { @MainActor in PresentationScreen.shared.connected = false }
    }
}

// The TV: the current slide, as large as it fits; the Minor mark when nothing is being presented.
struct ExternalSlideView: View {
    @ObservedObject private var screen = PresentationScreen.shared

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            if let deck = screen.deck, deck.slides.indices.contains(screen.index) {
                let slide = deck.slides[screen.index]
                ZStack {
                    SlideCanvas(slide: slide, deck: deck, index: screen.index, reveal: screen.reveal)
                        .id(screen.index)
                        .transition((slide.transition ?? deck.transition).swiftUI)
                }
                .overlay { LaserDot(point: screen.pointer) }
                .animation(.easeInOut(duration: 0.45), value: screen.index)
            } else {
                Image("minlogo")
                    .resizable()
                    .frame(width: 96, height: 96)
                    .opacity(0.5)
            }
        }
    }
}

struct LaserDot: View {
    let point: CGPoint?

    var body: some View {
        GeometryReader { geo in
            if let point {
                Circle()
                    .fill(Color.red)
                    .frame(width: max(geo.size.width * 0.018, 8), height: max(geo.size.width * 0.018, 8))
                    .shadow(color: .red, radius: 8)
                    .position(x: point.x * geo.size.width, y: point.y * geo.size.height)
            }
        }
        .allowsHitTesting(false)
    }
}

struct DeckPresenterView: View {
    let deck: Deck
    @State private var index: Int
    @State private var fullScreen: Bool
    @State private var started = Date()
    @State private var pointer: CGPoint?
    @State private var step = 0             // points and elements already in on this slide
    @State private var nextFolded: Bool?    // nil: as the screen's height suggests
    @ObservedObject private var screen = PresentationScreen.shared
    @Environment(\.dismiss) private var dismiss
    @Environment(\.verticalSizeClass) private var verticalSizeClass
    // The slide the show ended on, so the editor comes back to it.
    var onEnd: (UUID) -> Void = { _ in }

    private var compactHeight: Bool { UIScreen.main.bounds.height < 700 || verticalSizeClass == .compact }

    init(deck: Deck, start: Int, onEnd: @escaping (UUID) -> Void = { _ in }) {
        self.deck = deck
        self.onEnd = onEnd
        _index = State(initialValue: min(max(start, 0), max(deck.slides.count - 1, 0)))
        _fullScreen = State(initialValue: !PresentationScreen.shared.connected && !ProcessInfo.processInfo.arguments.contains("-demoPresenterView"))
    }

    private var slide: Slide? { deck.slides.indices.contains(index) ? deck.slides[index] : nil }

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            if fullScreen && !screen.connected {
                fullScreenSlide
            } else {
                presenter
            }
        }
        .statusBarHidden(true)
        .persistentSystemOverlays(.hidden)
        .onAppear {
            UIApplication.shared.isIdleTimerDisabled = true
            screen.deck = deck
            screen.index = index
            screen.reveal = 0
        }
        .onDisappear {
            UIApplication.shared.isIdleTimerDisabled = false
            screen.deck = nil
            screen.pointer = nil
            if let slide { onEnd(slide.id) }
        }
        // The deck can change while presenting (sync, an AI edit): the TV follows, and the slide
        // number stays valid.
        .onChange(of: deck) { updated in
            screen.deck = updated
            if index >= updated.slides.count {
                index = max(updated.slides.count - 1, 0)
                step = 0
                screen.index = index
            }
        }
        .onChange(of: index) { screen.index = $0 }
        .onChange(of: step) { screen.reveal = $0 }
        .onChange(of: pointer) { screen.pointer = $0 }
        .onChange(of: screen.connected) { connected in if connected { fullScreen = false } }
    }

    // MARK: - Full screen on the phone (turned sideways)

    private var fullScreenSlide: some View {
        GeometryReader { geo in
            // The slide turned a quarter, filling the phone held sideways.
            let width = geo.size.height
            let height = width * 9 / 16
            ZStack {
                if let slide {
                    slideWithPointer(slide)
                        .frame(width: width, height: height)
                }
                HStack(spacing: 0) {
                    Color.clear.contentShape(Rectangle()).onTapGesture { go(-1) }
                    Color.clear.contentShape(Rectangle()).onTapGesture { go(1) }
                }
                .frame(width: width, height: height)
                .allowsHitTesting(pointer == nil)
                VStack {
                    HStack {
                        circleButton("xmark", L("End Presentation")) { dismiss() }
                        Spacer()
                        circleButton("rectangle.portrait", L("Presenter View")) { fullScreen = false }
                    }
                    Spacer()
                }
                .padding(14)
                .frame(width: width, height: geo.size.width)
            }
            .rotationEffect(.degrees(90))
            .frame(width: geo.size.width, height: geo.size.height)
        }
        .ignoresSafeArea()
        .gesture(DragGesture(minimumDistance: 30).onEnded { value in
            // Sideways phone: a swipe along the phone's length moves between slides.
            if value.translation.height < -40 { go(1) } else if value.translation.height > 40 { go(-1) }
        })
    }

    // MARK: - Presenter view

    // The session's time, where the show is, the slide as it is shown (16:9), the next one (folds
    // to a line on a small screen), the notes, and Back / Next.
    private var presenter: some View {
        VStack(spacing: 12) {
            HStack(alignment: .top) {
                circleButton("xmark", L("End Presentation")) { dismiss() }
                Spacer()
                VStack(spacing: 2) {
                    TimelineView(.periodic(from: started, by: 1)) { context in
                        Text(Self.clock(context.date.timeIntervalSince(started)))
                            .minorFont(30, .bold, maxScale: 1.2)
                            .monospacedDigit()
                            .foregroundColor(.white)
                            .accessibilityLabel(L("Time: \(Self.clock(context.date.timeIntervalSince(started)))"))
                    }
                    Text("Presenter Mode").minorFont(13, maxScale: 1.2).foregroundColor(MinorColor.textSecondary)
                    Text(L("\(index + 1) of \(deck.slides.count)"))
                        .minorFont(12, maxScale: 1.2)
                        .monospacedDigit()
                        .foregroundColor(MinorColor.textTertiary)
                }
                .accessibilityElement(children: .combine)
                Spacer()
                if screen.connected {
                    Image(systemName: "tv")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundColor(MinorColor.accent)
                        .frame(width: 44, height: 44)
                        .accessibilityLabel("Showing on the display")
                } else {
                    circleButton("arrow.up.left.and.arrow.down.right", L("Full Screen")) { fullScreen = true }
                }
            }
            .padding(.horizontal, 12)
            if let slide {
                slideWithPointer(slide)
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                    .padding(.horizontal, 16)
            }
            nextCard
                .padding(.horizontal, 16)
            VStack(alignment: .leading, spacing: 8) {
                Text("Notes").minorFont(15, .semibold, maxScale: 1.3).accessibilityAddTraits(.isHeader)
                ScrollView {
                    Text(slide?.notes.isEmpty == false ? slide!.notes : L("No notes for this slide."))
                        .minorFont(18, maxScale: 1.5)
                        .foregroundColor(slide?.notes.isEmpty == false ? .white : MinorColor.textTertiary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            .padding(16)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .background(RoundedRectangle(cornerRadius: 16).fill(Color.white.opacity(0.06)))
            .padding(.horizontal, 16)
            HStack(spacing: 12) {
                Button { go(-1) } label: {
                    HStack(spacing: 8) {
                        Image(systemName: "chevron.left").font(.system(size: 16, weight: .semibold))
                        Text("Back").minorFont(17, .medium, maxScale: 1.3)
                    }
                    .frame(maxWidth: .infinity, minHeight: 56)
                    .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(Color.white.opacity(0.08)))
                }
                .disabled(index == 0 && step == 0)
                .opacity(index == 0 && step == 0 ? 0.4 : 1)
                .accessibilityLabel("Back")
                .accessibilityIdentifier("presenter.back")
                Button { hasMore ? go(1) : dismiss() } label: {
                    HStack(spacing: 8) {
                        Text(hasMore ? L("Next") : L("Finish")).minorFont(17, .semibold, maxScale: 1.3)
                        if hasMore { Image(systemName: "chevron.right").font(.system(size: 16, weight: .semibold)) }
                    }
                    .foregroundColor(.black)
                    .frame(maxWidth: .infinity, minHeight: 56)
                    .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(Color.white))
                }
                .accessibilityLabel(hasMore ? L("Next") : L("Finish"))
                .accessibilityIdentifier("presenter.next")
                .accessibilityHint(step < steps ? Text("Shows the next part of this slide") : Text(""))
            }
            .buttonStyle(.plain)
            .foregroundColor(.white)
            .padding(.horizontal, 16)
            .padding(.bottom, 10)
        }
        .padding(.top, 8)
    }

    private var hasMore: Bool { index < deck.slides.count - 1 || step < steps }

    // The next slide; on a small screen it starts folded to its title so the notes have room.
    @ViewBuilder
    private var nextCard: some View {
        let next = deck.slides.indices.contains(index + 1) ? deck.slides[index + 1] : nil
        Button {
            withAnimation(.minorMenu) { nextFolded = !(nextFolded ?? compactHeight) }
        } label: {
            HStack(spacing: 12) {
                if let next, !(nextFolded ?? compactHeight) {
                    SlideCanvas(slide: next, deck: deck, index: index + 1)
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                        .frame(width: 136)
                        .accessibilityHidden(true)
                }
                VStack(alignment: .leading, spacing: 2) {
                    Text("Up Next").minorFont(12, maxScale: 1.3).foregroundColor(MinorColor.textSecondary)
                    Text(next.map { $0.title.isEmpty ? L("Slide \(index + 2)") : $0.title } ?? L("End of the presentation"))
                        .minorFont(15, .medium, maxScale: 1.3)
                        .lineLimit(2)
                        .multilineTextAlignment(.leading)
                }
                Spacer(minLength: 4)
                if next != nil {
                    Image(systemName: (nextFolded ?? compactHeight) ? "chevron.down" : "chevron.up")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundColor(MinorColor.textTertiary)
                }
            }
            .padding(10)
            .frame(maxWidth: .infinity, minHeight: 48, alignment: .leading)
            .background(RoundedRectangle(cornerRadius: 14).fill(Color.white.opacity(0.06)))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(next == nil)
        .accessibilityHint(next == nil ? Text("") : Text("Shows or hides the next slide"))
    }

    // MARK: - Pieces

    // The slide; touch and drag shows the laser pointer (here and on the display).
    private func slideWithPointer(_ slide: Slide) -> some View {
        ZStack {
            SlideCanvas(slide: slide, deck: deck, index: index, reveal: step)
                .id(index)
                .transition((slide.transition ?? deck.transition).swiftUI)
        }
            .overlay { LaserDot(point: pointer) }
            .overlay {
                GeometryReader { geo in
                    Color.clear
                        .contentShape(Rectangle())
                        .gesture(
                            DragGesture(minimumDistance: 0)
                                .onChanged { value in
                                    pointer = CGPoint(
                                        x: min(max(value.location.x / geo.size.width, 0), 1),
                                        y: min(max(value.location.y / geo.size.height, 0), 1)
                                    )
                                }
                                .onEnded { _ in pointer = nil },
                            including: fullScreen && !screen.connected ? .none : .all
                        )
                }
            }
    }

    private var steps: Int { slide.map(Deck.buildSteps) ?? 0 }

    // Forward: the next point or element on this slide, then the next slide. Back: the reverse.
    private func go(_ direction: Int) {
        if direction > 0 && step < steps {
            Haptics.selection()
            withAnimation { step += 1 }
            return
        }
        if direction < 0 && step > 0 {
            withAnimation { step -= 1 }
            return
        }
        let target = index + direction
        guard deck.slides.indices.contains(target) else { return }
        Haptics.selection()
        withAnimation(.easeInOut(duration: 0.45)) {
            index = target
            step = direction > 0 ? 0 : Deck.buildSteps(deck.slides[target])
        }
        UIAccessibility.post(notification: .announcement, argument: L("Slide \(target + 1)"))
    }

    private func circleButton(_ icon: String, _ label: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.system(size: 15, weight: .bold))
                .foregroundColor(.white)
                .frame(width: 40, height: 40)
                .background(Circle().fill(Color.white.opacity(0.14)))
                .frame(width: 44, height: 44)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
    }

    // "03:42"; past an hour "1:03:42".
    static func clock(_ seconds: TimeInterval) -> String {
        let total = max(Int(seconds), 0)
        if total >= 3600 { return String(format: "%d:%02d:%02d", total / 3600, total / 60 % 60, total % 60) }
        return String(format: "%02d:%02d", total / 60, total % 60)
    }
}
