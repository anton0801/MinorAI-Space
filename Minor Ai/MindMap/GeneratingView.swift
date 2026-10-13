//
//  GeneratingView.swift
//  Minor Ai
//
//  Creating the Map: the map taking shape and the stage it is at, for a GenerationCenter job.
//  Closing asks first (Keep Creating · Stop · Build in Background); Stop drops the job, a late
//  answer never opens a map, and what was typed or picked goes back into the field. A failure keeps
//  the input on screen with what fits the reason: Try Again (the same job, never a second one),
//  sign in, or a plan; Change Topic puts the input back to edit.
//

import SwiftUI

struct GeneratingView: View {
    let jobID: UUID
    let theme: AppTheme
    var onDone: (UUID) -> Void
    var onClose: () -> Void
    var onUpgrade: () -> Void

    @ObservedObject private var account = AccountStore.shared
    @ObservedObject private var center = GenerationCenter.shared
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.accessibilityVoiceOverEnabled) private var voiceOver
    @State private var confirmClose = false
    @State private var lastJob: GenerationCenter.Job?

    private var job: GenerationCenter.Job? { center.jobs[jobID] ?? lastJob }
    private var failure: BackendError? { center.jobs[jobID]?.error }
    private var step: Int { job?.step ?? 0 }

    private var stage: String {
        guard let input = job?.input else { return L("Reading") }
        switch step {
        case 0:
            switch input {
            case .topic: return L("Thinking about the topic")
            case .link: return L("Reading the page")
            case .youtube: return L("Watching the video")
            case .text(_, let source): return source.kind == .voice ? L("Listening to your note") : L("Reading the material")
            }
        case 1: return L("Finding the main ideas")
        case 2: return L("Building the structure")
        default: return L("Adding details")
        }
    }

    private var label: String { job?.label ?? "" }

    var body: some View {
        ZStack {
            theme.background.ignoresSafeArea()
            if let failure {
                failed(failure)
            } else {
                building
            }
            if confirmClose {
                // A light shade: the map taking shape stays in view, as the design shows.
                Color.black.opacity(0.2)
                    .ignoresSafeArea()
                    .onTapGesture { confirmClose = false }
                    .accessibilityHidden(true)
                stopPanel
                    .transition(reduceMotion ? .opacity : .move(edge: .bottom).combined(with: .opacity))
            }
        }
        .foregroundColor(MinorColor.textPrimary)
        .animation(.minorMenu, value: confirmClose)
        .animation(.minorMenu, value: failure)
        .onAppear {
            if ProcessInfo.processInfo.arguments.contains("-demoStopAsk") { confirmClose = true }
            lastJob = center.jobs[jobID]
            center.watch(jobID, true)
            if center.jobs[jobID] == nil, MapStore.shared.map(jobID) != nil { onDone(jobID) }
        }
        .onDisappear { center.watch(jobID, false) }
        .onChange(of: center.jobs[jobID]) { job in
            if let job { lastJob = job }
            // The job disappears from the center once its map is saved.
            if job == nil, MapStore.shared.map(jobID) != nil { onDone(jobID) }
        }
    }

    // MARK: - Building

    private var building: some View {
        VStack(spacing: 0) {
            HStack(alignment: .top) {
                Button { confirmClose = true } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 14, weight: .bold))
                        .frame(width: 40, height: 40)
                        .background(Circle().fill(MinorColor.closeFill))
                        .frame(width: 44, height: 44)
                }
                .accessibilityLabel("Stop Creating")
                Spacer()
                VStack(spacing: 2) {
                    Text("Creating the Map").minorFont(24, .bold, maxScale: 1.3)
                    Text(label).minorFont(15, maxScale: 1.3).foregroundColor(MinorColor.textSecondary).lineLimit(1)
                }
                .accessibilityElement(children: .combine)
                .accessibilityAddTraits(.isHeader)
                Spacer()
                Color.clear.frame(width: 44, height: 44)
            }
            .padding(.horizontal, 12)
            .padding(.top, 6)

            MapTakingShape(topic: label, step: step)
                .frame(height: 260)
                .background(DotGrid().opacity(0.5))
                .padding(.horizontal, 16)
                .padding(.top, 20)
                .accessibilityHidden(true)

            VStack(spacing: 14) {
                Spinner(still: reduceMotion)
                Text(stage)
                    .minorFont(19, .semibold, maxScale: 1.3)
                    .multilineTextAlignment(.center)
            }
            .padding(.top, 24)
            .accessibilityElement(children: .combine)
            .accessibilityLabel(L("Creating the map: \(stage)"))

            Spacer()
            Text("You can leave this screen. The map will appear in Your Maps.")
                .minorFont(13, maxScale: 1.3)
                .foregroundColor(MinorColor.textTertiary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 40)
                .padding(.bottom, 20)
        }
    }

    // Asked before stopping: the map isn't made yet and the input goes back to the field.
    private var stopPanel: some View {
        VStack {
            Spacer()
            VStack(alignment: .leading, spacing: 10) {
                Capsule().fill(Color.white.opacity(0.22)).frame(width: 36, height: 5).frame(maxWidth: .infinity).accessibilityHidden(true)
                Text("Stop creating?").minorFont(22, .bold, maxScale: 1.3).accessibilityAddTraits(.isHeader)
                Text(inputIsTopic ? L("The map isn’t made yet. Your topic stays in the input field.") : L("The map isn’t made yet. Your material stays in the input field."))
                    .minorFont(15, maxScale: 1.4)
                    .foregroundColor(MinorColor.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
                Button { confirmClose = false } label: {
                    Text("Keep Creating")
                        .minorFont(17, .semibold, maxScale: 1.3)
                        .foregroundColor(.black)
                        .frame(maxWidth: .infinity, minHeight: 52)
                        .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(Color.white))
                }
                .buttonStyle(PressScale())
                .padding(.top, 6)
                Button(action: stop) {
                    Text("Stop")
                        .minorFont(17, .semibold, maxScale: 1.3)
                        .foregroundColor(MinorColor.dangerText)
                        .frame(maxWidth: .infinity, minHeight: 52)
                        .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(Color.white.opacity(0.04)))
                        .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).stroke(Color.white.opacity(0.1), lineWidth: 1))
                }
                .buttonStyle(.plain)
                Button {
                    center.notifyWhenReady(jobID)
                    confirmClose = false
                    onClose()
                } label: {
                    Text("Build in Background")
                        .minorFont(15, maxScale: 1.3)
                        .foregroundColor(MinorColor.textSecondary)
                        .frame(maxWidth: .infinity, minHeight: 44)
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 18)
            .padding(.top, 10)
            .padding(.bottom, 12)
            .background(
                RoundedRectangle(cornerRadius: 28, style: .continuous)
                    .fill(theme.chatRectangle)
                    .overlay(RoundedRectangle(cornerRadius: 28, style: .continuous).stroke(Color.white.opacity(0.08), lineWidth: 1))
                    .ignoresSafeArea(edges: .bottom)
            )
            .padding(.horizontal, 8)
        }
        .accessibilityAddTraits(voiceOver ? .isModal : [])
        .accessibilityAction(.escape) { confirmClose = false }
    }

    // MARK: - Failure

    private func failed(_ failure: BackendError) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Button(action: close) {
                HStack(spacing: 4) {
                    Image(systemName: "chevron.left").font(.system(size: 17, weight: .semibold))
                    Text("Back").minorFont(16, maxScale: 1.2)
                }
                .frame(minHeight: 44)
            }
            .buttonStyle(.plain)
            .padding(.horizontal, 16)
            Text("Creating a Map")
                .minorFont(32, .bold, maxScale: 1.3)
                .padding(.horizontal, 20)
                .padding(.top, 4)
                .accessibilityAddTraits(.isHeader)
            Text(inputIsTopic ? "Topic" : "Material")
                .textCase(.uppercase)
                .minorFont(12, .semibold, maxScale: 1.3)
                .foregroundColor(MinorColor.textTertiary)
                .padding(.horizontal, 20)
                .padding(.top, 18)
            Text(label)
                .minorFont(16, maxScale: 1.4)
                .lineLimit(4)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(14)
                .background(RoundedRectangle(cornerRadius: 14).fill(theme.chatRectangle))
                .overlay(RoundedRectangle(cornerRadius: 14).stroke(theme.chatStroke, lineWidth: 1))
                .padding(.horizontal, 16)
                .padding(.top, 6)
            Spacer()
            VStack(spacing: 12) {
                Image(systemName: failureIcon(failure))
                    .font(.system(size: 40, weight: .light))
                    .foregroundColor(MinorColor.textSecondary)
                    .accessibilityHidden(true)
                Text(failureTitle(failure))
                    .minorFont(22, .bold, maxScale: 1.3)
                    .multilineTextAlignment(.center)
                Text(failure.errorDescription ?? L("Something went wrong. Try again."))
                    .minorFont(15, maxScale: 1.4)
                    .foregroundColor(MinorColor.textSecondary)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
                VStack(spacing: 10) {
                    primaryAction(failure)
                    Button(action: changeInput) {
                        Text(inputIsTopic ? L("Change Topic") : L("Change the Material"))
                            .minorFont(17, .medium, maxScale: 1.3)
                            .frame(maxWidth: .infinity, minHeight: 52)
                            .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(Color.white.opacity(0.05)))
                            .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).stroke(Color.white.opacity(0.1), lineWidth: 1))
                    }
                    .buttonStyle(.plain)
                }
                .padding(.top, 10)
                Text("Your input is still here.")
                    .minorFont(13, maxScale: 1.3)
                    .foregroundColor(MinorColor.textTertiary)
            }
            .padding(.horizontal, 24)
            .accessibilityElement(children: .contain)
            Spacer()
        }
        .onAppear { UIAccessibility.post(notification: .announcement, argument: failure.errorDescription ?? "") }
    }

    // The action the reason calls for: a plan, signing in, or the same request again.
    @ViewBuilder
    private func primaryAction(_ failure: BackendError) -> some View {
        let title: String = {
            if case .modelLocked = failure, !account.isPro { return L("Get Minor PRO") }
            if needsUpgrade { return L("Get Minor Plus") }
            if case .signInRequired = failure { return L("Sign In") }
            return L("Retry")
        }()
        Button {
            if needsUpgrade { return onUpgrade() }
            if case .signInRequired = failure { return AuthGate.shared.require { center.retry(jobID) } }
            center.retry(jobID)
        } label: {
            Text(title)
                .minorFont(17, .semibold, maxScale: 1.3)
                .foregroundColor(.black)
                .frame(maxWidth: .infinity, minHeight: 52)
                .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(Color.white))
        }
        .buttonStyle(PressScale())
    }

    private func failureIcon(_ failure: BackendError) -> String {
        switch failure {
        case .offline, .interrupted: return "wifi.slash"
        case .limitReached, .planRequired, .modelLocked: return "lock"
        case .signInRequired, .unauthorized: return "person.crop.circle.badge.exclamationmark"
        case .badLink, .linkUnreachable, .youtubeNoTranscript: return "link"
        default: return "exclamationmark.triangle"
        }
    }

    private func failureTitle(_ failure: BackendError) -> String {
        switch failure {
        case .limitReached, .planRequired, .modelLocked: return L("This needs a plan")
        case .signInRequired: return L("Sign in to create maps")
        case .badLink, .linkUnreachable, .youtubeNoTranscript, .sourceTooLong: return L("Couldn’t read the source")
        default: return L("Couldn’t get the result")
        }
    }

    // Offered only while buying a plan would actually help; after an upgrade it's "Try Again".
    private var needsUpgrade: Bool {
        guard let failure else { return false }
        if case .modelLocked = failure { return !account.isPro }
        return failure.suggestsUpgrade && !account.isPaid
    }

    private var inputIsTopic: Bool {
        if case .topic = job?.input { return true }
        return job?.input == nil
    }

    // MARK: - Leaving

    // The job is dropped (a late answer is ignored) and the input goes back into the field.
    private func stop() {
        let input = job?.input
        center.cancel(jobID)
        confirmClose = false
        if let input { center.returnedInput = input }
        onClose()
    }

    private func changeInput() {
        stop()
    }

    private func close() {
        stop()
    }
}

