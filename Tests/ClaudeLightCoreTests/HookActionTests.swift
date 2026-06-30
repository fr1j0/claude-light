import XCTest
@testable import ClaudeLightCore

final class HookActionTests: XCTestCase {
    private func payload(_ event: String, message: String? = nil) -> HookPayload {
        HookPayload(sessionID: "s", hookEventName: event, cwd: "/tmp/p", message: message)
    }

    func test_sessionStart_isIdle() {
        XCTAssertEqual(action(for: payload("SessionStart")), .set(.idle))
    }

    func test_stop_nilTranscript_isIdle() {
        XCTAssertEqual(action(for: payload("Stop"), transcriptJSONL: nil), .set(.idle))
    }

    func test_stop_questionTranscript_isAttention() {
        let jsonl = #"{"type":"assistant","message":{"role":"assistant","content":[{"type":"text","text":"Which option?"}]}}"#
        XCTAssertEqual(action(for: payload("Stop"), transcriptJSONL: jsonl), .set(.attention))
    }

    func test_stop_nonQuestionTranscript_isIdle() {
        let jsonl = #"{"type":"assistant","message":{"role":"assistant","content":[{"type":"text","text":"Done."}]}}"#
        XCTAssertEqual(action(for: payload("Stop"), transcriptJSONL: jsonl), .set(.idle))
    }

    func test_prompt_and_preToolUse_areRunning() {
        XCTAssertEqual(action(for: payload("UserPromptSubmit")), .set(.running))
        XCTAssertEqual(action(for: payload("PreToolUse")), .set(.running))
    }

    func test_notification_permission_isWaiting() {
        XCTAssertEqual(action(for: payload("Notification", message: "needs your permission")), .set(.waiting))
    }

    func test_notification_idleNudge_isIgnored() {
        XCTAssertEqual(action(for: payload("Notification", message: "Claude is waiting for your input")), .ignore)
    }

    func test_sessionEnd_deletes() {
        XCTAssertEqual(action(for: payload("SessionEnd")), .delete)
    }

    func test_unknownEvent_isIgnored() {
        XCTAssertEqual(action(for: payload("PostToolUse")), .ignore)
    }
}
