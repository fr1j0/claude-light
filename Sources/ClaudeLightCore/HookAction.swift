import Foundation

public enum HookAction: Equatable, Sendable {
    case set(SessionStatus)
    case delete
    case ignore
}

public func action(for payload: HookPayload, transcriptJSONL: String? = nil) -> HookAction {
    switch payload.hookEventName {
    case "SessionStart":
        return .set(.idle)
    case "Stop":
        if let t = transcriptJSONL, let last = lastAssistantText(transcriptJSONL: t), textEndsWithQuestion(last) {
            return .set(.attention)
        }
        return .set(.idle)
    case "UserPromptSubmit", "PreToolUse":
        return .set(.running)
    case "Notification":
        return .set(.waiting)
    case "SessionEnd":
        return .delete
    default:
        return .ignore
    }
}
