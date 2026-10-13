//
//  JoinInviteView.swift
//  Minor Ai
//
//  An invite to a shared map, before joining: the map's title, who invites (when their account
//  has a name), the role the link gives and what opens with it. Nothing of the map's content is
//  loaded until the person joins; the picture is a neutral one. "Not Now" changes nothing. When
//  signing in is needed, it happens here and the same invite continues.
//

import SwiftUI

struct JoinInviteView: View {
    let token: String
    let theme: AppTheme
    var onJoined: (UUID) -> Void
    var onClose: () -> Void

    @ObservedObject private var auth = AuthService.shared
    @State private var preview: CollabService.InvitePreview?
    @State private var loadError: String?
    @State private var joinError: String?
    @State private var joining = false
    @State private var showSignIn = false
    @State private var joinAfterSignIn = false
    @State private var roleExplained = false

    var body: some View {
        VStack(spacing: 0) {
            header
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    InviteIllustration(title: preview?.status == .invalid ? nil : preview?.title)
                        .frame(height: 176)
                        .padding(.bottom, 10)
                    content
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 12)
            }
            footer
        }
        .foregroundColor(MinorColor.textPrimary)
        .background(MinorColor.editorSheet.ignoresSafeArea())
        .preferredColorScheme(.dark)
        .task { if preview == nil { await load() } }
        .sheet(isPresented: $showSignIn, onDismiss: {
            // Signed in: the same invite goes on; "Not Now" leaves it waiting here.
            if joinAfterSignIn && auth.isSignedIn { join() }
            joinAfterSignIn = false
        }) {
            SignInView(onFinish: { showSignIn = false })
        }
    }

    // MARK: - Parts

    private var header: some View {
        ZStack {
            Text("Map Invitation")
                .minorFont(17, .semibold, maxScale: 1.2)
                .accessibilityAddTraits(.isHeader)
            HStack {
                Spacer()
                Button(action: onClose) {
                    Image(systemName: "xmark")
                        .font(.system(size: 13, weight: .semibold))
                        .frame(width: 30, height: 30)
                        .background(Circle().fill(Color.white.opacity(0.1)))
                        .frame(width: 44, height: 44)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Close")
            }
        }
        .padding(.horizontal, 10)
        .padding(.top, 14)
        .padding(.bottom, 8)
    }

    @ViewBuilder
    private var content: some View {
        if let preview {
            switch preview.status {
            case .invalid:
                problem(icon: "xmark.circle", title: L("This link no longer works"), text: L("It was turned off or has expired. Ask the map’s owner for a new one."))
            case .full:
                titleBlock(preview)
                problem(icon: "person.3", title: L("This map is full"), text: L("It already has as many people as its owner’s plan allows. Ask the owner to make room."))
            case .member:
                titleBlock(preview)
                infoCard(icon: "checkmark.circle", title: L("You’re already on this map"), text: L("It opens as it is; nothing is added twice."))
            case .ok:
                titleBlock(preview)
                roleCard(preview.role)
                infoCard(icon: "lock", title: L("Only this map opens."), text: L("The author’s own chat and presentations stay closed."))
                Text("You don’t need a subscription to take part.")
                    .minorFont(13, style: .footnote, maxScale: 1.4)
                    .foregroundColor(MinorColor.textTertiary)
                    .frame(maxWidth: .infinity)
                    .multilineTextAlignment(.center)
                    .padding(.top, 6)
            }
            if let joinError {
                Text(joinError)
                    .minorFont(14, maxScale: 1.4)
                    .foregroundColor(MinorColor.dangerText)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityAddTraits(.updatesFrequently)
            }
        } else if let loadError {
            problem(icon: "wifi.exclamationmark", title: L("Couldn’t open the invitation"), text: loadError)
        } else {
            VStack(alignment: .leading, spacing: 10) {
                RoundedRectangle(cornerRadius: 6).fill(Color.white.opacity(0.08)).frame(width: 220, height: 28)
                RoundedRectangle(cornerRadius: 6).fill(Color.white.opacity(0.06)).frame(width: 160, height: 16)
                RoundedRectangle(cornerRadius: 14).fill(Color.white.opacity(0.05)).frame(height: 64)
            }
            .accessibilityElement()
            .accessibilityLabel(Text("Loading the invitation"))
        }
    }

    private func titleBlock(_ preview: CollabService.InvitePreview) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(preview.title.isEmpty ? L("Shared map") : preview.title)
                .minorFont(28, .bold, style: .title1, maxScale: 1.3)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityAddTraits(.isHeader)
            Text(preview.inviter.map { L("\($0) invites you") } ?? L("You’re invited to this map"))
                .minorFont(16, maxScale: 1.4)
                .foregroundColor(MinorColor.textSecondary)
        }
        .padding(.bottom, 6)
    }

    // The role the link gives: information, not a choice. Tapping it says how roles change.
    private func roleCard(_ role: CollabRole) -> some View {
        Button {
            withAnimation(.minorMenu) { roleExplained.toggle() }
        } label: {
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 14) {
                    Image(systemName: role == .viewer ? "eye" : "pencil")
                        .font(.system(size: 18))
                        .frame(width: 40, height: 40)
                        .background(Circle().fill(Color.white.opacity(0.08)))
                    VStack(alignment: .leading, spacing: 2) {
                        Text(role == .viewer ? L("Viewer") : L("Editor"))
                            .minorFont(16, .semibold, maxScale: 1.4)
                        Text(role == .viewer ? L("You’ll see the map and its changes") : L("You’ll be able to add and change ideas"))
                            .minorFont(13, maxScale: 1.4)
                            .foregroundColor(MinorColor.textSecondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    Spacer(minLength: 4)
                    Image(systemName: "chevron.right")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundColor(MinorColor.textTertiary)
                        .rotationEffect(.degrees(roleExplained ? 90 : 0))
                }
                if roleExplained {
                    Text("The role comes with the link. Only the map’s owner can change it later.")
                        .minorFont(13, maxScale: 1.4)
                        .foregroundColor(MinorColor.textTertiary)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.leading, 54)
                }
            }
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(RoundedRectangle(cornerRadius: 14).fill(Color.white.opacity(0.05)))
            .overlay(RoundedRectangle(cornerRadius: 14).stroke(Color.white.opacity(0.08), lineWidth: 1))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .combine)
        .accessibilityHint(Text("Explains the role"))
    }

    private func infoCard(icon: String, title: String, text: String) -> some View {
        HStack(alignment: .top, spacing: 14) {
            Image(systemName: icon)
                .font(.system(size: 18))
                .foregroundColor(MinorColor.textSecondary)
                .frame(width: 40, height: 40)
                .background(Circle().fill(Color.white.opacity(0.08)))
            VStack(alignment: .leading, spacing: 2) {
                Text(title).minorFont(15, .semibold, maxScale: 1.4)
                Text(text)
                    .minorFont(13, maxScale: 1.4)
                    .foregroundColor(MinorColor.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
        .padding(14)
        .background(RoundedRectangle(cornerRadius: 14).fill(Color.white.opacity(0.05)))
        .overlay(RoundedRectangle(cornerRadius: 14).stroke(Color.white.opacity(0.08), lineWidth: 1))
        .accessibilityElement(children: .combine)
    }

    private func problem(icon: String, title: String, text: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Image(systemName: icon).font(.system(size: 26)).foregroundColor(MinorColor.textSecondary)
            Text(title).minorFont(20, .bold, maxScale: 1.3)
            Text(text)
                .minorFont(15, maxScale: 1.4)
                .foregroundColor(MinorColor.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
    }

    @ViewBuilder
    private var footer: some View {
        VStack(spacing: 6) {
            switch (preview?.status, loadError) {
            case (.ok?, _):
                primary(L("Join"), busy: joining) { start() }
                secondary(L("Not Now"), action: onClose)
            case (.member?, _):
                primary(L("Open Map"), busy: joining) { start() }
            case (nil, _?):
                primary(L("Try Again"), busy: false) { Task { await load() } }
                secondary(L("Close"), action: onClose)
            case (nil, nil):
                primary(L("Join"), busy: true) {}
            default:
                primary(L("Close"), busy: false, action: onClose)
            }
        }
        .padding(.horizontal, 16)
        .padding(.top, 8)
        .padding(.bottom, 8)
    }

    private func primary(_ title: String, busy: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            ZStack {
                Text(title).opacity(busy ? 0 : 1)
                if busy { ProgressView().tint(.black) }
            }
            .minorFont(17, .semibold, maxScale: 1.3)
            .foregroundColor(.black)
            .frame(maxWidth: .infinity, minHeight: 50)
            .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(Color.white))
        }
        .buttonStyle(PressScale())
        .disabled(busy)
    }

    private func secondary(_ title: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .minorFont(16, maxScale: 1.3)
                .foregroundColor(MinorColor.textSecondary)
                .frame(maxWidth: .infinity, minHeight: 44)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    // MARK: - Actions

    private func load() async {
        loadError = nil
        #if DEBUG
        if let demo = Self.demoPreview { preview = demo; return }
        #endif
        do {
            preview = try await CollabService.shared.preview(token: token)
        } catch {
            loadError = (error as? LocalizedError)?.errorDescription ?? L("Check your connection and try again.")
        }
    }

    private func start() {
        joinError = nil
        guard auth.isSignedIn else {
            joinAfterSignIn = true
            showSignIn = true
            return
        }
        join()
    }

    private func join() {
        guard !joining else { return }
        joining = true
        joinError = nil
        Task {
            defer { joining = false }
            do {
                let id = try await CollabService.shared.join(token: token)
                Telemetry.log("collab_join")
                Haptics.success()
                onJoined(id)
            } catch CollabService.CollabError.mapFull {
                preview = preview.map { .init(mapID: $0.mapID, title: $0.title, role: $0.role, inviter: $0.inviter, status: .full) }
            } catch CollabService.CollabError.invalidInvite {
                preview = preview.map { .init(mapID: $0.mapID, title: $0.title, role: $0.role, inviter: $0.inviter, status: .invalid) }
            } catch {
                joinError = (error as? LocalizedError)?.errorDescription ?? L("Couldn’t open the shared map. Try again.")
            }
        }
    }

    #if DEBUG
    // -demoJoin [ok|member|full|invalid|viewer]: the invitation screen without a server, for screenshots.
    static var demoPreview: CollabService.InvitePreview? {
        let args = ProcessInfo.processInfo.arguments
        guard let i = args.firstIndex(of: "-demoJoin") else { return nil }
        let kind = args.indices.contains(i + 1) ? args[i + 1] : "ok"
        let ru = AppLanguage.current.locale.identifier.hasPrefix("ru")
        let status: CollabService.InvitePreview.Status = kind == "member" ? .member : kind == "full" ? .full : kind == "invalid" ? .invalid : .ok
        return .init(mapID: nil, title: ru ? "Запуск подкаста" : "Podcast Launch", role: kind == "viewer" ? .viewer : .editor,
                     inviter: ru ? "Анна" : "Anna", status: status)
    }
    #endif
}

// A shared map drawn without its content: the title in the middle and three blank ideas.
private struct InviteIllustration: View {
    let title: String?

    var body: some View {
        GeometryReader { geo in
            let w = geo.size.width, h = geo.size.height
            let center = CGPoint(x: w * 0.3, y: h / 2)
            let cards: [(CGPoint, String)] = [
                (CGPoint(x: w * 0.74, y: h * 0.2), "doc.text"),
                (CGPoint(x: w * 0.74, y: h * 0.5), "person.2"),
                (CGPoint(x: w * 0.74, y: h * 0.8), "chart.bar"),
            ]
            ZStack {
                Canvas { context, size in
                    var dots = Path()
                    for x in stride(from: 8.0, to: size.width, by: 16) {
                        for y in stride(from: 8.0, to: size.height, by: 16) {
                            dots.addEllipse(in: CGRect(x: x - 0.8, y: y - 0.8, width: 1.6, height: 1.6))
                        }
                    }
                    context.fill(dots, with: .color(.white.opacity(0.06)))
                    for (point, _) in cards {
                        var path = Path()
                        let start = CGPoint(x: center.x + 64, y: center.y)
                        let end = CGPoint(x: point.x - 56, y: point.y)
                        path.move(to: start)
                        path.addCurve(to: end, control1: CGPoint(x: (start.x + end.x) / 2, y: start.y), control2: CGPoint(x: (start.x + end.x) / 2, y: end.y))
                        context.stroke(path, with: .color(.white.opacity(0.28)), lineWidth: 1.4)
                        context.fill(Path(ellipseIn: CGRect(x: end.x - 3, y: end.y - 3, width: 6, height: 6)), with: .color(MinorColor.accent))
                    }
                }
                HStack(spacing: 8) {
                    Image(systemName: "point.3.connected.trianglepath.dotted").font(.system(size: 14, weight: .semibold))
                    Text(title?.isEmpty == false ? title! : L("Shared map"))
                        .font(.system(size: 13, weight: .semibold))
                        .lineLimit(2)
                        .minimumScaleFactor(0.8)
                }
                .padding(.horizontal, 12)
                .frame(width: 128, height: 46)
                .background(RoundedRectangle(cornerRadius: 12).fill(Color(hex: "#0E1A15")))
                .overlay(RoundedRectangle(cornerRadius: 12).stroke(MinorColor.accent, lineWidth: 1.5))
                .position(center)
                ForEach(cards.indices, id: \.self) { i in
                    HStack(spacing: 8) {
                        Image(systemName: cards[i].1).font(.system(size: 13)).foregroundColor(MinorColor.textSecondary)
                        VStack(alignment: .leading, spacing: 4) {
                            Capsule().fill(Color.white.opacity(0.22)).frame(width: 46, height: 4)
                            Capsule().fill(Color.white.opacity(0.12)).frame(width: 30, height: 4)
                        }
                    }
                    .padding(.horizontal, 12)
                    .frame(width: 112, height: 40)
                    .background(RoundedRectangle(cornerRadius: 10).fill(Color.white.opacity(0.05)))
                    .overlay(RoundedRectangle(cornerRadius: 10).stroke(Color.white.opacity(0.12), lineWidth: 1))
                    .position(cards[i].0)
                }
            }
        }
        .background(RoundedRectangle(cornerRadius: 16).fill(Color.black.opacity(0.25)))
        .overlay(RoundedRectangle(cornerRadius: 16).stroke(Color.white.opacity(0.06), lineWidth: 1))
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .accessibilityHidden(true)
    }
}
