//
//  MapStore.swift
//  Minor Ai
//
//  Keeps maps as JSON files in Application Support/Maps. Maps grow quickly,
//  so unlike conversations they do not live in UserDefaults.
//

import Foundation
import UIKit

@MainActor
final class MapStore: ObservableObject {
    static let shared = MapStore()

    @Published private(set) var maps: [MindMap] = []
    // Maps whose last write failed (for example, the disk is full); the editor shows "Not saved"
    // and the next successful write clears it.
    @Published private(set) var failedSaves: Set<UUID> = []

    private let folder: URL
    private let imagesFolder: URL
    private let historyFolder: URL
    // When each map's last version was kept (see Version history).
    private var lastVersion: [UUID: Date] = [:]
    private let imageCache = NSCache<NSUUID, UIImage>()
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()
    // Writes and deletes run in order off the main thread, so large maps don't stall the canvas
    // and a delete can never be undone by a write that was still queued.
    private let io = DispatchQueue(label: "com.minorailifegroup.MinorAI.maps", qos: .utility)

    private init() {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        folder = base.appendingPathComponent("Maps", isDirectory: true)
        imagesFolder = folder.appendingPathComponent("Images", isDirectory: true)
        historyFolder = folder.appendingPathComponent("History", isDirectory: true)
        try? FileManager.default.createDirectory(at: imagesFolder, withIntermediateDirectories: true)
        try? FileManager.default.createDirectory(at: historyFolder, withIntermediateDirectories: true)
        encoder.dateEncodingStrategy = .iso8601
        decoder.dateDecodingStrategy = .iso8601
        load()
        removeUnusedImages()
    }

    var pinned: [MindMap] { maps.filter(\.isPinned) }
    var recent: [MindMap] { maps.filter { !$0.isPinned } }

    func map(_ id: UUID) -> MindMap? { maps.first { $0.id == id } }

    // Saves a map, adding it when it is new.
    func save(_ map: MindMap) {
        var map = map
        map.updatedAt = Date()
        if let index = maps.firstIndex(where: { $0.id == map.id }) {
            maps[index] = map
        } else {
            maps.append(map)
        }
        sort()
        write(map)
    }

    // Changes the stored map in place. Does nothing (and returns nil) when the map was deleted
    // meanwhile, so late AI results never bring a deleted map back.
    @discardableResult
    func update(_ id: UUID, touch: Bool = true, _ change: (inout MindMap) -> Void) -> MindMap? {
        guard let index = maps.firstIndex(where: { $0.id == id }) else { return nil }
        var map = maps[index]
        if touch { keepVersion(map) }
        change(&map)
        if touch { map.updatedAt = Date() }
        maps[index] = map
        if touch { sort() }
        write(map)
        return map
    }

    func delete(_ id: UUID) {
        guard maps.contains(where: { $0.id == id }) else { return }
        // Other devices learn about the delete through sync.
        MapSync.shared.noteDeleted(id)
        maps.removeAll { $0.id == id }
        // A deleted map shouldn't stay public.
        if SharedMaps.contains(id) { SharedMaps.stopOrQueue(id) }
        let url = file(for: id)
        let history = historyFolder.appendingPathComponent(id.uuidString, isDirectory: true)
        io.async {
            try? FileManager.default.removeItem(at: url)
            try? FileManager.default.removeItem(at: history)
        }
    }

    // MARK: - Version history

    struct Version: Identifiable, Equatable {
        let url: URL
        let date: Date
        var id: URL { url }
    }

    static let versionInterval: TimeInterval = 10 * 60
    static let versionsKept = 30

