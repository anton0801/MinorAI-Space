//
//  CollabService.swift
//  Minor Ai
//
//  Maps edited together. The shared map lives in `collab_maps` with a version number; each
//  device keeps the version it last had (the base), pushes its edits only on top of the newest
//  version, and when someone else got there first, merges (CollabMerge) and pushes again.
//  While a shared map is open, new versions are pulled every few seconds.
//

import Combine
import Foundation

@MainActor
final class CollabService: ObservableObject {
    static let shared = CollabService()

    @Published private(set) var busy: Set<UUID> = []
    @Published private(set) var failed: Set<UUID> = []
    @Published private(set) var synced: [UUID: Date] = [:]

    enum CollabError: LocalizedError {
        case invalidInvite, notFound, planRequired, mapFull
        var errorDescription: String? {
            switch self {
            case .invalidInvite: return L("This invite link has expired or isn’t valid. Ask for a new one.")
            case .notFound: return L("This shared map is no longer available.")
            case .planRequired: return L("Inviting people is part of Minor Plus and PRO.")
            case .mapFull: return L("This map already has as many people as its owner’s plan allows.")
            }
        }
    }

    struct Member: Decodable, Identifiable, Equatable {
        let user_id: String
        let email: String?
        let role: String
        let member_limit: Int
        var id: String { user_id }
        var collabRole: CollabRole { CollabRole(rawValue: role) ?? .editor }
    }

    private var bases: [UUID: MindMap] = [:]
    private var uploaded: Set<String> = []
    private var running: Set<UUID> = []
    private var again: Set<UUID> = []
    private var watched: Set<UUID> = []
    private var poll: Timer?
    private var subscription: AnyCancellable?
    private let folder: URL

