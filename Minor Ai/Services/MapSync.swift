//
//  MapSync.swift
//  Minor Ai
//
//  Keeps maps the same on every device signed in to the account. Maps live on the phone and
//  are copied to the `synced_maps` table (only the owner can read them); pictures go to the
//  private `map-images` bucket. Pull first, then push: when the same map changed on two devices,
//  the newer edit wins. Deletes travel as tombstones. Settings → Sync Maps turns it off.
//

import Combine
import CryptoKit
import Foundation

@MainActor
final class MapSync: ObservableObject {
    static let shared = MapSync()

    @Published private(set) var isSyncing = false
    @Published private(set) var lastSynced: Date?
    @Published private(set) var failed = false

    static var isEnabled: Bool {
        get { UserDefaults.standard.object(forKey: "syncMaps") as? Bool ?? true }
        set {
            UserDefaults.standard.set(newValue, forKey: "syncMaps")
            if newValue { shared.syncSoon() }
        }
    }

    // What this device knows about one account's synced maps (kept in UserDefaults).
    struct State: Codable, Equatable {
        var cursor: String?                  // newest server_updated_at pulled so far
        var hashes: [UUID: String] = [:]     // content of each map as last sent or received
        var tombstones: [UUID: Date] = [:]   // maps deleted here, not yet sent
        var uploaded: Set<UUID> = []         // pictures already in the bucket
    }

    private var subscriptions: Set<AnyCancellable> = []
    private var running: Task<Void, Never>?
    private var again = false
    private let pageSize = 200

    func start() {
        guard subscriptions.isEmpty else { return }
        MapStore.shared.$maps
            .dropFirst()
            .debounce(for: .seconds(3), scheduler: RunLoop.main)
            .sink { [weak self] _ in self?.syncSoon() }
            .store(in: &subscriptions)
        AuthService.shared.$session
            .map { $0?.userID }
            .removeDuplicates()
            .sink { [weak self] _ in self?.syncSoon() }
            .store(in: &subscriptions)
    }

    func syncSoon() {
        guard Self.isEnabled, AuthService.shared.isSignedIn else { return }
        guard running == nil else {
            again = true
            return
        }
        running = Task {
            await run()
            running = nil
            if again {
                again = false
                syncSoon()
            }
        }
    }

    func noteDeleted(_ id: UUID) {
        guard let user = AuthService.shared.session?.userID else { return }
        var state = load(user)
        if state.hashes[id] != nil {
            state.tombstones[id] = Date()
            state.hashes[id] = nil
            save(state, user)
        }
    }

    // After the account is deleted: nothing of it stays on this device.
    func forget() {
        for key in UserDefaults.standard.dictionaryRepresentation().keys where key.hasPrefix("mapSync.") {
            UserDefaults.standard.removeObject(forKey: key)
        }
        lastSynced = nil
    }

    // MARK: - Run

    private func run() async {
        guard let user = AuthService.shared.session?.userID else { return }
        isSyncing = true
        defer { isSyncing = false }
        var state = load(user)
        do {
            try await pull(&state, user: user)
            save(state, user)
            try await push(&state, user: user)
            save(state, user)
            lastSynced = Date()
            failed = false
        } catch BackendError.offline {
            save(state, user)
        } catch {
            save(state, user)
            failed = true
        }
    }

    // MARK: - Pull

    private struct Row: Decodable {
        let id: UUID
        let map: MindMap?
        let updatedAt: String
        let deleted: Bool
        let serverUpdatedAt: String

        enum CodingKeys: String, CodingKey { case id, data, updated_at, deleted, server_updated_at }

