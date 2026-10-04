//
//  AccountStore.swift
//  Minor Ai
//
//  The user's plan and this month's usage, read from the profiles and usage tables
//  (row-level security lets each user read only their own rows), plus the detailed report for
//  the Limits screen and free days of Plus from invitations.
//

import Foundation

@MainActor
final class AccountStore: ObservableObject {
    static let shared = AccountStore()

    enum Plan: String, Decodable { case free, plus, pro }

    @Published private(set) var plan: Plan = .free { didSet { syncPaidFlag() } }
    @Published private(set) var mapsUsed = 0
    @Published private(set) var spendMicros = 0
    @Published private(set) var decksUsed = 0
    // Free Plus from invitations runs until then; waiting days start when a paid plan ends.
    @Published private(set) var bonusUntil: Date?
    @Published private(set) var bonusDays = 0
    // The Limits screen's report (nil until loaded, or when the server doesn't have it yet).
    @Published private(set) var report: UsageReport?

    let freeMapLimit = 3
    let freeDeckLimit = 1

    var isPaid: Bool {
        #if DEBUG
        if Self.demoPlan != nil { return true }
        #endif
        return plan != .free || SubscriptionStore.shared.activeTier != nil || bonusActive
    }

    // A real App Store subscription (not free days of Plus).
    var hasSubscription: Bool { plan != .free || SubscriptionStore.shared.activeTier != nil }
    var bonusActive: Bool { (bonusUntil ?? .distantPast) > Date() }

    // The plan the app should act on: the server's, or the store's while the server catches up.
    var effectivePlan: Plan {
        #if DEBUG
        if let demo = Self.demoPlan { return demo }
        #endif
        switch SubscriptionStore.shared.activeTier {
        case .pro: return .pro
        case .plus: return plan == .pro ? .pro : .plus
        case nil: return plan == .free && bonusActive ? .plus : plan
        }
    }

    var isPro: Bool { effectivePlan == .pro }

    // The model picked for maps, or the standard one when the plan no longer includes it (a plan
    // that ended, invitation days that ran out); used for presentations too.
    var allowedMapModelID: String {
        let chosen = AIModelCatalog.option(apiID: UserDefaults.standard.string(forKey: "mapModel") ?? "") ?? AIModelCatalog.defaultMap
        return (allowsMaps(with: chosen) ? chosen : AIModelCatalog.defaultMap).apiModelID
    }

    // Every plan chats with every model; maps with the strongest ones need a paid plan.
    func allowsMaps(with model: AIModelOption) -> Bool {
        switch model.mapPlan {
        case .free: return true
        case .plus: return effectivePlan != .free
        case .pro: return effectivePlan == .pro
        }
    }

    // Monthly AI allowance in millionths of a dollar of API cost (same as BUDGET_USD on the server).
    var allowanceMicros: Int {
        if let report { return report.allowance.limit }
        if !hasSubscription && bonusActive { return 2_000_000 }
        switch effectivePlan {
        case .free: return 250_000
        case .plus: return 5_000_000
        case .pro: return 10_000_000
        }
    }

    // Share of this month's AI allowance used, 0…1.
    var allowanceUsed: Double { min(1, Double(spendMicros) / Double(max(allowanceMicros, 1))) }
    var mapsLeft: Int { max(freeMapLimit - mapsUsed, 0) }
    var isOverFreeLimit: Bool { !isPaid && mapsUsed >= freeMapLimit }
    var isOverFreeDeckLimit: Bool { !isPaid && decksUsed >= freeDeckLimit }

    // Day the free counter resets: the first of next month (UTC, like the server).
    var resetDate: Date {
        let start = Self.utc.date(from: Self.utc.dateComponents([.year, .month], from: Date()))!
        return Self.utc.date(byAdding: .month, value: 1, to: start)!
    }

    // "Oct 1" in UTC, so the date matches the server's reset wherever the person lives.
    var resetDateText: String {
        var style = Date.FormatStyle.dateTime.month(.abbreviated).day()
        style.timeZone = TimeZone(identifier: "UTC")!
        style.locale = AppLanguage.current.locale
        return resetDate.formatted(style)
    }

