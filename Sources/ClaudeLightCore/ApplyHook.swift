import Foundation

public func applyHook(_ payload: HookPayload, to store: SessionStore, now: Date) throws {
    switch action(for: payload) {
    case .ignore:
        return
    case .delete:
        try store.delete(sessionID: payload.sessionID)
    case .set(let status):
        let cwd = payload.cwd ?? ""
        let project = cwd.isEmpty ? "unknown" : URL(fileURLWithPath: cwd).lastPathComponent
        let session = Session(
            sessionID: payload.sessionID,
            status: status,
            project: project,
            cwd: cwd,
            updatedAt: now
        )
        try store.write(session)
    }
}
