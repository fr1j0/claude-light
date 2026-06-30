import XCTest
@testable import ClaudeLightCore

final class ApplyHookTests: XCTestCase {
    private func tempStore() -> SessionStore {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("claude-light-apply-\(UUID().uuidString)")
        return SessionStore(directory: dir)
    }

    private let now = Date(timeIntervalSince1970: 1_719_745_200)

    func test_setAction_writesSession_withProjectFromCwd() throws {
        let store = tempStore()
        let p = HookPayload(sessionID: "s1", hookEventName: "UserPromptSubmit", cwd: "/Users/x/vatios", message: nil)
        try applyHook(p, to: store, now: now)
        let s = try XCTUnwrap(try store.loadAll().first)
        XCTAssertEqual(s.status, .running)
        XCTAssertEqual(s.project, "vatios")
        XCTAssertEqual(s.updatedAt, now)
    }

    func test_ignoreAction_writesNothing() throws {
        let store = tempStore()
        let p = HookPayload(sessionID: "s1", hookEventName: "Notification", cwd: "/x", message: "Claude is waiting for your input")
        try applyHook(p, to: store, now: now)
        XCTAssertEqual(try store.loadAll().count, 0)
    }

    func test_deleteAction_removesSession() throws {
        let store = tempStore()
        try applyHook(HookPayload(sessionID: "s1", hookEventName: "Stop", cwd: "/x/p", message: nil), to: store, now: now)
        try applyHook(HookPayload(sessionID: "s1", hookEventName: "SessionEnd", cwd: nil, message: nil), to: store, now: now)
        XCTAssertEqual(try store.loadAll().count, 0)
    }

    func test_missingCwd_projectIsUnknown() throws {
        let store = tempStore()
        try applyHook(HookPayload(sessionID: "s1", hookEventName: "Stop", cwd: nil, message: nil), to: store, now: now)
        XCTAssertEqual(try store.loadAll().first?.project, "unknown")
    }
}
