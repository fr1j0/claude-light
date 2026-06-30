import XCTest
@testable import ClaudeLightCore

final class QuestionDetectionTests: XCTestCase {

    // MARK: - textEndsWithQuestion

    func test_endsWithQuestion_true_plainQuestion() {
        XCTAssertTrue(textEndsWithQuestion("Which option?"))
    }

    func test_endsWithQuestion_true_trailingWhitespace() {
        XCTAssertTrue(textEndsWithQuestion("ok?\n  "))
    }

    func test_endsWithQuestion_false_period() {
        XCTAssertFalse(textEndsWithQuestion("Done."))
    }

    func test_endsWithQuestion_false_empty() {
        XCTAssertFalse(textEndsWithQuestion(""))
    }

    func test_endsWithQuestion_false_ternaryEndsWithC() {
        // "value = a ? b : c" ends with 'c', not '?'
        XCTAssertFalse(textEndsWithQuestion("value = a ? b : c"))
    }

    // MARK: - lastAssistantText

    // Fixtures shaped like real Claude Code JSONL entries
    private let userLine = #"{"type":"user","message":{"role":"user","content":"hi"}}"#

    private let assistantQuestionLine = #"{"type":"assistant","message":{"role":"assistant","content":[{"type":"text","text":"Which option do you prefer?"}]}}"#

    private let assistantStatementLine = #"{"type":"assistant","message":{"role":"assistant","content":[{"type":"text","text":"I have finished the task."}]}}"#

    private let assistantToolUseLine = #"{"type":"assistant","message":{"role":"assistant","content":[{"type":"tool_use","id":"t1","name":"bash","input":{}}]}}"#

    private let assistantStringContent = #"{"type":"assistant","message":{"role":"assistant","content":"Simple string answer."}}"#

    func test_lastAssistantText_returnsLastAssistantTextBlock() {
        let jsonl = [userLine, assistantQuestionLine].joined(separator: "\n")
        XCTAssertEqual(lastAssistantText(transcriptJSONL: jsonl), "Which option do you prefer?")
    }

    func test_lastAssistantText_skipsTrailingToolUseOnly() {
        // tool_use-only assistant entry should be skipped; returns the previous text entry
        let jsonl = [assistantQuestionLine, assistantToolUseLine].joined(separator: "\n")
        XCTAssertEqual(lastAssistantText(transcriptJSONL: jsonl), "Which option do you prefer?")
    }

    func test_lastAssistantText_skipsMalformedLines() {
        let jsonl = ["not-json", "{broken}", assistantStatementLine].joined(separator: "\n")
        XCTAssertEqual(lastAssistantText(transcriptJSONL: jsonl), "I have finished the task.")
    }

    func test_lastAssistantText_nilOnEmpty() {
        XCTAssertNil(lastAssistantText(transcriptJSONL: ""))
    }

    func test_lastAssistantText_nilWhenOnlyUserLines() {
        XCTAssertNil(lastAssistantText(transcriptJSONL: userLine))
    }

    func test_lastAssistantText_handlesStringContent() {
        let jsonl = [assistantStringContent].joined(separator: "\n")
        XCTAssertEqual(lastAssistantText(transcriptJSONL: jsonl), "Simple string answer.")
    }

    func test_lastAssistantText_returnsLastAmongMultipleAssistant() {
        let jsonl = [assistantStatementLine, assistantQuestionLine].joined(separator: "\n")
        XCTAssertEqual(lastAssistantText(transcriptJSONL: jsonl), "Which option do you prefer?")
    }
}
