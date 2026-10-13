//
//  CollabSheet.swift
//  Minor Ai
//
//  Sharing a map. A map only you have opens on Invite: pick the role first, then create a link
//  and send or copy it. A shared map opens on its people: roles and removal (the owner), turning
//  off links (people stay), stopping sharing or leaving. Only the map is shared: the owner's
//  chat, presentations and source files are not. Every change is checked by the server.
//

import SwiftUI
import UIKit

struct CollabSheet: View {
    let mapID: UUID
    let theme: AppTheme
    var onUpgrade: () -> Void

    enum Page { case invite, members }

    @Environment(\.dismiss) private var dismiss
    @ObservedObject private var store = MapStore.shared
    @ObservedObject private var collab = CollabService.shared
    @ObservedObject private var account = AccountStore.shared
    @ObservedObject private var auth = AuthService.shared
    @State private var page: Page
    @State private var inviteRole: CollabRole = .editor
    @State private var link: URL?
    @State private var creating = false
    @State private var copied = false
    @State private var error: String?
    @State private var members: [CollabService.Member] = []
    @State private var loadingMembers = false
    @State private var membersFailed = false
    @State private var changing: String?          // the member whose role or place is being changed
    @State private var linksOff = false
    @State private var confirmEnd = false
    @State private var confirmRevoke = false
    @State private var pendingRemove: CollabService.Member?
    @State private var showSignIn = false
    @State private var inviteAfterSignIn = false

    init(mapID: UUID, theme: AppTheme, onUpgrade: @escaping () -> Void) {
        self.mapID = mapID
        self.theme = theme
        self.onUpgrade = onUpgrade
        var shared = MapStore.shared.map(mapID)?.collab != nil
        #if DEBUG
        if Self.demoMembers != nil { shared = true }
        #endif
        _page = State(initialValue: shared ? .members : .invite)
    }

    private var map: MindMap? { store.map(mapID) }
    private var info: CollabInfo? {
        #if DEBUG
        if Self.demoMembers != nil { return CollabInfo(isOwner: true, version: 1) }
        #endif
        return map?.collab
    }
    private var isOwner: Bool { info?.isOwner == true }
    // The owner's plan sets how many people may join; the owner isn't counted.
    private var limit: Int { members.first?.member_limit ?? (account.plan == .pro ? 25 : account.plan == .plus ? 5 : 0) }
    private var others: Int { max(members.count - 1, 0) }
    private var isFull: Bool { info != nil && !members.isEmpty && others >= limit }

    var body: some View {
        VStack(spacing: 0) {
            switch page {
            case .invite: invitePage
            case .members: membersPage
            }
        }
        .foregroundColor(MinorColor.textPrimary)
        .background(MinorColor.editorSheet.ignoresSafeArea())
        .preferredColorScheme(.dark)
        .task { await loadMembers() }
        .onChange(of: info == nil) { unshared in
            // Sharing stopped (here or by the owner): back to inviting.
            if unshared { page = .invite; members = []; link = nil }
        }
        .sheet(isPresented: $showSignIn, onDismiss: {
            if inviteAfterSignIn && auth.isSignedIn { createLink() }
            inviteAfterSignIn = false
        }) {
            SignInView(onFinish: { showSignIn = false })
        }
        .confirmationDialog(isOwner ? L("Stop working together on this map?") : L("Leave this map?"),
                            isPresented: $confirmEnd, titleVisibility: .visible) {
            Button(isOwner ? L("Stop Sharing") : L("Leave Map"), role: .destructive) { end() }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text(isOwner
                 ? L("People on the map stop getting your changes and keep their own copy. The map stays with you; invite links stop working.")
                 : L("You keep your own copy on this iPhone; changes from others stop coming in."))
        }
        .confirmationDialog(L("Turn off invite links?"), isPresented: $confirmRevoke, titleVisibility: .visible) {
            Button(L("Turn Off Links"), role: .destructive) { revoke() }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("New people can’t join with the links you sent. Everyone already on the map stays.")
        }
        .confirmationDialog(pendingRemove.map { L("Remove \(displayName($0)) from the map?") } ?? "",
                            isPresented: Binding(get: { pendingRemove != nil }, set: { if !$0 { pendingRemove = nil } }),
                            titleVisibility: .visible, presenting: pendingRemove) { member in
            Button(L("Remove"), role: .destructive) { remove(member) }
            Button("Cancel", role: .cancel) {}
        } message: { _ in
            Text("They stop seeing your changes and keep the copy they already have. Invite links are turned off too, so an old link can’t bring them back.")
        }
    }

