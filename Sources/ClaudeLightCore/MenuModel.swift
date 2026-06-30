import Foundation

public struct StatusCounts: Sendable, Equatable {
    public let needYou: Int   // waiting + attention
    public let working: Int   // running
    public let idle: Int
    public init(needYou: Int, working: Int, idle: Int) {
        self.needYou = needYou
        self.working = working
        self.idle = idle
    }
}

public func statusCounts(for sessions: [Session]) -> StatusCounts {
    var needYou = 0, working = 0, idle = 0
    for session in sessions {
        switch session.status {
        case .waiting, .attention: needYou += 1
        case .running: working += 1
        case .idle: idle += 1
        }
    }
    return StatusCounts(needYou: needYou, working: working, idle: idle)
}

/// Words-and-counts summary for the dropdown header. nil = no live sessions.
public func summaryText(for counts: StatusCounts) -> String? {
    if counts.needYou == 0 && counts.working == 0 && counts.idle == 0 { return nil }
    var parts: [String] = []
    if counts.needYou > 0 {
        parts.append(counts.needYou == 1 ? "1 needs you" : "\(counts.needYou) need you")
    }
    if counts.working > 0 {
        parts.append("\(counts.working) working")
    }
    if parts.isEmpty { return "Idle" }   // only idle sessions
    return parts.joined(separator: " · ")
}
