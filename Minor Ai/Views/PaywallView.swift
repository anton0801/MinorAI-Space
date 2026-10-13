//
//  PaywallView.swift
//  Minor Ai
//
//  Minor Plus / PRO paywall: what the plan gives, plan and billing period chosen separately, the
//  App Store price in the person's currency for the whole period, the auto-renewal terms Apple
//  requires, Restore Purchases, Terms of Use and Privacy Policy. Scrolls on small screens and with
//  large text; nothing moves over the prices.
//

import StoreKit
import SwiftUI

struct PaywallView: View {
    var onClose: () -> Void

    @ObservedObject private var store = SubscriptionStore.shared
    @State private var tier: SubscriptionStore.Tier
    // Yearly first: the better deal, and the plan most people keep.
    @State private var period: SubscriptionStore.Period = .yearly
    @State private var message: String?
    @State private var isRestoring = false
    @State private var isLoadingPrices = false
    @State private var comparison: PlanComparisonView.Topic?

    init(tier: SubscriptionStore.Tier, onClose: @escaping () -> Void) {
        _tier = State(initialValue: tier)
        self.onClose = onClose
    }

    // Four reasons, from the plans' real limits (no promise of "unlimited").
    struct Benefit: Identifiable {
        let icon: String
        let text: String
        let topic: PlanComparisonView.Topic
        var id: String { text }
    }

    static func benefits(_ tier: SubscriptionStore.Tier) -> [Benefit] {
        switch tier {
        case .plus:
            return [
                Benefit(icon: "square.3.layers.3d", text: L("Up to 300 maps a month"), topic: .maps),
                Benefit(icon: "mic", text: L("YouTube, voice and documents"), topic: .sources),
                Benefit(icon: "sparkle", text: L("20× more AI than Free"), topic: .ai),
                Benefit(icon: "photo", text: L("60 AI images a month"), topic: .images),
            ]
        case .pro:
            return [
                Benefit(icon: "square.3.layers.3d", text: L("Up to 600 maps a month"), topic: .maps),
                Benefit(icon: "brain", text: L("The strongest AI models"), topic: .ai),
                Benefit(icon: "sparkle", text: L("40× more AI than Free"), topic: .ai),
                Benefit(icon: "photo", text: L("150 AI images a month"), topic: .images),
            ]
        }
    }

    private var isCurrentPlan: Bool { store.activeProductID == SubscriptionStore.productID(tier, period) }
    private var hasPrices: Bool { store.price(tier, .monthly) != nil || store.price(tier, .yearly) != nil }
    private var selectedPrice: String? { store.price(tier, period) }
    // "3 days" when this plan starts with a free trial for this Apple ID.
    private func trial(_ period: SubscriptionStore.Period) -> String? {
        store.activeProductID == SubscriptionStore.productID(tier, period) ? nil : store.freeTrial(tier, period)
    }
    private var planName: String { tier == .plus ? "Plus" : "PRO" }

