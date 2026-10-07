//
//  CollabSheet.swift
//  Minor Ai
//
//  Edit Together: invite people with a link as editors or viewers, see who is on the map,
//  change their roles or remove them (owner), stop sharing or leave.
//

import SwiftUI

struct CollabSheet: View {
    let mapID: UUID
    let theme: AppTheme
    var onUpgrade: () -> Void

    @Environment(\.dismiss) private var dismiss
    @ObservedObject private var store = MapStore.shared
    @ObservedObject private var collab = CollabService.shared
    @ObservedObject private var account = AccountStore.shared
    @State private var working = false
    @State private var error: String?
    @State private var shareItems: [Any]?
    @State private var members: [CollabService.Member] = []
    @State private var inviteRole: CollabRole = .editor
    @State private var confirmEnd = false
    @State private var confirmRevoke = false
    @State private var pendingRemove: CollabService.Member?

    private var map: MindMap? { store.map(mapID) }
    private var info: CollabInfo? { map?.collab }
    private var isOwner: Bool { info?.isOwner == true }
    private var limit: Int { members.first?.member_limit ?? (account.plan == .pro ? 25 : account.plan == .plus ? 5 : 0) }
    private var others: Int { max(members.count - 1, 0) }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    header
                    if info == nil {
                        notShared
                    } else if isOwner {
                        inviteSection
                        membersSection
                        secondary(L("Stop Sharing"), icon: "person.crop.circle.badge.xmark") { confirmEnd = true }
                    } else {
                        membersSection
                        secondary(L("Leave This Map"), icon: "rectangle.portrait.and.arrow.right") { confirmEnd = true }
                    }
                    if let error {
                        Text(error).font(.system(size: 14)).foregroundColor(MinorColor.dangerText)
                    }
                }
                .padding(20)
            }
            .foregroundColor(MinorColor.textPrimary)
            .background(theme.background.ignoresSafeArea())
            .navigationTitle("Edit Together")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }.foregroundColor(MinorColor.accent)
                }
            }
            .overlay { if working { ProgressView().tint(.white) } }
            .sheet(isPresented: Binding(get: { shareItems != nil }, set: { if !$0 { shareItems = nil } })) {
                ShareSheet(items: shareItems ?? [])
            }
            .confirmationDialog(isOwner ? L("Stop sharing? Others keep their own copy, but your changes won’t reach them.") : L("Leave this map? You keep your own copy."),
                                isPresented: $confirmEnd, titleVisibility: .visible) {
                Button(isOwner ? L("Stop Sharing") : L("Leave"), role: .destructive) { end() }
                Button("Cancel", role: .cancel) {}
            }
            .confirmationDialog(L("Turn off all invite links? People already on the map stay."), isPresented: $confirmRevoke, titleVisibility: .visible) {
                Button(L("Turn Off Links"), role: .destructive) { revoke() }
                Button("Cancel", role: .cancel) {}
            }
            .confirmationDialog(pendingRemove.map { L("Remove \($0.email ?? L("this person")) from the map? They keep their own copy. Invite links are turned off; send a new one to invite others.") } ?? "",
                                isPresented: Binding(get: { pendingRemove != nil }, set: { if !$0 { pendingRemove = nil } }),
                                titleVisibility: .visible, presenting: pendingRemove) { member in
                Button(L("Remove"), role: .destructive) { remove(member) }
                Button("Cancel", role: .cancel) {}
            }
        }
        .preferredColorScheme(.dark)
        .task { await loadMembers() }
    }

    // MARK: - Parts

    private var header: some View {
        HStack(spacing: 14) {
            Image(systemName: "person.2.fill")
                .font(.system(size: 22))
                .foregroundColor(.black)
                .frame(width: 52, height: 52)
                .background(Circle().fill(MinorColor.accent))
            VStack(alignment: .leading, spacing: 3) {
                Text(map?.title ?? "").font(.system(size: 17, weight: .semibold)).lineLimit(1)
                Text(statusText).font(.system(size: 14)).foregroundColor(MinorColor.textSecondary)
            }
        }
    }

    private var notShared: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Invite people with a link. Editors change the map with you, viewers only see it. Changes show up for everyone within seconds.")
                .font(.system(size: 15))
                .foregroundColor(MinorColor.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
            if account.isPaid {
                rolePicker
                primary(L("Create Invite Link"), icon: "link.badge.plus") { invite() }
            } else {
                planCard
            }
        }
    }

    private var planCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label("Part of Minor Plus and PRO", systemImage: "star.fill")
                .font(.system(size: 15, weight: .semibold))
            Text("Plus: up to 5 people on each map. PRO: up to 25. The people you invite don’t need a subscription.")
                .font(.system(size: 14))
                .foregroundColor(MinorColor.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
            primary(L("Get Minor Plus"), icon: "star.fill") {
                dismiss()
                onUpgrade()
            }
        }
        .padding(16)
        .background(RoundedRectangle(cornerRadius: 16).fill(theme.chatRectangle))
        .overlay(RoundedRectangle(cornerRadius: 16).stroke(theme.chatStroke, lineWidth: 1))
    }

    private var rolePicker: some View {
        VStack(alignment: .leading, spacing: 8) {
            Picker("Invite as", selection: $inviteRole) {
                Text("Editor").tag(CollabRole.editor)
                Text("Viewer").tag(CollabRole.viewer)
            }
            .pickerStyle(.segmented)
            Text(inviteRole == .viewer ? "Viewers see the map and its changes but can’t edit it." : "Editors add, change and move ideas, like you.")
                .font(.system(size: 13))
                .foregroundColor(MinorColor.textTertiary)
        }
    }

    private var inviteSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            sectionTitle(L("Invite"))
            rolePicker
            if limit == 0 {
                Text("Your plan has ended, so new people can’t join. Everyone already on the map stays.")
                    .font(.system(size: 14))
                    .foregroundColor(MinorColor.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
                primary(L("Get Minor Plus"), icon: "star.fill") {
                    dismiss()
                    onUpgrade()
                }
            } else {
                primary(L("Send Invite Link"), icon: "square.and.arrow.up") { invite() }
                    .disabled(others >= limit)
                    .opacity(others >= limit ? 0.5 : 1)
                HStack {
                    Text(L("People: \(others) of \(limit)"))
                        .font(.system(size: 13))
                        .foregroundColor(others >= limit ? MinorColor.dangerText : MinorColor.textTertiary)
                    Spacer()
                    Button("Turn Off Links") { confirmRevoke = true }
                        .font(.system(size: 13, weight: .medium))
                        .foregroundColor(MinorColor.textSecondary)
                }
            }
        }
    }

    private var membersSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            sectionTitle(L("People"))
            if members.isEmpty {
                Text(working ? L("Loading…") : L("Only you so far."))
                    .font(.system(size: 14))
                    .foregroundColor(MinorColor.textTertiary)
            }
            ForEach(members) { member in
                memberRow(member)
            }
        }
    }

    private func memberRow(_ member: CollabService.Member) -> some View {
        let isMe = member.user_id == AuthService.shared.session?.userID
        let name = member.email ?? L("Hidden email")
        return HStack(spacing: 12) {
            Text(String(name.prefix(1)).uppercased())
                .font(.system(size: 15, weight: .bold))
                .foregroundColor(.black)
                .frame(width: 36, height: 36)
                .background(Circle().fill(color(for: member.user_id)))
            VStack(alignment: .leading, spacing: 2) {
                Text(isMe ? L("\(name) (you)") : name)
                    .font(.system(size: 15))
                    .lineLimit(1)
                    .truncationMode(.middle)
                Text(roleName(member.collabRole))
                    .font(.system(size: 12))
                    .foregroundColor(MinorColor.textTertiary)
            }
            Spacer(minLength: 8)
            if isOwner && member.collabRole != .owner {
                Menu {
                    Picker("Role", selection: Binding(get: { member.collabRole }, set: { setRole($0, for: member) })) {
                        Label("Editor", systemImage: "pencil").tag(CollabRole.editor)
                        Label("Viewer", systemImage: "eye").tag(CollabRole.viewer)
                    }
                    Button(role: .destructive) { pendingRemove = member } label: { Label("Remove", systemImage: "person.badge.minus") }
                } label: {
                    HStack(spacing: 4) {
                        Text(roleName(member.collabRole))
                        Image(systemName: "chevron.up.chevron.down").font(.system(size: 10, weight: .semibold))
                    }
                    .font(.system(size: 13, weight: .medium))
                    .padding(.horizontal, 10)
                    .frame(height: 30)
                    .overlay(Capsule().stroke(theme.chatStroke, lineWidth: 1))
                }
                .accessibilityLabel(L("Role of \(name)"))
            }
        }
        .padding(.vertical, 4)
    }

    private func sectionTitle(_ text: String) -> some View {
        Text(text.uppercased())
            .font(.system(size: 12, weight: .semibold))
            .foregroundColor(MinorColor.textTertiary)
    }

    private var statusText: String {
        guard let info else { return L("Only you") }
        if collab.failed.contains(mapID) { return L("Couldn’t sync. It will try again.") }
        let people: String
        switch info.role {
        case .owner: people = L("You and \(others) others")
        case .editor: people = L("You can edit")
        case .viewer: people = L("You can view")
        }
        return "\(people) · " + (collab.busy.contains(mapID) ? L("Syncing…") : L("Up to date"))
    }

    private func roleName(_ role: CollabRole) -> String {
        switch role {
        case .owner: return L("Owner")
        case .editor: return L("Editor")
        case .viewer: return L("Viewer")
        }
    }

    private func color(for id: String) -> Color {
        let colors = BranchColor.allCases
        return colors[abs(id.hashValue) % colors.count].color
    }

    // MARK: - Actions

    private func loadMembers() async {
        guard info != nil else { return }
        if let list = try? await collab.members(mapID) { members = list }
    }

    private func invite() {
        guard AuthService.shared.isSignedIn else { return AuthGate.shared.require(invite) }
        run {
            let link = try await collab.inviteLink(for: mapID, role: inviteRole)
            Telemetry.log("collab_invite", ["role": inviteRole == .viewer ? "viewer" : "editor"])
            let title = map?.title ?? ""
            shareItems = [inviteRole == .viewer
                          ? L("Take a look at “\(title)” in Minor AI: \(link.absoluteString)")
                          : L("Let’s work on “\(title)” together in Minor AI: \(link.absoluteString)")]
            await loadMembers()
        }
    }

    private func setRole(_ role: CollabRole, for member: CollabService.Member) {
        guard role != member.collabRole else { return }
        run {
            try await collab.setRole(role, for: member.user_id, in: mapID)
            Haptics.selection()
            await loadMembers()
        }
    }

    private func remove(_ member: CollabService.Member) {
        run {
            try await collab.remove(member.user_id, from: mapID)
            await loadMembers()
        }
    }

    private func revoke() {
        run {
            try await collab.revokeInvites(mapID)
            Haptics.success()
        }
    }

    private func end() {
        run {
            if isOwner { try await collab.stopSharing(mapID) } else { try await collab.leave(mapID) }
            Haptics.success()
            members = []
        }
    }

    private func run(_ work: @escaping () async throws -> Void) {
        working = true
        error = nil
        Task {
            defer { working = false }
            do {
                try await work()
            } catch {
                self.error = (error as? LocalizedError)?.errorDescription ?? L("Couldn’t do that. Try again.")
            }
        }
    }

    private func primary(_ title: String, icon: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Label(title, systemImage: icon)
                .font(.system(size: 16, weight: .semibold))
                .foregroundColor(.black)
                .frame(maxWidth: .infinity)
                .frame(height: 50)
                .background(Capsule().fill(MinorColor.accent))
        }
        .buttonStyle(.plain)
        .disabled(working)
    }

    private func secondary(_ title: String, icon: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Label(title, systemImage: icon)
                .font(.system(size: 16, weight: .medium))
                .foregroundColor(MinorColor.dangerText)
                .frame(maxWidth: .infinity)
                .frame(height: 50)
                .overlay(Capsule().stroke(theme.chatStroke, lineWidth: 1))
        }
        .buttonStyle(.plain)
        .disabled(working)
    }
}
