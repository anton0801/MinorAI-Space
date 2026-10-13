//
//  SettingsView.swift
//  Minor Ai
//
//  Settings: a short list of sections (account and subscription, AI usage, appearance, language,
//  notifications, data and AI, help), each with its own page. Restore Purchases, managing the
//  subscription, logging out and account deletion (required by App Store review) live on the
//  account page; they are there for guests too where it makes sense.
//

import StoreKit
import SwiftUI

struct SettingsView: View {
    @Binding var selectedSphere: Int?
    var onUpgrade: (_ pro: Bool) -> Void
    var onDataDeleted: () -> Void

    enum Page: Hashable { case account, dataAI, appearance, language, notifications }

    @Environment(\.dismiss) private var dismiss
    @ObservedObject private var auth = AuthService.shared
    @ObservedObject private var account = AccountStore.shared
    @ObservedObject private var subscriptions = SubscriptionStore.shared
    @ObservedObject private var language = LanguageSettings.shared
    @State private var path: [Page] = []
    @State private var showSignIn = false
    @State private var confirmDelete = false
    @State private var isDeleting = false
    @State private var notice: String?
    @State private var confirmLogOut = false
    @State private var logOutUnsynced = false
    @State private var isLoggingOut = false
    @State private var isRestoring = false
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
    @ObservedObject private var network = NetworkMonitor.shared

    private let themes: [(id: Int, name: String, color: String)] = [
        (1, "Classic", "#121212"), (2, "Vio", "#1B1420"), (3, "Aqua", "#101317"),
        (4, "Rosa", "#171010"), (5, "Cosmos", "#0E0F17"), (6, "Flam", "#17100E"),
    ]

    private var theme: AppTheme { AppTheme(sphere: selectedSphere) }

