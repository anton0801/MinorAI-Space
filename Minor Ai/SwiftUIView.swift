//
//  SwiftUIView.swift
//  Minor Ai
//
//  Created by Stefano  on 13/3/25.
//

import SwiftUI
import UserNotifications

@main
struct MinorApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @Environment(\.scenePhase) private var scenePhase
    @StateObject private var language = LanguageSettings.shared

    var body: some Scene {
        WindowGroup {
            ContentView()
                .preferredColorScheme(.dark)
                // The language picked in Settings, applied at once: a new language rebuilds the screen.
                .environment(\.locale, language.language.locale)
                .id(language.language)
        }
        .onChange(of: scenePhase) { phase in
            switch phase {
            case .active:
                // Renewals, refunds, Ask to Buy approvals and the new month's limits.
                Task { await SharedMaps.retryPendingStops() }
                MapSync.shared.syncSoon()
                WidgetBridge.shared.refresh()
                Task {
                    await SubscriptionStore.shared.refreshIfStale()
                    await AccountStore.shared.refresh()
                }
            case .background:
                // Make sure maps and chats reach the disk before iOS may suspend the app.
                MapStore.shared.flush()
                ConversationStore.shared.flush()
            default:
                break
            }
        }
    }
}

// Opens a map when the user taps its "ready" notification.
final class AppDelegate: NSObject, UIApplicationDelegate, UNUserNotificationCenterDelegate {
    func application(_ application: UIApplication, didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil) -> Bool {
        UNUserNotificationCenter.current().delegate = self
        // Earlier test builds could keep provider API keys on the device; AI now runs only on
        // the server, so any leftover keys are erased.
        for key in ["AnthropicAPIKey", "OpenAIAPIKey"] { UserDefaults.standard.removeObject(forKey: key) }
        Task { @MainActor in
            Reminders.shared.start()
            MapSync.shared.start()
            WidgetBridge.shared.start()
        }
        return true
    }

    func userNotificationCenter(_ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse) async {
        let info = response.notification.request.content.userInfo
        guard let raw = info["mapID"] as? String, let id = UUID(uuidString: raw) else { return }
        let node = (info["nodeID"] as? String).flatMap(UUID.init(uuidString:))
        await MainActor.run {
            GenerationCenter.shared.ready = nil
            GenerationCenter.shared.focusNode = node
            GenerationCenter.shared.openRequest = id
        }
    }

    func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification) async -> UNNotificationPresentationOptions {
        // Task reminders show while the app is open too; for "map is ready" the app shows its own toast.
        notification.request.identifier.hasPrefix("task-") ? [.banner, .sound] : []
    }
}
