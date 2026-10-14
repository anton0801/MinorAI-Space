//
//  AppFolders.swift
//  Minor Ai
//
//  Where the app keeps its files: Application Support, or (DEBUG builds, -isolatedStore <name>)
//  a separate empty folder for that run, so recordings and screenshots show only the sample data
//  and never read or change what is already on the device.
//

import Foundation

#if DEBUG
// The isolated folder starts empty in every launch (each recorded scene sets up its own data).
private let isolatedSupport: URL? = {
    let args = ProcessInfo.processInfo.arguments
    guard let i = args.firstIndex(of: "-isolatedStore"), args.indices.contains(i + 1) else { return nil }
    let root = FileManager.default.temporaryDirectory.appendingPathComponent("isolated-\(args[i + 1])", isDirectory: true)
    try? FileManager.default.removeItem(at: root)
    let url = root.appendingPathComponent("Application Support", isDirectory: true)
    try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    return url
}()
#endif

extension FileManager {
    var appSupportURL: URL {
        #if DEBUG
        if let isolatedSupport { return isolatedSupport }
        #endif
        return urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
    }
}

#if DEBUG
enum TestRun {
    // Recordings (-noSync) and UI tests (-auditSignedOut, the tests' own sign-in slot): nothing is
    // sent to the server, whoever is signed in on the simulator.
    static let offServer: Bool = {
        let args = ProcessInfo.processInfo.arguments
        return args.contains("-noSync") || args.contains("-auditSignedOut")
    }()
}
#endif
