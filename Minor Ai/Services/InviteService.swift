//
//  InviteService.swift
//  Minor Ai
//
//  Invitations: the person's own code and how their friends are doing, taking a friend's code
//  (new accounts only), and the discount earned when a friend subscribes (a one-time App Store
//  offer code). Apple's DeviceCheck token goes with a code, so one iPhone can take only one
//  invitation, ever.
//

import DeviceCheck
import Foundation

@MainActor
final class InviteService: ObservableObject {
    static let shared = InviteService()

    struct Status: Decodable, Equatable {
        struct Days: Decodable, Equatable {
            let friend: Int
            let join: Int
        }

        // An offer code for a subscription the inviter picked.
        struct Discount: Decodable, Equatable, Identifiable {
            let code: String
            let product: String
            let url: String
            var id: String { code }
        }

        let code: String
        let link: String
        let friends: Int
        let active: Int
        let subscribed: Int
        let bonusUntil: String?
        let bonusDays: Int
        let redeemed: Bool
        let canRedeem: Bool
        let days: Days
        let limit: Int?
        let discountPercent: Int?
        let discountsAvailable: Int?
        let discounts: [Discount]?

        var url: URL? { URL(string: link) }
        var friendLimit: Int { limit ?? 3 }
        var percent: Int { discountPercent ?? 30 }
        var percentText: String { "\(percent)%" }
        var isFull: Bool { friends >= friendLimit }
    }

    enum InviteError: LocalizedError {
        case notFound, ownCode, tooLate, used, deviceUsed, limit, signIn, deviceCheck, noCodes, discountFailed, other

        var errorDescription: String? {
            switch self {
            case .notFound: return L("No invitation with this code. Check it and try again.")
            case .ownCode: return L("This is your own code. Share it with friends instead.")
            case .tooLate: return L("A friend’s code works within 14 days after you create your account.")
            case .used: return L("You already joined with an invitation.")
            case .deviceUsed: return L("An invitation was already used on this iPhone.")
            case .limit: return L("This code has already brought 3 friends, the most allowed.")
            case .signIn: return L("Sign in with email or Apple to use a code.")
            case .deviceCheck: return L("Couldn’t check this iPhone. Try again later.")
            case .noCodes: return L("Discounts have run out for a moment. We’re adding more; try again later.")
            case .discountFailed: return L("Couldn’t get the discount. Try again.")
            case .other: return L("Couldn’t apply the code. Try again.")
            }
        }

        static func from(_ code: String) -> InviteError {
            switch code {
            case "invite_not_found": return .notFound
            case "invite_own_code": return .ownCode
            case "invite_too_late": return .tooLate
            case "invite_used": return .used
            case "invite_device_used": return .deviceUsed
            case "invite_limit": return .limit
            case "sign_in_required": return .signIn
            case "device_check_required", "device_check_failed", "device_required": return .deviceCheck
            case "no_codes": return .noCodes
            default: return .other
            }
        }
    }

    @Published private(set) var status: Status?

    // A code that came with a link (minorai://invite/CODE), kept until it's used.
    @Published var pendingCode: String? {
        didSet { UserDefaults.standard.set(pendingCode, forKey: "invite.pending") }
    }

    private init() {
        pendingCode = UserDefaults.standard.string(forKey: "invite.pending")
    }

    // Upper-case, no spaces or dashes, at most 8 of the code's characters.
    static func clean(_ raw: String) -> String {
        let allowed = Set("ABCDEFGHJKLMNPQRSTUVWXYZ23456789")
        return String(raw.uppercased().filter { allowed.contains($0) }.prefix(8))
    }

    static func isValid(_ code: String) -> Bool { code.count == 8 && clean(code) == code }

    func load() async throws {
        #if DEBUG
        if AccountStore.isDemo { return }
        #endif
        struct Body: Encodable { let action = "invite" }
        status = try await BackendClient.shared.invoke("account", body: Body(), as: Status.self)
    }

    // Returns the days of Plus the friend got.
    func redeem(_ raw: String) async throws -> Int {
        let code = Self.clean(raw)
        guard Self.isValid(code) else { throw InviteError.notFound }
        struct Body: Encodable {
            let action = "redeem"
            let code: String
            let deviceToken: String?
            let sandbox: Bool
        }
        struct Reply: Decodable {
            let days: Int
            let bonusUntil: String?
        }
        var token: String?
        if DCDevice.current.isSupported {
            token = try? await DCDevice.current.generateToken().base64EncodedString()
        }
        #if DEBUG
        let sandbox = true
        #else
        let sandbox = false
        #endif
        do {
            let reply = try await BackendClient.shared.invoke("account", body: Body(code: code, deviceToken: token, sandbox: sandbox), as: Reply.self)
            pendingCode = nil
            AccountStore.shared.noteBonus(until: reply.bonusUntil.flatMap(AccountStore.parseDate))
            try? await load()
            await AccountStore.shared.refresh()
            return reply.days
        } catch BackendError.server(let code) {
            throw InviteError.from(code)
        } catch BackendError.signInRequired {
            throw InviteError.signIn
        }
    }

    #if DEBUG
    // Screenshots of Invite Friends without a server (-demoInvite).
    func installDemo() {
        status = Status(code: "K7M2Q9XA", link: "https://minorai.site/invite/#c=K7M2Q9XA", friends: 2, active: 2, subscribed: 1,
                        bonusUntil: nil, bonusDays: 0, redeemed: false, canRedeem: true, days: .init(friend: 3, join: 3),
                        limit: 3, discountPercent: 30, discountsAvailable: 1, discounts: [])
    }
    #endif

    // Subscriptions a discount can be for, in the order they are offered.
    static let discountProducts = [
        SubscriptionStore.productID(.plus, .monthly),
        SubscriptionStore.productID(.plus, .yearly),
        SubscriptionStore.productID(.pro, .monthly),
        SubscriptionStore.productID(.pro, .yearly),
    ]

    static func productName(_ id: String) -> String {
        switch id {
        case SubscriptionStore.productID(.plus, .monthly): return L("Minor Plus · Monthly")
        case SubscriptionStore.productID(.plus, .yearly): return L("Minor Plus · Yearly")
        case SubscriptionStore.productID(.pro, .monthly): return L("Minor PRO · Monthly")
        case SubscriptionStore.productID(.pro, .yearly): return L("Minor PRO · Yearly")
        default: return L("Minor Plus")
        }
    }

    // Turns an earned discount into an offer code for the chosen subscription.
    func claimDiscount(product: String) async throws -> Status.Discount {
        struct Body: Encodable {
            let action = "claim_discount"
            let product: String
        }
        do {
            let discount = try await BackendClient.shared.invoke("account", body: Body(product: product), as: Status.Discount.self)
            try? await load()
            return discount
        } catch BackendError.server(let code) {
            let error = InviteError.from(code)
            throw error == .other ? InviteError.discountFailed : error
        }
    }

    func forget() {
        status = nil
    }
}
