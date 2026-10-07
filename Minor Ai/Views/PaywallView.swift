//
//  PaywallView.swift
//  Minor Ai
//
//  Minor Plus / PRO paywall: plan and billing period, the App Store price in the person's currency,
//  the auto-renewal terms Apple requires, Terms of Use, Privacy Policy and Restore Purchases.
//  Scrolls on small screens and with large text; particles stand still with Reduce Motion.
//

import StoreKit
import SwiftUI

struct PaywallView: View {
    var onClose: () -> Void

    @ObservedObject private var store = SubscriptionStore.shared
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var tier: SubscriptionStore.Tier
    // Yearly first: the better deal, and the plan most people keep.
    @State private var period: SubscriptionStore.Period = .yearly
    @State private var message: String?
    @State private var isRestoring = false
    @State private var isLoadingPrices = false
    @State private var showAdvantages = false
    @State private var appeared = false
    @State private var sweep = false

    init(tier: SubscriptionStore.Tier, onClose: @escaping () -> Void) {
        _tier = State(initialValue: tier)
        self.onClose = onClose
    }

    static var plusFeatures: [String] {
        [
            L("Up to 300 mind maps a month"),
            L("YouTube and voice maps, long documents"),
            L("Advanced maps with Claude Opus 5.5"),
            L("20× more AI for chat, with any model"),
            L("60 AI images a month, in chat and on maps"),
        ]
    }

    static var proFeatures: [String] {
        [
            L("Everything in Plus, up to 600 maps a month"),
            L("Frontier maps with GPT-6 Astra and Claude Fable 5.1"),
            L("40× more AI for chat than the free plan"),
            L("150 AI images a month"),
            L("Export to Xmind and MindNode, share links"),
        ]
    }

    // iPhone SE and other short screens: a smaller logo and particle band keep the price on screen.
    private let compact = UIScreen.main.bounds.height < 700

    private var isCurrentPlan: Bool { store.activeProductID == SubscriptionStore.productID(tier, period) }
    private var billedPrice: String? { store.billedPrice(tier, period) }
    // "3 days" when this plan starts with a free trial for this Apple ID.
    private var trial: String? { isCurrentPlan ? nil : store.freeTrial(tier, period) }

