import Foundation
import Combine
import CoreServices
import ClaudeLightCore

@MainActor
final class SessionWatcher: ObservableObject {
    @Published private(set) var sessions: [Session] = []
    @Published private(set) var light: AggregateLight = .green
    @Published var hooksInstalled: Bool = false

    private let store: SessionStore
    private let installer: HookInstaller
    private var stream: FSEventStreamRef?
    private var timer: Timer?
    private var started = false

    init(store: SessionStore, installer: HookInstaller) {
        self.store = store
        self.installer = installer
    }

    /// Call exactly once. Idempotent: subsequent calls are no-ops.
    func start() {
        guard !started else { return }
        started = true
        hooksInstalled = installer.isInstalled()
        try? FileManager.default.createDirectory(at: store.directory, withIntermediateDirectories: true)
        reload()
        startFSEvents()
        // Re-evaluate staleness even when no file changes.
        timer = Timer.scheduledTimer(withTimeInterval: 30, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.reload() }
        }
    }

    /// Installs the Claude Code hooks and refreshes the published install state.
    func installHooks() {
        try? installer.install()
        hooksInstalled = installer.isInstalled()
    }

    /// Removes the Claude Code hooks and refreshes the published install state.
    func removeHooks() {
        try? installer.uninstall()
        hooksInstalled = installer.isInstalled()
    }

    func reload() {
        let all = (try? store.loadAll()) ?? []
        let live = liveSessions(all, now: Date())
            .sorted { $0.project < $1.project }
        self.sessions = live
        self.light = aggregateLight(for: live)
    }

    private func startFSEvents() {
        let callback: FSEventStreamCallback = { _, info, _, _, _, _ in
            guard let info else { return }
            let watcher = Unmanaged<SessionWatcher>.fromOpaque(info).takeUnretainedValue()
            Task { @MainActor in watcher.reload() }
        }
        var context = FSEventStreamContext(
            version: 0,
            info: Unmanaged.passUnretained(self).toOpaque(),
            retain: nil, release: nil, copyDescription: nil
        )
        let stream = FSEventStreamCreate(
            kCFAllocatorDefault, callback, &context,
            [store.directory.path] as CFArray,
            FSEventStreamEventId(kFSEventStreamEventIdSinceNow),
            0.3,
            UInt32(kFSEventStreamCreateFlagFileEvents | kFSEventStreamCreateFlagNoDefer)
        )
        self.stream = stream
        if let stream {
            FSEventStreamSetDispatchQueue(stream, DispatchQueue.main)
            FSEventStreamStart(stream)
        }
    }
}