    var body: some View {
        NavigationStack(path: $path) {
            main
                .navigationTitle(Text("Settings"))
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .navigationBarTrailing) {
                        Button { dismiss() } label: {
                            Image(systemName: "xmark")
                                .font(.system(size: 13, weight: .bold))
                                .foregroundColor(.white)
                                .frame(width: 30, height: 30)
                                .background(Circle().fill(MinorColor.closeFill))
                                .frame(width: 44, height: 44)
                                .contentShape(Rectangle())
                        }
                        .accessibilityLabel("Close")
                    }
                }
                .navigationDestination(for: Page.self) { page in
                    Group {
                        switch page {
                        case .account: accountPage
                        case .dataAI: dataPage
                        case .appearance: appearancePage
                        case .language: languagePage
                        case .notifications: notificationsPage
                        }
                    }
                    .navigationBarTitleDisplayMode(.large)
                    // Back names where it goes, as in the design.
                    .navigationBarBackButtonHidden(true)
                    .toolbar {
                        ToolbarItem(placement: .navigationBarLeading) {
                            Button { if !path.isEmpty { path.removeLast() } } label: {
                                HStack(spacing: 4) {
                                    Image(systemName: "chevron.left").font(.system(size: 17, weight: .semibold))
                                    Text("Settings").font(.system(size: 17))
                                }
                                .foregroundColor(.white)
                            }
                            .accessibilityLabel("Back to Settings")
                        }
                    }
                }
                .toolbarBackground(theme.background, for: .navigationBar)
                .toolbarColorScheme(.dark, for: .navigationBar)
        }
        .tint(.white)
        .foregroundColor(MinorColor.textPrimary)
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
        #if DEBUG
        .onAppear {
            // -settingsPage account|data|appearance|language|notifications, for screenshots.
            let args = ProcessInfo.processInfo.arguments
            if let i = args.firstIndex(of: "-settingsPage"), i + 1 < args.count {
                let pages: [String: Page] = ["account": .account, "data": .dataAI, "appearance": .appearance, "language": .language, "notifications": .notifications]
                if let page = pages[args[i + 1]] { path = [page] }
            }
        }
        #endif
    }

    // MARK: - Main page

    private var main: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                if auth.signedOutByServer && !auth.isSignedIn {
                    Text("You were signed out. Sign in again to get your plan back on this iPhone.")
                        .minorFont(13, style: .footnote, maxScale: 1.4)
                        .foregroundColor(MinorColor.textSecondary)
                }
                card {
                    navRow(.account, icon: "person.crop.circle", "Account and Subscription", subtitle: accountSubtitle, last: true)
                }
                if auth.isSignedIn { usageCard }

                section("App") {
                    navRow(.appearance, icon: "sun.max", "Appearance", value: themeName)
                    navRow(.language, icon: "globe", "Language", value: language.language.resolved.nativeName)
                    navRow(.notifications, icon: "bell", "Notifications", last: true)
                }
                section("Data") {
                    navRow(.dataAI, icon: "point.3.connected.trianglepath.dotted", "Data and AI", subtitle: L("Assistant access and sync"), last: true)
                }
                section("Help") {
                    actionRow("questionmark.circle", "Support") { UIApplication.shared.open(LegalLinks.support) }
                    actionRow("person.2", "Invite Friends", subtitle: L("Get Plus"), last: true) { showInvite = true }
                }

                VStack(spacing: 10) {
                    HStack(spacing: 14) {
                        Button("Privacy") { UIApplication.shared.open(LegalLinks.privacy) }
                        Rectangle().fill(MinorColor.textTertiary.opacity(0.5)).frame(width: 1, height: 12).accessibilityHidden(true)
                        Button("Terms of Use") { UIApplication.shared.open(LegalLinks.terms) }
                    }
                    .minorFont(12, style: .caption1, maxScale: 1.4)
                    .foregroundColor(MinorColor.textSecondary)
                    Text(L("Minor AI · Version \(Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "1.0")"))
                        .minorFont(12, style: .caption1, maxScale: 1.4)
                        .foregroundColor(MinorColor.textTertiary)
                }
                .frame(maxWidth: .infinity)
                .padding(.top, 4)
                .padding(.bottom, 24)
            }
            .padding(.horizontal, 20)
            .padding(.top, 8)
        }
        .background(theme.background.ignoresSafeArea())
    }

    // "Sign in with Apple · Free"; for a guest, what signing in gives.
    private var accountSubtitle: String {
        guard auth.isSignedIn else { return L("Sign in to keep your maps and plan") }
        let method = auth.provider == .apple ? L("Signed in with Apple") : L("Signed in with email")
        return "\(method) · \(subscriptionValue)"
    }

    private var themeName: String {
        L(String.LocalizationValue(themes.first { $0.id == (selectedSphere ?? 1) }?.name ?? "Classic"))
    }

    // This month's AI allowance: a real share once the server answered, "checking" until then.
    private var usageCard: some View {
        Button { showUsage = true } label: {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Text("AI Usage").minorFont(16, .medium, maxScale: 1.4)
                    Spacer()
                    Text(limitsValue ?? L("Checking the limit"))
                        .minorFont(15, .semibold, maxScale: 1.4)
                        .monospacedDigit()
                        .foregroundColor(limitsValue == nil ? MinorColor.textSecondary : .white)
                }
                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        Capsule().fill(Color.white.opacity(0.12))
                        Capsule()
                            .fill(MinorColor.accent)
                            .frame(width: limitsValue == nil ? 0 : max(6, geo.size.width * CGFloat(account.allowanceUsed)))
                    }
                }
                .frame(height: 6)
                HStack {
                    Text("Limit Details").minorFont(13, style: .footnote, maxScale: 1.4).foregroundColor(MinorColor.textSecondary)
                    Spacer()
                    Image(systemName: "chevron.right").font(.system(size: 12, weight: .semibold)).foregroundColor(MinorColor.textTertiary)
                }
            }
            .padding(16)
            .background(RoundedRectangle(cornerRadius: 14).fill(theme.chatRectangle))
            .overlay(RoundedRectangle(cornerRadius: 14).stroke(theme.chatStroke, lineWidth: 1))
            .contentShape(Rectangle())
        }
        .buttonStyle(PressScale())
        .accessibilityElement(children: .combine)
    }

    // MARK: - Account and subscription

    private var accountPage: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                if auth.isSignedIn {
                    card {
                        HStack(spacing: 14) {
                            avatar
                            VStack(alignment: .leading, spacing: 3) {
                                Text(auth.provider == .apple ? "Signed in with Apple" : "Signed in with email")
                                    .minorFont(17, .semibold, maxScale: 1.4)
                                // The full address wraps instead of being cut; it can be copied.
                                Text(auth.session?.email ?? L("Hidden email"))
                                    .minorFont(14, maxScale: 1.4)
                                    .foregroundColor(MinorColor.textSecondary)
                                    .fixedSize(horizontal: false, vertical: true)
                                    .textSelection(.enabled)
                            }
                            Spacer(minLength: 0)
                        }
                        .padding(14)
                    }
                } else {
                    card {
                        Button { showSignIn = true } label: {
                            HStack(spacing: 14) {
                                avatar
                                VStack(alignment: .leading, spacing: 3) {
                                    Text("Sign In or Create Account")
                                        .minorFont(16, .semibold, maxScale: 1.4)
                                    Text("Your maps and plan on all your devices")
                                        .minorFont(13, maxScale: 1.4)
                                        .foregroundColor(MinorColor.textSecondary)
                                        .fixedSize(horizontal: false, vertical: true)
                                }
                                Spacer(minLength: 0)
                                Image(systemName: "chevron.right")
                                    .font(.system(size: 15, weight: .semibold))
                                    .foregroundColor(MinorColor.textTertiary)
                            }
                            .padding(14)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .accessibilityElement(children: .combine)
                        .accessibilityAddTraits(.isButton)
                    }
                }

                planCard

                card {
                    if auth.isSignedIn {
                        actionRow("gauge.with.dots.needle.33percent", "AI Limits", value: limitsValue) { showUsage = true }
                    }
                    actionRow("creditcard", "Manage Subscription", subtitle: L("App Store subscriptions")) { manageSubscription() }
                    actionRow("arrow.clockwise", "Restore Purchases", value: isRestoring ? L("Checking…") : nil, last: true) { restore() }
                }
                Text("Bought Minor Plus before? Restore it here.")
                    .minorFont(13, style: .footnote, maxScale: 1.4)
                    .foregroundColor(MinorColor.textTertiary)
                    .padding(.top, -14)
                    .padding(.horizontal, 4)

                if auth.isSignedIn {
                    card {
                        actionRow("rectangle.portrait.and.arrow.right", "Log Out") { confirmLogOut = true }
                        actionRow("trash", "Delete Account", danger: true, last: true) { confirmDelete = true }
                    }
                }
            }
            .padding(.horizontal, 20)
            .padding(.top, 8)
            .padding(.bottom, 24)
        }
        .background(theme.background.ignoresSafeArea())
        .navigationTitle(Text("Account and Subscription"))
    }

    private var avatar: some View {
        Image(systemName: "person")
            .font(.system(size: 24, weight: .light))
            .foregroundColor(.white)
            .frame(width: 56, height: 56)
            .background(Circle().fill(Color.white.opacity(0.08)))
            .accessibilityHidden(true)
    }

    // The plan as the server confirms it; one way to change it.
    private var planCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Current Plan")
                .textCase(.uppercase)
                .minorFont(13, .semibold, style: .footnote, maxScale: 1.3)
                .foregroundColor(MinorColor.textTertiary)
            VStack(alignment: .leading, spacing: 0) {
                HStack(spacing: 14) {
                    Circle().fill(MinorColor.accent).frame(width: 11, height: 11)
                    Text(subscriptionValue).minorFont(20, .bold, maxScale: 1.3)
                }
                Text(planDetail)
                    .minorFont(14, maxScale: 1.4)
                    .foregroundColor(MinorColor.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.leading, 25)
                    .padding(.top, 6)
                Button { onUpgrade(account.isPro || account.effectivePlan == .plus) } label: {
                    Text(account.effectivePlan == .free ? "Choose a Plan" : "Change Plan")
                        .minorFont(16, .semibold, maxScale: 1.3)
                        .foregroundColor(.black)
                        .frame(maxWidth: .infinity, minHeight: 44)
                        .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(Color.white))
                }
                .buttonStyle(PressScale())
                .padding(.top, 16)
            }
            .padding(16)
            .background(RoundedRectangle(cornerRadius: 14).fill(theme.chatRectangle))
            .overlay(RoundedRectangle(cornerRadius: 14).stroke(theme.chatStroke, lineWidth: 1))
        }
    }

    private var planDetail: String {
        switch account.effectivePlan {
        case .free: return L("The essentials of Minor, with a small monthly AI allowance.")
        case .plus:
            if !account.hasSubscription, let until = account.bonusUntil { return L("Free days from invitations, until \(UsageView.day(until)).") }
            return L("300 maps a month, stronger models, YouTube and voice.")
        case .pro: return L("The strongest models and the largest allowance.")
        }
    }

    // MARK: - Data and AI

    private var dataPage: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                Text("You decide what Minor can use.")
                    .minorFont(15, maxScale: 1.4)
                    .foregroundColor(MinorColor.textSecondary)
                    .padding(.top, -10)
                section("Assistant") {
                    // The chat assistant gets the list of maps and reads one when asked about it.
                    toggleRow("map", "Map Access",
                              detail: "Sees titles and progress. Reads a map when you ask about it.", isOn: $assistantSeesMaps)
                        .onChange(of: assistantSeesMaps) { Workspace.isEnabled = $0 }
                    actionRow("sparkles", "AI Data Sharing", subtitle: L("To process your requests with AI."), value: consentGiven ? L("Allowed") : L("Off"), last: true) {
                        if consentGiven { confirmRevoke = true } else { showConsent = true }
                    }
                }
                section("Sync") {
                    if auth.isSignedIn {
                        toggleRow("icloud", "Sync Maps", detail: "Maps and presentations on all your devices with this account.", isOn: $syncMaps)
                            .onChange(of: syncMaps) { MapSync.isEnabled = $0 }
                        syncStatusRow
                    } else {
                        actionRow("icloud", "Sync Maps", subtitle: L("Sign in to keep maps and presentations on all your devices."), last: true) { showSignIn = true }
                    }
                }
                section("Documents") {
                    actionRow("lock", "Privacy") { UIApplication.shared.open(LegalLinks.privacy) }
                    actionRow("doc.text", "Terms of Use", last: true) { UIApplication.shared.open(LegalLinks.terms) }
                }
                Text("Chats stay on this iPhone; they are not synced.")
                    .minorFont(13, style: .footnote, maxScale: 1.4)
                    .foregroundColor(MinorColor.textTertiary)
            }
            .padding(.horizontal, 20)
            .padding(.top, 8)
            .padding(.bottom, 24)
        }
        .background(theme.background.ignoresSafeArea())
        .navigationTitle(Text("Data and AI"))
    }

    // What sync is actually doing, from MapSync: off, waiting for the network, syncing, failed, done.
    private var syncStatusRow: some View {
        let state: (icon: String, color: Color, text: String) = {
            guard syncMaps else { return ("pause.circle", MinorColor.textSecondary, L("Maps stay on this iPhone only.")) }
            if !sync.rejectedTitles.isEmpty {
                return ("exclamationmark.triangle", MinorColor.dangerText, L("Too large to sync: \(sync.rejectedTitles.prefix(3).map { "“\($0)”" }.joined(separator: ", ")). Split it into smaller maps."))
            }
            if !network.isOnline { return ("wifi.slash", MinorColor.textSecondary, L("Waiting for the network.")) }
            if sync.isSyncing { return ("arrow.triangle.2.circlepath", MinorColor.textSecondary, L("Syncing…")) }
            if sync.failed { return ("exclamationmark.triangle", MinorColor.dangerText, L("Couldn’t sync. It will try again.")) }
            if let date = sync.lastSynced {
                return ("checkmark.circle.fill", MinorColor.accent, L("Everything is synced, \(date.formatted(.relative(presentation: .named).locale(AppLanguage.current.locale)))."))
            }
            return ("clock", MinorColor.textSecondary, L("Waiting for the first sync."))
        }()
        return HStack(alignment: .top, spacing: 10) {
            Image(systemName: state.icon).font(.system(size: 15)).foregroundColor(state.color).frame(width: 24)
            Text(state.text)
                .minorFont(13, style: .footnote, maxScale: 1.4)
                .foregroundColor(MinorColor.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .accessibilityElement(children: .combine)
    }

    // MARK: - Appearance

    private var appearancePage: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Text("The background and glow of the app. Maps and slides keep their own designs.")
                    .minorFont(15, maxScale: 1.4)
                    .foregroundColor(MinorColor.textSecondary)
                LazyVGrid(columns: [GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12)], spacing: 12) {
                    ForEach(themes, id: \.id) { item in
                        let chosen = (selectedSphere ?? 1) == item.id
                        Button {
                            Haptics.selection()
                            withAnimation(.easeInOut(duration: 0.2)) { selectedSphere = item.id }
                        } label: {
                            VStack(spacing: 8) {
                                ZStack(alignment: .bottom) {
                                    RoundedRectangle(cornerRadius: 14).fill(Color(hex: item.color))
                                    Rectangle()
                                        .fill(AppTheme(sphere: item.id).blur)
                                        .frame(height: 30)
                                        .blur(radius: 14)
                                        .opacity(0.6)
                                        .clipShape(RoundedRectangle(cornerRadius: 14))
                                }
                                .frame(height: 88)
                                .clipShape(RoundedRectangle(cornerRadius: 14))
                                .overlay(RoundedRectangle(cornerRadius: 14).stroke(chosen ? Color.white : Color.white.opacity(0.15), lineWidth: chosen ? 2 : 1))
                                Text(LocalizedStringKey(item.name)).minorFont(13, chosen ? .semibold : .regular, maxScale: 1.3)
                            }
                        }
                        .buttonStyle(PressScale())
                        .accessibilityLabel(Text("\(L(String.LocalizationValue(item.name))) theme"))
                        .accessibilityAddTraits(chosen ? .isSelected : [])
                    }
                }
            }
            .padding(.horizontal, 20)
            .padding(.top, 8)
            .padding(.bottom, 24)
        }
        .background(theme.background.ignoresSafeArea())
        .navigationTitle(Text("Appearance"))
    }

    // MARK: - Language

    private var languagePage: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                card {
                    ForEach(Array(AppLanguage.allCases.enumerated()), id: \.element.id) { index, option in
                        Button {
                            guard option != language.language else { return }
                            LanguageSettings.shared.choose(option)
                        } label: {
                            HStack(spacing: 12) {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(option.nativeName).minorFont(17, maxScale: 1.4)
                                    if option == .system {
                                        Text(L("Now \(AppLanguage.system.resolved.nativeName)"))
                                            .minorFont(13, style: .footnote, maxScale: 1.4)
                                            .foregroundColor(MinorColor.textSecondary)
                                    }
                                }
                                Spacer()
                                if option == language.language {
                                    Image(systemName: "checkmark").font(.system(size: 15, weight: .semibold)).foregroundColor(MinorColor.accent)
                                }
                            }
                            .padding(.horizontal, 16)
                            .frame(minHeight: 52)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .accessibilityAddTraits(option == language.language ? .isSelected : [])
                        .overlay(alignment: .bottom) {
                            if index < AppLanguage.allCases.count - 1 { divider }
                        }
                    }
                }
                Text("The app restarts its screens in the new language.")
                    .minorFont(13, style: .footnote, maxScale: 1.4)
                    .foregroundColor(MinorColor.textTertiary)
            }
            .padding(.horizontal, 20)
            .padding(.top, 8)
            .padding(.bottom, 24)
        }
        .background(theme.background.ignoresSafeArea())
        .navigationTitle(Text("Language"))
    }

    // MARK: - Notifications

    private var notificationsPage: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                // Also for reminders when signed out: the toggles alone would look like they work.
                if !push.allowed && (taskReminders || (auth.isSignedIn && (push.collab || push.account))) {
                    Button { UIApplication.shared.open(URL(string: UIApplication.openSettingsURLString)!) } label: {
                        HStack(alignment: .top, spacing: 10) {
                            Image(systemName: "bell.slash").foregroundColor(MinorColor.dangerText)
                            Text("Notifications are off for Minor. Turn them on in iOS Settings.")
                                .minorFont(14, maxScale: 1.4)
                                .foregroundColor(MinorColor.accent)
                                .fixedSize(horizontal: false, vertical: true)
                            Spacer(minLength: 0)
                        }
                        .padding(14)
                        .background(RoundedRectangle(cornerRadius: 14).fill(theme.chatRectangle))
                        .overlay(RoundedRectangle(cornerRadius: 14).stroke(theme.chatStroke, lineWidth: 1))
                    }
                    .buttonStyle(.plain)
                }
                section("Tasks") {
                    toggleRow("bell.badge", "Task Reminders", detail: "A notification when a task with a date is due.", isOn: $taskReminders)
                        .onChange(of: taskReminders) { value in
                            Reminders.isEnabled = value
                            if value { Reminders.shared.requestPermission() }
                        }
                    if taskReminders {
                        toggleRow("sun.max", "Morning Brief", detail: "At 8:30: today’s tasks and cards to review.", isOn: $morningBrief)
                            .onChange(of: morningBrief) { value in
                                Reminders.morningBrief = value
                                if value { Reminders.shared.requestPermission() }
                            }
                    }
                    toggleRow("calendar.badge.plus", "Tasks in Calendar", detail: "Tasks with a date in a “Minor AI” calendar.", isOn: $tasksInCalendar, last: true)
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
                }
                if auth.isSignedIn {
                    section("Account") {
                        toggleRow("person.2.badge.gearshape", "Shared Map Updates", detail: "When someone changes a map you share or joins it.", isOn: $push.collab)
                            .onChange(of: push.collab) { if $0 { push.askIfNeeded() } }
                        toggleRow("gift", "Invitations and Limits", detail: "Rewards for invited friends, and when your AI allowance runs low.", isOn: $push.account, last: true)
                            .onChange(of: push.account) { if $0 { push.askIfNeeded() } }
                    }
                }
            }
            .padding(.horizontal, 20)
            .padding(.top, 8)
            .padding(.bottom, 24)
        }
        .background(theme.background.ignoresSafeArea())
        .navigationTitle(Text("Notifications"))
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

    private var divider: some View {
        Rectangle().fill(Color.white.opacity(0.08)).frame(height: 1).padding(.leading, 50)
    }

    private func card<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        VStack(spacing: 0) { content() }
            .background(RoundedRectangle(cornerRadius: 14).fill(theme.chatRectangle))
            .overlay(RoundedRectangle(cornerRadius: 14).stroke(theme.chatStroke, lineWidth: 1))
            .clipShape(RoundedRectangle(cornerRadius: 14))
    }

    private func section<Content: View>(_ title: LocalizedStringKey, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .textCase(.uppercase)
                .minorFont(13, .semibold, style: .footnote, maxScale: 1.3)
                .foregroundColor(MinorColor.textTertiary)
                .padding(.leading, 4)
                .accessibilityAddTraits(.isHeader)
            card(content: content)
        }
    }

    private func toggleRow(_ icon: String, _ title: LocalizedStringKey, detail: LocalizedStringKey, isOn: Binding<Bool>, last: Bool = false) -> some View {
        Toggle(isOn: isOn) {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: icon).font(.system(size: 17)).frame(width: 24).padding(.top, 1).accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 3) {
                    Text(title).minorFont(16, maxScale: 1.4).fixedSize(horizontal: false, vertical: true)
                    Text(detail)
                        .minorFont(13, style: .footnote, maxScale: 1.4)
                        .foregroundColor(MinorColor.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
        .tint(MinorColor.accent)
        .foregroundColor(MinorColor.textPrimary)
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .frame(minHeight: 56)
        .overlay(alignment: .bottom) { if !last { divider } }
    }

    private func navRow(_ page: Page, icon: String, _ title: LocalizedStringKey, subtitle: String? = nil, value: String? = nil, last: Bool = false) -> some View {
        Button { path.append(page) } label: {
            rowLabel(icon, title, subtitle: subtitle, value: value)
        }
        .buttonStyle(.plain)
        .overlay(alignment: .bottom) { if !last { divider } }
    }

    private func actionRow(_ icon: String, _ title: LocalizedStringKey, subtitle: String? = nil, value: String? = nil, danger: Bool = false, last: Bool = false, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            rowLabel(icon, title, subtitle: subtitle, value: value, danger: danger)
        }
        .buttonStyle(.plain)
        .overlay(alignment: .bottom) { if !last { divider } }
    }

    // Title (wrapping, never cut), a short value on the right, a longer explanation under the title.
    private func rowLabel(_ icon: String, _ title: LocalizedStringKey, subtitle: String? = nil, value: String? = nil, danger: Bool = false) -> some View {
        HStack(spacing: 12) {
            Image(systemName: icon).font(.system(size: 17)).frame(width: 24).accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).minorFont(16, maxScale: 1.4).fixedSize(horizontal: false, vertical: true)
                if let subtitle {
                    Text(subtitle)
                        .minorFont(13, style: .footnote, maxScale: 1.4)
                        .foregroundColor(MinorColor.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            Spacer(minLength: 8)
            if let value {
                Text(value)
                    .minorFont(14, maxScale: 1.3)
                    .foregroundColor(MinorColor.textChevron)
                    .lineLimit(1)
            }
            if !danger {
                Image(systemName: "chevron.right")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(MinorColor.textTertiary)
                    .accessibilityHidden(true)
            }
        }
        .foregroundColor(danger ? MinorColor.dangerText : MinorColor.textPrimary)
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .frame(minHeight: 52)
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
    }

    // MARK: - Actions

    private func manageSubscription() {
        Task {
            if let scene = UIApplication.shared.connectedScenes.first(where: { $0.activationState == .foregroundActive }) as? UIWindowScene {
                do {
                    try await AppStore.showManageSubscriptions(in: scene)
                    await account.refresh()
                    return
                } catch {}
            }
            if let url = URL(string: "https://apps.apple.com/account/subscriptions") { await UIApplication.shared.open(url) }
        }
    }

    private func restore() {
        guard !isRestoring else { return }
        isRestoring = true
        Task {
            defer { isRestoring = false }
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
            ProjectChatStore.shared.deleteAll()
            ProjectMaterialStore.shared.deleteAll()
            ProjectMemoryStore.shared.deleteAll()
            RecentDocuments.shared.clear()
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
                ProjectChatStore.shared.deleteAll()
                ProjectMaterialStore.shared.deleteAll()
                ProjectMemoryStore.shared.deleteAll()
                RecentDocuments.shared.clear()
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
