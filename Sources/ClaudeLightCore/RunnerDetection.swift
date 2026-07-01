import Foundation

/// One parallel sub-runner dispatched by a session (an `Agent`/`Task` tool_use).
public struct Runner: Equatable, Sendable {
    public enum State: String, Sendable { case running, failed }
    public let id: String
    public let label: String
    public let state: State

    public init(id: String, label: String, state: State) {
        self.id = id
        self.label = label
        self.state = state
    }
}

/// The runners to display under a running session: visible rows plus a count of
/// active runners hidden by the volume cap ("+N more running").
public struct RunnerList: Equatable, Sendable {
    public let visible: [Runner]
    public let overflowRunning: Int

    public init(visible: [Runner], overflowRunning: Int) {
        self.visible = visible
        self.overflowRunning = overflowRunning
    }

    public static let empty = RunnerList(visible: [], overflowRunning: 0)
    public var isEmpty: Bool { visible.isEmpty && overflowRunning == 0 }
}

/// Pairs `Agent`/`Task` tool_use blocks with their tool_results in a parent
/// session's transcript (JSONL) to surface its parallel runners.
///
/// State per runner: no matching tool_result → **running**; `is_error: true` →
/// **failed** (persisted so you notice it); otherwise → **done** (dropped).
/// Only running + failed are returned. Running runners are capped at `maxActive`
/// with the remainder reported as `overflowRunning`; failed runners are never
/// capped. Defensive/fail-safe: unparseable lines are skipped.
public func runners(fromTranscript jsonl: String, maxActive: Int = 5) -> RunnerList {
    struct Pending { let id: String; let label: String }
    var order: [Pending] = []
    var seen = Set<String>()
    var errored: [String: Bool] = [:]   // tool_use_id → is_error present

    for line in jsonl.split(separator: "\n", omittingEmptySubsequences: true) {
        guard let data = line.data(using: .utf8),
              let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let content = (obj["message"] as? [String: Any])?["content"] as? [[String: Any]]
        else { continue }

        for block in content {
            switch block["type"] as? String {
            case "tool_use":
                guard let name = block["name"] as? String, name == "Task" || name == "Agent",
                      let id = block["id"] as? String, !seen.contains(id) else { continue }
                let desc = (block["input"] as? [String: Any])?["description"] as? String ?? ""
                seen.insert(id)
                order.append(Pending(id: id, label: String(desc.prefix(40))))
            case "tool_result":
                guard let id = block["tool_use_id"] as? String else { continue }
                errored[id] = (block["is_error"] as? Bool) ?? false
            default:
                continue
            }
        }
    }

    var visible: [Runner] = []
    var runningShown = 0
    var overflow = 0
    for p in order {
        if let isError = errored[p.id] {
            if isError { visible.append(Runner(id: p.id, label: p.label, state: .failed)) }
            // completed successfully → dropped
        } else {
            if runningShown < maxActive {
                visible.append(Runner(id: p.id, label: p.label, state: .running))
                runningShown += 1
            } else {
                overflow += 1
            }
        }
    }
    return RunnerList(visible: visible, overflowRunning: overflow)
}
