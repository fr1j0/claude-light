import Foundation

/// Heuristic: the assistant's final text reads as a *blocking* question awaiting
/// a reply. To avoid false "awaiting your reply" flags we require it to be a
/// concise question, not a long deliverable that merely trails off into one:
///  - ignore code (a `?` inside fenced/inline code isn't a question to the user),
///  - only flag when the remaining prose is short and ends with `?`.
public func textEndsWithQuestion(_ text: String) -> Bool {
    let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
    // A long turn that happens to end with a question is a check-in, not a block.
    guard trimmed.count <= questionMaxLength else { return false }
    let prose = strippingCode(trimmed).trimmingCharacters(in: .whitespacesAndNewlines)
    return prose.last == "?"
}

/// Upper bound (characters) for treating a turn as a pending question. Tunable.
private let questionMaxLength = 240

/// Remove fenced ```code``` blocks and `inline` code spans so a `?` inside code
/// isn't mistaken for a question.
private func strippingCode(_ s: String) -> String {
    var t = s.replacingOccurrences(of: "```[\\s\\S]*?```", with: " ", options: .regularExpression)
    t = t.replacingOccurrences(of: "`[^`]*`", with: " ", options: .regularExpression)
    return t
}

/// Best-effort extraction of the LAST assistant message's text from a Claude Code
/// transcript (JSONL). Scans lines bottom-up; returns nil if nothing parseable.
/// Format is undocumented and may change, so this is defensive and fail-safe.
public func lastAssistantText(transcriptJSONL: String) -> String? {
    let lines = transcriptJSONL.split(separator: "\n", omittingEmptySubsequences: true)
    for line in lines.reversed() {
        guard let data = line.data(using: .utf8),
              let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { continue }
        let message = obj["message"] as? [String: Any]
        let isAssistant = (obj["type"] as? String) == "assistant" || (message?["role"] as? String) == "assistant"
        guard isAssistant, let content = message?["content"] else { continue }
        if let s = content as? String {
            if !s.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { return s }
            continue
        }
        if let blocks = content as? [[String: Any]] {
            let text = blocks.filter { ($0["type"] as? String) == "text" }
                             .compactMap { $0["text"] as? String }
                             .joined(separator: "\n")
            if !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { return text }
            continue   // assistant entry with no text (e.g. tool_use) -> keep scanning older entries
        }
    }
    return nil
}
