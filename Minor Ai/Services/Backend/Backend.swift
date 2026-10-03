//
//  Backend.swift
//  Minor Ai
//
//  Thin URLSession client for the Minor Supabase project: auth (GoTrue) and edge functions.
//  The publishable key is meant to ship in the app; provider API keys stay on the server.
//

import Foundation
import UIKit

enum BackendConfig {
    static let url = URL(string: "https://dgddfvotzutogrmzfscx.supabase.co")!
    static let publishableKey = "sb_publishable_vh9mGBL2koNUhynPOy1feg_qnVLScXj"
}

enum BackendError: LocalizedError, Equatable {
    case offline
    case interrupted
    case unauthorized
    case signInRequired
    case limitReached(kind: String)
    case planRequired
    case modelLocked
    case sourceTooLong
    case mapTooLarge
    case notConfigured
    case busy
    case youtubeNoTranscript
    case badLink
    case linkUnreachable
    case aiFailed
    case imageBlocked
    case server(code: String)

    // Kept in sync by AccountStore so messages never upsell people who already pay.
    static var isPaidUser = false

    var errorDescription: String? {
        let paid = Self.isPaidUser
        switch self {
        case .offline: return L("You’re offline. Check your connection and try again.")
        case .interrupted: return L("The connection was interrupted. Try again.")
        case .unauthorized: return L("Couldn’t reach your account. Try again in a moment.")
        case .signInRequired: return L("Sign in to build maps and chat with AI.")
        case .limitReached(let kind):
            if kind == "shares" { return L("You’ve reached the limit of shared links.") }
            if paid {
                return kind == "budget"
                    ? L("You’ve used this month’s AI allowance. It renews on the 1st; lighter models use less of it.")
                    : L("You’ve reached this month’s fair-use limit. It resets on the 1st.")
            }
            switch kind {
            case "maps": return L("You’ve used 3 of 3 free maps this month.")
            case "chats": return L("You’ve used all free messages this month.")
            case "budget": return L("You’ve used this month’s free AI allowance. Stronger models use it faster; Minor Plus gives you 20 times more.")
            case "fetches": return L("You’ve used this month’s free link and video reads.")
            case "images": return L("You’ve used this month’s free AI images. Minor Plus creates up to 60 a month.")
            default: return L("You’ve used all free AI actions this month.")
            }
        case .planRequired: return L("YouTube and voice maps are part of Minor Plus.")
        case .modelLocked: return L("Maps with this model are part of a higher plan.")
        case .sourceTooLong:
            return paid ? L("This source is too long. Try a shorter part of it.") : L("This source is too long for the free plan. Minor Plus reads much longer documents.")
        case .mapTooLarge: return L("This map is too large to change in one command. Expand ideas one by one instead.")
        case .notConfigured: return L("AI isn’t set up on the server yet.")
        case .busy: return L("AI is busy right now. Try again in a moment.")
        case .youtubeNoTranscript: return L("This video has no transcript, so it can’t be mapped.")
        case .badLink: return L("This doesn’t look like a public web link. Check it and try again.")
        case .linkUnreachable: return L("Couldn’t open this page. Check the link and try again.")
        case .aiFailed: return L("AI couldn’t finish this. Try again in a moment.")
        case .imageBlocked: return L("This image can’t be created. Try describing it differently.")
        case .server: return L("Something went wrong on our side. Try again in a moment.")
        }
    }

    // Whether buying a plan would solve this error (and the person doesn't already pay).
    var suggestsUpgrade: Bool {
        guard !Self.isPaidUser else { return false }
        switch self {
        case .limitReached, .planRequired, .modelLocked, .sourceTooLong: return true
        default: return false
        }
    }

    static func from(code: String, kind: String?) -> BackendError {
        switch code {
        case "unauthorized": return .unauthorized
        case "sign_in_required": return .signInRequired
        case "limit_reached": return .limitReached(kind: kind ?? "maps")
        case "plan_required": return .planRequired
        case "model_locked": return .modelLocked
        case "source_too_long", "too_large": return .sourceTooLong
        case "map_too_large": return .mapTooLarge
        case "ai_not_configured": return .notConfigured
        case "ai_busy": return .busy
        case "youtube_no_transcript": return .youtubeNoTranscript
        case "bad_link", "bad_video_link": return .badLink
        case "link_unreachable", "link_unreadable", "video_unreachable": return .linkUnreachable
        case "ai_failed": return .aiFailed
        case "image_blocked": return .imageBlocked
        default: return .server(code: code)
        }
    }
}

final class BackendClient {
    static let shared = BackendClient()

    private let session: URLSession

    init() {
        let config = URLSessionConfiguration.default
        // Longer than the server's own limits (fetch + 120 s for the AI), so a slow map isn't
        // abandoned (and paid for twice on retry) while the server is still finishing it.
        config.timeoutIntervalForRequest = 180
        self.session = URLSession(configuration: config)
    }

    // Calls an edge function as the signed-in user and decodes its JSON reply.
    // A 401 refreshes the session once and retries.
    func invoke<Body: Encodable, Reply: Decodable>(_ function: String, body: Body, as: Reply.Type = Reply.self) async throws -> Reply {
        let payload = try JSONEncoder().encode(body)
        var attempt = 0
        while true {
            let token = try await AuthService.shared.validAccessToken(forceRefresh: attempt > 0)
            var request = URLRequest(url: BackendConfig.url.appendingPathComponent("functions/v1/\(function)"))
            request.httpMethod = "POST"
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.setValue(BackendConfig.publishableKey, forHTTPHeaderField: "apikey")
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
            if let device = await Self.deviceID { request.setValue(device, forHTTPHeaderField: "x-device-id") }
            // The app's language: AI writes in it when the material doesn't decide the language.
            request.setValue(AppLanguage.current.code, forHTTPHeaderField: "x-app-language")
            request.httpBody = payload

            let (data, response) = try await send(request)
            if (200..<300).contains(response.statusCode) {
                do {
                    return try JSONDecoder().decode(Reply.self, from: data)
                } catch {
                    throw BackendError.aiFailed
                }
            }
            if response.statusCode == 401 && attempt == 0 {
                attempt += 1
                continue
            }
            let failure = try? JSONDecoder().decode(FunctionFailure.self, from: data)
            if response.statusCode == 401 { throw BackendError.unauthorized }
            throw BackendError.from(code: failure?.error ?? "http_\(response.statusCode)", kind: failure?.kind)
        }
    }

    func send(_ request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        do {
            let (data, response) = try await session.data(for: request)
            guard let http = response as? HTTPURLResponse else { throw BackendError.server(code: "no_response") }
            return (data, http)
        } catch let error as URLError {
            switch error.code {
            case .notConnectedToInternet, .dataNotAllowed, .internationalRoamingOff:
                throw BackendError.offline
            case .cancelled:
                throw CancellationError()
            default:
                throw BackendError.interrupted
            }
        }
    }

    // Free-plan limits are also counted per device, so a new anonymous account does not reset them.
    @MainActor static var deviceID: String? { UIDevice.current.identifierForVendor?.uuidString }

    private struct FunctionFailure: Decodable {
        let error: String
        let kind: String?
    }
}
