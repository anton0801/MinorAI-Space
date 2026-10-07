//
//  Telemetry.swift
//  Minor Ai
//
//  Anonymous usage statistics with Google Analytics for Firebase: which features people use and
//  where they stop (onboarding, paywall), so the app can get better. No advertising ID, no account
//  ID, no map, chat or document content: only event names and small parameters (a map's source
//  kind, a plan, a format). The Firebase product is FirebaseAnalyticsCore (no ad modules).
//
//  Off when GoogleService-Info.plist isn't in the app, under tests, and in DEBUG builds unless the
//  "-analytics" launch argument is passed (add "-FIRDebugEnabled" to see events in DebugView).
//

import FirebaseAnalytics
import FirebaseCore
import StoreKit

@MainActor
enum Telemetry {
    private(set) static var isConfigured = false

    // Called first thing at launch.
    static func start() {
        guard !isConfigured, Bundle.main.path(forResource: "GoogleService-Info", ofType: "plist") != nil else { return }
        if ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil { return }
        #if DEBUG
        guard ProcessInfo.processInfo.arguments.contains("-analytics") else { return }
        #endif
        FirebaseApp.configure()
        isConfigured = true
        // Usage statistics only, nothing for ads.
        Analytics.setConsent([.analyticsStorage: .granted, .adStorage: .denied, .adUserData: .denied, .adPersonalization: .denied])
        Analytics.setUserProperty(AppLanguage.current.code, forName: "app_language")
    }

    // An event: a snake_case name (up to 40 characters) and up to 25 short parameters.
    static func log(_ name: String, _ parameters: [String: Any] = [:]) {
        guard isConfigured else { return }
        Analytics.logEvent(name, parameters: parameters.isEmpty ? nil : parameters)
    }

    // The plan people pay for, so reports can be split by it.
    static func setPlan(_ plan: String) {
        guard isConfigured else { return }
        Analytics.setUserProperty(plan, forName: "plan")
    }

    // A completed App Store purchase (StoreKit 2), for Firebase's revenue and purchase reports.
    static func purchase(_ transaction: Transaction) {
        guard isConfigured else { return }
        Analytics.logTransaction(transaction)
    }
}
