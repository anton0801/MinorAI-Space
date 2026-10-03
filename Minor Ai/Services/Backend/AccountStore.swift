//
//  AccountStore.swift
//  Minor Ai
//
//  The user's plan and this month's usage, read from the profiles and usage tables
//  (row-level security lets each user read only their own rows).
//

import Foundation

@MainActor
final class AccountStore: ObservableObject {
    static let shared = AccountStore()

    enum Plan: String, Decodable { case free, plus, pro }

    @Published private(set) var plan: Plan = .free { didSet { syncPaidFlag() } }
    @Published private(set) var mapsUsed = 0
    @Published private(set) var spendMicros = 0

    let freeMapLimit = 3

    var isPaid: Bool { plan != .free || SubscriptionStore.shared.activeTier != nil }

    // The plan the app should act on: the server's, or the store's while the server catches up.
    var effectivePlan: Plan {
        switch SubscriptionStore.shared.activeTier {
        case .pro: return .pro
        case .plus: return plan == .pro ? .pro : .plus
        case nil: return plan
        }
    }

    var isPro: Bool { effectivePlan == .pro }

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
        spendMicros = usage.first?.spend_micros ?? 0
        syncPaidFlag()
    }

    // The server said the free map quota is used up; show it right away instead of after a refresh.
    func noteLimitReached(kind: String) {
        if kind == "maps" { mapsUsed = max(mapsUsed, freeMapLimit) }
        if kind == "budget" { spendMicros = max(spendMicros, allowanceMicros) }
    }

    // A new map was made; counts it locally until the next refresh.
    func noteMapCreated() {
        mapsUsed += 1
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
            let formatter = ISO8601DateFormatter()
            formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
            if let date = formatter.date(from: text) { return date }
            formatter.formatOptions = [.withInternetDateTime]
            return formatter.date(from: text) ?? .distantFuture
        }
        return try decoder.decode([Row].self, from: data)
    }
}
