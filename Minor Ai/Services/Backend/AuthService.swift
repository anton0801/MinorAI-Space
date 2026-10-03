//
//  AuthService.swift
//  Minor Ai
//
//  Supabase Auth over plain HTTP: email and password (with 6-digit codes from email for sign-up
//  confirmation and password reset), Sign in with Apple, token refresh, sign out and account
//  deletion. AI features need a signed-in account; the session lives in the Keychain.
//

import AuthenticationServices
import CryptoKit
import Foundation
import Security

struct AuthSession: Codable, Equatable {
    var accessToken: String
    var refreshToken: String
    var expiresAt: Date
    var userID: String
    var email: String?
    var isAnonymous: Bool
}

@MainActor
final class AuthService: ObservableObject {
    static let shared = AuthService()

    @Published private(set) var session: AuthSession?
    // Set when a signed-in (Apple) session was revoked on the server, so Settings can offer to sign in again.
    @Published var signedOutByServer = false

    private let keychain = KeychainStore(account: "supabase.session")
    private var refreshTask: Task<AuthSession, Error>?
    // Bumped on every sign-in or sign-out, so a slow refresh or sign-up never overwrites a newer session.
    private var generation = 0

    private init() {
        session = keychain.load(AuthSession.self)
        // Earlier builds created anonymous sessions; AI now needs a real account.
        if session?.isAnonymous == true {
            session = nil
            keychain.delete()
        }
    }

    // Signed in with email or Apple (anonymous sessions don't count).
    var isSignedIn: Bool { session.map { !$0.isAnonymous } ?? false }
    var isAnonymous: Bool { !isSignedIn }

    // MARK: - Email and password

    enum SignUpResult { case signedIn, needsCode }

    // Creates an account. When the project asks to confirm emails, a 6-digit code is sent and
    // `verifySignUp` finishes the sign-up.
    func signUp(email: String, password: String) async throws -> SignUpResult {
        struct Body: Encodable {
            let email: String
            let password: String
            let data: [String: String]
        }
        let data = try await postRaw("auth/v1/signup", body: Body(email: email, password: password, data: ["lang": AppLanguage.current.code]))
        if let response = try? JSONDecoder().decode(TokenResponse.self, from: data) {
            signedIn(with: response)
            return .signedIn
        }
        return .needsCode
    }

    func verifySignUp(email: String, code: String) async throws {
        let response: TokenResponse = try await postForm("auth/v1/verify", body: VerifyBody(type: "signup", email: email, token: code))
        signedIn(with: response)
    }

    func resendSignUpCode(email: String) async throws {
        struct Body: Encodable { let type = "signup"; let email: String }
        _ = try await postRaw("auth/v1/resend", body: Body(email: email))
    }

    func signIn(email: String, password: String) async throws {
        struct Body: Encodable { let email: String; let password: String }
        let response: TokenResponse = try await postForm("auth/v1/token?grant_type=password", body: Body(email: email, password: password))
        signedIn(with: response)
    }

    // Sends a 6-digit code for a new password.
    func sendPasswordReset(email: String) async throws {
        struct Body: Encodable { let email: String }
        _ = try await postRaw("auth/v1/recover", body: Body(email: email))
    }

    // Checks the code, signs in and sets the new password.
    func resetPassword(email: String, code: String, newPassword: String) async throws {
        let response: TokenResponse = try await postForm("auth/v1/verify", body: VerifyBody(type: "recovery", email: email, token: code))
        signedIn(with: response)
        struct Body: Encodable { let password: String }
        var request = URLRequest(url: URL(string: "auth/v1/user", relativeTo: BackendConfig.url)!)
        request.httpMethod = "PUT"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(BackendConfig.publishableKey, forHTTPHeaderField: "apikey")
        request.setValue("Bearer \(response.access_token)", forHTTPHeaderField: "Authorization")
        request.httpBody = try JSONEncoder().encode(Body(password: newPassword))
        let (data, http) = try await BackendClient.shared.send(request)
        guard (200..<300).contains(http.statusCode) else { throw AuthError.from(data) }
    }

    private func signedIn(with response: TokenResponse) {
        generation += 1
        store(response)
        signedOutByServer = false
    }

    func signInWithApple(idToken: String, rawNonce: String, authorizationCode: String?) async throws {
        let response: TokenResponse = try await postForm(
            "auth/v1/token?grant_type=id_token",
            body: IDTokenBody(provider: "apple", id_token: idToken, nonce: rawNonce)
        )
        signedIn(with: response)
        // The server keeps Apple's refresh token so account deletion can revoke it. Best effort.
        if let authorizationCode, !authorizationCode.isEmpty {
            struct Body: Encodable { let action = "apple_code"; let code: String }
            struct Reply: Decodable { let stored: Bool }
            _ = try? await BackendClient.shared.invoke("account", body: Body(code: authorizationCode), as: Reply.self)
        }
    }

