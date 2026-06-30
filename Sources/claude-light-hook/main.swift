import Foundation
import ClaudeLightCore

// A hook must never disrupt the Claude Code session: swallow all errors, always exit 0.
let input = FileHandle.standardInput.readDataToEndOfFile()

if let payload = try? ClaudeLightJSON.decoder.decode(HookPayload.self, from: input) {
    let store = SessionStore(directory: SessionStore.defaultDirectory())
    try? applyHook(payload, to: store, now: Date())
}

exit(0)