    var body: some View {
        ZStack(alignment: .topLeading) {
            BlurView(style: .dark)
                .ignoresSafeArea()
                .accessibilityHidden(true)

            ScrollView(showsIndicators: false) {
                VStack(spacing: 0) {
                    Image("Biglogo")
                        .resizable()
                        .scaledToFit()
                        .frame(width: compact ? 76 : 130, height: compact ? 76 : 130)
                        .scaleEffect(appeared || reduceMotion ? 1 : 0.7)
                        .rotationEffect(.degrees(appeared || reduceMotion ? 0 : -10))
                        .accessibilityHidden(true)

                    Text(tier == .plus ? "Minor Plus" : "Minor PRO")
                        .minorFont(26, .bold, style: .title1, maxScale: 1.3)
                        .foregroundColor(tier == .plus ? .white : MinorColor.pro)
                        .padding(.top, 4)
                        .accessibilityAddTraits(.isHeader)

                    featureCard
                        .padding(.top, compact ? 12 : 20)

                    VStack(spacing: 12) {
                        PlanSwitch(
                            selection: $period,
                            left: (.monthly, L("Monthly"), nil),
                            right: (.yearly, L("Yearly"), store.yearlySavings(tier).map { "−\($0)%" })
                        )
                        PlanSwitch(
                            selection: $tier,
                            left: (.plus, "Plus", nil),
                            right: (.pro, "PRO", nil),
                            rightColor: MinorColor.pro
                        )
                    }
                    .frame(maxWidth: 300)
                    .padding(.top, compact ? 12 : 20)

                    PaywallParticles(paused: reduceMotion)
                        .frame(height: compact ? 36 : 96)
                        .accessibilityHidden(true)

                    // Above the button, smaller than the price: Apple wants the amount billed to be
                    // the most prominent price on the screen.
                    if let trial, billedPrice != nil {
                        Label(L("\(trial) free"), systemImage: "gift.fill")
                            .minorFont(14, .semibold, style: .subheadline, maxScale: 1.4)
                            .foregroundColor(MinorColor.accent)
                            .padding(.horizontal, 14)
                            .padding(.vertical, 6)
                            .background(Capsule().fill(MinorColor.accent.opacity(0.14)))
                            .padding(.bottom, 10)
                            .accessibilityHidden(true)
                    }

                    priceButton

                    if let detail = priceDetail {
                        Text(detail)
                            .minorFont(13, style: .footnote)
                            .foregroundColor(MinorColor.textSecondary)
                            .multilineTextAlignment(.center)
                            .padding(.top, 10)
                    }

                    if let message {
                        Text(message)
                            .minorFont(13, .medium, style: .footnote)
                            .foregroundColor(.white)
                            .multilineTextAlignment(.center)
                            .padding(.top, 10)
                            .accessibilityAddTraits(.updatesFrequently)
                    }

                    Text("Payment is charged to your Apple ID when you confirm the purchase. The subscription renews automatically at the same price and period unless you cancel it at least 24 hours before the current period ends. Manage or cancel it anytime in your App Store account settings. Each plan includes a monthly AI allowance; stronger models use more of it.")
                        .minorFont(11, style: .caption2, maxScale: 1.8)
                        .foregroundColor(MinorColor.textTertiary)
                        .multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.top, 14)

                    links
                        .padding(.top, 14)
                }
                .padding(.horizontal, 16)
                .padding(.top, compact ? 8 : 36)
                .padding(.bottom, 20)
                .frame(maxWidth: 440)
                .frame(maxWidth: .infinity)
            }

            Button(action: onClose) {
                Image(systemName: "xmark")
                    .font(.system(size: 14, weight: .bold))
                    .foregroundColor(.white)
                    .frame(width: 30, height: 30)
                    .background(Circle().fill(MinorColor.closeFill.opacity(0.8)))
                    .frame(width: 44, height: 44)
                    .contentShape(Rectangle())
            }
            .padding(.leading, 8)
            .accessibilityLabel("Close")
        }
        .foregroundColor(.white)
        .accessibilityElement(children: .contain)
        .accessibilityAddTraits(.isModal)
        .accessibilityAction(.escape, onClose)
        .onAppear {
            withAnimation(.spring(response: 1.0, dampingFraction: 0.8).delay(0.1)) { appeared = true }
            // Someone who already pays sees their own billing period first (monthly or yearly).
            if let current = store.activeProductID {
                period = current.hasSuffix("MonthlyPlan") ? .monthly : .yearly
            }
        }
        .task {
            if store.products.isEmpty { await loadPrices() }
        }
        .task(id: reduceMotion) {
            guard !reduceMotion else { return }
            // The light sweep across the price button, every few seconds.
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 4_000_000_000)
                sweep = false
                try? await Task.sleep(nanoseconds: 50_000_000)
                withAnimation(.linear(duration: 0.6)) { sweep = true }
            }
        }
        .onChange(of: tier) { _ in message = nil }
        .onChange(of: period) { _ in message = nil }
        .sheet(isPresented: $showAdvantages) { PremiumAdvantagesView() }
    }

    // MARK: - Parts

    private var featureCard: some View {
        VStack(alignment: .leading, spacing: 13) {
            ForEach(tier == .plus ? Self.plusFeatures : Self.proFeatures, id: \.self) { feature in
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Image(systemName: "checkmark")
                        .minorFont(15)
                        .accessibilityHidden(true)
                    Text(feature)
                        .minorFont(17)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.leading, 20)
        .padding(.trailing, 44)
        .padding(.vertical, 22)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(Color(hex: "#252525"))
                .overlay(RoundedRectangle(cornerRadius: 16).stroke(Color(hex: "#6A6A6A"), lineWidth: 1))
        )
        .overlay(alignment: .topTrailing) {
            Button { showAdvantages = true } label: {
                Image(systemName: "info.circle")
                    .font(.system(size: 20))
                    .frame(width: 44, height: 44)
                    .contentShape(Rectangle())
            }
            .accessibilityLabel("Premium advantages")
        }
        .animation(.easeInOut(duration: 0.25), value: tier)
    }

    private var priceButton: some View {
        Button(action: purchase) {
            ZStack {
                RoundedRectangle(cornerRadius: 16).fill(MinorColor.premium)
                GeometryReader { geo in
                    LinearGradient(colors: [.clear, MinorColor.sweep, .clear], startPoint: .leading, endPoint: .trailing)
                        .frame(width: 50)
                        .offset(x: sweep ? geo.size.width : -50)
                        .opacity(sweep ? 1 : 0)
                }
                priceLabel
            }
            .frame(minHeight: 60)
            .clipShape(RoundedRectangle(cornerRadius: 16))
            .contentShape(RoundedRectangle(cornerRadius: 16))
        }
        .buttonStyle(.plain)
        .disabled(store.isPurchasing || isCurrentPlan || isLoadingPrices)
        .accessibilityLabel(priceAccessibilityLabel)
    }

    @ViewBuilder
    private var priceLabel: some View {
        if store.isPurchasing || (billedPrice == nil && isLoadingPrices) {
            ProgressView().tint(.white)
        } else if isCurrentPlan {
            Text("Your Current Plan").minorFont(18, .bold, maxScale: 1.3)
        } else if let billedPrice {
            Text(billedPrice)
                .minorFont(20, .bold, maxScale: 1.3)
                .padding(.vertical, 8)
        } else {
            Text("Load Prices").minorFont(18, .bold, maxScale: 1.3)
        }
    }

    private var priceAccessibilityLabel: String {
        if isCurrentPlan { return L("Your current plan") }
        guard let billedPrice else { return L("Load prices") }
        let subscribe = L("Subscribe to Minor \(tier == .plus ? "Plus" : "PRO") for \(billedPrice)")
        return trial.map { subscribe + ", " + L("\($0) free") } ?? subscribe
    }

    private var priceDetail: String? {
        guard let price = store.price(tier, period), !isCurrentPlan else { return nil }
        let billing: String
        switch (period, trial) {
        case (.monthly, nil):
            billing = L("\(price) billed every month. Cancel anytime.")
        case (.monthly, let trial?):
            billing = L("\(trial) free, then \(price) billed every month. Cancel anytime.")
        case (.yearly, let trial):
            let perMonth = store.monthlyEquivalent(tier).map { " (\($0))" } ?? ""
            billing = trial.map { L("\($0) free, then \(price) billed every year\(perMonth). Cancel anytime.") }
                ?? L("\(price) billed every year\(perMonth). Cancel anytime.")
        }
        return [billing, switchNote].compactMap { $0 }.joined(separator: " ")
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
            HStack(spacing: 14) { linkItems(separator: true) }
            VStack(spacing: 6) { linkItems(separator: false) }
        }
        .minorFont(12, style: .caption1, maxScale: 1.6)
        .foregroundColor(.white)
    }

    @ViewBuilder
    private func linkItems(separator: Bool) -> some View {
        Link("Terms of Use", destination: LegalLinks.terms)
            .frame(minHeight: 32)
        if separator { Text("|").accessibilityHidden(true) }
        Link("Privacy Policy", destination: LegalLinks.privacy)
            .frame(minHeight: 32)
        if separator { Text("|").accessibilityHidden(true) }
        Button(isRestoring ? "Restoring…" : "Restore Purchases", action: restore)
            .disabled(isRestoring)
            .frame(minHeight: 32)
    }

    // MARK: - Actions

    private func loadPrices() async {
        isLoadingPrices = true
        await store.loadProducts()
        isLoadingPrices = false
        if store.products.isEmpty {
            message = L("Couldn’t load prices from the App Store. Check your connection and try again.")
        } else if billedPrice == nil {
            // The App Store answered without this plan (not available in this country yet, or
            // just approved and not everywhere yet): the connection isn't the problem.
            message = L("This plan isn’t available in the App Store right now. Try again later or choose another plan.")
        }
    }

    private func purchase() {
        guard billedPrice != nil else {
            message = nil
            Task { await loadPrices() }
            return
        }
        message = nil
        Telemetry.log("purchase_start", ["tier": tier == .pro ? "pro" : "plus", "period": period == .yearly ? "yearly" : "monthly", "trial": trial == nil ? 0 : 1])
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
}