    // Versions of a map kept on this device, newest first.
    func versions(of id: UUID) -> [Version] {
        let folder = historyFolder.appendingPathComponent(id.uuidString, isDirectory: true)
        let files = (try? FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil)) ?? []
        return files.compactMap { url in
            guard url.pathExtension == "json", let seconds = Double(url.deletingPathExtension().lastPathComponent) else { return nil }
            return Version(url: url, date: Date(timeIntervalSince1970: seconds))
        }
        .sorted { $0.date > $1.date }
    }

    func load(_ version: Version) -> MindMap? {
        guard let data = try? Data(contentsOf: version.url) else { return nil }
        return try? decoder.decode(MindMap.self, from: data)
    }

    // Brings back an earlier version; the current one is kept as a version first, so a restore
    // can itself be undone.
    func restore(_ version: Version, of id: UUID) {
        guard let old = load(version), let current = map(id) else { return }
        keepVersion(current, force: true)
        update(id) { map in
            map.root = old.root
            map.links = old.links
        }
    }

    // Keeps the map as it was before this write, at most every 10 minutes per map.
    private func keepVersion(_ map: MindMap, force: Bool = false) {
        let now = Date()
        if !force, let last = lastVersion[map.id], now.timeIntervalSince(last) < Self.versionInterval { return }
        guard let data = try? encoder.encode(map) else { return }
        lastVersion[map.id] = now
        let folder = historyFolder.appendingPathComponent(map.id.uuidString, isDirectory: true)
        let url = folder.appendingPathComponent("\(Int(now.timeIntervalSince1970)).json")
        let kept = Self.versionsKept
        io.async {
            try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            try? data.write(to: url, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
            let files = ((try? FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil)) ?? [])
                .filter { $0.pathExtension == "json" }
                .sorted { $0.lastPathComponent > $1.lastPathComponent }
            for old in files.dropFirst(kept) { try? FileManager.default.removeItem(at: old) }
        }
    }

    // Every map file, including ones set aside as unreadable. Local only: after account deletion
    // the server has already removed shared images.
    func deleteAll() {
        MapSync.shared.forget()
        maps = []
        failedSaves = []
        SharedMaps.clear()
        let folder = folder
        let imagesFolder = imagesFolder
        let historyFolder = historyFolder
        imageCache.removeAllObjects()
        io.async {
            let files = (try? FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil)) ?? []
            for file in files { try? FileManager.default.removeItem(at: file) }
            try? FileManager.default.createDirectory(at: imagesFolder, withIntermediateDirectories: true)
            try? FileManager.default.createDirectory(at: historyFolder, withIntermediateDirectories: true)
        }
        lastVersion = [:]
    }

    // MARK: - Sync (MapSync)

    // A map from another device, kept exactly as it came (its own edit date included).
    func applySynced(_ map: MindMap) {
        if let index = maps.firstIndex(where: { $0.id == map.id }) {
            maps[index] = map
        } else {
            maps.append(map)
        }
        sort()
        write(map)
    }

    // A map deleted on another device.
    func removeSynced(_ id: UUID) {
        guard maps.contains(where: { $0.id == id }) else { return }
        maps.removeAll { $0.id == id }
        let url = file(for: id)
        io.async { try? FileManager.default.removeItem(at: url) }
    }

    func hasImage(_ id: UUID) -> Bool {
        FileManager.default.fileExists(atPath: imageURL(id).path)
    }

    // A picture downloaded for a synced map, stored under its own id.
    func storeSyncedImage(_ id: UUID, data: Data) {
        guard UIImage(data: data) != nil else { return }
        let url = imageURL(id)
        io.async { try? data.write(to: url, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication]) }
    }

    func togglePin(_ id: UUID) {
        update(id, touch: false) { $0.isPinned.toggle() }
    }

    func duplicate(_ id: UUID) -> MindMap? {
        guard var copy = map(id) else { return nil }
        copy.id = UUID()
        copy.isPinned = false
        copy.createdAt = Date()
        copy.root.title += " copy"
        save(copy)
        return copy
    }

    // MARK: - Pictures on nodes

    // Saves a picture for a node: at most 1600 px on the long side, JPEG. Returns nil if it isn't an image.
    func storeImage(_ data: Data, isAI: Bool) -> NodeImage? {
        guard let source = UIImage(data: data), source.size.width > 0, source.size.height > 0 else { return nil }
        let scale = min(1, 1600 / max(source.size.width, source.size.height))
        let size = CGSize(width: (source.size.width * scale).rounded(), height: (source.size.height * scale).rounded())
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        let image = UIGraphicsImageRenderer(size: size, format: format).image { _ in source.draw(in: CGRect(origin: .zero, size: size)) }
        guard let jpeg = image.jpegData(compressionQuality: 0.85) else { return nil }
        let picture = NodeImage(id: UUID(), aspect: Double(size.height / size.width), isAI: isAI)
        let url = imageURL(picture.id)
        imageCache.setObject(image, forKey: picture.id as NSUUID)
        io.async { try? jpeg.write(to: url, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication]) }
        return picture
    }

    func image(_ id: UUID) -> UIImage? {
        if let cached = imageCache.object(forKey: id as NSUUID) { return cached }
        guard let image = UIImage(contentsOfFile: imageURL(id).path) else { return nil }
        imageCache.setObject(image, forKey: id as NSUUID)
        return image
    }

    func imageData(_ id: UUID) -> Data? {
        try? Data(contentsOf: imageURL(id))
    }

    private func imageURL(_ id: UUID) -> URL {
        imagesFolder.appendingPathComponent("\(id.uuidString).jpg")
    }

    // Pictures no map refers to any more (deleted nodes, maps or replaced pictures). Undo keeps
    // working during a session because this only runs at launch.
    private func removeUnusedImages() {
        let used = Set(maps.flatMap { $0.root.imageIDs }.map(\.uuidString))
        let folder = imagesFolder
        io.async {
            let files = (try? FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil)) ?? []
            for file in files where !used.contains(file.deletingPathExtension().lastPathComponent) {
                try? FileManager.default.removeItem(at: file)
            }
        }
    }

    // Waits until queued writes reach the disk (used before the app is suspended).
    nonisolated func flush() {
        io.sync {}
    }

    private func write(_ map: MindMap) {
        let id = map.id
        guard let data = try? encoder.encode(map) else {
            failedSaves.insert(id)
            return
        }
        let url = file(for: id)
        io.async {
            let saved = (try? data.write(to: url, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])) != nil
            Task { @MainActor in
                let store = MapStore.shared
                if saved {
                    if store.failedSaves.contains(id) { store.failedSaves.remove(id) }
                } else if store.map(id) != nil {
                    store.failedSaves.insert(id)
                }
            }
        }
    }

    private func load() {
        let files = (try? FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil)) ?? []
        maps = files
            .filter { $0.pathExtension == "json" }
            .compactMap { url in
                guard let data = try? Data(contentsOf: url) else { return nil }
                if let map = try? decoder.decode(MindMap.self, from: data) { return map }
                // Keep unreadable files aside instead of losing them.
                let aside = url.deletingPathExtension().appendingPathExtension("unreadable")
                try? FileManager.default.moveItem(at: url, to: aside)
                return nil
            }
        sort()
    }

    private func sort() {
        maps.sort { $0.updatedAt > $1.updatedAt }
    }

    private func file(for id: UUID) -> URL {
        folder.appendingPathComponent("\(id.uuidString).json")
    }
}
