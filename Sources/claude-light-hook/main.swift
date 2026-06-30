import Foundation
import ClaudeLightCore

// A hook must never disrupt the Claude Code session: swallow all errors, always exit 0.
let input = FileHandle.standardInput.readDataToEndOfFile()

if let payload = try? ClaudeLightJSON.decoder.decode(HookPayload.self, from: input) {
    let store = SessionStore(directory: SessionStore.defaultDirectory())
    var transcriptJSONL: String? = nil
    if payload.hookEventName == "Stop", let path = payload.transcriptPath {
        transcriptJSONL = try? String(contentsOfFile: path, encoding: .utf8)
    }
    try? applyHook(payload, to: store, now: Date(), transcriptJSONL: transcriptJSONL)
}

exit(0)
