//
//  SubscriptionStore.swift
//  Minor Ai
//
//  StoreKit 2 subscriptions: Plus and PRO, monthly and yearly. Every verified transaction is
//  sent to the `subscription` edge function, which sets the plan the server's limits use.
//  Local testing uses StoreKit/Minor.storekit (selected in the Minor Ai scheme).
//

import StoreKit

@MainActor
final class SubscriptionStore: ObservableObject {
    static let shared = SubscriptionStore()

    enum Tier { case plus, pro }
    enum Period { case monthly, yearly }
    enum Outcome { case purchased, cancelled, pending }

    @Published private(set) var products: [String: Product] = [:]
    @Published private(set) var activeProductID: String? {
        didSet { AccountStore.shared.syncPaidFlag() }
    }
    @Published private(set) var isPurchasing = false

    private var updates: Task<Void, Never>?
    private var lastRefresh = Date.distantPast

    private init() {
        updates = Task { [weak self] in
            for await result in Transaction.updates {
                await self?.handle(result)
            }
        }
        Task {
            await loadProducts()
            await refreshEntitlements()
        }
    }

    // Product IDs in App Store Connect. The Plus ones existed before Minor became a mind-map app;
    // the half-year Plus plan is no longer offered but still honored for people who have it.
    static func productID(_ tier: Tier, _ period: Period) -> String {
        switch (tier, period) {
        case (.plus, .monthly): return "com.minorailifegroup.MinorAI.plusMonthlyPlan"
        case (.plus, .yearly): return "com.minorailifegroup.MinorAI.plusYearlyPlan"
        case (.pro, .monthly): return "com.minorailifegroup.MinorAI.proMonthlyPlan"
        case (.pro, .yearly): return "com.minorailifegroup.MinorAI.proYearlyPlan"
        }
    }

    static let legacyPlusIDs = ["com.minorailifegroup.MinorAI.plusHalfYearPlan"]

    static let allIDs = [Tier.plus, .pro].flatMap { tier in [Period.monthly, .yearly].map { productID(tier, $0) } } + legacyPlusIDs

    static func tier(of productID: String) -> Tier? {
        if productID == Self.productID(.pro, .monthly) || productID == Self.productID(.pro, .yearly) { return .pro }
        if allIDs.contains(productID) { return .plus }
        return nil
    }

    // The plan this Apple ID pays for. Not counted when the server said it belongs to another
    // Minor account: the server's plan (free here) is what the limits follow.
    var activeTier: Tier? {
        guard let id = activeProductID, !(ownedElsewhere && AuthService.shared.isSignedIn) else { return nil }
        return Self.tier(of: id)
    }

    // Another account signed in: the previous answer about ownership no longer applies.
    func accountChanged() {
        ownedElsewhere = false
        notConfirmed = false
        Task { await refreshEntitlements() }
    }

    // Price from the App Store in the person's currency; nil until StoreKit answers
    // (a hard-coded dollar price would be wrong in most countries).
    func price(_ tier: Tier, _ period: Period) -> String? {
        products[Self.productID(tier, period)]?.displayPrice
    }

    // "$12.99/month" or "$119.99/year".
    func billedPrice(_ tier: Tier, _ period: Period) -> String? {
        price(tier, period).map { period == .monthly ? L("\($0)/month") : L("\($0)/year") }
    }

    // Yearly price spread over 12 months, e.g. "$8.49/month".
    func monthlyEquivalent(_ tier: Tier) -> String? {
        guard let product = products[Self.productID(tier, .yearly)] else { return nil }
        let perMonth = product.price / 12
        return L("\(perMonth.formatted(product.priceFormatStyle))/month")
    }

    // Percent saved by paying yearly, from real store prices.
    func yearlySavings(_ tier: Tier) -> Int? {
        guard let monthly = products[Self.productID(tier, .monthly)]?.price,
              let yearly = products[Self.productID(tier, .yearly)]?.price,
              monthly > 0 else { return nil }
        let full = NSDecimalNumber(decimal: monthly * 12).doubleValue
        let paid = NSDecimalNumber(decimal: yearly).doubleValue
        let percent = Int(((full - paid) / full * 100).rounded())
        return percent > 0 ? percent : nil
    }

    func loadProducts() async {
        guard let loaded = try? await Product.products(for: Self.allIDs), !loaded.isEmpty else { return }
        products = Dictionary(uniqueKeysWithValues: loaded.map { ($0.id, $0) })
    }

