//
//  AIConsentView.swift
//  Minor Ai
//
//  One-time permission before anything is sent to a third-party AI provider
//  (App Store Review Guideline 5.1.2(i)).
//

import SwiftUI

enum AIConsent {
    private static let key = "aiConsentGiven"

    static var isGiven: Bool { UserDefaults.standard.bool(forKey: key) }

    static func give() { UserDefaults.standard.set(true, forKey: key) }

    static func revoke() { UserDefaults.standard.removeObject(forKey: key) }
}

struct AIConsentView: View {
    var onAllow: () -> Void
    var onDecline: () -> Void

    var body: some View {
        // The explanation scrolls; the two choices stay on screen at any sheet height and text size.
        VStack(spacing: 0) {
            Capsule().fill(MinorColor.fillThumb).frame(width: 36, height: 5).padding(.top, 8)
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    Image(systemName: "sparkles")
                        .font(.system(size: 28))
                        .padding(.top, 8)
                        .accessibilityHidden(true)
                    Text("Before Minor Answers")
                        .font(.system(size: 22, weight: .bold))
                        .accessibilityAddTraits(.isHeader)
                    Text("To build maps and answer questions, Minor sends what you type, the files and photos you attach, and your voice transcripts to OpenAI or Anthropic. They process it to create the answer and don’t use it to train their models. Your name and email are not sent.")
                        .font(.system(size: 15))
                        .foregroundColor(MinorColor.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                    Link("Read the Privacy Policy", destination: LegalLinks.privacy)
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundColor(MinorColor.textPrimary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.bottom, 12)
            }
            Button {
                AIConsent.give()
                onAllow()
            } label: {
                Text("Allow and Continue")
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundColor(.black)
                    .frame(maxWidth: .infinity)
                    .frame(minHeight: 50)
                    .background(Capsule().fill(MinorColor.sendFill))
            }
            .padding(.top, 8)
            Button("Not Now", action: onDecline)
                .font(.system(size: 17))
                .foregroundColor(MinorColor.textSecondary)
                .frame(maxWidth: .infinity)
                .frame(minHeight: 44)
        }
        .foregroundColor(MinorColor.textPrimary)
        .padding(.horizontal, 24)
        .padding(.bottom, 12)
        .background(MinorColor.sheet.ignoresSafeArea())
        .presentationDetents([.medium, .large])
        .interactiveDismissDisabled()
    }
}

// Public pages the app links to (the website lives in the repo's website/ folder).
enum LegalLinks {
    static let privacy = URL(string: "https://minorai.site/privacy/")!
    static let support = URL(string: "https://minorai.site/support/")!
    // Apple's standard EULA works as the Terms of Use for App Store subscriptions.
    static let terms = URL(string: "https://www.apple.com/legal/internet-services/itunes/dev/stdeula/")!

    static var agreement: AttributedString {
        let markdown = L("By continuing you agree to the [Terms of Use](\(terms.absoluteString)) and [Privacy Policy](\(privacy.absoluteString)).")
        return (try? AttributedString(markdown: markdown)) ?? AttributedString(markdown)
    }
}