    var body: some View {
        ZStack(alignment: .top) {
            Color(hex: "#0F0F0F").ignoresSafeArea()
            // A quiet glow in the corner; nothing moves over the prices or links.
            RadialGradient(colors: [MinorColor.accent.opacity(0.16), .clear], center: .topTrailing, startRadius: 10, endRadius: 360)
                .frame(height: 420)
                .ignoresSafeArea()
                .allowsHitTesting(false)
                .accessibilityHidden(true)

            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 0) {
                    HStack {
                        Text(verbatim: "Minor AI")
                            .minorFont(17, maxScale: 1.3)
                            .foregroundColor(MinorColor.textSecondary)
                        Spacer()
                        Button(action: onClose) {
                            Image(systemName: "xmark")
                                .font(.system(size: 15, weight: .semibold))
                                .foregroundColor(.white)
                                .frame(width: 36, height: 36)
                                .background(Circle().fill(Color.white.opacity(0.1)))
                                .frame(width: 44, height: 44)
                                .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("Close")
                    }
                    .padding(.trailing, -4)

                    Text("Your next big project.")
                        .minorFont(32, .heavy, style: .largeTitle, maxScale: 1.15)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.top, 10)
                        .accessibilityAddTraits(.isHeader)
                    Text(tier == .plus ? "With Minor Plus" : "With Minor PRO")
                        .minorFont(22, maxScale: 1.3)
                        .foregroundColor(MinorColor.textTertiary)
                        .padding(.top, 4)

                    tierPicker.padding(.top, 16)
                    benefitsCard.padding(.top, 14)

                    VStack(spacing: 10) {
                        periodRow(.monthly)
                        periodRow(.yearly)
                    }
                    .padding(.top, 14)

                    buyButton.padding(.top, 14)

                    Text(billingLine)
                        .minorFont(13, style: .footnote, maxScale: 1.6)
                        .foregroundColor(MinorColor.textTertiary)
                        .multilineTextAlignment(.center)
                        .frame(maxWidth: .infinity)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.top, 10)

                    if store.activeTier != nil {
                        Button("Manage Subscription", action: manageSubscription)
                            .minorFont(14, .medium, maxScale: 1.4)
                            .foregroundColor(MinorColor.accent)
                            .frame(maxWidth: .infinity, minHeight: 44)
                    }

                    if let message {
                        Text(message)
                            .minorFont(14, .medium, style: .footnote, maxScale: 1.5)
                            .foregroundColor(.white)
                            .multilineTextAlignment(.center)
                            .frame(maxWidth: .infinity)
                            .fixedSize(horizontal: false, vertical: true)
                            .padding(.top, 10)
                            .accessibilityAddTraits(.updatesFrequently)
                    }

                    Rectangle().fill(Color.white.opacity(0.08)).frame(height: 1).padding(.top, 12)
                    links.padding(.top, 2)

                    Text("Payment is charged to your Apple ID when you confirm the purchase. The subscription renews automatically at the same price and period unless you cancel it at least 24 hours before the current period ends. Manage or cancel it anytime in your App Store account settings. Each plan includes a monthly AI allowance; stronger models use more of it.")
                        .minorFont(11, style: .caption2, maxScale: 1.8)
                        .foregroundColor(MinorColor.textTertiary)
                        .multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.top, 10)
                }
                .padding(.horizontal, 20)
                .padding(.top, 8)
                .padding(.bottom, 20)
                .frame(maxWidth: 480)
                .frame(maxWidth: .infinity)
            }
        }
        .foregroundColor(.white)
        .accessibilityElement(children: .contain)
        .accessibilityAddTraits(.isModal)
        .accessibilityAction(.escape, onClose)
        .onAppear {
            // Someone who already pays sees their own billing period first (monthly or yearly).
            if let current = store.activeProductID {
                period = current.hasSuffix("MonthlyPlan") ? .monthly : .yearly
            }
        }
        .task {
            if store.products.isEmpty { await loadPrices() }
        }
        .onChange(of: tier) { _ in message = nil }
        .onChange(of: period) { _ in message = nil }
        .sheet(item: $comparison) { topic in PlanComparisonView(focus: topic) }
    }

    // MARK: - Parts

    private var tierPicker: some View {
        HStack(spacing: 6) {
            ForEach([SubscriptionStore.Tier.plus, .pro], id: \.self) { value in
                let chosen = tier == value
                Button {
                    guard !chosen else { return }
                    Haptics.selection()
                    withAnimation(.easeInOut(duration: 0.2)) { tier = value }
                } label: {
                    Text(value == .plus ? "Plus" : "PRO")
                        .minorFont(17, chosen ? .semibold : .medium, maxScale: 1.3)
                        .foregroundColor(chosen ? .white : MinorColor.textSecondary)
                        .frame(maxWidth: .infinity, minHeight: 44)
                        .background(RoundedRectangle(cornerRadius: 12).fill(chosen ? MinorColor.accent.opacity(0.12) : Color.clear))
                        .overlay(RoundedRectangle(cornerRadius: 12).stroke(chosen ? MinorColor.accent : Color.clear, lineWidth: 1.5))
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(value == .plus ? "Minor Plus" : "Minor PRO")
                .accessibilityAddTraits(chosen ? [.isButton, .isSelected] : .isButton)
            }
        }
        .padding(4)
        .background(RoundedRectangle(cornerRadius: 15).fill(Color.white.opacity(0.05)))
        .overlay(RoundedRectangle(cornerRadius: 15).stroke(Color.white.opacity(0.08), lineWidth: 1))
    }

    // What the plan gives; each line opens its part of the full comparison.
    private var benefitsCard: some View {
        VStack(spacing: 0) {
            ForEach(Self.benefits(tier)) { benefit in
                Button { comparison = benefit.topic } label: {
                    HStack(spacing: 14) {
                        Image(systemName: benefit.icon)
                            .font(.system(size: 19))
                            .frame(width: 26)
                            .accessibilityHidden(true)
                        Text(benefit.text)
                            .minorFont(17, maxScale: 1.4)
                            .fixedSize(horizontal: false, vertical: true)
                        Spacer(minLength: 8)
                        Image(systemName: "chevron.right")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundColor(MinorColor.textTertiary)
                            .accessibilityHidden(true)
                    }
                    .padding(.horizontal, 16)
                    .frame(minHeight: 48)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityHint(Text("Shows the plans side by side"))
                Rectangle().fill(Color.white.opacity(0.08)).frame(height: 1).padding(.leading, 56)
            }
            Button { comparison = .all } label: {
                HStack(spacing: 6) {
                    Text("All Features and Limits")
                    Image(systemName: "chevron.right").font(.system(size: 11, weight: .semibold))
                }
                .minorFont(14, maxScale: 1.4)
                .foregroundColor(MinorColor.textSecondary)
                .frame(maxWidth: .infinity, minHeight: 44)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        }
        .background(RoundedRectangle(cornerRadius: 16).fill(Color.white.opacity(0.04)))
        .overlay(RoundedRectangle(cornerRadius: 16).stroke(Color.white.opacity(0.08), lineWidth: 1))
        .animation(.easeInOut(duration: 0.2), value: tier)
    }

    private func periodRow(_ value: SubscriptionStore.Period) -> some View {
        let chosen = period == value
        let price = store.price(tier, value)
        let current = store.activeProductID == SubscriptionStore.productID(tier, value)
        return Button {
            guard !chosen else { return }
            Haptics.selection()
            period = value
        } label: {
            HStack(spacing: 14) {
                ZStack {
                    Circle().stroke(chosen ? MinorColor.accent : MinorColor.textTertiary, lineWidth: 1.5)
                    if chosen { Circle().fill(MinorColor.accent).padding(5) }
                }
                .frame(width: 24, height: 24)
                VStack(alignment: .leading, spacing: 2) {
                    Text(value == .monthly ? "Month" : "Year")
                        .minorFont(17, .semibold, maxScale: 1.4)
                    if current {
                        Text("Your current plan").minorFont(12, maxScale: 1.4).foregroundColor(MinorColor.accent)
                    } else if let trial = trial(value), price != nil {
                        Text(L("\(trial) free")).minorFont(12, .medium, maxScale: 1.4).foregroundColor(MinorColor.accent)
                    } else if value == .yearly, let perMonth = store.monthlyEquivalent(tier) {
                        Text(L("≈ \(perMonth)")).minorFont(12, maxScale: 1.4).foregroundColor(MinorColor.textTertiary)
                    }
                }
                Spacer(minLength: 8)
                if let price {
                    // The amount billed for the whole period is the most prominent price.
                    (Text(price).font(.system(size: 20, weight: .bold)) + Text(verbatim: " ") + Text(value == .monthly ? L("/ month") : L("/ year")).font(.system(size: 15)).foregroundColor(MinorColor.textSecondary))
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                } else if isLoadingPrices {
                    RoundedRectangle(cornerRadius: 5).fill(Color.white.opacity(0.1)).frame(width: 96, height: 20)
                        .accessibilityLabel(Text("Loading the price"))
                } else {
                    Text("—").foregroundColor(MinorColor.textTertiary)
                }
            }
            .padding(.horizontal, 16)
            .frame(minHeight: 54)
            .background(RoundedRectangle(cornerRadius: 14).fill(chosen ? MinorColor.accent.opacity(0.1) : Color.white.opacity(0.04)))
            .overlay(RoundedRectangle(cornerRadius: 14).stroke(chosen ? MinorColor.accent : Color.white.opacity(0.08), lineWidth: chosen ? 1.5 : 1))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(store.isPurchasing)
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(chosen ? [.isButton, .isSelected] : .isButton)
    }

    private var buyButton: some View {
        Button(action: purchase) {
            ZStack {
                Text(buyTitle).opacity(store.isPurchasing ? 0 : 1)
                if store.isPurchasing || (isLoadingPrices && !hasPrices) { ProgressView().tint(.black) }
            }
            .minorFont(18, .semibold, maxScale: 1.3)
            .foregroundColor(.black)
            .frame(maxWidth: .infinity, minHeight: 52)
            .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(Color.white))
            .opacity(isCurrentPlan || (isLoadingPrices && !hasPrices) ? 0.5 : 1)
        }
        .buttonStyle(PressScale())
        .disabled(store.isPurchasing || isCurrentPlan || (isLoadingPrices && !hasPrices))
        .accessibilityLabel(buyAccessibilityLabel)
    }

    private var buyTitle: String {
        if isCurrentPlan { return L("Your Current Plan") }
        if isLoadingPrices && !hasPrices { return "" }
        if selectedPrice == nil { return L("Load Prices Again") }
        return tier == .plus ? L("Get Plus (paywall)") : L("Get PRO (paywall)")
    }

    private var buyAccessibilityLabel: String {
        if isCurrentPlan { return L("Your current plan") }
        guard let price = selectedPrice else { return isLoadingPrices ? L("Loading prices") : L("Load prices again") }
        let subscribe = L("Subscribe to Minor \(planName) for \(period == .monthly ? L("\(price)/month") : L("\(price)/year"))")
        return trial(period).map { subscribe + ", " + L("\($0) free") } ?? subscribe
    }

    // What happens to the money: the full amount for the period, a trial first when there is one.
    private var billingLine: String {
        guard let price = selectedPrice else {
            return isLoadingPrices ? L("Loading prices from the App Store…") : L("Prices come from the App Store.")
        }
        if isCurrentPlan { return L("This is your current plan.") }
        let each = period == .monthly ? L("\(price) a month") : L("\(price) a year")
        var line = trial(period).map { L("\($0) free, then \(each) · Renews automatically") } ?? L("\(each) · Renews automatically")
        if let note = switchNote { line += "\n" + note }
        return line
    }

    // For someone who already pays, when a change takes effect. Apple's rules for one subscription
    // group: moving up to PRO starts at once (the unused part of Plus is refunded); moving down to
    // Plus, or to another billing period, starts when the current period ends.
    private var switchNote: String? {
        guard let current = store.activeTier, !isCurrentPlan else { return nil }
        if current == .plus && tier == .pro { return L("PRO starts right away; the App Store refunds the unused part of Plus.") }
        return L("Your plan changes when the current billing period ends.")
    }

    private var links: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 0) { linkItems(separator: true) }
            VStack(spacing: 0) { linkItems(separator: false) }
        }
        .minorFont(12, maxScale: 1.6)
        .foregroundColor(MinorColor.textSecondary)
        .frame(maxWidth: .infinity)
    }

    @ViewBuilder
    private func linkItems(separator: Bool) -> some View {
        Button(isRestoring ? L("Restoring…") : L("Restore Purchases"), action: restore)
            .disabled(isRestoring || store.isPurchasing)
            .frame(minHeight: 44)
            .padding(.horizontal, 5)
        if separator { Rectangle().fill(Color.white.opacity(0.2)).frame(width: 1, height: 16).accessibilityHidden(true) }
        Link(L("Terms (legal)"), destination: LegalLinks.terms)
            .frame(minHeight: 44)
            .padding(.horizontal, 5)
            .accessibilityLabel(Text("Terms of Use"))
        if separator { Rectangle().fill(Color.white.opacity(0.2)).frame(width: 1, height: 16).accessibilityHidden(true) }
        Link("Privacy", destination: LegalLinks.privacy)
            .frame(minHeight: 44)
            .padding(.horizontal, 5)
            .accessibilityLabel(Text("Privacy Policy"))
    }

    // MARK: - Actions

    private func loadPrices() async {
        isLoadingPrices = true
        message = nil
        await store.loadProducts()
        isLoadingPrices = false
        if store.products.isEmpty {
            message = L("Couldn’t load prices from the App Store. Check your connection and try again.")
        } else if selectedPrice == nil {
            // The App Store answered without this plan (not available in this country yet, or
            // just approved and not everywhere yet): the connection isn't the problem.
            message = L("This plan isn’t available in the App Store right now. Try again later or choose another plan.")
        }
    }

    private func purchase() {
        guard !store.isPurchasing else { return }
        guard selectedPrice != nil else {
            Task { await loadPrices() }
            return
        }
        message = nil
        let tier = tier, period = period
        Telemetry.log("purchase_start", ["tier": tier == .pro ? "pro" : "plus", "period": period == .yearly ? "yearly" : "monthly", "trial": trial(period) == nil ? 0 : 1])
        Task {
            do {
                switch try await store.purchase(tier, period) {
                case .purchased:
                    Haptics.success()
                    // A move to Plus or to another billing period waits for the period to end: say so
                    // instead of closing as if nothing changed.
                    if store.activeProductID == SubscriptionStore.productID(tier, period) {
                        onClose()
                    } else {
                        message = L("Done. Your plan changes when the current billing period ends.")
                    }
                case .pending:
                    message = L("Waiting for approval. Your plan starts as soon as the purchase is approved.")
                case .cancelled:
                    break
                }
            } catch StoreKitError.userCancelled {
                return
            } catch StoreKitError.networkError {
                message = BackendError.offline.errorDescription
            } catch let error as SubscriptionStore.StoreError {
                message = error.errorDescription
            } catch {
                message = L("The purchase didn’t go through. You weren’t charged. Try again.")
            }
        }
    }

    private func restore() {
        guard !isRestoring else { return }
        message = nil
        isRestoring = true
        Task {
            defer { isRestoring = false }
            do {
                if try await store.restore() {
                    Haptics.success()
                    onClose()
                } else {
                    message = L("No active subscription was found for this Apple ID.")
                }
            } catch StoreKitError.userCancelled {
                return
            } catch let error as SubscriptionStore.StoreError {
                message = error.errorDescription
            } catch {
                message = L("Couldn’t restore purchases. Check your connection and try again.")
            }
        }
    }

    private func manageSubscription() {
        Task {
            if let scene = UIApplication.shared.connectedScenes.first(where: { $0.activationState == .foregroundActive }) as? UIWindowScene {
                do {
                    try await AppStore.showManageSubscriptions(in: scene)
                    await store.refreshEntitlements()
                    return
                } catch {}
            }
            if let url = URL(string: "https://apps.apple.com/account/subscriptions") { await UIApplication.shared.open(url) }
        }
    }
}