// The map as it comes together: the topic in the middle, branches filling in with the stages, the
// rest still dashed.
private struct MapTakingShape: View {
    let topic: String
    let step: Int

    var body: some View {
        GeometryReader { geo in
            let w = geo.size.width, h = geo.size.height
            let root = CGPoint(x: w * 0.5, y: h * 0.5)
            let branches: [(CGPoint, Color, Bool)] = [
                (CGPoint(x: w * 0.2, y: h * 0.18), BranchColor.mint.color, step >= 1),
                (CGPoint(x: w * 0.82, y: h * 0.3), BranchColor.lilac.color, step >= 2),
                (CGPoint(x: w * 0.16, y: h * 0.6), .gray, step >= 3),
                (CGPoint(x: w * 0.84, y: h * 0.62), .gray, false),
                (CGPoint(x: w * 0.2, y: h * 0.86), .gray, false),
                (CGPoint(x: w * 0.8, y: h * 0.9), .gray, false),
            ]
            ZStack {
                // Lines first, so every box sits on top of them.
                ForEach(branches.indices, id: \.self) { i in
                    let (point, color, solid) = branches[i]
                    Path { path in
                        path.move(to: root)
                        let mid = (root.x + point.x) / 2
                        path.addCurve(to: point, control1: CGPoint(x: mid, y: root.y), control2: CGPoint(x: mid, y: point.y))
                    }
                    .stroke(solid ? color : Color.white.opacity(0.25), style: StrokeStyle(lineWidth: solid ? 2.5 : 1.5, dash: solid ? [] : [4, 4]))
                }
                ForEach(branches.indices, id: \.self) { i in
                    let (point, color, solid) = branches[i]
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(Color(white: 0.07))
                        .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(solid ? color.opacity(0.12) : Color.clear))
                        .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).stroke(solid ? color : Color.white.opacity(0.25), style: StrokeStyle(lineWidth: solid ? 2 : 1.2, dash: solid ? [] : [4, 4])))
                        .overlay {
                            if solid { Capsule().fill(Color.white.opacity(0.75)).frame(width: 52, height: 6) }
                        }
                        .frame(width: 96, height: 38)
                        .position(point)
                }
                Text(topic)
                    .minorFont(14, .semibold, maxScale: 1.1)
                    .multilineTextAlignment(.center)
                    .lineLimit(2)
                    .padding(.horizontal, 12)
                    .frame(width: 128, height: 56)
                    .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(BranchColor.lilac.color.opacity(0.14)))
                    .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(Color(white: 0.07)))
                    .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).stroke(BranchColor.lilac.color, lineWidth: 2))
                    .position(root)
            }
            .animation(.easeInOut(duration: 0.3), value: step)
        }
    }
}