    // Returns an access token that stays valid for at least a minute, refreshing if needed.
    // `forceRefresh` is used after the server rejected a token that still looked valid.
    func validAccessToken(forceRefresh: Bool = false) async throws -> String {
        guard isSignedIn, let current = session else { throw BackendError.signInRequired }
        if !forceRefresh && current.expiresAt.timeIntervalSinceNow > 60 { return current.accessToken }
        return try await refresh(current).accessToken
    }

    func signOut() {
        generation += 1
        session = nil
        keychain.delete()
    }

    // Deletes the account on the server (required by App Store review), then signs out.
    func deleteAccount() async throws {
        struct Body: Encodable { let action = "delete" }
        struct Reply: Decodable { let deleted: Bool }
        let _: Reply = try await BackendClient.shared.invoke("account", body: Body())
        signOut()
        signedOutByServer = false
    }

    // MARK: - Private

    // One refresh at a time. Recovery from a revoked session happens inside the shared task, so
    // every caller waiting on it gets the new session, not an error.
    private func refresh(_ current: AuthSession) async throws -> AuthSession {
        if let refreshTask { return try await refreshTask.value }
        let started = generation
        let task = Task { () throws -> AuthSession in
            do {
                let response: TokenResponse = try await post(
                    "auth/v1/token?grant_type=refresh_token",
                    body: RefreshBody(refresh_token: current.refreshToken)
                )
                if generation == started { store(response) }
                guard let session else { throw BackendError.unauthorized }
                return session
            } catch AuthFailure.revoked {
                // The refresh token is gone (revoked, reused or the user was deleted): start over.
                // Network errors and server hiccups keep the session so the next call can retry.
                if generation == started {
                    signOut()
                    signedOutByServer = true
                }
                guard let session else { throw BackendError.signInRequired }
                return session
            }
        }
        refreshTask = task
        defer { refreshTask = nil }
        return try await task.value
    }

    private func store(_ response: TokenResponse) {
        let new = AuthSession(
            accessToken: response.access_token,
            refreshToken: response.refresh_token,
            expiresAt: Date().addingTimeInterval(TimeInterval(response.expires_in)),
            userID: response.user.id,
            email: response.user.email?.isEmpty == false ? response.user.email : nil,
            isAnonymous: response.user.is_anonymous ?? false
        )
        session = new
        keychain.save(new)
    }

    private func post<Body: Encodable, Reply: Decodable>(_ path: String, body: Body) async throws -> Reply {
        var request = URLRequest(url: URL(string: path, relativeTo: BackendConfig.url)!)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(BackendConfig.publishableKey, forHTTPHeaderField: "apikey")
        request.httpBody = try JSONEncoder().encode(body)
        let (data, response) = try await BackendClient.shared.send(request)
        guard (200..<300).contains(response.statusCode) else {
            let failure = try? JSONDecoder().decode(AuthErrorBody.self, from: data)
            if failure?.isRevokedSession == true { throw AuthFailure.revoked }
            if response.statusCode == 429 { throw BackendError.busy }
            if (400..<500).contains(response.statusCode) { throw BackendError.unauthorized }
            throw BackendError.server(code: "auth_\(response.statusCode)")
        }
        do {
            return try JSONDecoder().decode(Reply.self, from: data)
        } catch {
            throw BackendError.server(code: "auth_decode")
        }
    }

    private enum AuthFailure: Error { case revoked }

    private struct VerifyBody: Encodable {
        let type: String
        let email: String
        let token: String
    }

    // Like `post`, but failures carry a message for the sign-in screen.
    private func postForm<Body: Encodable, Reply: Decodable>(_ path: String, body: Body) async throws -> Reply {
        let data = try await postRaw(path, body: body)
        do {
            return try JSONDecoder().decode(Reply.self, from: data)
        } catch {
            throw AuthError.unknown
        }
    }

    private func postRaw<Body: Encodable>(_ path: String, body: Body) async throws -> Data {
        var request = URLRequest(url: URL(string: path, relativeTo: BackendConfig.url)!)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(BackendConfig.publishableKey, forHTTPHeaderField: "apikey")
        request.httpBody = try JSONEncoder().encode(body)
        let (data, response) = try await BackendClient.shared.send(request)
        guard (200..<300).contains(response.statusCode) else { throw AuthError.from(data) }
        return data
    }

