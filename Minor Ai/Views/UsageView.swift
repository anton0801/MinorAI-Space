//
//  UsageView.swift
//  Minor Ai
//
//  Limits: how much of this month's AI allowance is used and what it went to (maps,
//  presentations, the assistant, pictures), and the month's request counts.
//

import SwiftUI

struct UsageView: View {
    var onUpgrade: (_ pro: Bool) -> Void

    @Environment(\.dismiss) private var dismiss
    @ObservedObject private var account = AccountStore.shared
    @ObservedObject private var auth = AuthService.shared
    @State private var loaded = false
    @State private var showSignIn = false

    #if DEBUG
    private var demo: Bool { AccountStore.isDemo }
    #else
    private let demo = false
    #endif
    @State private var showInvite = false

    enum Area: CaseIterable {
        case maps, decks, chat, images, other

        var title: LocalizedStringKey {
            switch self {
            case .maps: return "Maps"
            case .decks: return "Presentations"
            case .chat: return "Assistant"
            case .images: return "AI Pictures"
            case .other: return "Other"
            }
        }

        var detail: LocalizedStringKey {
            switch self {
            case .maps: return "New maps, expanding, editing, summaries and quizzes"
            case .decks: return "New presentations, slide edits and the AI designer"
            case .chat: return "Messages to the assistant"
            case .images: return "Pictures for ideas, slides and chats"
            case .other: return "Before the breakdown was added"
            }
        }

        var icon: String {
            switch self {
            case .maps: return "point.3.connected.trianglepath.dotted"
            case .decks: return "rectangle.on.rectangle.angled"
            case .chat: return "bubble.left.and.bubble.right.fill"
            case .images: return "photo.fill"
            case .other: return "ellipsis"
            }
        }

