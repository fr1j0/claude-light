import Foundation
import Combine
import CoreServices
import AppKit
import ClaudeLightCore

@MainActor
final class SessionWatcher: ObservableObject {
    @Published private(set) var sessions: [Session] = []
    @Published var hooksInstalled: Bool = false
    @Published private(set) var icon: IconState = IconState(lamp: .off, blink: false, breathe: false)
    @Published private(set) var summary: String? = nil
    @Published private(set) var animationPhase: Double = 0
    @Published private(set) var isDarkMenuBar: Bool = true

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
        let live = sortedForMenu(liveSessions(all, now: Date()))
        self.sessions = live
        let state = iconState(for: live)
        self.icon = state
        self.summary = summaryText(for: statusCounts(for: live))
        updateClock(animating: state.blink || state.breathe)
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
