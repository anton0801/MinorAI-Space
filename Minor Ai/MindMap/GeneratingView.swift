//
//  GeneratingView.swift
//  Minor Ai
//
//  Building Your Map: breathing mark and step list for a GenerationCenter job.
//  The user can stop it, keep waiting, or let it finish in the background.
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
    @State private var confirmClose = false
    @State private var breathe = false
    @State private var lastJob: GenerationCenter.Job?

    private var job: GenerationCenter.Job? { center.jobs[jobID] ?? lastJob }
    private var failure: BackendError? { center.jobs[jobID]?.error }
    private var step: Int { job?.step ?? 0 }

    private var steps: [String] {
        let rest = [L("Finding the main ideas"), L("Building branches"), L("Adding details")]
        guard let input = job?.input else { return [L("Reading")] + rest }
        let first: String
        switch input {
        case .topic(let topic): first = L("Thinking about “\(String(topic.prefix(32)))”")
        case .link(let url): first = L("Reading \(URL(string: url)?.host ?? L("the page"))")
        case .youtube: first = L("Watching the video")
        case .text(_, let source): first = source.kind == .voice ? L("Listening to your note") : L("Reading “\(String(source.label.prefix(32)))”")
        }
        return [first] + rest
    }

    private var subtitle: String {
        guard let input = job?.input else { return L("Usually 10–20 seconds.") }
        switch input {
        case .topic: return L("Usually 10–20 seconds.")
        case .link(let url): return L("From \(URL(string: url)?.host ?? L("a web page")). Usually 10–20 seconds.")
        case .youtube: return L("From YouTube. Usually 20–40 seconds.")
        case .text(_, let source): return L("From “\(source.label)”. Usually 10–20 seconds.")
        }
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

            VStack(spacing: 0) {
                HStack {
                    Button { failure == nil ? (confirmClose = true) : close(cancel: true) } label: {
                        Image(systemName: "xmark")
                            .font(.system(size: 13, weight: .bold))
                            .foregroundColor(.white)
                            .frame(width: 30, height: 30)
                            .background(Circle().fill(MinorColor.closeFill))
                            .frame(width: 44, height: 44)
                    }
                    .accessibilityLabel("Close")
                    Spacer()
                }
                .padding(.horizontal, 12)

                Spacer(minLength: 20)
                ZStack {
                    Circle()
                        .fill(theme.glowSolid)
                        .frame(width: 166, height: 166)
                        .blur(radius: 30)
                        .opacity(breathe ? 0.4 : 0.22)
                        .scaleEffect(breathe ? 1.08 : 1)
                    Image("logo").resizable().scaledToFit().frame(width: 110, height: 110)
                }
                .accessibilityHidden(true)
                .onAppear {
                    guard !reduceMotion else { return }
                    withAnimation(.easeInOut(duration: 1.2).repeatForever(autoreverses: true)) { breathe = true }
                }

                Text("Building Your Map")
                    .font(.system(size: 20, weight: .bold))
                    .padding(.top, 36)
                Text(subtitle)
                    .font(.system(size: 15))
                    .foregroundColor(MinorColor.textSecondary)
                    .multilineTextAlignment(.center)
                    .padding(.top, 6)
                    .padding(.horizontal, 24)

                VStack(alignment: .leading, spacing: 14) {
                    ForEach(Array(steps.enumerated()), id: \.offset) { index, title in
                        stepRow(index: index, title: title)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 20)
                .padding(.vertical, 18)
                .minorSurface(theme)
                .padding(.horizontal, 16)
                .padding(.top, 28)

                if let failure {
                    VStack(spacing: 12) {
                        Text(failure.errorDescription ?? "")
                            .font(.system(size: 13))
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.horizontal, 14)
                            .padding(.vertical, 10)
                            .background(RoundedRectangle(cornerRadius: 12).fill(MinorColor.danger.opacity(0.25)))
                            .overlay(RoundedRectangle(cornerRadius: 12).stroke(MinorColor.danger.opacity(0.6), lineWidth: 1))
                        Button {
                            if needsUpgrade { onUpgrade() } else { center.retry(jobID) }
                        } label: {
                            Text(needsUpgrade ? (failure == .modelLocked ? "Get Minor PRO" : "Get Minor Plus") : "Try Again")
                                .font(.system(size: 16, weight: .semibold))
                                .foregroundColor(.black)
                                .frame(maxWidth: .infinity)
                                .frame(height: 50)
                                .background(Capsule().fill(MinorColor.sendFill))
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.top, 20)
                } else {
                    Text("You can leave this screen. The map will appear in Your Maps.")
                        .font(.system(size: 13))
                        .foregroundColor(MinorColor.textTertiary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 40)
                        .padding(.top, 24)
                }
                Spacer()
            }
        }
        .foregroundColor(MinorColor.textPrimary)
        .confirmationDialog("Stop building this map?", isPresented: $confirmClose, titleVisibility: .visible) {
            Button("Stop", role: .destructive) { close(cancel: true) }
            Button("Build in Background") {
                center.notifyWhenReady(jobID)
                close(cancel: false)
            }
            Button("Keep Building", role: .cancel) {}
        }
        .onAppear {
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

    // Offered only while buying a plan would actually help; after an upgrade it's "Try Again".
    private var needsUpgrade: Bool {
        guard let failure else { return false }
        if case .modelLocked = failure { return !AccountStore.shared.isPro }
        return failure.suggestsUpgrade && !account.isPaid
    }

    private func close(cancel: Bool) {
        if cancel { center.cancel(jobID) }
        onClose()
    }

    private func stepRow(index: Int, title: String) -> some View {
        let done = index < step
        let now = index == step && failure == nil
        let failed = index == step && failure != nil
        return HStack(spacing: 12) {
            ZStack {
                Circle()
                    .fill(done ? MinorColor.sendFill : Color.clear)
                    .overlay(Circle().stroke(failed ? MinorColor.danger : now ? theme.glowSolid : theme.chatStroke, lineWidth: 1))
                if done {
                    Image(systemName: "checkmark").font(.system(size: 11, weight: .bold)).foregroundColor(.black)
                } else if now {
                    Circle().fill(theme.glowSolid).frame(width: 8, height: 8).opacity(breathe ? 1 : 0.4)
                } else if failed {
                    Image(systemName: "xmark").font(.system(size: 10, weight: .bold)).foregroundColor(MinorColor.danger)
                }
            }
            .frame(width: 22, height: 22)
            Text(title)
                .font(.system(size: 15))
                .foregroundColor(failed ? MinorColor.danger : done || now ? MinorColor.textPrimary : MinorColor.textTertiary)
                .lineLimit(1)
        }
        .accessibilityElement(children: .combine)
        .accessibilityValue(done ? "Done" : now ? "In progress" : failed ? "Failed" : "Waiting")
    }
}