    func refresh() async {
        struct ProfileRow: Decodable { let plan: Plan; let plan_expires_at: Date? }
        struct UsageRow: Decodable { let maps: Int; let spend_micros: Int? }
        guard let profiles: [ProfileRow] = try? await select("profiles", [URLQueryItem(name: "select", value: "plan,plan_expires_at")]) else {
            syncPaidFlag()
            return
        }
        if let profile = profiles.first {
            let expired = profile.plan_expires_at.map { $0 < Date() } ?? false
            plan = expired ? .free : profile.plan
        } else {
            plan = .free
        }
        let usage: [UsageRow] = (try? await select("usage", [
            URLQueryItem(name: "select", value: "maps,spend_micros"),
            URLQueryItem(name: "period", value: "eq.\(Self.period)"),
        ])) ?? []
        mapsUsed = usage.first?.maps ?? 0
        // A subscriber's allowance is counted on the subscription (see loadReport), not this row.
        if !hasSubscription { spendMicros = usage.first?.spend_micros ?? 0 }
        // Separate, so a server without the presentations counter yet doesn't break the rest.
        struct DeckRow: Decodable { let decks: Int? }
        let decks: [DeckRow] = (try? await select("usage", [
            URLQueryItem(name: "select", value: "decks"),
            URLQueryItem(name: "period", value: "eq.\(Self.period)"),
        ])) ?? []
        decksUsed = decks.first?.decks ?? 0
        await refreshBonus()
        syncPaidFlag()
    }

    // Free days of Plus from invitations. Days that waited for a paid plan start once it has ended.
    private func refreshBonus() async {
        struct BonusRow: Decodable { let bonus_until: Date?; let bonus_days: Int? }
        guard let rows: [BonusRow] = try? await select("profiles", [URLQueryItem(name: "select", value: "bonus_until,bonus_days")]),
              let row = rows.first else { return }
        bonusUntil = row.bonus_until
        bonusDays = row.bonus_days ?? 0
        if bonusDays > 0 && !hasSubscription, let started = try? await claimBonus() {
            bonusUntil = started
            bonusDays = 0
        }
    }

    private func claimBonus() async throws -> Date? {
        let token = try await AuthService.shared.validAccessToken()
        var request = URLRequest(url: BackendConfig.url.appendingPathComponent("rest/v1/rpc/claim_bonus"))
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(BackendConfig.publishableKey, forHTTPHeaderField: "apikey")
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.httpBody = Data("{}".utf8)
        let (data, response) = try await BackendClient.shared.send(request)
        guard (200..<300).contains(response.statusCode) else { throw BackendError.server(code: "rest_\(response.statusCode)") }
        let text = String(decoding: data, as: UTF8.self).trimmingCharacters(in: CharacterSet(charactersIn: "\" \n"))
        return Self.parseDate(text)
    }

    // This month's allowance with what it went to, and request counts (the Limits screen).
    // Paid plans are counted on the subscription, so this is also where their allowance comes from.
    func loadReport() async {
        #if DEBUG
        if Self.isDemo { return }
        #endif
        guard AuthService.shared.isSignedIn else {
            report = nil
            return
        }
        struct Body: Encodable { let action = "usage" }
        guard let loaded = try? await BackendClient.shared.invoke("account", body: Body(), as: UsageReport.self) else { return }
        report = loaded
        spendMicros = loaded.allowance.used
        mapsUsed = loaded.counts.maps.used
        decksUsed = loaded.counts.decks.used
        bonusUntil = loaded.bonusDate ?? (hasSubscription ? bonusUntil : nil)
    }

    #if DEBUG
    // -demoPlus / -demoPro: the app acts as if that plan were bought (screens and gates only;
    // the server still applies the real plan).
    static var demoPlan: Plan? {
        let args = ProcessInfo.processInfo.arguments
        if args.contains("-demoPro") { return .pro }
        if args.contains("-demoPlus") { return .plus }
        return nil
    }

    // Screenshots of the Limits screen without a server (-demoUsage).
    func installDemo() {
        let json = """
        {"plan":"plus","bonusUntil":null,"resetsAt":"2026-11-01T00:00:00.000Z",
         "allowance":{"limit":5000000,"used":1870000,"areas":{"maps":720000,"decks":410000,"chat":610000,"images":130000}},
         "counts":{"maps":{"used":14,"limit":300},"decks":{"used":3,"limit":20},"expands":{"used":96,"limit":3000},
                   "chats":{"used":212,"limit":5000},"images":{"used":49,"limit":60},"fetches":{"used":18,"limit":1000}}}
        """
        report = try? JSONDecoder().decode(UsageReport.self, from: Data(json.utf8))
        spendMicros = report?.allowance.used ?? 0
        bonusDays = 7
    }

