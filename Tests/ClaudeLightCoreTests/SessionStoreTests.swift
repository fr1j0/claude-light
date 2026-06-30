import XCTest
@testable import ClaudeLightCore

final class SessionStoreTests: XCTestCase {
    private func tempStore() -> SessionStore {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("claude-light-tests-\(UUID().uuidString)")
        return SessionStore(directory: dir)
    }

    private func makeSession(_ id: String, _ status: SessionStatus) -> Session {
        Session(sessionID: id, status: status, project: "p", cwd: "/tmp/p",
                updatedAt: Date(timeIntervalSince1970: 1_719_745_200))
    }

    func test_write_then_loadAll_returnsSession() throws {
        let store = tempStore()
        try store.write(makeSession("a", .running))
        let all = try store.loadAll()
        XCTAssertEqual(all.count, 1)
        XCTAssertEqual(all.first?.sessionID, "a")
        XCTAssertEqual(all.first?.status, .running)
    }

    func test_write_isUpsert() throws {
        let store = tempStore()
        try store.write(makeSession("a", .running))
        try store.write(makeSession("a", .idle))
        let all = try store.loadAll()
        XCTAssertEqual(all.count, 1)
        XCTAssertEqual(all.first?.status, .idle)
    }

    func test_delete_removesFile_andIsIdempotent() throws {
        let store = tempStore()
        try store.write(makeSession("a", .running))
        try store.delete(sessionID: "a")
        XCTAssertEqual(try store.loadAll().count, 0)
        XCTAssertNoThrow(try store.delete(sessionID: "a")) // already gone
    }

    func test_loadAll_onMissingDirectory_returnsEmpty() throws {
        let store = tempStore() // never created
        XCTAssertEqual(try store.loadAll().count, 0)
    }

    func test_loadAll_skipsCorruptFiles() throws {
        let store = tempStore()
        try store.write(makeSession("a", .running))
        try FileManager.default.createDirectory(at: store.directory, withIntermediateDirectories: true)
        try Data("not json".utf8).write(to: store.fileURL(for: "broken"))
        let all = try store.loadAll()
        XCTAssertEqual(all.count, 1)
        XCTAssertEqual(all.first?.sessionID, "a")
    }
}