    // GoTrue reports errors as {error_code, msg} (new) or {error, error_description} (old).
    private struct AuthErrorBody: Decodable {
        let error_code: String?
        let error: String?

        var isRevokedSession: Bool {
            let revoked: Set<String> = [
                "refresh_token_not_found", "refresh_token_already_used", "session_not_found",
                "session_expired", "user_not_found", "user_banned",
            ]
            if let error_code, revoked.contains(error_code) { return true }
            return error == "invalid_grant"
        }
    }

    private struct EmptyBody: Encodable {}
    private struct RefreshBody: Encodable { let refresh_token: String }
    private struct IDTokenBody: Encodable {
        let provider: String
        let id_token: String
        let nonce: String
    }
    private struct TokenResponse: Decodable {
        let access_token: String
        let refresh_token: String
        let expires_in: Int
        let user: User
        struct User: Decodable {
            let id: String
            let email: String?
            let is_anonymous: Bool?
        }
    }
}

// Nonce helpers for Sign in with Apple: Apple gets the SHA-256 hash, Supabase gets the raw value.
enum AppleNonce {
    static func make(length: Int = 32) -> String {
        let charset = Array("0123456789ABCDEFGHIJKLMNOPQRSTUVXYZabcdefghijklmnopqrstuvwxyz-._")
        var bytes = [UInt8](repeating: 0, count: length)
        _ = SecRandomCopyBytes(kSecRandomDefault, length, &bytes)
        return String(bytes.map { charset[Int($0) % charset.count] })
    }

    static func sha256(_ input: String) -> String {
        SHA256.hash(data: Data(input.utf8)).map { String(format: "%02x", $0) }.joined()
    }
}

// Minimal generic-password Keychain wrapper for one Codable value.
struct KeychainStore {
    let account: String
    private let service = "com.minorailifegroup.MinorAI"

    func save<T: Encodable>(_ value: T) {
        guard let data = try? JSONEncoder().encode(value) else { return }
        delete()
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlock,
            kSecValueData as String: data,
        ]
        SecItemAdd(query as CFDictionary, nil)
    }

    func load<T: Decodable>(_ type: T.Type) -> T? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]
        var item: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &item) == errSecSuccess, let data = item as? Data else { return nil }
        return try? JSONDecoder().decode(T.self, from: data)
    }

    func delete() {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
        SecItemDelete(query as CFDictionary)
    }
}

// What the sign-in screen tells people when Supabase Auth says no.
enum AuthError: LocalizedError, Equatable {
    case wrongCredentials
    case emailNotConfirmed
    case alreadyRegistered
    case weakPassword
    case invalidEmail
    case badCode
    case tooManyAttempts
    case signUpDisabled
    case unknown

    var errorDescription: String? {
        switch self {
        case .wrongCredentials: return L("Wrong email or password.")
        case .emailNotConfirmed: return L("Confirm your email first: enter the code we sent you.")
        case .alreadyRegistered: return L("An account with this email already exists. Sign in instead.")
        case .weakPassword: return L("Use at least 8 characters, with letters and numbers.")
        case .invalidEmail: return L("Enter a valid email address.")
        case .badCode: return L("This code is wrong or has expired. Request a new one.")
        case .tooManyAttempts: return L("Too many attempts. Try again in a few minutes.")
        case .signUpDisabled: return L("Signing up with email isn’t available right now.")
        case .unknown: return L("Something went wrong. Try again.")
        }
    }

    static func from(_ data: Data) -> AuthError {
        struct Body: Decodable {
            let error_code: String?
            let error: String?
            let error_description: String?
            let msg: String?
        }
        let body = try? JSONDecoder().decode(Body.self, from: data)
        let message = (body?.msg ?? body?.error_description ?? "").lowercased()
        switch body?.error_code ?? body?.error ?? "" {
        case "invalid_credentials": return .wrongCredentials
        case "email_not_confirmed": return .emailNotConfirmed
        case "user_already_exists", "email_exists": return .alreadyRegistered
        case "weak_password": return .weakPassword
        case "email_address_invalid", "validation_failed": return .invalidEmail
        case "otp_expired", "otp_disabled", "bad_code_verifier": return .badCode
        case "over_email_send_rate_limit", "over_request_rate_limit": return .tooManyAttempts
        case "signup_disabled", "email_provider_disabled": return .signUpDisabled
        default: break
        }
        if message.contains("invalid login credentials") { return .wrongCredentials }
        if message.contains("email not confirmed") { return .emailNotConfirmed }
        if message.contains("token has expired") || message.contains("invalid") && message.contains("otp") { return .badCode }
        if message.contains("rate limit") { return .tooManyAttempts }
        if message.contains("password") { return .weakPassword }
        return .unknown
    }
}
