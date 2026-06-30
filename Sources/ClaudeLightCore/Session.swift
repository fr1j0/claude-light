import Foundation

public enum SessionStatus: String, Codable, Sendable {
    case running
    case waiting
    case idle
}

public struct Session: Codable, Sendable, Equatable {
    public let sessionID: String
    public var status: SessionStatus
    public var project: String
    public var cwd: String
    public var updatedAt: Date

    public init(sessionID: String, status: SessionStatus, project: String, cwd: String, updatedAt: Date) {
        self.sessionID = sessionID
        self.status = status
        self.project = project
        self.cwd = cwd
        self.updatedAt = updatedAt
    }

    enum CodingKeys: String, CodingKey {
        case sessionID = "session_id"
        case status
        case project
        case cwd
        case updatedAt = "updated_at"
    }
}

public enum ClaudeLightJSON {
    public static let encoder: JSONEncoder = {
        let e = JSONEncoder()
        e.dateEncodingStrategy = .iso8601
        e.outputFormatting = [.withoutEscapingSlashes]
        return e
    }()

    public static let decoder: JSONDecoder = {
        let d = JSONDecoder()
        d.dateDecodingStrategy = .iso8601
        return d
    }()
}