// Two-option capsule switch (Monthly / Yearly, Plus / PRO).
private struct PlanSwitch<Value: Hashable>: View {
    @Binding var selection: Value
    let left: (value: Value, title: String, badge: String?)
    let right: (value: Value, title: String, badge: String?)
    var rightColor: Color = .white

    var body: some View {
        HStack(spacing: 0) {
            option(left, color: .white)
            option(right, color: rightColor)
        }
        .background(alignment: .leading) {
            GeometryReader { geo in
                Capsule()
                    .fill(Color.white.opacity(0.2))
                    .frame(width: geo.size.width / 2)
                    .offset(x: selection == left.value ? 0 : geo.size.width / 2)
                    .animation(.spring(response: 0.4, dampingFraction: 0.8), value: selection)
            }
        }
        .background(Capsule().fill(Color(hex: "#1C1C1C")))
        .overlay(Capsule().stroke(Color(hex: "#6A6A6A"), lineWidth: 1))
        .clipShape(Capsule())
    }

    private func option(_ item: (value: Value, title: String, badge: String?), color: Color) -> some View {
        let selected = selection == item.value
        return Button {
            withAnimation(.easeInOut(duration: 0.3)) { selection = item.value }
            Haptics.selection()
        } label: {
            HStack(spacing: 6) {
                Text(item.title)
                    .minorFont(16, .medium, maxScale: 1.4)
                    .foregroundColor(selected ? color : MinorColor.textSecondary)
                if let badge = item.badge {
                    Text(badge)
                        .minorFont(11, .semibold, style: .caption2, maxScale: 1.4)
                        .foregroundColor(.black)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Capsule().fill(MinorColor.accent))
                        .accessibilityLabel(L("save \(String(badge.dropFirst()))"))
                }
            }
            .frame(maxWidth: .infinity, minHeight: 40)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }
}