        var color: Color {
            switch self {
            case .maps: return MinorColor.accent
            case .decks: return Color(hex: "#7CC4FF")
            case .chat: return Color(hex: "#C9A2FF")
            case .images: return Color(hex: "#FC86C3")
            case .other: return Color.white.opacity(0.35)
            }
        }
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    if auth.isSignedIn || demo {
                        allowanceCard
                        if let report = account.report {
                            countsCard(report)
                        }
                        if account.bonusActive || account.bonusDays > 0 { bonusCard }
                        if plan != .pro {
                            Button { onUpgrade(plan == .plus) } label: {
                                Label(plan == .plus ? "Get More with Minor PRO" : "Get More with Minor Plus", systemImage: "star.fill")
                                    .font(.system(size: 16, weight: .semibold))
                                    .foregroundColor(.black)
                                    .frame(maxWidth: .infinity, minHeight: 50)
                                    .background(Capsule().fill(MinorColor.accent))
                            }
                            .buttonStyle(.plain)
                        }
                        Button { showInvite = true } label: {
                                Label("Invite Friends and Get Plus", systemImage: "gift.fill")
                                    .font(.system(size: 16, weight: .medium))
                                    .frame(maxWidth: .infinity, minHeight: 50)
                                    .background(Capsule().strokeBorder(MinorColor.fillThumb, lineWidth: 1))
                        }
                        .buttonStyle(.plain)
                        Text("The allowance is the cost of AI work: stronger models, long sources and long answers use more of it. Requests are counted separately. Both renew on the 1st of each month.")
                            .font(.system(size: 13))
                            .foregroundColor(MinorColor.textTertiary)
                            .fixedSize(horizontal: false, vertical: true)
                    } else {
                        signInCard
                    }
                }
                .padding(20)
            }
            .foregroundColor(MinorColor.textPrimary)
            .background(MinorColor.sheet.ignoresSafeArea())
            .navigationTitle("Limits")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }.foregroundColor(MinorColor.accent)
                }
            }
            .refreshable { await account.loadReport() }
        }
        .preferredColorScheme(.dark)
        .sheet(isPresented: $showSignIn) { SignInView(onFinish: { showSignIn = false }) }
        .sheet(isPresented: $showInvite) { InviteView() }
        .task {
            await account.loadReport()
            withAnimation(.easeOut(duration: 0.7)) { loaded = true }
        }
    }

    // MARK: - Allowance

    private var limit: Double { Double(max(account.report?.allowance.limit ?? account.allowanceMicros, 1)) }
    private var used: Double { Double(account.report?.allowance.used ?? account.spendMicros) }

    private func spent(_ area: Area) -> Double {
        guard let areas = account.report?.allowance.areas else { return area == .other ? used : 0 }
        switch area {
        case .maps: return Double(areas.maps)
        case .decks: return Double(areas.decks)
        case .chat: return Double(areas.chat)
        case .images: return Double(areas.images)
        case .other: return max(used - Double(areas.maps + areas.decks + areas.chat + areas.images), 0)
        }
    }

    // Areas shown as rows: the four named ones always, "Other" only when there is some.
    private var areas: [Area] {
        Area.allCases.filter { $0 != .other || spent(.other) > 0.5 }
    }

    // The plan the allowance belongs to: the server's report when there is one.
    private var plan: AccountStore.Plan {
        account.report.flatMap { AccountStore.Plan(rawValue: $0.plan) } ?? account.effectivePlan
    }

    private var planName: String {
        switch plan {
        case .pro: return L("Minor PRO")
        case .plus:
            let bonus = account.report.map { $0.bonusUntil != nil } ?? !account.hasSubscription
            return bonus ? L("Plus from invitations") : L("Minor Plus")
        case .free: return L("Free")
        }
    }

    private var allowanceCard: some View {
        let usedShare = min(used / limit, 1)
        return VStack(alignment: .leading, spacing: 14) {
            HStack {
                Text("AI Allowance").font(.system(size: 17, weight: .semibold))
                Spacer()
                Text(planName)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(plan == .pro ? .black : MinorColor.textPrimary)
                    .padding(.horizontal, 10).padding(.vertical, 4)
                    .background(Capsule().fill(plan == .pro ? MinorColor.pro : MinorColor.fillThumb))
            }
            HStack(alignment: .firstTextBaseline) {
                Text(verbatim: Self.percent(usedShare))
                    .font(.system(size: 44, weight: .bold).monospacedDigit())
                Text("used").font(.system(size: 17)).foregroundColor(MinorColor.textSecondary)
                Spacer()
                VStack(alignment: .trailing, spacing: 2) {
                    Text(verbatim: Self.percent(1 - usedShare))
                        .font(.system(size: 17, weight: .semibold).monospacedDigit())
                    Text("left").font(.system(size: 12)).foregroundColor(MinorColor.textTertiary)
                }
            }
            AllowanceBar(segments: areas.map { ($0.color, loaded ? spent($0) / limit : 0) })
                .accessibilityHidden(true)
            Text("Renews on \(account.resetDateText)")
                .font(.system(size: 13))
                .foregroundColor(MinorColor.textTertiary)
            if account.report != nil {
                VStack(spacing: 0) {
                    ForEach(areas, id: \.self) { area in
                        areaRow(area)
                        if area != areas.last { Rectangle().fill(MinorColor.divider.opacity(0.5)).frame(height: 1) }
                    }
                }
                .padding(.top, 2)
            }
        }
        .padding(18)
        .background(RoundedRectangle(cornerRadius: 16).fill(MinorColor.row))
    }

    private func areaRow(_ area: Area) -> some View {
        let value = spent(area)
        return HStack(spacing: 12) {
            Image(systemName: area.icon)
                .font(.system(size: 13, weight: .semibold))
                .foregroundColor(.black)
                .frame(width: 28, height: 28)
                .background(Circle().fill(area.color))
            VStack(alignment: .leading, spacing: 2) {
                Text(area.title).font(.system(size: 15, weight: .medium))
                Text(area.detail)
                    .font(.system(size: 12))
                    .foregroundColor(MinorColor.textTertiary)
                    .lineLimit(3)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 8)
            VStack(alignment: .trailing, spacing: 2) {
                Text(verbatim: Self.percent(value / limit))
                    .font(.system(size: 15, weight: .semibold).monospacedDigit())
                if used > 0.5 && value > 0.5 {
                    Text("\(Self.percent(value / used)) of used")
                        .font(.system(size: 11).monospacedDigit())
                        .foregroundColor(MinorColor.textTertiary)
                }
            }
            .fixedSize()
        }
        .padding(.vertical, 10)
        .accessibilityElement(children: .combine)
    }

    // MARK: - Requests

    private func countsCard(_ report: UsageReport) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("This Month").font(.system(size: 17, weight: .semibold)).padding(.bottom, 8)
            countRow("point.3.connected.trianglepath.dotted", "New Maps", report.counts.maps)
            countRow("rectangle.on.rectangle.angled", "New Presentations", report.counts.decks)
            countRow("wand.and.stars", "AI Actions on Maps and Slides", report.counts.expands)
            countRow("bubble.left.and.bubble.right", "Assistant Messages", report.counts.chats)
            countRow("photo", "AI Pictures", report.counts.images)
            countRow("link", "Links and Videos Read", report.counts.fetches, last: true)
        }
        .padding(18)
        .background(RoundedRectangle(cornerRadius: 16).fill(MinorColor.row))
    }

    private func countRow(_ icon: String, _ title: LocalizedStringKey, _ count: UsageReport.Count, last: Bool = false) -> some View {
        let tint: Color = count.share >= 1 ? MinorColor.dangerText : count.share >= 0.8 ? MinorColor.pro : MinorColor.accent
        return VStack(alignment: .leading, spacing: 7) {
            HStack(spacing: 10) {
                Image(systemName: icon).font(.system(size: 14)).frame(width: 20).foregroundColor(MinorColor.textSecondary)
                Text(title).font(.system(size: 15))
                Spacer(minLength: 8)
                Text(verbatim: "\(count.used.formatted(.number.locale(AppLanguage.current.locale))) / \(count.limit.formatted(.number.locale(AppLanguage.current.locale)))")
                    .font(.system(size: 14, weight: .semibold).monospacedDigit())
                    .foregroundColor(count.share >= 1 ? MinorColor.dangerText : MinorColor.textPrimary)
            }
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(MinorColor.fillThumb)
                    Capsule().fill(tint).frame(width: loaded && count.used > 0 ? max(geo.size.width * count.share, 4) : 0)
                }
            }
            .frame(height: 4)
        }
        .padding(.vertical, 8)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(title))
        .accessibilityValue(Text(verbatim: "\(count.used) / \(count.limit)"))
    }

    // MARK: - Other parts

    private var bonusCard: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: "gift.fill")
                .font(.system(size: 16))
                .foregroundColor(.black)
                .frame(width: 34, height: 34)
                .background(Circle().fill(MinorColor.accent))
            VStack(alignment: .leading, spacing: 4) {
                if account.bonusActive, let until = account.bonusUntil {
                    Text("Minor Plus from invitations until \(Self.day(until)).")
                        .font(.system(size: 15, weight: .medium))
                }
                if account.bonusDays > 0 {
                    Text("Days of Plus waiting: \(account.bonusDays). They start when your subscription ends.")
                        .font(.system(size: 14))
                        .foregroundColor(MinorColor.textSecondary)
                }
                if account.bonusActive && !account.hasSubscription {
                    Text("Free Plus has a smaller AI allowance than a subscription.")
                        .font(.system(size: 12))
                        .foregroundColor(MinorColor.textTertiary)
                }
            }
            .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .background(RoundedRectangle(cornerRadius: 16).fill(MinorColor.row))
    }

    private var signInCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Sign in to use AI and see your limits.")
                .font(.system(size: 16))
                .foregroundColor(MinorColor.textSecondary)
            Button { showSignIn = true } label: {
                Text("Sign In or Create Account")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundColor(.black)
                    .frame(maxWidth: .infinity, minHeight: 50)
                    .background(Capsule().fill(MinorColor.accent))
            }
            .buttonStyle(.plain)
        }
    }

    // "12%", "<1%" for a little, "0%" for nothing.
    static func percent(_ share: Double) -> String {
        let value = max(share, 0) * 100
        if value == 0 { return "0%" }
        if value < 1 { return "<1%" }
        return "\(Int(value.rounded()))%"
    }

    static func day(_ date: Date) -> String {
        var style = Date.FormatStyle.dateTime.month(.abbreviated).day()
        style.locale = AppLanguage.current.locale
        return date.formatted(style)
    }
}

// The allowance as one bar: a colored part for each area, the rest of the track is what's left.
struct AllowanceBar: View {
    let segments: [(color: Color, share: Double)]

    var body: some View {
        GeometryReader { geo in
            let total = segments.reduce(0) { $0 + max($1.share, 0) }
            let scale = total > 1 ? 1 / total : 1
            HStack(spacing: 2) {
                ForEach(Array(segments.enumerated()), id: \.offset) { _, segment in
                    let width = geo.size.width * max(segment.share, 0) * scale
                    if width >= 0.5 {
                        Rectangle().fill(segment.color).frame(width: max(width - 2, 2))
                    }
                }
                Spacer(minLength: 0)
            }
            .frame(width: geo.size.width, alignment: .leading)
            .background(MinorColor.fillThumb)
            .clipShape(Capsule())
        }
        .frame(height: 12)
    }
}