        init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            id = try c.decode(UUID.self, forKey: .id)
            map = try? c.decode(MindMap.self, forKey: .data)
            updatedAt = try c.decode(String.self, forKey: .updated_at)
            deleted = (try? c.decode(Bool.self, forKey: .deleted)) ?? false
            serverUpdatedAt = try c.decode(String.self, forKey: .server_updated_at)
        }
    }

    private func pull(_ state: inout State, user: String) async throws {
        while true {
            var query = [
                URLQueryItem(name: "select", value: "id,data,updated_at,deleted,server_updated_at"),
                URLQueryItem(name: "order", value: "server_updated_at.asc"),
                URLQueryItem(name: "limit", value: "\(pageSize)"),
            ]
            if let cursor = state.cursor { query.append(URLQueryItem(name: "server_updated_at", value: "gt.\(cursor)")) }
            let data = try await rest("GET", query: query)
            let rows = try Self.decoder.decode([Row].self, from: data)
            for row in rows {
                apply(row, state: &state)
                state.cursor = row.serverUpdatedAt
            }
            for row in rows where !row.deleted {
                guard let map = row.map else { continue }
                for image in map.root.imageIDs where !MapStore.shared.hasImage(image) {
                    if let bytes = try? await download(image, user: user) {
                        MapStore.shared.storeSyncedImage(image, data: bytes)
                        state.uploaded.insert(image)
                    }
                }
            }
            if rows.count < pageSize { return }
        }
    }

    private func apply(_ row: Row, state: inout State) {
        let local = MapStore.shared.map(row.id)
        let remoteDate = Self.date(row.updatedAt) ?? .distantPast
        if row.deleted {
            // A delete wins over older edits; an edit made here after it brings the map back.
            if let local, local.updatedAt > remoteDate { return }
            MapStore.shared.removeSynced(row.id)
            state.hashes[row.id] = nil
            return
        }
        guard let remote = row.map, remote.id == row.id else { return }
        if state.tombstones[row.id] != nil { return }
        if let local, local.updatedAt > remote.updatedAt, Self.hash(local) != state.hashes[row.id] { return }
        MapStore.shared.applySynced(remote)
        state.hashes[row.id] = Self.hash(remote)
    }

    // MARK: - Push

    private struct Upload: Encodable {
        let user_id: String
        let id: UUID
        let data: MindMap
        let updated_at: String
        let deleted: Bool
    }

    private struct Tombstone: Encodable {
        struct Empty: Encodable {}
        let user_id: String
        let id: UUID
        let data = Empty()
        let updated_at: String
        let deleted = true
    }

    private func push(_ state: inout State, user: String) async throws {
        let changed = MapStore.shared.maps.filter { state.hashes[$0.id] != Self.hash($0) }
        for batch in stride(from: 0, to: changed.count, by: 10).map({ Array(changed[$0..<min($0 + 10, changed.count)]) }) {
            for map in batch {
                for image in map.root.imageIDs where !state.uploaded.contains(image) {
                    guard let bytes = MapStore.shared.imageData(image) else { continue }
                    try await upload(image, data: bytes, user: user)
                    state.uploaded.insert(image)
                }
            }
            let rows = batch.map { Upload(user_id: user, id: $0.id, data: $0, updated_at: Self.string($0.updatedAt), deleted: false) }
            _ = try await rest("POST", query: [URLQueryItem(name: "on_conflict", value: "user_id,id")], body: try Self.encoder.encode(rows), upsert: true)
            for map in batch { state.hashes[map.id] = Self.hash(map) }
        }
        let gone = state.tombstones
        if !gone.isEmpty {
            let rows = gone.map { Tombstone(user_id: user, id: $0.key, updated_at: Self.string($0.value)) }
            _ = try await rest("POST", query: [URLQueryItem(name: "on_conflict", value: "user_id,id")], body: try Self.encoder.encode(rows), upsert: true)
            for id in gone.keys { state.tombstones[id] = nil }
        }
    }

    // MARK: - HTTP

    private func rest(_ method: String, query: [URLQueryItem], body: Data? = nil, upsert: Bool = false) async throws -> Data {
        var components = URLComponents(url: BackendConfig.url.appendingPathComponent("rest/v1/synced_maps"), resolvingAgainstBaseURL: false)!
        components.queryItems = query
        // "+" in timestamps must stay a plus, not become a space.
        components.percentEncodedQuery = components.percentEncodedQuery?.replacingOccurrences(of: "+", with: "%2B")
        var request = URLRequest(url: components.url!)
        request.httpMethod = method
        request.httpBody = body
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        if upsert { request.setValue("resolution=merge-duplicates,return=minimal", forHTTPHeaderField: "Prefer") }
        return try await send(request)
    }

    private func upload(_ id: UUID, data: Data, user: String) async throws {
        var request = URLRequest(url: BackendConfig.url.appendingPathComponent("storage/v1/object/map-images/\(user)/\(id.uuidString).jpg"))
        request.httpMethod = "POST"
        request.httpBody = data
        request.setValue("image/jpeg", forHTTPHeaderField: "Content-Type")
        request.setValue("true", forHTTPHeaderField: "x-upsert")
        _ = try await send(request)
    }

    private func download(_ id: UUID, user: String) async throws -> Data {
        var request = URLRequest(url: BackendConfig.url.appendingPathComponent("storage/v1/object/authenticated/map-images/\(user)/\(id.uuidString).jpg"))
        request.httpMethod = "GET"
        return try await send(request)
    }

    // Signed requests; a rejected token is refreshed once.
    private func send(_ base: URLRequest) async throws -> Data {
        for attempt in 0..<2 {
            var request = base
            let token = try await AuthService.shared.validAccessToken(forceRefresh: attempt > 0)
            request.setValue(BackendConfig.publishableKey, forHTTPHeaderField: "apikey")
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
            let (data, response) = try await BackendClient.shared.send(request)
            if (200..<300).contains(response.statusCode) { return data }
            if response.statusCode == 401 && attempt == 0 { continue }
            throw BackendError.server(code: "sync_\(response.statusCode)")
        }
        throw BackendError.unauthorized
    }

    // MARK: - Helpers

    private func load(_ user: String) -> State {
        guard let data = UserDefaults.standard.data(forKey: "mapSync.\(user)"),
              let state = try? JSONDecoder().decode(State.self, from: data) else { return State() }
        return state
    }

    private func save(_ state: State, _ user: String) {
        if let data = try? JSONEncoder().encode(state) { UserDefaults.standard.set(data, forKey: "mapSync.\(user)") }
    }

    static let encoder: JSONEncoder = {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.sortedKeys]
        return encoder
    }()

    static let decoder: JSONDecoder = {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }()

    static func hash(_ map: MindMap) -> String {
        guard let data = try? encoder.encode(map) else { return "" }
        return SHA256.hash(data: data).prefix(12).map { String(format: "%02x", $0) }.joined()
    }

    private static func string(_ date: Date) -> String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter.string(from: date)
    }

    static func date(_ text: String) -> Date? {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = formatter.date(from: text) { return date }
        formatter.formatOptions = [.withInternetDateTime]
        if let date = formatter.date(from: text) { return date }
        // Postgres sends microseconds and "+00:00"; keep milliseconds.
        let trimmed = text.replacingOccurrences(of: #"(\.\d{3})\d+"#, with: "$1", options: .regularExpression)
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter.date(from: trimmed)
    }
}
