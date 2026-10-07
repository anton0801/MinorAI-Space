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
                .modifier(LaunchReveal())
        }
        .onChange(of: scenePhase) { phase in
            switch phase {
            case .active:
                // Renewals, refunds, Ask to Buy approvals and the new month's limits.
                Task { await SharedMaps.retryPendingStops() }
                MapSync.shared.syncSoon()
                WidgetBridge.shared.refresh()
                Task { await CollabService.shared.refreshAll() }
                Task {
                    await SubscriptionStore.shared.refreshIfStale()
                    await AccountStore.shared.refresh()
                }
            case .background:
                // Make sure maps and chats reach the disk before iOS may suspend the app.
                MapStore.shared.flush()
                DeckStore.shared.flush()
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
        Telemetry.start()
        LaunchSplash.shared.install()
        UNUserNotificationCenter.current().delegate = self
        // Earlier test builds could keep provider API keys on the device; AI now runs only on
        // the server, so any leftover keys are erased.
        for key in ["AnthropicAPIKey", "OpenAIAPIKey"] { UserDefaults.standard.removeObject(forKey: key) }
        Task { @MainActor in
            MapStore.shared.removeUnusedImages(keeping: DeckStore.shared.imageIDs.union(LookStore.shared.imageIDs).union(TemplateStore.shared.imageIDs))
            Reminders.shared.start()
            MapSync.shared.start()
            WidgetBridge.shared.start()
            CalendarSync.shared.start()
            CollabService.shared.start()
            PushService.shared.start()
            await PushService.shared.registerIfAllowed()
        }
        return true
    }

    func application(_ application: UIApplication, didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data) {
        Task { @MainActor in PushService.shared.didRegister(deviceToken) }
    }

    func application(_ application: UIApplication, didFailToRegisterForRemoteNotificationsWithError error: Error) {
        print("push registration failed:", error.localizedDescription)
    }

    // A TV or display (AirPlay or a cable) gets its own scene that shows the presented slide;
    // everything else is the app's SwiftUI window.
    func application(_ application: UIApplication, configurationForConnecting connectingSceneSession: UISceneSession, options: UIScene.ConnectionOptions) -> UISceneConfiguration {
        if connectingSceneSession.role == .windowExternalDisplayNonInteractive {
            let configuration = UISceneConfiguration(name: "External Display", sessionRole: connectingSceneSession.role)
            configuration.delegateClass = ExternalDisplayDelegate.self
            return configuration
        }
        return UISceneConfiguration(name: nil, sessionRole: connectingSceneSession.role)
    }

    func userNotificationCenter(_ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse) async {
        let info = response.notification.request.content.userInfo
        if let route = (info["route"] as? String).flatMap(URL.init(string:)) {
            await MainActor.run { GenerationCenter.shared.routeRequest = route }
            return
        }
        guard let raw = info["mapID"] as? String, let id = UUID(uuidString: raw) else { return }
        let node = (info["nodeID"] as? String).flatMap(UUID.init(uuidString:))
        await MainActor.run {
            GenerationCenter.shared.ready = nil
            GenerationCenter.shared.focusNode = node
            GenerationCenter.shared.openRequest = id
        }
    }

    func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification) async -> UNNotificationPresentationOptions {
        // Task reminders and the server's notifications show while the app is open too; for
        // "map is ready" the app shows its own toast.
        if notification.request.trigger is UNPushNotificationTrigger { return [.banner, .list, .sound] }
        return notification.request.identifier.hasPrefix("task-") ? [.banner, .sound] : []
    }
}
