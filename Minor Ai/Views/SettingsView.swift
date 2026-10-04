//
//  SettingsView.swift
//  Minor Ai
//
//  Settings sheet (DesignSystem → screens → 12): account, subscription, themes, general,
//  log out and account deletion (required by App Store review).
//

import StoreKit
import SwiftUI

struct SettingsView: View {
    @Binding var selectedSphere: Int?
    var onUpgrade: (_ pro: Bool) -> Void
    var onDataDeleted: () -> Void

    @Environment(\.dismiss) private var dismiss
    @ObservedObject private var auth = AuthService.shared
    @ObservedObject private var account = AccountStore.shared
    @ObservedObject private var subscriptions = SubscriptionStore.shared
    @ObservedObject private var language = LanguageSettings.shared
    @State private var themesOpen = false
    @State private var showSignIn = false
    @State private var confirmDelete = false
    @State private var isDeleting = false
    @State private var notice: String?
    @State private var confirmLogOut = false
    @State private var logOutUnsynced = false
    @State private var isLoggingOut = false
    @State private var consentGiven = AIConsent.isGiven
    @State private var showConsent = false
    @State private var confirmRevoke = false
    @State private var assistantSeesMaps = Workspace.isEnabled
    @State private var taskReminders = Reminders.isEnabled
    @State private var morningBrief = Reminders.morningBrief
    @State private var tasksInCalendar = CalendarSync.isEnabled
    @State private var syncMaps = MapSync.isEnabled
    @State private var showUsage = false
    @State private var showInvite = false
    @ObservedObject private var sync = MapSync.shared
    @ObservedObject private var push = PushService.shared

    private let themes: [(id: Int, name: String, color: String)] = [
        (1, "Classic", "#121212"), (2, "Vio", "#1B1420"), (3, "Aqua", "#101317"),
        (4, "Rosa", "#171010"), (5, "Cosmos", "#0E0F17"), (6, "Flam", "#17100E"),
    ]

