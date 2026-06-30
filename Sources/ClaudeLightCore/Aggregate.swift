import Foundation

public enum AggregateLight: String, Sendable {
    case red
    case orange
    case green
}

public func liveSessions(_ sessions: [Session], now: Date, ttl: TimeInterval = 1800) -> [Session] {
    sessions.filter { now.timeIntervalSince($0.updatedAt) <= ttl }
}

public func aggregateLight(for sessions: [Session]) -> AggregateLight {
    if sessions.contains(where: { $0.status == .waiting }) { return .red }
    if sessions.contains(where: { $0.status == .running }) { return .orange }
    return .green
}
