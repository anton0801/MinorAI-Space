//
//  InviteView.swift
//  Minor Ai
//
//  Invite Friends: the person's code and link, what friends and the inviter get, how many
//  friends joined (at most 3), the discount earned when a friend subscribes, and a field for a
//  friend's code (new accounts).
//

import SwiftUI

struct InviteView: View {
    var initialCode: String?

    @Environment(\.dismiss) private var dismiss
    @ObservedObject private var invites = InviteService.shared
    @ObservedObject private var auth = AuthService.shared
    @ObservedObject private var account = AccountStore.shared
    @State private var loading = false
    @State private var loadError: String?
    @State private var friendCode = ""
    @State private var redeeming = false
    @State private var redeemMessage: String?
    @State private var redeemFailed = false
    @State private var copied = false
    @State private var showSignIn = false
    @State private var claiming: String?
    @State private var discountError: String?

    #if DEBUG
    private var demo: Bool { AccountStore.isDemo }
    #else
    private let demo = false
    #endif

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 20) {
                    hero
                    if !auth.isSignedIn && !demo {
                        signInCard
                    } else if let status = invites.status {
                        codeCard(status)
                        if (status.discountsAvailable ?? 0) > 0 || !(status.discounts ?? []).isEmpty { discountCard(status) }
                        stepsCard(status)
                        statsCard(status)
                        if account.bonusActive || account.bonusDays > 0 { bonusLine }
                        if status.canRedeem { redeemCard }
                        if status.redeemed {
                            Label("You joined with a friend’s invitation.", systemImage: "checkmark.circle.fill")
                                .font(.system(size: 14))
                                .foregroundColor(MinorColor.textSecondary)
                        }
                        rules(status)
                    } else if let loadError {
                        VStack(spacing: 12) {
                            Text(loadError).font(.system(size: 15)).foregroundColor(MinorColor.textSecondary).multilineTextAlignment(.center)
                            Button("Try Again") { Task { await load() } }.foregroundColor(MinorColor.accent)
                        }
                        .padding(.top, 20)
                    } else {
                        ProgressView().tint(.white).padding(.top, 30)
                    }
                }
                .padding(20)
            }
            .foregroundColor(MinorColor.textPrimary)
            .background(MinorColor.sheet.ignoresSafeArea())
            .navigationTitle("Invite Friends")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }.foregroundColor(MinorColor.accent)
                }
            }
        }
        .preferredColorScheme(.dark)
        .sheet(isPresented: $showSignIn) { SignInView(onFinish: { showSignIn = false }) }
        .task(id: auth.session?.userID) {
            if let code = initialCode ?? invites.pendingCode { friendCode = InviteService.clean(code) }
            await load()
        }
    }

    private func load() async {
        guard auth.isSignedIn, !demo else { return }
        loadError = nil
        do {
            try await invites.load()
        } catch {
            loadError = (error as? LocalizedError)?.errorDescription ?? L("Couldn’t load your invitations. Try again.")
        }
    }

    // MARK: - Parts

    private var hero: some View {
        VStack(spacing: 12) {
            Image(systemName: "gift.fill")
                .font(.system(size: 28))
                .foregroundColor(.black)
                .frame(width: 68, height: 68)
                .background(Circle().fill(MinorColor.accent))
                .shadow(color: MinorColor.accent.opacity(0.35), radius: 18)
            Text("Invite Friends, Get Plus")
                .font(.system(size: 24, weight: .bold))
                .multilineTextAlignment(.center)
            Text("Your friends try Minor Plus for free, and you get days of Plus and a discount on a subscription.")
                .font(.system(size: 15))
                .foregroundColor(MinorColor.textSecondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 4)
    }

    private func codeCard(_ status: InviteService.Status) -> some View {
        VStack(spacing: 14) {
            Text("Your Code")
                .textCase(.uppercase)
                .font(.system(size: 12, weight: .semibold))
                .foregroundColor(MinorColor.textTertiary)
            Text(verbatim: status.code)
                .font(.system(size: 34, weight: .heavy, design: .monospaced))
                .tracking(5)
                .foregroundColor(MinorColor.accent)
                .minimumScaleFactor(0.6)
                .lineLimit(1)
                .textSelection(.enabled)
            if status.isFull {
                Text("You’ve invited \(status.friendLimit) friends, the most allowed. Thank you!")
                    .font(.system(size: 14))
                    .foregroundColor(MinorColor.textSecondary)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            } else {
                shareButtons(status)
            }
        }
        .padding(18)
        .frame(maxWidth: .infinity)
        .background(RoundedRectangle(cornerRadius: 16).fill(MinorColor.row))
    }

    private func shareButtons(_ status: InviteService.Status) -> some View {
        HStack(spacing: 10) {
            Button {
                UIPasteboard.general.string = status.code
                withAnimation { copied = true }
                DispatchQueue.main.asyncAfter(deadline: .now() + 1.6) { withAnimation { copied = false } }
            } label: {
                Label(copied ? "Copied" : "Copy", systemImage: copied ? "checkmark" : "doc.on.doc")
                    .font(.system(size: 15, weight: .medium))
                    .frame(maxWidth: .infinity, minHeight: 46)
                    .background(Capsule().strokeBorder(MinorColor.fillThumb, lineWidth: 1))
            }
            .buttonStyle(.plain)
            if let url = status.url {
                Button {
                    Telemetry.log("invite_share")
                    SystemShare.present(text: shareMessage(status), url: url, subject: "Minor AI")
                } label: {
                    Label("Share Invite", systemImage: "square.and.arrow.up")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundColor(.black)
                        .frame(maxWidth: .infinity, minHeight: 46)
                        .background(Capsule().fill(MinorColor.accent))
                }
                .buttonStyle(.plain)
            }
        }
    }

    // Three sentences, so each number gets its own plural form.
    private func shareMessage(_ status: InviteService.Status) -> String {
        [
            L("Try Minor AI: mind maps and presentations from notes, videos and ideas."),
            L("With my invitation you get \(status.days.friend) days of Minor Plus free."),
            L("Code: \(status.code)"),
        ].joined(separator: " ")
    }

    private func stepsCard(_ status: InviteService.Status) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            step("person.badge.plus", "A friend signs up with your code", reward: L("+\(status.days.friend) days of Plus for them"))
            Rectangle().fill(MinorColor.divider.opacity(0.5)).frame(height: 1).padding(.leading, 50)
            step("point.3.connected.trianglepath.dotted", "They make their first map", reward: L("+\(status.days.join) days of Plus for you"))
            Rectangle().fill(MinorColor.divider.opacity(0.5)).frame(height: 1).padding(.leading, 50)
            step("star.fill", "They subscribe to Plus or PRO", reward: L("\(status.percentText) off any subscription for you"))
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 6)
        .background(RoundedRectangle(cornerRadius: 16).fill(MinorColor.row))
    }

    private func step(_ icon: String, _ title: LocalizedStringKey, reward: String) -> some View {
        HStack(spacing: 14) {
            Image(systemName: icon)
                .font(.system(size: 15, weight: .semibold))
                .foregroundColor(MinorColor.accent)
                .frame(width: 36, height: 36)
                .background(Circle().fill(MinorColor.accent.opacity(0.14)))
            VStack(alignment: .leading, spacing: 3) {
                Text(title).font(.system(size: 15, weight: .medium)).fixedSize(horizontal: false, vertical: true)
                Text(verbatim: reward).font(.system(size: 13, weight: .semibold)).foregroundColor(MinorColor.accent)
            }
            Spacer(minLength: 0)
        }
        .padding(.vertical, 12)
        .accessibilityElement(children: .combine)
    }

    private func statsCard(_ status: InviteService.Status) -> some View {
        HStack(spacing: 0) {
            stat(status.friends, "Joined", of: status.friendLimit)
            Rectangle().fill(MinorColor.divider.opacity(0.5)).frame(width: 1, height: 36)
            stat(status.active, "Made a Map")
            Rectangle().fill(MinorColor.divider.opacity(0.5)).frame(width: 1, height: 36)
            stat(status.subscribed, "Subscribed")
        }
        .padding(.vertical, 14)
        .background(RoundedRectangle(cornerRadius: 16).fill(MinorColor.row))
    }

    private func stat(_ value: Int, _ title: LocalizedStringKey, of limit: Int? = nil) -> some View {
        VStack(spacing: 4) {
            Text(verbatim: limit.map { "\(value)/\($0)" } ?? "\(value)").font(.system(size: 22, weight: .bold).monospacedDigit())
            Text(title).font(.system(size: 12)).foregroundColor(MinorColor.textTertiary).lineLimit(1).minimumScaleFactor(0.8)
        }
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .combine)
    }

    // A friend subscribed: pick a subscription to get the discount for, or use a code already taken.
    private func discountCard(_ status: InviteService.Status) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 10) {
                Image(systemName: "tag.fill")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundColor(.black)
                    .frame(width: 32, height: 32)
                    .background(Circle().fill(MinorColor.pro))
                Text("Your \(status.percentText) Discount").font(.system(size: 17, weight: .semibold))
            }
            if (status.discountsAvailable ?? 0) > 0 {
                Text("A friend subscribed. Pick the subscription you want \(status.percentText) off; the App Store will open with your code.")
                    .font(.system(size: 14))
                    .foregroundColor(MinorColor.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
                VStack(spacing: 8) {
                    ForEach(InviteService.discountProducts, id: \.self) { product in
                        Button { claim(product) } label: {
                            HStack {
                                Text(verbatim: InviteService.productName(product)).font(.system(size: 15, weight: .medium))
                                Spacer()
                                if claiming == product {
                                    ProgressView().tint(.white)
                                } else {
                                    Text(verbatim: "−\(status.percent)%").font(.system(size: 14, weight: .bold)).foregroundColor(MinorColor.pro)
                                }
                            }
                            .padding(.horizontal, 14)
                            .frame(minHeight: 46)
                            .background(RoundedRectangle(cornerRadius: 12).fill(MinorColor.track))
                        }
                        .buttonStyle(.plain)
                        .disabled(claiming != nil)
                    }
                }
            }
            ForEach(status.discounts ?? []) { discount in
                HStack(spacing: 10) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(verbatim: InviteService.productName(discount.product)).font(.system(size: 15, weight: .medium))
                        Text(verbatim: discount.code)
                            .font(.system(size: 13, weight: .semibold, design: .monospaced))
                            .foregroundColor(MinorColor.textTertiary)
                            .textSelection(.enabled)
                    }
                    Spacer()
                    Button { if let url = URL(string: discount.url) { UIApplication.shared.open(url) } } label: {
                        Text("Use")
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundColor(.black)
                            .padding(.horizontal, 18)
                            .frame(minHeight: 38)
                            .background(Capsule().fill(MinorColor.accent))
                    }
                    .buttonStyle(.plain)
                }
            }
            if let discountError {
                Text(discountError).font(.system(size: 13)).foregroundColor(MinorColor.dangerText).fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 16).strokeBorder(MinorColor.pro.opacity(0.6), lineWidth: 1))
    }

    private func claim(_ product: String) {
        claiming = product
        discountError = nil
        Task {
            do {
                let discount = try await invites.claimDiscount(product: product)
                if let url = URL(string: discount.url) { await UIApplication.shared.open(url) }
            } catch {
                discountError = (error as? LocalizedError)?.errorDescription ?? L("Couldn’t get the discount. Try again.")
            }
            claiming = nil
        }
    }

    private var bonusLine: some View {
        VStack(alignment: .leading, spacing: 4) {
            if account.bonusActive, let until = account.bonusUntil {
                Label("Minor Plus from invitations until \(UsageView.day(until)).", systemImage: "sparkles")
                    .font(.system(size: 15, weight: .medium))
            }
            if account.bonusDays > 0 {
                Text("Days of Plus waiting: \(account.bonusDays). They start when your subscription ends.")
                    .font(.system(size: 13))
                    .foregroundColor(MinorColor.textSecondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .background(RoundedRectangle(cornerRadius: 16).strokeBorder(MinorColor.accent.opacity(0.5), lineWidth: 1))
    }

    private var redeemCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Got a Code from a Friend?").font(.system(size: 17, weight: .semibold))
            Text("Enter it within 14 days after creating your account.")
                .font(.system(size: 13))
                .foregroundColor(MinorColor.textTertiary)
            HStack(spacing: 10) {
                TextField("", text: $friendCode, prompt: Text(verbatim: "XXXXXXXX").foregroundColor(MinorColor.textTertiary))
                    .font(.system(size: 20, weight: .semibold, design: .monospaced))
                    .tracking(3)
                    .textInputAutocapitalization(.characters)
                    .autocorrectionDisabled()
                    .onChange(of: friendCode) { value in
                        let clean = InviteService.clean(value)
                        if clean != value { friendCode = clean }
                    }
                    .padding(.horizontal, 14)
                    .frame(height: 50)
                    .background(RoundedRectangle(cornerRadius: 12).fill(MinorColor.track))
                    .accessibilityLabel("Friend’s code")
                Button { redeem() } label: {
                    Group {
                        if redeeming { ProgressView().tint(.black) } else { Text("Apply").font(.system(size: 16, weight: .semibold)) }
                    }
                    .foregroundColor(InviteService.isValid(friendCode) ? .black : MinorColor.textSecondary)
                    .padding(.horizontal, 18)
                    .frame(minWidth: 92, minHeight: 50)
                    .background(Capsule().fill(InviteService.isValid(friendCode) ? MinorColor.accent : MinorColor.fillThumb))
                    .fixedSize()
                }
                .buttonStyle(.plain)
                .disabled(!InviteService.isValid(friendCode) || redeeming)
            }
            if let redeemMessage {
                Text(redeemMessage)
                    .font(.system(size: 14))
                    .foregroundColor(redeemFailed ? MinorColor.dangerText : MinorColor.accent)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(18)
        .background(RoundedRectangle(cornerRadius: 16).fill(MinorColor.row))
    }

    private func rules(_ status: InviteService.Status) -> some View {
        Text("Up to \(status.friendLimit) friends per code. Free Plus has a smaller AI allowance than a subscription; if you already subscribe, the days wait and start when it ends. The discount is an App Store offer code for the subscription you pick. One invitation per iPhone; a friend’s code works for new accounts.")
            .font(.system(size: 12))
            .foregroundColor(MinorColor.textTertiary)
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var signInCard: some View {
        VStack(spacing: 14) {
            Text("Sign in to get your code and invite friends.")
                .font(.system(size: 15))
                .foregroundColor(MinorColor.textSecondary)
                .multilineTextAlignment(.center)
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

    private func redeem() {
        redeeming = true
        redeemMessage = nil
        Task {
            do {
                let days = try await invites.redeem(friendCode)
                Telemetry.log("invite_redeem", ["days": days])
                redeemFailed = false
                redeemMessage = L("Done! You have \(days) days of Minor Plus.")
                friendCode = ""
            } catch {
                redeemFailed = true
                redeemMessage = (error as? LocalizedError)?.errorDescription ?? L("Couldn’t apply the code. Try again.")
            }
            redeeming = false
        }
    }
}
