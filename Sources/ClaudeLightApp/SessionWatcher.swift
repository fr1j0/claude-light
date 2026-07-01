import Foundation
import Combine
import CoreServices
import AppKit
import ClaudeLightCore

@MainActor
final class SessionWatcher: ObservableObject {
    @Published private(set) var sessions: [Session] = []
    @Published var hooksInstalled: Bool = false
    @Published private(set) var errorReasons: [String: String] = [:]
    @Published private(set) var icon: IconState = IconState(red: .off, orange: .off, green: .off)
    @Published private(set) var summary: String? = nil
    @Published private(set) var animationPhase: Double = 0
    @Published private(set) var isDarkMenuBar: Bool = true
    @Published private(set) var runnersBySession: [String: RunnerList] = [:]
    /// Opt-in: show a running session's parallel runners as indented rows.
    @Published var showRunners: Bool {
        didSet {
            UserDefaults.standard.set(showRunners, forKey: Self.showRunnersKey)
            reload()
        }
    }

    private static let showRunnersKey = "showRunners"
    private let store: SessionStore
    private let installer: HookInstaller
    private var stream: FSEventStreamRef?
    private var staleTimer: Timer?
    private var clockTimer: Timer?
    private var started = false
    private let clockInterval: TimeInterval = 0.08

    init(store: SessionStore, installer: HookInstaller) {
        self.store = store
        self.installer = installer
        self.showRunners = UserDefaults.standard.bool(forKey: Self.showRunnersKey)
    }

    /// Call exactly once. Idempotent: subsequent calls are no-ops.
    func start() {
        guard !started else { return }
        started = true
        hooksInstalled = installer.isInstalled()
        updateAppearance()
        observeAppearance()
        try? FileManager.default.createDirectory(at: store.directory, withIntermediateDirectories: true)
        reload()
        startFSEvents()
        staleTimer = Timer.scheduledTimer(withTimeInterval: 30, repeats: true) { [weak self] _ in
            guard let self else { return }
            Task { @MainActor in self.reload() }
        }
    }

    func installHooks() {
        try? installer.install()
        hooksInstalled = installer.isInstalled()
    }

    func removeHooks() {
        try? installer.uninstall()
        hooksInstalled = installer.isInstalled()
    }

    func reload() {
        let all = (try? store.loadAll()) ?? []
        var live = liveSessions(all, now: Date())
        var reasons: [String: String] = [:]
        var runnerMap: [String: RunnerList] = [:]
        for i in live.indices where live[i].status == .running {
            guard let path = live[i].transcriptPath else { continue }
            if let tail = transcriptTail(path: path),
               let reason = apiErrorReason(transcriptJSONL: tail) {
                live[i].status = .error
                reasons[live[i].sessionID] = reason
                continue                                  // errored → not a running runner host
            }
            if showRunners, let wide = transcriptTail(path: path, maxBytes: 4 * 1024 * 1024) {
                let list = runners(fromTranscript: wide)
                if !list.isEmpty { runnerMap[live[i].sessionID] = list }
            }
        }
        let sorted = sortedForMenu(live)
        self.sessions = sorted
        self.errorReasons = reasons
        self.runnersBySession = runnerMap
        let state = iconState(for: sorted)
        self.icon = state
        self.summary = summaryText(for: statusCounts(for: sorted))
        updateClock(animating: state.isAnimating)
    }

    /// Reads the last `maxBytes` of a transcript file (whole file if smaller).
    /// Fail-safe: returns nil on any error. A partial first line is fine —
    /// `apiErrorReason` scans bottom-up and skips unparseable lines.
    private func transcriptTail(path: String, maxBytes: Int = 64 * 1024) -> String? {
        guard let handle = FileHandle(forReadingAtPath: path) else { return nil }
        defer { try? handle.close() }
        guard let end = try? handle.seekToEnd() else { return nil }
        let start = end > UInt64(maxBytes) ? end - UInt64(maxBytes) : 0
        try? handle.seek(toOffset: start)
        guard let data = try? handle.readToEnd(), !data.isEmpty else { return nil }
        return String(decoding: data, as: UTF8.self)
    }

    /// Runs the animation clock only while a lamp is blinking or breathing.
    private func updateClock(animating: Bool) {
        if animating {
            guard clockTimer == nil else { return }
            clockTimer = Timer.scheduledTimer(withTimeInterval: clockInterval, repeats: true) { [weak self] _ in
                guard let self else { return }
                Task { @MainActor in self.animationPhase += self.clockInterval }
            }
        } else {
            clockTimer?.invalidate()
            clockTimer = nil
            animationPhase = 0
        }
    }

    // MARK: - Menu-bar appearance (for the adaptive mono color)

    private func updateAppearance() {
        let match = NSApp.effectiveAppearance.bestMatch(from: [.darkAqua, .aqua])
        isDarkMenuBar = (match == .darkAqua)
    }

    private func observeAppearance() {
        DistributedNotificationCenter.default().addObserver(
            forName: Notification.Name("AppleInterfaceThemeChangedNotification"),
            object: nil, queue: .main
        ) { [weak self] _ in
            guard let self else { return }
            Task { @MainActor in self.updateAppearance() }
        }
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