    var body: some View {
        VStack(spacing: 0) {
            ZStack {
                Text("Settings").font(.system(size: 20, weight: .bold))
                HStack {
                    Spacer()
                    Button { dismiss() } label: {
                        Image(systemName: "xmark")
                            .font(.system(size: 13, weight: .bold))
                            .frame(width: 30, height: 30)
                            .background(Circle().fill(MinorColor.closeFill))
                            .frame(width: 44, height: 44)
                            .contentShape(Rectangle())
                    }
                    .accessibilityLabel("Close")
                }
            }
            .padding(.top, 20)
            .padding(.bottom, 16)
            .padding(.horizontal, 20)

            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    if auth.signedOutByServer && !auth.isSignedIn {
                        Text("You were signed out. Sign in again to get your plan back on this iPhone.")
                            .font(.system(size: 13))
                            .foregroundColor(MinorColor.textSecondary)
                    }
                    group("Account") {
                        if !auth.isSignedIn {
                            row("person.crop.circle", "Sign In or Create Account") { showSignIn = true }
                        } else {
                            rowLabel("person.crop.circle", "Account", value: auth.session?.email ?? L("Hidden email"), chevron: false)
                                .overlay(alignment: .bottom) { Rectangle().fill(MinorColor.divider).frame(height: 1) }
                                .accessibilityElement(children: .combine)
                        }
                        row("star", "Subscription", value: subscriptionValue) {
                            // Our own plans screen, also for subscribers: they move between Plus and PRO
                            // there. Cancelling stays in the iPhone's App Store settings, as Apple intends.
                            onUpgrade(account.isPro)
                        }
                        row("gauge.with.dots.needle.33percent", "Limits", value: limitsValue) { showUsage = true }
                        row("gift", "Invite Friends", value: L("Get Plus")) { showInvite = true }
                        row("arrow.clockwise", "Restore Purchases", last: true) { restore() }
                    }

                    group("Premium") {
                        if !account.isPro {
                            row("star.fill", "Upgrade to PRO") { onUpgrade(true) }
                        }
                        row("paintbrush.fill", "Chat Themes", chevronRotated: themesOpen, last: !themesOpen) {
                            withAnimation(.spring(response: 0.5, dampingFraction: 0.7)) { themesOpen.toggle() }
                        }
                        if themesOpen {
                            HStack(spacing: 15) {
                                ForEach(themes, id: \.id) { theme in
                                    Button {
                                        withAnimation(.easeInOut(duration: 0.2)) { selectedSphere = theme.id }
                                    } label: {
                                        VStack(spacing: 6) {
                                            Circle()
                                                .fill(Color(hex: theme.color))
                                                .frame(width: 40, height: 40)
                                                .overlay(Circle().stroke(Color.white, lineWidth: 1).opacity((selectedSphere ?? 1) == theme.id ? 1 : 0))
                                            Text(LocalizedStringKey(theme.name)).font(.system(size: 12))
                                        }
                                    }
                                    .buttonStyle(.plain)
                                    .accessibilityLabel("\(theme.name) theme")
                                    .accessibilityAddTraits((selectedSphere ?? 1) == theme.id ? .isSelected : [])
                                }
                            }
                            .frame(maxWidth: .infinity)
                            .frame(height: 80)
                        }
                    }

                    group("General") {
                        Menu {
                            ForEach(AppLanguage.allCases) { option in
                                Button {
                                    LanguageSettings.shared.choose(option)
                                } label: {
                                    if option == language.language {
                                        Label(option.nativeName, systemImage: "checkmark")
                                    } else {
                                        Text(option.nativeName)
                                    }
                                }
                            }
                        } label: {
                            rowLabel("globe", "Language", value: language.language == .system
                                     ? "\(AppLanguage.system.nativeName) · \(language.language.resolved.nativeName)"
                                     : language.language.nativeName)
                        }
                        .overlay(alignment: .bottom) { Rectangle().fill(MinorColor.divider).frame(height: 1) }
                        row("sparkles", "AI Data Sharing", value: consentGiven ? L("Allowed") : L("Off")) {
                            if consentGiven { confirmRevoke = true } else { showConsent = true }
                        }
                        // The chat assistant gets the list of maps and reads one when asked about it.
                        toggleRow("point.3.connected.trianglepath.dotted", "Assistant Sees My Maps",
                                  detail: "Titles and progress; a map's content only when you ask about it.", isOn: $assistantSeesMaps)
                            .onChange(of: assistantSeesMaps) { Workspace.isEnabled = $0 }
                        if auth.isSignedIn {
                            toggleRow("arrow.triangle.2.circlepath", "Sync Maps", detail: LocalizedStringKey(syncStatus), isOn: $syncMaps)
                                .onChange(of: syncMaps) { MapSync.isEnabled = $0 }
                        }
                        toggleRow("bell.badge", "Task Reminders", detail: "A notification when a task with a date is due.", isOn: $taskReminders)
                            .onChange(of: taskReminders) { value in
                                Reminders.isEnabled = value
                                if value { Reminders.shared.requestPermission() }
                            }
                        toggleRow("calendar.badge.plus", "Tasks in Calendar", detail: "Tasks with a date in a “Minor AI” calendar.", isOn: $tasksInCalendar)
                            .onChange(of: tasksInCalendar) { value in
                                guard value != CalendarSync.isEnabled else { return }
                                if value {
                                    Task {
                                        let granted = await CalendarSync.shared.enable()
                                        if !granted {
                                            tasksInCalendar = false
                                            notice = L("Allow calendar access for Minor in Settings to add tasks to your calendar.")
                                        }
                                    }
                                } else {
                                    CalendarSync.shared.disable()
                                }
                            }
                        if taskReminders {
                            toggleRow("sun.max", "Morning Brief", detail: "At 8:30: today’s tasks and cards to review.", isOn: $morningBrief)
                                .onChange(of: morningBrief) { value in
                                    Reminders.morningBrief = value
                                    if value { Reminders.shared.requestPermission() }
                                }
                        }
                        if auth.isSignedIn {
                            toggleRow("person.2.badge.gearshape", "Shared Map Updates", detail: "When someone changes a map you share or joins it.", isOn: $push.collab)
                                .onChange(of: push.collab) { if $0 { push.askIfNeeded() } }
                            toggleRow("gift", "Invitations and Limits", detail: "Rewards for invited friends, and when your AI allowance runs low.", isOn: $push.account)
                                .onChange(of: push.account) { if $0 { push.askIfNeeded() } }
                        }
                        // Also for reminders when signed out: the toggles alone would look like they work.
                        if !push.allowed && (taskReminders || (auth.isSignedIn && (push.collab || push.account))) {
                                Button { UIApplication.shared.open(URL(string: UIApplication.openSettingsURLString)!) } label: {
                                    Text("Notifications are off for Minor. Turn them on in iOS Settings.")
                                        .font(.system(size: 13))
                                        .foregroundColor(MinorColor.accent)
                                        .frame(maxWidth: .infinity, alignment: .leading)
                                        .padding(.horizontal, 20)
                                        .padding(.vertical, 10)
                                }
                                .buttonStyle(.plain)
                                .overlay(alignment: .bottom) { Rectangle().fill(MinorColor.divider).frame(height: 1) }
                        }
                        row("questionmark.circle", "Help & Support") { UIApplication.shared.open(LegalLinks.support) }
                        row("doc.text", "Privacy Policy") { UIApplication.shared.open(LegalLinks.privacy) }
                        row("doc.text", "Terms of Use", last: true) { UIApplication.shared.open(LegalLinks.terms) }
                    }


                    if auth.isSignedIn {
                        group(nil) {
                            row("rectangle.portrait.and.arrow.right", "Log Out", last: true) { confirmLogOut = true }
                        }
                    }

                    if auth.isSignedIn {
                        group(nil) {
                            row("trash", "Delete Account", danger: true, last: true) { confirmDelete = true }
                        }
                    }

                    HStack {
                        Text(verbatim: "Minor AI")
                        Spacer()
                        Text("Version \(Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "1.0")")
                    }
                    .font(.system(size: 12))
                    .foregroundColor(MinorColor.textSignature)
                    .padding(.top, 4)
                    .padding(.bottom, 24)
                }
                .padding(.horizontal, 20)
            }
        }
        .foregroundColor(MinorColor.textPrimary)
        .background(MinorColor.sheet.ignoresSafeArea())
        .disabled(isDeleting || isLoggingOut)
        .overlay { if isDeleting || isLoggingOut { ProgressView().tint(.white) } }
        // Can't be swiped away mid-deletion, or its result would be shown nowhere.
        .interactiveDismissDisabled(isDeleting || isLoggingOut)
        // Results (restore, calendar access, errors) show where the person is looking.
        .alert(notice ?? "", isPresented: Binding(get: { notice != nil }, set: { if !$0 { notice = nil } })) {
            Button("OK", role: .cancel) {}
        }
        .confirmationDialog("Log out?", isPresented: $confirmLogOut, titleVisibility: .visible) {
            Button("Log Out", role: .destructive) { logOut(force: false) }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text(MapSync.isEnabled
                 ? "Your maps and presentations stay in your account and come back when you sign in. Chats are kept only on this iPhone and will be deleted."
                 : "Sync Maps is off, so your maps, presentations and chats are only on this iPhone and will be deleted. Turn on Sync Maps first to keep them in your account.")
        }
        .alert("Some changes aren’t in your account yet", isPresented: $logOutUnsynced) {
            Button("Log Out Anyway", role: .destructive) { logOut(force: true) }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Connect to the internet and try again, or log out and lose the changes that haven’t synced.")
        }
        .alert("Delete your account?", isPresented: $confirmDelete) {
            Button("Delete Account", role: .destructive) { deleteAccount() }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text(account.hasSubscription
                 ? "Your account, maps, chats and shared links will be permanently deleted. Your App Store subscription is not cancelled by this: cancel it first in the iPhone Settings → your name → Subscriptions. This can’t be undone."
                 : "Your account, maps, chats and shared links will be permanently deleted. This can’t be undone.")
        }
        .confirmationDialog("Stop sending requests to AI?", isPresented: $confirmRevoke, titleVisibility: .visible) {
            Button("Turn Off", role: .destructive) {
                AIConsent.revoke()
                consentGiven = false
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Minor will ask again before it sends anything to OpenAI or Anthropic. Maps and chats need AI to work.")
        }
        .sheet(isPresented: $showConsent) {
            AIConsentView(
                onAllow: {
                    showConsent = false
                    consentGiven = true
                },
                onDecline: { showConsent = false }
            )
        }
        .sheet(isPresented: $showSignIn) {
            SignInView(onFinish: { showSignIn = false })
        }
        .sheet(isPresented: $showUsage) {
            UsageView(onUpgrade: { pro in
                showUsage = false
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) { onUpgrade(pro) }
            })
        }
        .sheet(isPresented: $showInvite) { InviteView() }
        .task {
            await account.refresh()
            await push.registerIfAllowed()
            await account.loadReport()
        }
    }

    private var subscriptionValue: String {
        // This Apple ID pays for a subscription that belongs to another Minor account.
        if subscriptions.ownedElsewhere && auth.isSignedIn && !account.hasSubscription { return L("On another account") }
        // Paid on this iPhone, but the server (which sets the limits) didn't accept the purchase.
        if subscriptions.notConfirmed && auth.isSignedIn && account.plan == .free { return L("Not confirmed") }
        switch account.effectivePlan {
        case .pro: return L("Minor PRO")
        case .plus:
            if !account.hasSubscription, let until = account.bonusUntil { return L("Plus until \(UsageView.day(until))") }
            return L("Minor Plus")
        case .free: return L("Free")
        }
    }

    // "37% used" of this month's AI allowance, once known.
    private var limitsValue: String? {
        guard auth.isSignedIn, account.report != nil || account.spendMicros > 0 else { return nil }
        return L("\(UsageView.percent(account.allowanceUsed)) used")
    }

    // MARK: - Rows

    private func group<Content: View>(_ title: LocalizedStringKey?, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 15) {
            if let title {
                Text(title)
                    .textCase(.uppercase)
                    .font(.system(size: 14, weight: .medium))
                    .foregroundColor(MinorColor.textTertiary)
            }
            VStack(spacing: 0) { content() }
                .background(MinorColor.row)
                .clipShape(RoundedRectangle(cornerRadius: 10))
        }
    }

    private var syncStatus: String {
        guard syncMaps else { return L("Maps stay on this iPhone only.") }
        if !sync.rejectedTitles.isEmpty {
            return L("Too large to sync: \(sync.rejectedTitles.prefix(3).map { "“\($0)”" }.joined(separator: ", ")). Split it into smaller maps.")
        }
        if sync.isSyncing { return L("Syncing…") }
        if sync.failed { return L("Couldn’t sync. It will try again.") }
        if let date = sync.lastSynced {
            return L("Your maps on all your devices. Synced \(date.formatted(.relative(presentation: .named).locale(AppLanguage.current.locale))).")
        }
        return L("Your maps on all your devices with this account.")
    }

    private func toggleRow(_ icon: String, _ title: LocalizedStringKey, detail: LocalizedStringKey, isOn: Binding<Bool>) -> some View {
        Toggle(isOn: isOn) {
            HStack(spacing: 10) {
                Image(systemName: icon).font(.system(size: 17)).frame(width: 24).accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 2) {
                    Text(title).font(.system(size: 17)).lineLimit(1)
                    Text(detail)
                        .font(.system(size: 12))
                        .foregroundColor(MinorColor.textTertiary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
        .tint(MinorColor.accent)
        .foregroundColor(MinorColor.textPrimary)
        .padding(.horizontal, 20)
        .padding(.vertical, 8)
        .frame(minHeight: 50)
        .overlay(alignment: .bottom) { Rectangle().fill(MinorColor.divider).frame(height: 1) }
    }

    private func row(
        _ icon: String, _ title: LocalizedStringKey, value: String? = nil, chevron: Bool = true,
        chevronRotated: Bool = false, danger: Bool = false, last: Bool = false, action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            rowLabel(icon, title, value: value, chevron: chevron, chevronRotated: chevronRotated, danger: danger)
        }
        .buttonStyle(.plain)
        .overlay(alignment: .bottom) {
            if !last { Rectangle().fill(MinorColor.divider).frame(height: 1) }
        }
    }

    private func rowLabel(
        _ icon: String, _ title: LocalizedStringKey, value: String? = nil, chevron: Bool = true,
        chevronRotated: Bool = false, danger: Bool = false
    ) -> some View {
        HStack(spacing: 10) {
            Image(systemName: icon).font(.system(size: 17)).frame(width: 24).accessibilityHidden(true)
            Text(title).font(.system(size: 17)).lineLimit(1)
            Spacer(minLength: 8)
            if let value {
                Text(value)
                    .font(.system(size: 15))
                    .foregroundColor(MinorColor.textChevron)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
            if chevron {
                Image(systemName: "chevron.right")
                    .font(.system(size: 15))
                    .foregroundColor(MinorColor.textChevron)
                    .rotationEffect(.degrees(chevronRotated ? 90 : 0))
                    .accessibilityHidden(true)
            }
        }
        .foregroundColor(danger ? MinorColor.dangerText : MinorColor.textPrimary)
        .padding(.horizontal, 20)
        .frame(minHeight: 50)
        .contentShape(Rectangle())
    }

    // MARK: - Actions

    private func restore() {
        Task {
            do {
                notice = try await subscriptions.restore()
                    ? L("Purchases restored.")
                    : L("No active subscription was found for this Apple ID.")
            } catch let error as SubscriptionStore.StoreError {
                notice = error.errorDescription
            } catch StoreKitError.userCancelled {
                // The person closed the Apple ID prompt: nothing to report.
            } catch {
                notice = L("Couldn’t restore purchases. Try again.")
            }
        }
    }

    // Logging out leaves nothing of the account on this iPhone (the next account would otherwise
    // see these maps and upload them to itself). With sync on, everything is sent first.
    private func logOut(force: Bool) {
        isLoggingOut = true
        Task {
            if !force, !(await MapSync.shared.syncAndWait()) {
                isLoggingOut = false
                logOutUnsynced = true
                return
            }
            GenerationCenter.shared.cancelAll()
            MapStore.shared.deleteAll()
            DeckStore.shared.deleteAll()
            StudyStore.shared.forgetAll()
            CollabService.shared.forgetAll()
            CalendarSync.shared.disable()
            ConversationStore.shared.deleteBackups()
            onDataDeleted()
            auth.signOut()
            await account.refresh()
            isLoggingOut = false
        }
    }

    private func deleteAccount() {
        isDeleting = true
        Task {
            do {
                try await auth.deleteAccount()
                GenerationCenter.shared.cancelAll()
                MapStore.shared.deleteAll()
                DeckStore.shared.deleteAll()
                StudyStore.shared.forgetAll()
                CollabService.shared.forgetAll()
                CalendarSync.shared.disable()
                ConversationStore.shared.deleteBackups()
                AIConsent.revoke()
                onDataDeleted()
                await account.refresh()
                isDeleting = false
                dismiss()
            } catch {
                isDeleting = false
                notice = (error as? LocalizedError)?.errorDescription ?? L("Couldn’t delete your account. Try again.")
            }
        }
    }
}
