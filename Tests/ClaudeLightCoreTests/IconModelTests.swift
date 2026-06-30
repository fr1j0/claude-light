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

extension IconModelTests {
    private func steady() -> IconState { IconState(lamp: .green, blink: false, breathe: false) }
    private func blinking() -> IconState { IconState(lamp: .red, blink: true, breathe: false) }
    private func breathing() -> IconState { IconState(lamp: .orange, blink: false, breathe: true) }

    func test_litAlpha_steady_isFull() {
        XCTAssertEqual(litAlpha(for: steady(), phase: 0.0), 1.0, accuracy: 0.0001)
        XCTAssertEqual(litAlpha(for: steady(), phase: 12.3), 1.0, accuracy: 0.0001)
    }
    func test_litAlpha_blink_squareWave() {
        XCTAssertEqual(litAlpha(for: blinking(), phase: 0.0), 1.0, accuracy: 0.0001)
        XCTAssertEqual(litAlpha(for: blinking(), phase: 0.2), 1.0, accuracy: 0.0001)
        XCTAssertEqual(litAlpha(for: blinking(), phase: 0.3), 0.2, accuracy: 0.0001)
        XCTAssertEqual(litAlpha(for: blinking(), phase: 0.6), 1.0, accuracy: 0.0001) // wraps
    }
    func test_litAlpha_breathe_range() {
        XCTAssertEqual(litAlpha(for: breathing(), phase: 0.0), 1.0, accuracy: 0.0001)
        XCTAssertEqual(litAlpha(for: breathing(), phase: 0.75), 0.55, accuracy: 0.0001) // half of 1.5
    }
}
