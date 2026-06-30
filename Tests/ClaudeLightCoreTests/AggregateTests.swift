import XCTest
@testable import ClaudeLightCore

final class AggregateTests: XCTestCase {
    private func s(_ status: SessionStatus, ageSeconds: TimeInterval = 0) -> Session {
        Session(sessionID: UUID().uuidString, status: status, project: "p", cwd: "/p",
                updatedAt: Date(timeIntervalSince1970: 1_000_000 - ageSeconds))
    }
    private let now = Date(timeIntervalSince1970: 1_000_000)

    func test_emptyIsGreen() {
        XCTAssertEqual(aggregateLight(for: []), .green)
    }

    func test_redWinsOverOrangeAndGreen() {
        XCTAssertEqual(aggregateLight(for: [s(.idle), s(.running), s(.waiting)]), .red)
    }

    func test_orangeWinsOverGreen() {
        XCTAssertEqual(aggregateLight(for: [s(.idle), s(.running)]), .orange)
    }

    func test_allIdleIsGreen() {
        XCTAssertEqual(aggregateLight(for: [s(.idle), s(.idle)]), .green)
    }

    func test_liveSessions_dropsStale() {
        let fresh = s(.running, ageSeconds: 60)
        let stale = s(.waiting, ageSeconds: 3600)
        let live = liveSessions([fresh, stale], now: now, ttl: 1800)
        XCTAssertEqual(live.map(\.sessionID), [fresh.sessionID])
    }

    func test_liveSessions_keepsExactlyAtTTL() {
        let edge = s(.running, ageSeconds: 1800)
        XCTAssertEqual(liveSessions([edge], now: now, ttl: 1800).count, 1)
    }
}
