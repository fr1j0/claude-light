import Foundation

/// Heuristic: the assistant's final text reads as a question awaiting a reply
/// if, after trimming trailing whitespace, its last character is '?'.
public func textEndsWithQuestion(_ text: String) -> Bool {
    text.trimmingCharacters(in: .whitespacesAndNewlines).last == "?"
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