// The paywall's drifting stars, lamps and rockets, computed from time (no per-frame state).
private struct PaywallParticles: View {
    var paused: Bool

    private struct Seed {
        let image: String
        let size: CGFloat
        let x: CGFloat
        let y: CGFloat
        let speed: CGFloat
        let wobble: CGFloat
        let phase: CGFloat
        let spin: Double
    }

    @State private var start = Date()
    private let seeds: [Seed] = {
        var generator = SystemRandomNumberGenerator()
        func make(_ images: [String], size: CGFloat, speed: ClosedRange<CGFloat>) -> [Seed] {
            (0..<25).map { _ in
                Seed(
                    image: images.randomElement(using: &generator)!,
                    size: size,
                    x: .random(in: 0...1, using: &generator),
                    y: .random(in: 0.1...0.9, using: &generator),
                    speed: .random(in: speed, using: &generator) * (Bool.random(using: &generator) ? 1 : -1),
                    wobble: .random(in: 3...12, using: &generator),
                    phase: .random(in: 0...(2 * .pi), using: &generator),
                    spin: .random(in: 15...60, using: &generator) * (Bool.random(using: &generator) ? 1 : -1)
                )
            }
        }
        return make(["GStar", "GLamp", "GLaunch"], size: 15, speed: 12...40) + make(["Star", "Lamp", "Launch"], size: 20, speed: 15...55)
    }()

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 30, paused: paused)) { timeline in
            Canvas { context, size in
                let t = CGFloat(timeline.date.timeIntervalSince(start))
                let span = size.width + 60
                var images: [String: GraphicsContext.ResolvedImage] = [:]
                for seed in seeds {
                    let image = images[seed.image] ?? context.resolve(Image(seed.image))
                    images[seed.image] = image
                    var x = (seed.x * span + seed.speed * t).truncatingRemainder(dividingBy: span)
                    if x < 0 { x += span }
                    let y = seed.y * size.height + sin(t * 0.7 + seed.phase) * seed.wobble
                    var layer = context
                    layer.translateBy(x: x - 30, y: y)
                    layer.rotate(by: .degrees(Double(t) * seed.spin))
                    layer.draw(image, in: CGRect(x: -seed.size / 2, y: -seed.size / 2, width: seed.size, height: seed.size))
                }
            }
        }
        .mask(LinearGradient(colors: [.clear, .black, .black, .clear], startPoint: .leading, endPoint: .trailing))
    }
}

