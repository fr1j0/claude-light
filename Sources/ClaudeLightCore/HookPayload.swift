import Foundation

public struct HookPayload: Codable, Sendable {
    public let sessionID: String
    public let hookEventName: String
    public let cwd: String?
    public let message: String?

    public init(sessionID: String, hookEventName: String, cwd: String?, message: String?) {
        self.sessionID = sessionID
        self.hookEventName = hookEventName
        self.cwd = cwd
        self.message = message
    }

    enum CodingKeys: String, CodingKey {
        case sessionID = "session_id"
        case hookEventName = "hook_event_name"
        case cwd
        case message
    }
}