    // MARK: - Invite

    private var invitePage: some View {
        VStack(spacing: 0) {
            header(title: L("Invite to Map"), subtitle: map?.title, back: info != nil)
            ScrollView {
                VStack(alignment: .leading, spacing: 8) {
                    roleOption(.editor, title: L("Editor"), detail: L("Adds and changes ideas"))
                    roleOption(.viewer, title: L("Viewer"), detail: L("Sees the map without changing it"))
                    HStack(alignment: .top, spacing: 12) {
                        Image(systemName: "lock").font(.system(size: 16)).foregroundColor(MinorColor.textSecondary).frame(width: 24)
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Only this map is shared").minorFont(14, .semibold, maxScale: 1.4)
                            Text("Your chat, presentations and source files don’t open with it.")
                                .minorFont(12, style: .caption1, maxScale: 1.4)
                                .foregroundColor(MinorColor.textSecondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                    .padding(.top, 8)
                    .accessibilityElement(children: .combine)
                    Rectangle().fill(Color.white.opacity(0.08)).frame(height: 1).padding(.vertical, 4)
                    Label("People you invite don’t need a subscription", systemImage: "info.circle")
                        .minorFont(12, style: .caption1, maxScale: 1.4)
                        .foregroundColor(MinorColor.textTertiary)
                    if let link { linkCard(link) }
                    if let error { errorText(error) }
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 12)
            }
            inviteFooter
        }
    }

    private func roleOption(_ role: CollabRole, title: String, detail: String) -> some View {
        let chosen = inviteRole == role
        return Button {
            guard !chosen else { return }
            Haptics.selection()
            inviteRole = role
            // A link carries its role: another role needs a new link.
            link = nil
            copied = false
        } label: {
            HStack(spacing: 14) {
                ZStack {
                    Circle().stroke(chosen ? MinorColor.accent : MinorColor.textTertiary, lineWidth: 1.5)
                    if chosen { Circle().fill(MinorColor.accent).padding(5) }
                }
                .frame(width: 22, height: 22)
                VStack(alignment: .leading, spacing: 2) {
                    Text(title).minorFont(16, .semibold, maxScale: 1.4)
                    Text(detail).minorFont(13, maxScale: 1.4).foregroundColor(MinorColor.textSecondary)
                }
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 14)
            .frame(minHeight: 60)
            .background(RoundedRectangle(cornerRadius: 14).fill(chosen ? MinorColor.accent.opacity(0.06) : Color.white.opacity(0.04)))
            .overlay(RoundedRectangle(cornerRadius: 14).stroke(chosen ? MinorColor.accent : Color.white.opacity(0.08), lineWidth: chosen ? 1.5 : 1))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(creating)
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(chosen ? [.isButton, .isSelected] : .isButton)
    }

    // The link that was made: send it with any app, or copy it.
    private func linkCard(_ url: URL) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Label(inviteRole == .viewer ? L("Link for a viewer is ready") : L("Link for an editor is ready"), systemImage: "link")
                .minorFont(14, .semibold, maxScale: 1.4)
            Text("Works for 14 days. Anyone with it can ask to join, up to your plan’s limit.")
                .minorFont(12, style: .caption1, maxScale: 1.4)
                .foregroundColor(MinorColor.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
            HStack(spacing: 8) {
                smallButton(L("Send"), icon: "square.and.arrow.up") { send(url) }
                smallButton(copied ? L("Copied") : L("Copy"), icon: copied ? "checkmark" : "doc.on.doc") { copy(url) }
            }
        }
        .padding(14)
        .background(RoundedRectangle(cornerRadius: 14).fill(Color.white.opacity(0.05)))
        .overlay(RoundedRectangle(cornerRadius: 14).stroke(Color.white.opacity(0.08), lineWidth: 1))
        .padding(.top, 6)
    }

    @ViewBuilder
    private var inviteFooter: some View {
        VStack(spacing: 8) {
            if auth.isSignedIn && !account.isPaid && info == nil {
                Text("Inviting is part of Minor Plus (invite up to 5 people to a map) and PRO (up to 25).")
                    .minorFont(13, maxScale: 1.4)
                    .foregroundColor(MinorColor.textSecondary)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
                primary(L("Get Minor Plus")) {
                    dismiss()
                    onUpgrade()
                }
            } else if info != nil && limit == 0 && !loadingMembers && !members.isEmpty {
                Text("Your plan has ended, so new people can’t join. Everyone already on the map stays.")
                    .minorFont(13, maxScale: 1.4)
                    .foregroundColor(MinorColor.textSecondary)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
                primary(L("Get Minor Plus")) {
                    dismiss()
                    onUpgrade()
                }
            } else if isFull {
                Text(L("The map has \(others) of \(limit) people. Remove someone to invite another."))
                    .minorFont(13, maxScale: 1.4)
                    .foregroundColor(MinorColor.textSecondary)
                    .multilineTextAlignment(.center)
                primary(L("Create Link"), busy: false) {}
                    .disabled(true)
                    .opacity(0.4)
            } else if link == nil {
                primary(auth.isSignedIn ? L("Create Link") : L("Sign In to Invite"), busy: creating) { createLink() }
            }
        }
        .padding(.horizontal, 16)
        .padding(.top, 8)
        .padding(.bottom, 8)
    }

    // MARK: - Members

    private var membersPage: some View {
        VStack(spacing: 0) {
            header(title: L("People on the Map"), subtitle: statusText, back: false)
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    if loadingMembers && members.isEmpty {
                        ForEach(0..<3, id: \.self) { _ in skeletonRow }
                    } else if membersFailed && members.isEmpty {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Couldn’t load the people on this map.").minorFont(15, maxScale: 1.4)
                            Button("Try Again") { Task { await loadMembers() } }
                                .minorFont(15, .semibold, maxScale: 1.3)
                                .foregroundColor(MinorColor.accent)
                                .frame(minHeight: 44)
                        }
                    } else {
                        ForEach(Array(members.enumerated()), id: \.element.id) { index, member in
                            memberRow(member)
                            if index < members.count - 1 { Rectangle().fill(Color.white.opacity(0.08)).frame(height: 1).padding(.leading, 56) }
                        }
                    }
                    if isOwner {
                        primary(L("Invite"), icon: "plus") { page = .invite }
                            .disabled(isFull || limit == 0)
                            .opacity(isFull || limit == 0 ? 0.4 : 1)
                            .padding(.top, 10)
                        if !members.isEmpty && limit > 0 {
                            Text(L("Invited: \(others) of \(limit)"))
                                .minorFont(12, style: .caption1, maxScale: 1.4)
                                .foregroundColor(isFull ? MinorColor.dangerText : MinorColor.textTertiary)
                                .frame(maxWidth: .infinity)
                                .padding(.top, 6)
                        }
                        Text("Invite Links")
                            .minorFont(15, .semibold, maxScale: 1.3)
                            .padding(.top, 14)
                            .padding(.bottom, 8)
                            .accessibilityAddTraits(.isHeader)
                        HStack(spacing: 12) {
                            Image(systemName: "link").font(.system(size: 15)).foregroundColor(MinorColor.textSecondary).frame(width: 22)
                            Text(linksOff ? L("Links are off. People on the map stay.") : L("People on the map keep access"))
                                .minorFont(12, maxScale: 1.4)
                                .foregroundColor(MinorColor.textSecondary)
                                .lineLimit(2)
                                .minimumScaleFactor(0.85)
                            Spacer(minLength: 8)
                            if !linksOff {
                                Button { confirmRevoke = true } label: {
                                    Text("Turn Off Links")
                                        .minorFont(13, .semibold, maxScale: 1.3)
                                        .padding(.horizontal, 12)
                                        .frame(minHeight: 32)
                                        .background(RoundedRectangle(cornerRadius: 9).fill(Color.white.opacity(0.08)))
                                        .frame(minHeight: 44)
                                        .contentShape(Rectangle())
                                }
                                .buttonStyle(.plain)
                            }
                        }
                        .padding(.horizontal, 12)
                        .frame(minHeight: 52)
                        .background(RoundedRectangle(cornerRadius: 12).fill(Color.white.opacity(0.04)))
                        .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color.white.opacity(0.08), lineWidth: 1))
                        endButton(L("Stop Working Together"), icon: "person.2.slash")
                            .padding(.top, 10)
                    } else if info != nil {
                        endButton(L("Leave Map"), icon: "rectangle.portrait.and.arrow.right")
                            .padding(.top, 18)
                    }
                    if let error { errorText(error).padding(.top, 10) }
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 16)
            }
        }
    }

    private func memberRow(_ member: CollabService.Member) -> some View {
        let isMe = member.user_id == auth.session?.userID
        let name = isMe ? L("You") : displayName(member)
        return HStack(spacing: 14) {
            Text(String((isMe ? L("You") : (member.email ?? "?")).prefix(1)).uppercased())
                .font(.system(size: 16, weight: .bold))
                .foregroundColor(.black)
                .frame(width: 40, height: 40)
                .background(Circle().fill(color(for: member.user_id)))
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text(name)
                    .minorFont(16, .semibold, maxScale: 1.4)
                    .lineLimit(1)
                    .truncationMode(.middle)
                Text(roleName(member.collabRole))
                    .minorFont(13, maxScale: 1.4)
                    .foregroundColor(MinorColor.textSecondary)
            }
            Spacer(minLength: 8)
            if changing == member.user_id {
                ProgressView().tint(.white).frame(width: 44, height: 44)
            } else if isOwner && member.collabRole != .owner {
                Menu {
                    Picker("Role", selection: Binding(get: { member.collabRole }, set: { setRole($0, for: member) })) {
                        Label("Editor", systemImage: "pencil").tag(CollabRole.editor)
                        Label("Viewer", systemImage: "eye").tag(CollabRole.viewer)
                    }
                    Button(role: .destructive) { pendingRemove = member } label: { Label("Remove from Map", systemImage: "person.badge.minus") }
                } label: {
                    Image(systemName: "chevron.down")
                        .font(.system(size: 13, weight: .semibold))
                        .frame(width: 32, height: 32)
                        .background(Circle().fill(Color.white.opacity(0.08)))
                        .frame(width: 44, height: 44)
                        .contentShape(Rectangle())
                }
                .accessibilityLabel(L("Role of \(name)"))
                .accessibilityValue(roleName(member.collabRole))
            }
        }
        .frame(minHeight: 56)
        .accessibilityElement(children: .contain)
    }

    private var skeletonRow: some View {
        HStack(spacing: 14) {
            Circle().fill(Color.white.opacity(0.08)).frame(width: 40, height: 40)
            VStack(alignment: .leading, spacing: 6) {
                Capsule().fill(Color.white.opacity(0.1)).frame(width: 120, height: 10)
                Capsule().fill(Color.white.opacity(0.06)).frame(width: 70, height: 8)
            }
            Spacer()
        }
        .frame(minHeight: 60)
        .accessibilityHidden(true)
    }

    private func endButton(_ title: String, icon: String) -> some View {
        Button { confirmEnd = true } label: {
            HStack(spacing: 12) {
                Image(systemName: icon).font(.system(size: 16))
                Text(title).minorFont(15, .medium, maxScale: 1.3)
                Spacer(minLength: 0)
            }
            .foregroundColor(MinorColor.dangerText)
            .padding(.horizontal, 14)
            .frame(minHeight: 50)
            .background(RoundedRectangle(cornerRadius: 12).fill(MinorColor.danger.opacity(0.1)))
            .overlay(RoundedRectangle(cornerRadius: 12).stroke(MinorColor.danger.opacity(0.25), lineWidth: 1))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(changing != nil)
    }

    // MARK: - Pieces

    private func header(title: String, subtitle: String?, back: Bool) -> some View {
        HStack(alignment: .center, spacing: 6) {
            if back {
                Button { withAnimation(.minorMenu) { page = .members } } label: {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 18, weight: .semibold))
                        .frame(width: 36, height: 44)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("People on the Map")
            }
            EditorSheetHeader(title: title, subtitle: subtitle, closeButton: true) { dismiss() }
        }
        .padding(.leading, back ? 6 : 16)
        .padding(.trailing, 16)
        .padding(.top, 16)
        .padding(.bottom, 12)
    }

    private func errorText(_ text: String) -> some View {
        Text(text)
            .minorFont(14, maxScale: 1.4)
            .foregroundColor(MinorColor.dangerText)
            .fixedSize(horizontal: false, vertical: true)
            .accessibilityAddTraits(.updatesFrequently)
    }

    private func primary(_ title: String, icon: String? = nil, busy: Bool = false, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            ZStack {
                HStack(spacing: 8) {
                    if let icon { Image(systemName: icon).font(.system(size: 15, weight: .semibold)) }
                    Text(title)
                }
                .opacity(busy ? 0 : 1)
                if busy { ProgressView().tint(.black) }
            }
            .minorFont(16, .semibold, maxScale: 1.3)
            .foregroundColor(.black)
            .frame(maxWidth: .infinity, minHeight: 48)
            .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(Color.white))
        }
        .buttonStyle(PressScale())
        .disabled(busy)
    }

    private func smallButton(_ title: String, icon: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Label(title, systemImage: icon)
                .minorFont(14, .medium, maxScale: 1.3)
                .frame(maxWidth: .infinity, minHeight: 44)
                .background(RoundedRectangle(cornerRadius: 11).fill(Color.white.opacity(0.08)))
        }
        .buttonStyle(.plain)
    }

    private var statusText: String {
        guard let info else { return L("Only you") }
        if collab.failed.contains(mapID) { return L("Couldn’t sync. It will try again.") }
        let you: String
        switch info.role {
        case .owner: you = L("You own this map")
        case .editor: you = L("You can edit")
        case .viewer: you = L("You can view")
        }
        return "\(you) · " + (collab.busy.contains(mapID) ? L("Syncing…") : L("Up to date"))
    }

    private func displayName(_ member: CollabService.Member) -> String {
        member.email ?? L("Hidden email")
    }

    private func roleName(_ role: CollabRole) -> String {
        switch role {
        case .owner: return L("Owner (map role)")
        case .editor: return L("Editor")
        case .viewer: return L("Viewer")
        }
    }

    private func color(for id: String) -> Color {
        // Stable across launches (hashValue isn't).
        let colors = BranchColor.allCases
        let sum = id.unicodeScalars.reduce(0) { ($0 &* 31 &+ Int($1.value)) & 0xFFFF }
        return colors[sum % colors.count].color
    }

    // MARK: - Actions

    private func loadMembers() async {
        #if DEBUG
        if let demo = Self.demoMembers { members = demo; return }
        #endif
        guard info != nil else { return }
        loadingMembers = true
        defer { loadingMembers = false }
        do {
            members = try await collab.members(mapID)
            membersFailed = false
        } catch {
            membersFailed = true
        }
    }

    // A link is a real invite on the server; sending it is a separate step the person takes.
    private func createLink() {
        guard auth.isSignedIn else {
            inviteAfterSignIn = true
            showSignIn = true
            return
        }
        guard !creating else { return }
        creating = true
        error = nil
        copied = false
        Task {
            defer { creating = false }
            do {
                let url = try await collab.inviteLink(for: mapID, role: inviteRole)
                Telemetry.log("collab_invite", ["role": inviteRole == .viewer ? "viewer" : "editor"])
                link = url
                linksOff = false
                Haptics.success()
                send(url)
                await loadMembers()
            } catch {
                self.error = (error as? LocalizedError)?.errorDescription ?? L("Couldn’t create the link. Check your connection and try again.")
            }
        }
    }

    private func send(_ url: URL) {
        let title = map?.title ?? ""
        let text = inviteRole == .viewer
            ? L("Take a look at “\(title)” in Minor AI:")
            : L("Let’s work on “\(title)” together in Minor AI:")
        SystemShare.present(text: text, url: url, subject: title)
    }

    // "Copied" only once the link is on the clipboard.
    private func copy(_ url: URL) {
        UIPasteboard.general.url = url
        guard UIPasteboard.general.hasURLs || UIPasteboard.general.hasStrings else { return }
        Haptics.success()
        withAnimation(.minorMenu) { copied = true }
        Task {
            try? await Task.sleep(nanoseconds: 2_000_000_000)
            withAnimation(.minorMenu) { copied = false }
        }
    }

    // The server decides; on failure the list shows what is really in place.
    private func setRole(_ role: CollabRole, for member: CollabService.Member) {
        guard role != member.collabRole else { return }
        changing = member.user_id
        error = nil
        Task {
            defer { changing = nil }
            do {
                try await collab.setRole(role, for: member.user_id, in: mapID)
                Haptics.selection()
            } catch {
                self.error = (error as? LocalizedError)?.errorDescription ?? L("Couldn’t change the role. Try again.")
            }
            await loadMembers()
        }
    }

    private func remove(_ member: CollabService.Member) {
        changing = member.user_id
        error = nil
        Task {
            defer { changing = nil }
            do {
                try await collab.remove(member.user_id, from: mapID)
                linksOff = true
                Haptics.success()
            } catch {
                self.error = (error as? LocalizedError)?.errorDescription ?? L("Couldn’t remove them. Try again.")
            }
            await loadMembers()
        }
    }

    private func revoke() {
        error = nil
        Task {
            do {
                try await collab.revokeInvites(mapID)
                link = nil
                withAnimation(.minorMenu) { linksOff = true }
                Haptics.success()
            } catch {
                self.error = (error as? LocalizedError)?.errorDescription ?? L("Couldn’t turn off the links. Try again.")
            }
        }
    }

    private func end() {
        error = nil
        changing = "end"
        Task {
            defer { changing = nil }
            do {
                if isOwner { try await collab.stopSharing(mapID) } else { try await collab.leave(mapID) }
                Haptics.success()
                members = []
                dismiss()
            } catch {
                self.error = (error as? LocalizedError)?.errorDescription ?? L("Couldn’t do that. Try again.")
            }
        }
    }

    #if DEBUG
    // -demoMembers: the people list without a server, for screenshots.
    static var demoMembers: [CollabService.Member]? {
        guard ProcessInfo.processInfo.arguments.contains("-demoMembers") else { return nil }
        let me = AuthService.shared.session?.userID ?? "me"
        return [
            .init(user_id: me, email: "you@example.com", role: "owner", member_limit: 5),
            .init(user_id: "anna", email: "anna@example.com", role: "editor", member_limit: 5),
            .init(user_id: "mark", email: "mark@example.com", role: "viewer", member_limit: 5),
        ]
    }
    #endif
}
