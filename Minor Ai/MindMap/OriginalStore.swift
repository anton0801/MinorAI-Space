//
//  OriginalStore.swift
//  Minor Ai
//
//  Originals of materials (PDFs, scans, voice recordings) in the app's private folder,
//  Application Support/Originals, named by their SHA-256 so the same file is kept once. A file is
//  copied in while the picked copy can still be read: first to a temporary file, then hashed, then
//  moved to its name, so a failed or interrupted copy never shows as a kept original. Nothing here
//  is uploaded or shared; files no material uses any more are removed.
//

import CryptoKit
import Foundation
import UniformTypeIdentifiers

enum OriginalStore {
    enum ImportError: LocalizedError {
        case noSpace
        case unreadable
        case writeFailed

        var errorDescription: String? {
            switch self {
            case .noSpace: return L("Not enough space on this iPhone to keep the original. The text is saved.")
            case .unreadable: return L("Couldn’t read the file to keep its original. The text is saved.")
            case .writeFailed: return L("Couldn’t keep the original. The text is saved.")
            }
        }
    }

    static let folder: URL = {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        let folder = base.appendingPathComponent("Originals", isDirectory: true)
        try? FileManager.default.createDirectory(at: folder.appendingPathComponent(".incoming", isDirectory: true), withIntermediateDirectories: true)
        return folder
    }()

    static var incoming: URL { folder.appendingPathComponent(".incoming", isDirectory: true) }

    // The kept file, when it is still there.
    static func url(for asset: OriginalAsset) -> URL? {
        guard asset.state == .ready, !asset.path.contains("/"), !asset.path.hasPrefix(".") else { return nil }
        let url = folder.appendingPathComponent(asset.path)
        return FileManager.default.fileExists(atPath: url.path) ? url : nil
    }

    // Keeps a copy of a picked file (call off the main thread). The picked URL is read while it is
    // accessible; the copy is checked and named by its hash.
    static func keep(fileAt source: URL, name: String) throws -> OriginalAsset {
        let scoped = source.startAccessingSecurityScopedResource()
        defer { if scoped { source.stopAccessingSecurityScopedResource() } }
        let size = (try? source.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0
        try checkSpace(for: size)
        let ext = source.pathExtension.lowercased()
        let temporary = incoming.appendingPathComponent("\(UUID().uuidString).\(ext.isEmpty ? "bin" : ext)")
        do {
            try FileManager.default.copyItem(at: source, to: temporary)
        } catch {
            try? FileManager.default.removeItem(at: temporary)
            throw isOutOfSpace(error) ? ImportError.noSpace : ImportError.unreadable
        }
        return try adopt(temporary, name: name, mime: mime(for: ext))
    }

    // Keeps data made in the app (a scan put together as a PDF).
    static func keep(data: Data, ext: String, name: String) throws -> OriginalAsset {
        try checkSpace(for: data.count)
        let temporary = incoming.appendingPathComponent("\(UUID().uuidString).\(ext)")
        do {
            try data.write(to: temporary, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
        } catch {
            try? FileManager.default.removeItem(at: temporary)
            throw isOutOfSpace(error) ? ImportError.noSpace : ImportError.writeFailed
        }
        return try adopt(temporary, name: name, mime: mime(for: ext))
    }

    // A finished file in the incoming folder (a recording written there) becomes a kept original:
    // hashed, then moved to its name. The temporary file is gone either way.
    static func adopt(_ temporary: URL, name: String, mime: String) throws -> OriginalAsset {
        defer { try? FileManager.default.removeItem(at: temporary) }
        guard let hash = sha256(of: temporary) else { throw ImportError.unreadable }
        let size = (try? temporary.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0
        let ext = temporary.pathExtension.lowercased()
        let fileName = "\(hash).\(ext)"
        let target = folder.appendingPathComponent(fileName)
        if FileManager.default.fileExists(atPath: target.path) {
            // The same file kept before: fresh again, so a cleanup now doesn't take it.
            try? FileManager.default.setAttributes([.modificationDate: Date()], ofItemAtPath: target.path)
        } else {
            do {
                try FileManager.default.moveItem(at: temporary, to: target)
                try? (target as NSURL).setResourceValue(URLFileProtection.completeUntilFirstUserAuthentication, forKey: .fileProtectionKey)
            } catch {
                throw isOutOfSpace(error) ? ImportError.noSpace : ImportError.writeFailed
            }
        }
        return OriginalAsset(path: fileName, mime: mime, size: size, sha256: hash, name: String(name.prefix(200)))
    }

    // SHA-256 of a file, read a megabyte at a time.
    static func sha256(of url: URL) -> String? {
        guard let handle = try? FileHandle(forReadingFrom: url) else { return nil }
        defer { try? handle.close() }
        var hasher = SHA256()
        while true {
            let chunk = autoreleasepool { (try? handle.read(upToCount: 1_048_576)) ?? nil }
            guard let chunk, !chunk.isEmpty else { break }
            hasher.update(data: chunk)
        }
        return hasher.finalize().map { String(format: "%02x", $0) }.joined()
    }

    // Removes kept files that no material uses (after a material, an original or a map is
    // removed), and temporary files left by an interrupted copy.
    // A file kept in the last minutes may belong to a material whose save is still on its way:
    // only older files are ever removed.
    static func removeUnused(keeping used: Set<String>) {
        let files = (try? FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: [.contentModificationDateKey])) ?? []
        for file in files where !file.lastPathComponent.hasPrefix(".") && !used.contains(file.lastPathComponent) {
            let changed = (try? file.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? Date()
            guard Date().timeIntervalSince(changed) > 600 else { continue }
            try? FileManager.default.removeItem(at: file)
        }
        let stale = (try? FileManager.default.contentsOfDirectory(at: incoming, includingPropertiesForKeys: [.contentModificationDateKey])) ?? []
        for file in stale {
            let changed = (try? file.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast
            if Date().timeIntervalSince(changed) > 3600 { try? FileManager.default.removeItem(at: file) }
        }
    }

    static func removeAll() {
        try? FileManager.default.removeItem(at: folder)
        try? FileManager.default.createDirectory(at: incoming, withIntermediateDirectories: true)
    }

    static func mime(for ext: String) -> String {
        UTType(filenameExtension: ext)?.preferredMIMEType ?? "application/octet-stream"
    }

    // Room for the file and a margin, so keeping it never fills the phone.
    private static func checkSpace(for size: Int) throws {
        let values = try? folder.resourceValues(forKeys: [.volumeAvailableCapacityForImportantUsageKey])
        if let free = values?.volumeAvailableCapacityForImportantUsage, free < Int64(size) + 50_000_000 {
            throw ImportError.noSpace
        }
    }

    private static func isOutOfSpace(_ error: Error) -> Bool {
        let ns = error as NSError
        if ns.domain == NSCocoaErrorDomain && ns.code == NSFileWriteOutOfSpaceError { return true }
        if ns.domain == NSPOSIXErrorDomain && ns.code == Int(ENOSPC) { return true }
        return (ns.userInfo[NSUnderlyingErrorKey] as? NSError).map { isOutOfSpace($0) } ?? false
    }
}