// The canvas's dots behind the map taking shape.
private struct DotGrid: View {
    var body: some View {
        Canvas { ctx, size in
            let step: CGFloat = 18
            var y: CGFloat = step / 2
            while y < size.height {
                var x: CGFloat = step / 2
                while x < size.width {
                    ctx.fill(Path(ellipseIn: CGRect(x: x - 0.8, y: y - 0.8, width: 1.6, height: 1.6)), with: .color(Color.white.opacity(0.18)))
                    x += step
                }
                y += step
            }
        }
        .accessibilityHidden(true)
    }
}

// A ring turning while Minor works; still (an open ring) with Reduce Motion.
private struct Spinner: View {
    let still: Bool
    @State private var turning = false

    var body: some View {
        ZStack {
            Circle().stroke(Color.white.opacity(0.15), lineWidth: 3)
            Circle()
                .trim(from: 0, to: 0.28)
                .stroke(Color.white, style: StrokeStyle(lineWidth: 3, lineCap: .round))
                .rotationEffect(.degrees(turning ? 360 : 0))
        }
        .frame(width: 34, height: 34)
        .onAppear {
            guard !still else { return }
            withAnimation(.linear(duration: 0.9).repeatForever(autoreverses: false)) { turning = true }
        }
        .accessibilityHidden(true)
    }
}
