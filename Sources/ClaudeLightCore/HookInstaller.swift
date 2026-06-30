import Foundation

public let claudeLightHookEvents: [String] = [
    "SessionStart", "UserPromptSubmit", "PreToolUse", "Notification", "Stop", "SessionEnd"
]

private func groupCommands(_ group: [String: Any]) -> [String] {
    (group["hooks"] as? [[String: Any]] ?? []).compactMap { $0["command"] as? String }
}

public func installedHooks(into root: [String: Any], command: String) -> [String: Any] {
    var root = root
    // Fix 2: if "hooks" key exists but is not a [String: Any], leave the whole root unchanged.
    if root["hooks"] != nil, (root["hooks"] as? [String: Any]) == nil {
        return root
    }
    var hooks = (root["hooks"] as? [String: Any]) ?? [:]

    for event in claudeLightHookEvents {
        // Fix 1: cast to [Any] first so non-dict elements don't discard the whole array.
        let rawGroups = (hooks[event] as? [Any]) ?? []
        var groups = rawGroups.compactMap { $0 as? [String: Any] }
        let alreadyPresent = groups.contains { groupCommands($0).contains(command) }
        if !alreadyPresent {
            var group: [String: Any] = ["hooks": [["type": "command", "command": command]]]
            if event == "PreToolUse" { group["matcher"] = "*" }
            groups.append(group)
        }
        hooks[event] = groups
    }

    root["hooks"] = hooks
    return root
}

public func uninstalledHooks(from root: [String: Any], command: String) -> [String: Any] {
    var root = root
    guard var hooks = root["hooks"] as? [String: Any] else { return root }

    for event in claudeLightHookEvents {
        guard var groups = hooks[event] as? [[String: Any]] else { continue }
        groups = groups.compactMap { group in
            var group = group
            let inner = (group["hooks"] as? [[String: Any]] ?? [])
                .filter { ($0["command"] as? String) != command }
            if inner.isEmpty { return nil }
            group["hooks"] = inner
            return group
        }
        if groups.isEmpty { hooks.removeValue(forKey: event) } else { hooks[event] = groups }
    }

    if hooks.isEmpty { root.removeValue(forKey: "hooks") } else { root["hooks"] = hooks }
    return root
}

public struct HookInstaller {
    public let settingsURL: URL
    public let command: String

    public init(settingsURL: URL, command: String) {
        self.settingsURL = settingsURL
        self.command = command
    }

    private func loadRoot() throws -> [String: Any] {
        guard FileManager.default.fileExists(atPath: settingsURL.path),
              let data = try? Data(contentsOf: settingsURL),
              let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        else { return [:] }
        return obj
    }

    private func save(_ root: [String: Any]) throws {
        let data = try JSONSerialization.data(
            withJSONObject: root,
            options: [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        )
        try FileManager.default.createDirectory(
            at: settingsURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try data.write(to: settingsURL, options: .atomic)
    }

    public func install() throws {
        try save(installedHooks(into: try loadRoot(), command: command))
    }

    public func uninstall() throws {
        try save(uninstalledHooks(from: try loadRoot(), command: command))
    }
}
