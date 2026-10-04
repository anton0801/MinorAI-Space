//
//  StoreKitPurchaseTests.swift
//  Minor AiTests
//
//  Purchases against the local StoreKit configuration (StoreKit/Minor.storekit): buying Plus,
//  upgrading to PRO, expiry, refunds, Ask to Buy, failed and repeated purchases. Signed out, so
//  the server sync is skipped and only the device's view of the plan is checked.
//

import Foundation
import StoreKit
import StoreKitTest
import Testing
@testable import Minor_Ai

@MainActor
@Suite(.serialized)
final class StoreKitPurchaseTests {
    let session: SKTestSession
    let store = SubscriptionStore.shared

    init() async throws {
        let url = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("StoreKit/Minor.storekit")
        session = try SKTestSession(contentsOf: url)
        session.resetToDefaultState()
        session.disableDialogs = true
        session.clearTransactions()
        await store.loadProducts()
        await store.refreshEntitlements()
    }

    deinit {
        session.clearTransactions()
    }

    // Transaction.updates delivers some changes a moment later.
    private func waitFor(_ condition: @MainActor () -> Bool) async {
        for _ in 0..<40 where !condition() {
            try? await Task.sleep(nanoseconds: 100_000_000)
        }
    }

    @Test func productsAndPricesLoad() async throws {
        #expect(store.products.count == 5)
        #expect(store.price(.plus, .monthly) != nil && store.price(.pro, .yearly) != nil)
        #expect((store.yearlySavings(.plus) ?? 0) > 0 && (store.yearlySavings(.pro) ?? 0) > 0)
    }

    @Test func buyPlusThenUpgradeToPro() async throws {
        #expect(store.activeTier == nil)
        #expect(try await store.purchase(.plus, .monthly) == .purchased)
        #expect(store.activeTier == .plus)
        #expect(AccountStore.shared.effectivePlan == .plus && AccountStore.shared.isPaid && AccountStore.shared.hasSubscription)
        #expect(try await store.purchase(.pro, .yearly) == .purchased)
        await waitFor { self.store.activeTier == .pro }
        #expect(store.activeTier == .pro)
        #expect(AccountStore.shared.effectivePlan == .pro && AccountStore.shared.isPro)
    }

    @Test func expiredSubscriptionEndsThePlan() async throws {
        #expect(try await store.purchase(.plus, .monthly) == .purchased)
        try session.expireSubscription(productIdentifier: SubscriptionStore.productID(.plus, .monthly))
        await store.refreshEntitlements()
        await waitFor { self.store.activeTier == nil }
        #expect(store.activeTier == nil)
        #expect(!AccountStore.shared.isPaid)
    }

    @Test func refundEndsThePlan() async throws {
        #expect(try await store.purchase(.pro, .monthly) == .purchased)
        let transaction = try #require(session.allTransactions().last)
        try session.refundTransaction(identifier: transaction.identifier)
        await store.refreshEntitlements()
        await waitFor { self.store.activeTier == nil }
        #expect(store.activeTier == nil)
    }

    @Test func askToBuyWaitsForApproval() async throws {
        session.askToBuyEnabled = true
        #expect(try await store.purchase(.plus, .yearly) == .pending)
        #expect(store.activeTier == nil && !store.isPurchasing)
        let pending = try #require(session.allTransactions().last)
        try session.approveAskToBuyTransaction(identifier: pending.identifier)
        await waitFor { self.store.activeTier == .plus }
        #expect(store.activeTier == .plus)
        session.askToBuyEnabled = false
    }

    @Test func failedPurchaseLeavesNoPlanAndUnlocksTheButton() async throws {
        session.failTransactionsEnabled = true
        await #expect(throws: (any Error).self) { try await self.store.purchase(.plus, .monthly) }
        #expect(!store.isPurchasing && store.activeTier == nil)
        session.failTransactionsEnabled = false
    }

    @Test func secondTapWhilePurchasingIsIgnored() async throws {
        async let first = store.purchase(.plus, .monthly)
        async let second = store.purchase(.pro, .monthly)
        let outcomes = [try await first, try await second]
        // Whichever ran first buys; the other is ignored instead of starting a second purchase.
        #expect(outcomes.filter { $0 == .purchased }.count == 1 && outcomes.contains(.cancelled))
        #expect(store.activeTier != nil)
    }
}
