//
//  GenerationCenter.swift
//  Minor Ai
//
//  Map generation jobs that outlive the Building screen: the user can leave, the map keeps
//  building, shows up in Your Maps as "Building… N%" and announces itself when ready.
//

import UIKit
import UserNotifications

@MainActor
final class GenerationCenter: ObservableObject {
    static let shared = GenerationCenter()

    struct Job: Identifiable, Equatable {
        let id: UUID            // becomes the map id when it is ready
        let input: MapInput
        var model = AIModelCatalog.defaultMap
        let startedAt: Date
        var step = 0            // 0 reading · 1 main ideas · 2 branches · 3 details · 4 done
        var error: BackendError?

        var label: String {
            switch input {
            case .topic(let topic): return topic
            case .link(let url), .youtube(let url): return URL(string: url)?.host ?? url
            case .text(_, let source): return source.label
            }
        }

        // Rough progress for the Your Maps card: generation usually takes 10–20 seconds.
        var progress: Int {
            if step >= 4 { return 100 }
            // Clamped, so moving the device clock can't show negative or runaway progress.
            let elapsed = max(0, Date().timeIntervalSince(startedAt))
            return min(95, Int(elapsed / 20 * 100))
        }
    }

    @Published private(set) var jobs: [UUID: Job] = [:]
    @Published var ready: UUID?    // a map that finished while its screen was closed
    @Published var openRequest: UUID?   // a "map is ready" notification was tapped
    @Published var focusNode: UUID?     // an idea to select once its map is open (task reminders, Today)
    @Published var topicRequest: String?  // "Create Mind Map" from Siri or Shortcuts
    @Published var todayRequest = false   // the Today widget was tapped
    @Published var studyRequest: UUID?    // open Study for this map (Today → Review)
    @Published var routeRequest: URL?     // a notification that opens a screen (minorai://…)

    private var tasks: [UUID: Task<Void, Never>] = [:]
    private var watched: Set<UUID> = []
    private var notify: Set<UUID> = []

    var running: [Job] { jobs.values.sorted { $0.startedAt > $1.startedAt } }

    func start(_ input: MapInput, model: AIModelOption = AIModelCatalog.defaultMap) -> UUID {
        // A second tap on Build, or the same source again, joins the job already running.
        if let running = jobs.values.first(where: { $0.input == input && $0.model == model && $0.error == nil }) {
            return running.id
        }
        let id = UUID()
        jobs[id] = Job(id: id, input: input, model: model, startedAt: Date())
        run(id)
        return id
    }

    func retry(_ id: UUID) {
        guard let job = jobs[id] else { return }
        // A model the plan no longer includes falls back to the standard one.
        let model = AccountStore.shared.allowsMaps(with: job.model) ? job.model : AIModelCatalog.defaultMap
        jobs[id] = Job(id: id, input: job.input, model: model, startedAt: Date())
        run(id)
    }

    func cancel(_ id: UUID) {
        tasks[id]?.cancel()
        tasks[id] = nil
        jobs[id] = nil
        notify.remove(id)
        watched.remove(id)
    }

    // Account deleted or data erased: nothing may be saved afterwards.
    func cancelAll() {
        for id in Array(jobs.keys) { cancel(id) }
        ready = nil
        openRequest = nil
    }

    // "Build in Background": ask once for permission, then send a notification when the map is ready.
    func notifyWhenReady(_ id: UUID) {
        notify.insert(id)
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { _, _ in }
    }

    // The Building screen tells the center whether someone is looking at a job.
    func watch(_ id: UUID, _ isWatching: Bool) {
        if isWatching { watched.insert(id) } else { watched.remove(id) }
    }

    private func run(_ id: UUID) {
        tasks[id]?.cancel()
        tasks[id] = Task { [weak self] in
            guard let self, let job = self.jobs[id] else { return }
            let input = job.input
            // Keeps the request alive for a while if the user leaves the app mid-generation.
            let background = BackgroundTime(name: "Build map")
            defer { background.end() }
            let ticker = Task { [weak self] in
                for next in 1...2 {
                    try? await Task.sleep(nanoseconds: 2_500_000_000)
                    guard !Task.isCancelled else { return }
                    self?.advance(id, to: next)
                }
            }
            defer { ticker.cancel() }
            do {
                let generated = try await MapService.shared.generate(input, model: job.model)
                let root = generated.root
                guard !Task.isCancelled, self.jobs[id] != nil else { return }
                self.advance(id, to: 4)
                var source = input.source
                if generated.truncated { source.label += L(" · first part") }
                MapStore.shared.save(MindMap(id: id, root: root, source: source))
                Telemetry.log("map_created", [
                    "source": input.source.kind.rawValue, "model": job.model.apiModelID,
                    "branches": root.children.count, "seconds": Int(Date().timeIntervalSince(job.startedAt)),
                ])
                // The map exists now; the job goes at once so it is never listed twice.
                self.jobs[id] = nil
                self.tasks[id] = nil
                AccountStore.shared.noteMapCreated()
                Haptics.success()
                if !self.watched.contains(id) { self.ready = id }
                if self.notify.remove(id) != nil, UIApplication.shared.applicationState != .active {
                    Self.postReadyNotification(id: id, title: root.title)
                }
                Task { await AccountStore.shared.refresh() }
            } catch is CancellationError {
                return
            } catch {
                guard !Task.isCancelled, self.jobs[id] != nil else { return }
                Telemetry.log("map_failed", ["source": input.source.kind.rawValue])
                if case BackendError.limitReached(let kind) = error { AccountStore.shared.noteLimitReached(kind: kind) }
                Haptics.error()
                self.jobs[id]?.error = (error as? BackendError) ?? .aiFailed
                self.jobs[id]?.step = min(self.jobs[id]?.step ?? 0, 2)
                self.tasks[id] = nil
            }
        }
    }

    private static func postReadyNotification(id: UUID, title: String) {
        let content = UNMutableNotificationContent()
        content.title = L("Your map is ready")
        content.body = L("“\(title)” is waiting in Your Maps.")
        content.sound = .default
        content.userInfo = ["mapID": id.uuidString]
        UNUserNotificationCenter.current().add(UNNotificationRequest(identifier: id.uuidString, content: content, trigger: nil))
    }

    private func advance(_ id: UUID, to step: Int) {
        guard let current = jobs[id]?.step, current < step else { return }
        jobs[id]?.step = step
    }
}

extension MainActor {
    // MainActor.assumeIsolated is iOS 17+; on iOS 16 the caller is already on the main thread.
    nonisolated static func assumeIsolatedCompat(_ body: @MainActor () -> Void) {
        if #available(iOS 17, *) {
            MainActor.assumeIsolated(body)
        } else {
            precondition(Thread.isMainThread)
            withoutActuallyEscaping(body) { body in
                unsafeBitCast(body, to: (() -> Void).self)()
            }
        }
    }
}

// A UIKit background task that always ends, either when the work is done or when iOS asks.
@MainActor
final class BackgroundTime {
    private var identifier: UIBackgroundTaskIdentifier = .invalid

    init(name: String) {
        // iOS calls the expiration handler on the main thread and expects the task to end
        // before it returns, so it is ended right there rather than in a later Task.
        identifier = UIApplication.shared.beginBackgroundTask(withName: name) { [weak self] in
            MainActor.assumeIsolatedCompat { self?.end() }
        }
    }

    func end() {
        guard identifier != .invalid else { return }
        UIApplication.shared.endBackgroundTask(identifier)
        identifier = .invalid
    }
}
