import Foundation

public enum HookAction: Equatable, Sendable {
    case set(SessionStatus)
    case delete
    case ignore
}

public func action(for payload: HookPayload) -> HookAction {
    switch payload.hookEventName {
    case "SessionStart", "Stop":
        return .set(.idle)
    case "UserPromptSubmit", "PreToolUse":
        return .set(.running)
    case "Notification":
        return isPermissionNotification(message: payload.message ?? "") ? .set(.waiting) : .ignore
    case "SessionEnd":
        return .delete
    default:
        return .ignore
    }
}