// What a subscription adds, opened from the (i) button on the paywall.
struct PremiumAdvantagesView: View {
    @Environment(\.dismiss) private var dismiss

    static var items: [(icon: String, color: Color, text: String)] {
        [
            ("map", Color(hex: "#CC3399"), L("Build up to 300 mind maps a month with Plus and 600 with PRO, from any topic, link, document, video or voice note.")),
            ("brain", Color(hex: "#9966CC"), L("Build maps with the strongest models: Claude Opus 5.5 with Plus, GPT-6 Astra and Claude Fable 5.1 with PRO.")),
            ("sparkles", Color(hex: "#3380FF"), L("Chat with any model, from GPT-6 Luna to Claude Fable 5.1. Plus gives 20× and PRO 40× the free monthly AI allowance; stronger models use it faster.")),
            ("photo.on.rectangle", Color(hex: "#FFD66B"), L("Create images in chat and add pictures to your ideas: 60 a month with Plus, 150 with PRO.")),
            ("rectangle.on.rectangle.angled", Color(hex: "#2FFF9E"), L("Make presentations from your maps with AI: 20 a month with up to 20 slides with Plus, 60 with up to 30 slides with PRO, with PowerPoint export.")),
            ("paintbrush.pointed", Color(hex: "#C9A2FF"), L("Design presentations your way: own styles and a brand, charts, tables and photos on slides, animations, an AI designer and your own templates.")),
            ("person.2", Color(hex: "#FC86C3"), L("Edit maps together: invite up to 5 people to a map with Plus and 25 with PRO, as editors or viewers. They don’t need a subscription.")),
            ("play.rectangle", Color(hex: "#66B3E6"), L("Turn YouTube videos, voice notes and long documents into clear maps.")),
            ("bubble.left", Color(hex: "#0A84FF"), L("Expand, summarize and explore your ideas with AI, and add chat answers back to your map.")),
            ("square.and.arrow.up", Color(hex: "#FF3366"), L("With PRO, export maps to Xmind and MindNode and share them with a link.")),
        ]
    }

    var body: some View {
        VStack(spacing: 0) {
            ZStack {
                Text("Premium Advantage")
                    .minorFont(18, .bold, style: .headline, maxScale: 1.3)
                    .accessibilityAddTraits(.isHeader)
                HStack {
                    Spacer()
                    Button { dismiss() } label: {
                        Image(systemName: "xmark")
                            .font(.system(size: 16, weight: .bold))
                            .frame(width: 30, height: 30)
                            .background(Circle().fill(MinorColor.closeFill))
                            .frame(width: 44, height: 44)
                    }
                    .accessibilityLabel("Close")
                }
            }
            .padding(.top, 16)

            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 28) {
                    ForEach(Self.items, id: \.text) { item in
                        HStack(alignment: .top, spacing: 12) {
                            Image(systemName: item.icon)
                                .foregroundColor(item.color)
                                .font(.system(size: 20))
                                .frame(width: 26)
                                .accessibilityHidden(true)
                            Text(item.text)
                                .minorFont(15)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        .accessibilityElement(children: .combine)
                    }
                }
                .padding(.top, 28)
                .padding(.bottom, 20)
            }
        }
        .padding(.horizontal, 20)
        .foregroundColor(.white)
        .background(MinorColor.sheet.ignoresSafeArea())
        .presentationDetents([.large])
    }
}