// Free, Plus and PRO side by side, from the plans' real limits. Opens at the part a benefit was
// about.
struct PlanComparisonView: View {
    enum Topic: String, Identifiable { case all, maps, sources, ai, images; var id: String { rawValue } }

    var focus: Topic = .all
    @Environment(\.dismiss) private var dismiss

    private struct Row: Identifiable {
        let topic: Topic
        let title: String
        let values: [String]      // Free, Plus, PRO; "✓" and "—" read as yes and no
        var id: String { title }
    }

    private var rows: [Row] {
        [
            Row(topic: .maps, title: L("Mind maps a month"), values: ["3", "300", "600"]),
            Row(topic: .maps, title: L("Presentations a month"), values: ["1", "20", "60"]),
            Row(topic: .maps, title: L("Slides in a presentation"), values: ["8", "20", "30"]),
            Row(topic: .sources, title: L("Topic, text, link, document"), values: ["✓", "✓", "✓"]),
            Row(topic: .sources, title: L("YouTube and voice notes"), values: ["—", "✓", "✓"]),
            Row(topic: .sources, title: L("Long documents"), values: ["—", "✓", "✓"]),
            Row(topic: .ai, title: L("Monthly AI allowance"), values: ["1×", "20×", "40×"]),
            Row(topic: .ai, title: L("Chat models"), values: [L("Light (models)"), L("Strong (models)"), L("All (models)")]),
            Row(topic: .images, title: L("AI images a month"), values: ["3", "60", "150"]),
            Row(topic: .all, title: L("People you can invite to a map"), values: ["—", "5", "25"]),
            Row(topic: .all, title: L("Own slide styles and brand"), values: ["—", "✓", "✓"]),
            Row(topic: .all, title: L("PowerPoint export"), values: ["—", "✓", "✓"]),
            Row(topic: .all, title: L("Xmind and MindNode export, map links"), values: ["—", "—", "✓"]),
        ]
    }

