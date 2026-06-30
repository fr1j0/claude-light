import XCTest
@testable import ClaudeLightCore

final class IconModelTests: XCTestCase {
    private func s(_ status: SessionStatus) -> Session {
        Session(sessionID: UUID().uuidString, status: status, project: "p", cwd: "/p",
                updatedAt: Date(timeIntervalSince1970: 1_000_000))
    }

    func test_empty_isOff() {
        XCTAssertEqual(iconState(for: []), IconState(lamp: .off, blink: false, breathe: false))
    }
    func test_allIdle_isGreenSteady() {
        XCTAssertEqual(iconState(for: [s(.idle), s(.idle)]), IconState(lamp: .green, blink: false, breathe: false))
    }
    func test_running_isOrangeBreathing() {
        XCTAssertEqual(iconState(for: [s(.idle), s(.running)]), IconState(lamp: .orange, blink: false, breathe: true))
    }
    func test_waitingOnly_isRedSteady() {
        XCTAssertEqual(iconState(for: [s(.waiting), s(.running)]), IconState(lamp: .red, blink: false, breathe: false))
    }
    func test_attention_isRedBlinking() {
        XCTAssertEqual(iconState(for: [s(.attention), s(.running)]), IconState(lamp: .red, blink: true, breathe: false))
    }
}
