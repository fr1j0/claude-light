import XCTest
@testable import ClaudeLightCore

final class MenuModelTests: XCTestCase {
    private func s(_ status: SessionStatus, project: String = "p") -> Session {
        Session(sessionID: UUID().uuidString, status: status, project: project, cwd: "/p",
                updatedAt: Date(timeIntervalSince1970: 1_000_000))
    }

    func test_counts_bucketsWaitingAndAttentionTogether() {
        let c = statusCounts(for: [s(.waiting), s(.attention), s(.running), s(.idle), s(.idle)])
        XCTAssertEqual(c, StatusCounts(needYou: 2, working: 1, idle: 2))
    }
    func test_summary_nilWhenEmpty() {
        XCTAssertNil(summaryText(for: StatusCounts(needYou: 0, working: 0, idle: 0)))
    }
    func test_summary_singularNeedsYou() {
        XCTAssertEqual(summaryText(for: StatusCounts(needYou: 1, working: 0, idle: 0)), "1 needs you")
    }
    func test_summary_pluralAndWorking() {
        XCTAssertEqual(summaryText(for: StatusCounts(needYou: 2, working: 3, idle: 1)), "2 need you · 3 working")
    }
    func test_summary_idleOnly() {
        XCTAssertEqual(summaryText(for: StatusCounts(needYou: 0, working: 0, idle: 4)), "Idle")
    }
}

extension MenuModelTests {
    func test_sorted_urgencyThenProject() {
        let input = [
            s(.idle, project: "z"),
            s(.running, project: "b"),
            s(.attention, project: "m"),
            s(.running, project: "a"),
            s(.waiting, project: "k"),
        ]
        let order = sortedForMenu(input).map { "\($0.status.rawValue):\($0.project)" }
        XCTAssertEqual(order, ["attention:m", "waiting:k", "running:a", "running:b", "idle:z"])
    }

    func test_relativeTime_boundaries() {
        XCTAssertEqual(relativeTime(secondsAgo: -5), "0s")
        XCTAssertEqual(relativeTime(secondsAgo: 0), "0s")
        XCTAssertEqual(relativeTime(secondsAgo: 59), "59s")
        XCTAssertEqual(relativeTime(secondsAgo: 60), "1m")
        XCTAssertEqual(relativeTime(secondsAgo: 3599), "59m")
        XCTAssertEqual(relativeTime(secondsAgo: 3600), "1h")
        XCTAssertEqual(relativeTime(secondsAgo: 86399), "23h")
        XCTAssertEqual(relativeTime(secondsAgo: 86400), "1d")
    }
}