    func purchase(_ tier: Tier, _ period: Period) async throws -> Outcome {
        guard !isPurchasing else { return .cancelled }
        isPurchasing = true
        defer { isPurchasing = false }

        if products.isEmpty { await loadProducts() }
        guard let product = products[Self.productID(tier, period)] else { throw StoreError.unavailable }

        // Buying doesn't require an account (App Store Review 5.1.1(v)). When signed in, the purchase
        // carries the account id; otherwise it is linked to the account at sign-in.
        var options: Set<Product.PurchaseOption> = []
        if AuthService.shared.isSignedIn, let id = AuthService.shared.session?.userID, let token = UUID(uuidString: id) {
            options.insert(.appAccountToken(token))
        }
        switch try await product.purchase(options: options) {
        case .success(let result):
            guard case .verified = result else { throw StoreError.unverified }
            await handle(result)
            return .purchased
        case .pending:
            return .pending
        case .userCancelled:
            return .cancelled
        @unknown default:
            return .cancelled
        }
    }

    // The server keeps a subscription on the account it belongs to (see the `subscription`
    // function): set when this Apple ID's subscription is linked to another Minor account.
    @Published private(set) var ownedElsewhere = false
    // Apple confirmed the purchase on this iPhone but the server couldn't verify it (in testing:
    // an Xcode StoreKit purchase for an account not listed in XCODE_TEST_USERS).
    @Published private(set) var notConfirmed = false

    // Returns true when an active subscription was found.
    func restore() async throws -> Bool {
        try await AppStore.sync()
        await refreshEntitlements()
        if activeProductID != nil && ownedElsewhere { throw StoreError.ownedElsewhere }
        return activeProductID != nil
    }

    // Called when the app comes back to the foreground: renewals, refunds and Ask to Buy
    // approvals that happened meanwhile show up without a restart.
    func refreshIfStale() async {
        guard Date().timeIntervalSince(lastRefresh) > 60 else { return }
        if products.isEmpty { await loadProducts() }
        await refreshEntitlements()
    }

    func refreshEntitlements() async {
        lastRefresh = Date()
        var best: (Transaction, String)?
        // currentEntitlements already leaves out expired subscriptions and keeps ones in a billing
        // grace period, so no date check here.
        for await result in Transaction.currentEntitlements {
            guard case .verified(let transaction) = result, transaction.revocationDate == nil else { continue }
            guard let tier = Self.tier(of: transaction.productID) else { continue }
            if best == nil || (tier == .pro && Self.tier(of: best!.0.productID) != .pro) {
                best = (transaction, result.jwsRepresentation)
            }
        }
        activeProductID = best?.0.productID
        // The server is told in the background: the paywall closes as soon as Apple confirms.
        if let jws = best?.1 {
            Task { await sync(jws) }
        } else {
            Task { await AccountStore.shared.refresh() }
        }
    }

    private func handle(_ result: VerificationResult<Transaction>) async {
        guard case .verified(let transaction) = result else { return }
        let jws = result.jwsRepresentation
        await transaction.finish()
        await refreshEntitlements()
        // Every transaction (renewals, other products) is recorded on the server too.
        Task { await sync(jws) }
    }

    private func sync(_ jws: String) async {
        struct Body: Encodable { let signedTransaction: String }
        struct Reply: Decodable { let plan: String }
        do {
            let _: Reply = try await BackendClient.shared.invoke("subscription", body: Body(signedTransaction: jws))
            ownedElsewhere = false
            notConfirmed = false
        } catch BackendError.server(let code) where code == "owned_elsewhere" {
            ownedElsewhere = true
        } catch BackendError.server(let code) where code == "unverified" || code == "wrong_product" {
            notConfirmed = AuthService.shared.isSignedIn
        } catch {}
        await AccountStore.shared.refresh()
    }

    enum StoreError: LocalizedError {
        case unavailable
        case noAccount
        case unverified
        case ownedElsewhere

        var errorDescription: String? {
            switch self {
            case .unavailable: return L("The App Store isn’t available right now. Try again later.")
            case .ownedElsewhere: return L("This subscription is linked to another Minor account. Sign in to that account, or write to support@minorai.site to move it.")
            case .noAccount: return L("Couldn’t reach your account. Check your connection and try again.")
            case .unverified: return L("The App Store couldn’t verify this purchase. Try Restore Purchases.")
            }
        }
    }
}
