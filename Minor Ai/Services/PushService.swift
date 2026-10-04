//
//  PushService.swift
//  Minor Ai
//
//  Remote notifications from Minor's server through Apple (APNs): this device's token for the
//  signed-in person, what they want to hear about, and the events the app reports (a shared map
//  was saved, someone joined, a role changed). The server decides who gets a notification.
//

import Combine
import UIKit
import UserNotifications

@MainActor
final class PushService: ObservableObject {
    static let shared = PushService()

    // Changes and people in shared maps.
    @Published var collab: Bool {
        didSet { UserDefaults.standard.set(collab, forKey: Keys.collab); Task { await upload() } }
    }
    // Invitations, rewards and the AI allowance.
    @Published var account: Bool {
        didSet { UserDefaults.standard.set(account, forKey: Keys.account); Task { await upload() } }
    }
    @Published private(set) var allowed = false

    private enum Keys {
        static let collab = "push.collab"
        static let account = "push.account"
        static let token = "push.token"
        static let uploaded = "push.uploaded"
        static let uploadedAt = "push.uploadedAt"
    }

    private var token: String? { UserDefaults.standard.string(forKey: Keys.token) }
    private var sessionWatch: AnyCancellable?
    private var lastChanged: [UUID: Date] = [:]

    private init() {
        collab = UserDefaults.standard.object(forKey: Keys.collab) as? Bool ?? true
        account = UserDefaults.standard.object(forKey: Keys.account) as? Bool ?? true
    }

    #if DEBUG
    private let sandbox = true
    #else
    private let sandbox = false
    #endif

    func start() {
        // Signing in (or into another account) sends this device's token for that person.
        sessionWatch = AuthService.shared.$session
            .map { $0?.isAnonymous == false ? $0?.userID : nil }
            .removeDuplicates()
            .sink { [weak self] user in
                guard user != nil else { return }
                Task { await self?.registerIfAllowed() }
            }
    }

    // When notifications are already allowed (by reminders or before), asks Apple for the token.
    func registerIfAllowed() async {
        let status = await UNUserNotificationCenter.current().notificationSettings().authorizationStatus
        allowed = status == .authorized || status == .provisional || status == .ephemeral
        if allowed { UIApplication.shared.registerForRemoteNotifications() }
    }

    // Asks once, at a moment it makes sense (shared maps, invitations, the settings toggles).
    func askIfNeeded() {
        Task {
            let granted = (try? await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge])) ?? false
            allowed = granted
            if granted { UIApplication.shared.registerForRemoteNotifications() }
        }
    }

    func didRegister(_ deviceToken: Data) {
        let hex = deviceToken.map { String(format: "%02x", $0) }.joined()
        UserDefaults.standard.set(hex, forKey: Keys.token)
        Task { await upload() }
    }

    // Sends the token with the language and choices; skipped when nothing changed this week.
    func upload(force: Bool = false) async {
        guard let token, let user = AuthService.shared.session, !user.isAnonymous else { return }
        let language = AppLanguage.current.code
        let signature = [token, user.userID, language, "\(collab)", "\(account)", "\(sandbox)"].joined(separator: "|")
        let defaults = UserDefaults.standard
        if !force, defaults.string(forKey: Keys.uploaded) == signature,
           let at = defaults.object(forKey: Keys.uploadedAt) as? Date, at > Date().addingTimeInterval(-7 * 86_400) { return }
        struct Args: Encodable {
            let p_token: String
            let p_sandbox: Bool
            let p_language: String
            let p_collab: Bool
            let p_account: Bool
        }
        let args = Args(p_token: token, p_sandbox: sandbox, p_language: language, p_collab: collab, p_account: account)
        guard let access = try? await AuthService.shared.validAccessToken(),
              (try? await rpc("register_push_token", args, accessToken: access)) != nil else { return }
        defaults.set(signature, forKey: Keys.uploaded)
        defaults.set(Date(), forKey: Keys.uploadedAt)
    }

    // On sign-out this device stops getting that person's notifications. Called with the session's
    // token before it is dropped.
    func signedOut(accessToken: String) {
        UserDefaults.standard.removeObject(forKey: Keys.uploaded)
        guard let token else { return }
        struct Args: Encodable { let p_token: String }
        Task { _ = try? await rpc("unregister_push_token", Args(p_token: token), accessToken: accessToken) }
    }

    // MARK: - Events

    // A shared map was saved from this device: the others hear about it (at most every 10 minutes
    // from here; the server also keeps it to one notification per 30 minutes per person).
    func mapChanged(_ id: UUID) {
        if let last = lastChanged[id], last > Date().addingTimeInterval(-600) { return }
        lastChanged[id] = Date()
        report(["action": "collab", "event": "changed", "map": id.uuidString])
    }

    func joined(_ id: UUID) {
        report(["action": "collab", "event": "joined", "map": id.uuidString])
    }

    func roleChanged(_ id: UUID, user: String) {
        report(["action": "role", "map": id.uuidString, "user": user])
    }

    // A test notification to this person's devices; returns how many got it.
    func sendTest() async throws -> Int {
        await upload(force: true)
        struct Reply: Decodable { let sent: Int }
        return try await BackendClient.shared.invoke("push", body: ["action": "test"], as: Reply.self).sent
    }

    private func report(_ body: [String: String]) {
        guard AuthService.shared.isSignedIn else { return }
        struct Reply: Decodable {}
        Task { _ = try? await BackendClient.shared.invoke("push", body: body, as: Reply.self) }
    }

    private func rpc<Args: Encodable>(_ name: String, _ args: Args, accessToken: String) async throws -> Data {
        var request = URLRequest(url: BackendConfig.url.appendingPathComponent("rest/v1/rpc/\(name)"))
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(BackendConfig.publishableKey, forHTTPHeaderField: "apikey")
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        request.httpBody = try JSONEncoder().encode(args)
        let (data, response) = try await BackendClient.shared.send(request)
        guard (200..<300).contains(response.statusCode) else { throw BackendError.server(code: "rest_\(response.statusCode)") }
        return data
    }
}