    static var isDemo: Bool {
        ProcessInfo.processInfo.arguments.contains("-demoUsage") || ProcessInfo.processInfo.arguments.contains("-demoInvite")
    }
    #endif

    // Signed out: back to the free plan until another account signs in.
    func reset() {
        plan = .free
        mapsUsed = 0
        spendMicros = 0
        decksUsed = 0
        bonusUntil = nil
        bonusDays = 0
        report = nil
        syncPaidFlag()
    }

    func noteBonus(until: Date?) {
        if let until { bonusUntil = until }
        syncPaidFlag()
    }

    nonisolated static func parseDate(_ text: String) -> Date? {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = formatter.date(from: text) { return date }
        formatter.formatOptions = [.withInternetDateTime]
        if let date = formatter.date(from: text) { return date }
        // Microseconds, as Postgres writes them ("2026-10-12T10:00:00.123456+00:00").
        let postgres = DateFormatter()
        postgres.locale = Locale(identifier: "en_US_POSIX")
        for format in ["yyyy-MM-dd'T'HH:mm:ss.SSSSSSXXXXX", "yyyy-MM-dd HH:mm:ss.SSSSSSXXXXX", "yyyy-MM-dd HH:mm:ss.SSSXXXXX", "yyyy-MM-dd HH:mm:ssXXXXX", "yyyy-MM-dd HH:mm:ss.SSSSSSX", "yyyy-MM-dd HH:mm:ssX"] {
            postgres.dateFormat = format
            if let date = postgres.date(from: text) { return date }
        }
        return nil
    }

    // The server said the free map quota is used up; show it right away instead of after a refresh.
    func noteLimitReached(kind: String) {
        if kind == "maps" { mapsUsed = max(mapsUsed, freeMapLimit) }
        if kind == "budget" { spendMicros = max(spendMicros, allowanceMicros) }
        if kind == "decks" { decksUsed = max(decksUsed, freeDeckLimit) }
    }

    // A new map was made; counts it locally until the next refresh.
    func noteMapCreated() {
        mapsUsed += 1
    }

    func noteDeckCreated() {
        decksUsed += 1
    }

    func syncPaidFlag() {
        BackendError.isPaidUser = effectivePlan != .free
    }

    private static let utc: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        return calendar
    }()

    static var period: String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.timeZone = TimeZone(identifier: "UTC")
        formatter.dateFormat = "yyyy-MM"
        return formatter.string(from: Date())
    }

    private func select<Row: Decodable>(_ table: String, _ query: [URLQueryItem], retried: Bool = false) async throws -> [Row] {
        let token = try await AuthService.shared.validAccessToken(forceRefresh: retried)
        var components = URLComponents(url: BackendConfig.url.appendingPathComponent("rest/v1/\(table)"), resolvingAgainstBaseURL: false)!
        components.queryItems = query
        var request = URLRequest(url: components.url!)
        request.setValue(BackendConfig.publishableKey, forHTTPHeaderField: "apikey")
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        let (data, response) = try await BackendClient.shared.send(request)
        // A token the server rejects (clock change, revoked session) is refreshed once.
        if response.statusCode == 401 && !retried { return try await select(table, query, retried: true) }
        guard (200..<300).contains(response.statusCode) else { throw BackendError.server(code: "rest_\(response.statusCode)") }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .custom { decoder in
            let text = try decoder.singleValueContainer().decode(String.self)
            return Self.parseDate(text) ?? .distantFuture
        }
        return try decoder.decode([Row].self, from: data)
    }
}

// The server's report for the Limits screen (`account` function, action "usage").
struct UsageReport: Decodable, Equatable {
    struct Count: Decodable, Equatable {
        let used: Int
        let limit: Int
        var share: Double { limit > 0 ? min(1, Double(used) / Double(limit)) : 0 }
    }
    struct Areas: Decodable, Equatable {
        let maps: Int
        let decks: Int
        let chat: Int
        let images: Int
    }
    struct Allowance: Decodable, Equatable {
        let limit: Int
        let used: Int
        let areas: Areas
    }
    struct Counts: Decodable, Equatable {
        let maps: Count
        let decks: Count
        let expands: Count
        let chats: Count
        let images: Count
        let fetches: Count
    }

    let plan: String
    let bonusUntil: String?
    let resetsAt: String
    let allowance: Allowance
    let counts: Counts

    var bonusDate: Date? { bonusUntil.flatMap(AccountStore.parseDate) }
    var resetDate: Date? { AccountStore.parseDate(resetsAt) }
}