    private init() {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        folder = base.appendingPathComponent("Collab", isDirectory: true)
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let files = (try? FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil)) ?? []
        for file in files where file.pathExtension == "json" {
            if let data = try? Data(contentsOf: file), let map = try? JSONDecoder.iso.decode(MindMap.self, from: data) {
                bases[map.id] = map
            }
        }
        uploaded = Set(UserDefaults.standard.stringArray(forKey: "collab.uploaded") ?? [])
    }

    func start() {
        guard subscription == nil else { return }
        subscription = MapStore.shared.$maps
            .debounce(for: .seconds(1.2), scheduler: RunLoop.main)
            .sink { [weak self] maps in self?.pushChanged(maps) }
    }

    // The part of a map everyone shares (not who pinned it or how it's laid out on one phone).
    static func shared(_ map: MindMap) -> MindMap {
        var copy = map
        copy.collab = nil
        copy.isPinned = false
        copy.layout = nil
        return copy
    }

    func isShared(_ id: UUID) -> Bool { MapStore.shared.map(id)?.collab != nil }

    // MARK: - Sharing

    // Shares the map (the first time) and returns a new invite link for an editor or a viewer.
    func inviteLink(for mapID: UUID, role: CollabRole = .editor) async throws -> URL {
        guard let map = MapStore.shared.map(mapID), let user = AuthService.shared.session?.userID else { throw CollabError.notFound }
        if map.collab == nil {
            struct Row: Encodable { let id: UUID; let owner: String; let data: MindMap }
            struct Created: Decodable { let version: Int }
            let body = try MapSync.encoder.encode(Row(id: map.id, owner: user, data: Self.shared(map)))
            let data = try await rest("POST", "collab_maps", body: body, prefer: "return=representation")
            let created = try JSONDecoder().decode([Created].self, from: data)
            let version = created.first?.version ?? 1
            setCollab(mapID, CollabInfo(isOwner: true, version: version))
            saveBase(Self.shared(map))
            try await uploadImages(of: map)
        }
        struct Args: Encodable { let p_map: UUID; let p_role: String }
        let token = try await rpc("create_collab_invite", Args(p_map: mapID, p_role: role == .viewer ? "viewer" : "editor"))
        let text = String(decoding: token, as: UTF8.self).trimmingCharacters(in: CharacterSet(charactersIn: "\" \n"))
        // The owner hears when someone joins or changes the map.
        PushService.shared.askIfNeeded()
        // After "#": browsers never send it, so the secret stays out of the website's server logs.
        return URL(string: "https://minorai.site/join/#t=\(text)")!
    }

    func join(token: String) async throws -> UUID {
        struct Args: Encodable { let p_token: String }
        let data: Data
        do {
            data = try await rpc("join_collab_map", Args(p_token: token))
        } catch CollabError.mapFull {
            throw CollabError.mapFull
        } catch BackendError.server(let code) where code.hasPrefix("collab_4") {
            throw CollabError.invalidInvite
        }
        let raw = String(decoding: data, as: UTF8.self).trimmingCharacters(in: CharacterSet(charactersIn: "\" \n"))
        guard let id = UUID(uuidString: raw) else { throw CollabError.invalidInvite }
        try await pull(id)
        PushService.shared.joined(id)
        PushService.shared.askIfNeeded()
        return id
    }

    func stopSharing(_ id: UUID) async throws {
        // Its pictures go first (allowed only while the map is still shared).
        await removeImages(of: id)
        _ = try await rest("DELETE", "collab_maps", query: [URLQueryItem(name: "id", value: "eq.\(id.uuidString)")])
        unshare(id)
    }

    private func removeImages(of id: UUID) async {
        struct Listed: Decodable { let name: String }
        struct ListBody: Encodable { let prefix: String; let limit = 1000 }
        struct DeleteBody: Encodable { let prefixes: [String] }
        let folder = id.uuidString
        for _ in 0..<5 {
            var list = URLRequest(url: BackendConfig.url.appendingPathComponent("storage/v1/object/list/collab-images"))
            list.httpMethod = "POST"
            list.setValue("application/json", forHTTPHeaderField: "Content-Type")
            list.httpBody = try? JSONEncoder().encode(ListBody(prefix: folder))
            guard let data = try? await send(list), let files = try? JSONDecoder().decode([Listed].self, from: data), !files.isEmpty else { return }
            var remove = URLRequest(url: BackendConfig.url.appendingPathComponent("storage/v1/object/collab-images"))
            remove.httpMethod = "DELETE"
            remove.setValue("application/json", forHTTPHeaderField: "Content-Type")
            remove.httpBody = try? JSONEncoder().encode(DeleteBody(prefixes: files.map { "\(folder)/\($0.name)" }))
            guard (try? await send(remove)) != nil, files.count == 1000 else { return }
        }
    }

    func leave(_ id: UUID) async throws {
        guard let user = AuthService.shared.session?.userID else { return }
        _ = try await rest("DELETE", "collab_members", query: [
            URLQueryItem(name: "map_id", value: "eq.\(id.uuidString)"),
            URLQueryItem(name: "user_id", value: "eq.\(user)"),
        ])
        unshare(id)
    }

    // Everyone on the map, owner first.
    func members(_ id: UUID) async throws -> [Member] {
        struct Args: Encodable { let p_map: UUID }
        let data = try await rpc("collab_member_list", Args(p_map: id))
        return try JSONDecoder().decode([Member].self, from: data)
    }

    func setRole(_ role: CollabRole, for user: String, in id: UUID) async throws {
        struct Args: Encodable { let p_map: UUID; let p_user: String; let p_role: String }
        _ = try await rpc("set_collab_role", Args(p_map: id, p_user: user, p_role: role.rawValue))
        PushService.shared.roleChanged(id, user: user)
    }

    // Also turns off the map's invite links, so an old link can't bring them back.
    func remove(_ user: String, from id: UUID) async throws {
        struct Args: Encodable { let p_map: UUID; let p_user: String }
        _ = try await rpc("remove_collab_member", Args(p_map: id, p_user: user))
    }

    // Turns off every invite link; people already on the map stay.
    func revokeInvites(_ id: UUID) async throws {
        struct Args: Encodable { let p_map: UUID }
        _ = try await rpc("revoke_collab_invites", Args(p_map: id))
    }

    // MARK: - Keeping up to date

    // While a shared map is on screen, new versions arrive every few seconds.
    func watch(_ id: UUID) {
        guard isShared(id) else { return }
        watched.insert(id)
        Task { try? await pullIfNewer(id) }
        if poll == nil {
            poll = Timer.scheduledTimer(withTimeInterval: 4, repeats: true) { [weak self] _ in
                Task { @MainActor in
                    guard let self else { return }
                    for id in self.watched where !self.running.contains(id) { try? await self.pullIfNewer(id) }
                }
            }
        }
    }

    func unwatch(_ id: UUID) {
        watched.remove(id)
        if watched.isEmpty {
            poll?.invalidate()
            poll = nil
        }
    }

    // Every shared map this person can open: new ones are added, newer versions merged, and
    // maps no longer shared with them stay as their own copies.
    func refreshAll() async {
        guard AuthService.shared.isSignedIn else { return }
        struct Row: Decodable { let id: UUID; let version: Int }
        guard let data = try? await rest("GET", "collab_maps", query: [URLQueryItem(name: "select", value: "id,version")]),
              let rows = try? JSONDecoder().decode([Row].self, from: data) else { return }
        let ids = Set(rows.map(\.id))
        for row in rows {
            let local = MapStore.shared.map(row.id)?.collab?.version ?? 0
            if row.version > local { try? await pull(row.id) }
        }
        for map in MapStore.shared.maps where map.collab != nil && !ids.contains(map.id) { unshare(map.id) }
    }

    private struct MyRole: Decodable { let role: String }

    // This person's role, read with the map: the owner can change it at any time.
    private func role(owner: String, members: [MyRole]?) -> CollabRole {
        if owner == AuthService.shared.session?.userID { return .owner }
        return members?.first.flatMap { CollabRole(rawValue: $0.role) } ?? .editor
    }

    private func roleQuery() -> [URLQueryItem] {
        [URLQueryItem(name: "collab_members.user_id", value: "eq.\(AuthService.shared.session?.userID ?? "")")]
    }

    private func pullIfNewer(_ id: UUID) async throws {
        struct Row: Decodable { let version: Int; let owner: String; let collab_members: [MyRole]? }
        let data = try await rest("GET", "collab_maps", query: [
            URLQueryItem(name: "select", value: "version,owner,collab_members(role)"),
            URLQueryItem(name: "id", value: "eq.\(id.uuidString)"),
        ] + roleQuery())
        guard let row = try JSONDecoder().decode([Row].self, from: data).first else {
            unshare(id)
            return
        }
        let current = MapStore.shared.map(id)?.collab
        let role = role(owner: row.owner, members: row.collab_members)
        if let current, current.role != role {
            setCollab(id, CollabInfo(isOwner: current.isOwner, version: current.version, role: role))
        }
        if row.version > (current?.version ?? 0) { try await pull(id) }
    }

    private struct RemoteRow: Decodable {
        let id: UUID
        let owner: String
        let version: Int
        let data: MindMap
        let collab_members: [MyRole]?
    }

    func pull(_ id: UUID) async throws {
        let data = try await rest("GET", "collab_maps", query: [
            URLQueryItem(name: "select", value: "id,owner,version,data,collab_members(role)"),
            URLQueryItem(name: "id", value: "eq.\(id.uuidString)"),
        ] + roleQuery())
        guard let row = try MapSync.decoder.decode([RemoteRow].self, from: data).first else { throw CollabError.notFound }
        var remote = row.data
        remote.id = row.id
        let info = CollabInfo(isOwner: row.owner == AuthService.shared.session?.userID, version: row.version,
                              role: role(owner: row.owner, members: row.collab_members))
        let local = MapStore.shared.map(id)
        var result: MindMap
        if let local, local.collab != nil, let base = bases[id] {
            result = CollabMerge.merge(base: base, local: local, remote: remote)
        } else if let local {
            // A copy that wasn't known as shared yet: the shared version wins; personal choices stay.
            result = remote
            result.isPinned = local.isPinned
            result.layout = local.layout
        } else {
            result = remote
        }
        result.collab = info
        MapStore.shared.applySynced(result)
        saveBase(Self.shared(remote))
        synced[id] = Date()
        failed.remove(id)
        await downloadImages(of: result)
        // Our edits on top of theirs go back up (a viewer's never do).
        if info.canEdit, MapSync.hash(Self.shared(result)) != MapSync.hash(Self.shared(remote)) { await push(id) }
    }

    private func pushChanged(_ maps: [MindMap]) {
        for map in maps where map.collab?.canEdit == true {
            guard let base = bases[map.id] else { continue }
            if MapSync.hash(Self.shared(map)) != MapSync.hash(base) { Task { await push(map.id) } }
        }
    }

    // Sends this device's version on top of the version it is based on; if someone else changed
    // the map first, merges and tries again.
    func push(_ id: UUID) async {
        guard let map = MapStore.shared.map(id), let collab = map.collab, collab.canEdit else { return }
        if running.contains(id) {
            again.insert(id)
            return
        }
        running.insert(id)
        busy.insert(id)
        defer {
            running.remove(id)
            busy.remove(id)
            if again.remove(id) != nil { Task { await push(id) } }
        }
        do {
            try await uploadImages(of: map)
            struct Patch: Encodable { let data: MindMap }
            struct Updated: Decodable { let version: Int }
            let shared = Self.shared(map)
            let body = try MapSync.encoder.encode(Patch(data: shared))
            let data = try await rest("PATCH", "collab_maps", query: [
                URLQueryItem(name: "id", value: "eq.\(id.uuidString)"),
                URLQueryItem(name: "version", value: "eq.\(collab.version)"),
                URLQueryItem(name: "select", value: "version"),
            ], body: body, prefer: "return=representation")
            if let updated = try JSONDecoder().decode([Updated].self, from: data).first {
                setCollab(id, CollabInfo(isOwner: collab.isOwner, version: updated.version, role: collab.role))
                saveBase(shared)
                synced[id] = Date()
                failed.remove(id)
                PushService.shared.mapChanged(id)
            } else {
                // Someone was first: take their version, merge ours in, and send again.
                running.remove(id)
                try await pull(id)
            }
        } catch {
            failed.insert(id)
        }
    }

    // MARK: - Pictures (bucket "collab-images/<map id>/<image id>.jpg")

    private func uploadImages(of map: MindMap) async throws {
        for image in map.root.imageIDs {
            let key = "\(map.id.uuidString)/\(image.uuidString)"
            guard !uploaded.contains(key), let bytes = MapStore.shared.imageData(image) else { continue }
            var request = URLRequest(url: BackendConfig.url.appendingPathComponent("storage/v1/object/collab-images/\(key).jpg"))
            request.httpMethod = "POST"
            request.httpBody = bytes
            request.setValue("image/jpeg", forHTTPHeaderField: "Content-Type")
            request.setValue("true", forHTTPHeaderField: "x-upsert")
            _ = try await send(request)
            uploaded.insert(key)
            UserDefaults.standard.set(Array(uploaded), forKey: "collab.uploaded")
        }
    }

    private func downloadImages(of map: MindMap) async {
        for image in map.root.imageIDs where !MapStore.shared.hasImage(image) {
            var request = URLRequest(url: BackendConfig.url.appendingPathComponent("storage/v1/object/authenticated/collab-images/\(map.id.uuidString)/\(image.uuidString).jpg"))
            request.httpMethod = "GET"
            if let data = try? await send(request) { MapStore.shared.storeSyncedImage(image, data: data) }
        }
    }

    // MARK: - Local state

    private func setCollab(_ id: UUID, _ info: CollabInfo?) {
        MapStore.shared.update(id, touch: false) { $0.collab = info }
    }

    private func unshare(_ id: UUID) {
        setCollab(id, nil)
        bases[id] = nil
        watched.remove(id)
        try? FileManager.default.removeItem(at: folder.appendingPathComponent("\(id.uuidString).json"))
    }

    private func saveBase(_ map: MindMap) {
        bases[map.id] = map
        if let data = try? JSONEncoder.iso.encode(map) {
            try? data.write(to: folder.appendingPathComponent("\(map.id.uuidString).json"), options: .atomic)
        }
    }

    func forgetAll() {
        bases = [:]
        uploaded = []
        UserDefaults.standard.removeObject(forKey: "collab.uploaded")
        let files = (try? FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil)) ?? []
        for file in files { try? FileManager.default.removeItem(at: file) }
    }

    // MARK: - HTTP

    private func rest(_ method: String, _ table: String, query: [URLQueryItem] = [], body: Data? = nil, prefer: String? = nil) async throws -> Data {
        var components = URLComponents(url: BackendConfig.url.appendingPathComponent("rest/v1/\(table)"), resolvingAgainstBaseURL: false)!
        if !query.isEmpty { components.queryItems = query }
        var request = URLRequest(url: components.url!)
        request.httpMethod = method
        request.httpBody = body
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        if let prefer { request.setValue(prefer, forHTTPHeaderField: "Prefer") }
        return try await send(request)
    }

    private func rpc<Args: Encodable>(_ name: String, _ args: Args) async throws -> Data {
        var request = URLRequest(url: BackendConfig.url.appendingPathComponent("rest/v1/rpc/\(name)"))
        request.httpMethod = "POST"
        request.httpBody = try JSONEncoder().encode(args)
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        return try await send(request)
    }

    private func send(_ base: URLRequest) async throws -> Data {
        for attempt in 0..<2 {
            var request = base
            let token = try await AuthService.shared.validAccessToken(forceRefresh: attempt > 0)
            request.setValue(BackendConfig.publishableKey, forHTTPHeaderField: "apikey")
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
            let (data, response) = try await BackendClient.shared.send(request)
            if (200..<300).contains(response.statusCode) { return data }
            if response.statusCode == 401 && attempt == 0 { continue }
            // Reasons the database gives on purpose (see 20261005100000_collab_roles.sql).
            struct Failure: Decodable { let code: String? }
            switch (try? JSONDecoder().decode(Failure.self, from: data))?.code {
            case "MA001": throw CollabError.planRequired
            case "MA002": throw CollabError.mapFull
            default: throw BackendError.server(code: "collab_\(response.statusCode)")
            }
        }
        throw BackendError.unauthorized
    }
}