    var body: some View {
        VStack(spacing: 0) {
            EditorSheetHeader(title: L("All Features and Limits"), subtitle: L("Limits start over every month"), closeButton: true) { dismiss() }
                .padding(.horizontal, 16)
                .padding(.top, 16)
                .padding(.bottom, 10)
            HStack(spacing: 0) {
                Spacer(minLength: 0)
                ForEach(["Free", "Plus", "PRO"], id: \.self) { name in
                    Text(verbatim: name)
                        .minorFont(13, .semibold, maxScale: 1.3)
                        .foregroundColor(name == "Free" ? MinorColor.textSecondary : .white)
                        .frame(width: 62)
                }
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 6)
            .accessibilityHidden(true)
            ScrollViewReader { reader in
                ScrollView {
                    VStack(spacing: 0) {
                        ForEach(rows) { row in
                            HStack(spacing: 0) {
                                Text(row.title)
                                    .minorFont(14, maxScale: 1.4)
                                    .fixedSize(horizontal: false, vertical: true)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                ForEach(row.values.indices, id: \.self) { i in
                                    Text(verbatim: row.values[i])
                                        .minorFont(14, i == 0 ? .regular : .semibold, maxScale: 1.3)
                                        .foregroundColor(row.values[i] == "—" ? MinorColor.textTertiary : (i == 0 ? MinorColor.textSecondary : .white))
                                        .lineLimit(1)
                                        .minimumScaleFactor(0.7)
                                        .frame(width: 62)
                                }
                            }
                            .padding(.vertical, 12)
                            .background(row.topic == focus && focus != .all ? MinorColor.accent.opacity(0.06) : Color.clear)
                            .overlay(alignment: .bottom) { Rectangle().fill(Color.white.opacity(0.08)).frame(height: 1) }
                            .id(row.id)
                            .accessibilityElement(children: .ignore)
                            .accessibilityLabel(Text("\(row.title). Free: \(spoken(row.values[0])), Plus: \(spoken(row.values[1])), PRO: \(spoken(row.values[2]))"))
                        }
                        Text("Stronger models use the AI allowance faster. People you invite to a map don’t need a subscription.")
                            .minorFont(12, style: .caption1, maxScale: 1.5)
                            .foregroundColor(MinorColor.textTertiary)
                            .fixedSize(horizontal: false, vertical: true)
                            .padding(.top, 12)
                    }
                    .padding(.horizontal, 16)
                    .padding(.bottom, 20)
                }
                .onAppear {
                    if focus != .all, let first = rows.first(where: { $0.topic == focus }) { reader.scrollTo(first.id, anchor: .top) }
                }
            }
        }
        .foregroundColor(.white)
        .background(MinorColor.editorSheet.ignoresSafeArea())
        .preferredColorScheme(.dark)
        .presentationDetents([.large])
    }

    private func spoken(_ value: String) -> String {
        value == "✓" ? L("yes") : value == "—" ? L("no") : value
    }
}
