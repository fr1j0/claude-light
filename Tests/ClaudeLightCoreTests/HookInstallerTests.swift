import XCTest
@testable import ClaudeLightCore

final class HookInstallerTests: XCTestCase {
    let cmd = "/Applications/Claude Light.app/Contents/MacOS/claude-light-hook"

    private func commands(_ root: [String: Any], _ event: String) -> [String] {
        guard let hooks = root["hooks"] as? [String: Any],
              let groups = hooks[event] as? [[String: Any]] else { return [] }
        return groups.flatMap { ($0["hooks"] as? [[String: Any]] ?? []) }
            .compactMap { $0["command"] as? String }
    }

    func test_install_addsAllSixEvents() {
        let out = installedHooks(into: [:], command: cmd)
        for event in claudeLightHookEvents {
            XCTAssertTrue(commands(out, event).contains(cmd), "missing \(event)")
        }
    }

    func test_install_isIdempotent() {
        let once = installedHooks(into: [:], command: cmd)
        let twice = installedHooks(into: once, command: cmd)
        XCTAssertEqual(commands(twice, "Stop").filter { $0 == cmd }.count, 1)
    }

    func test_install_preservesExistingUnrelatedHooks() {
        let existing: [String: Any] = [
            "hooks": ["Stop": [["hooks": [["type": "command", "command": "/other/tool"]]]]]
        ]
        let out = installedHooks(into: existing, command: cmd)
        XCTAssertTrue(commands(out, "Stop").contains("/other/tool"))
        XCTAssertTrue(commands(out, "Stop").contains(cmd))
    }

    func test_preToolUse_groupHasMatcher() {
        let out = installedHooks(into: [:], command: cmd)
        let hooks = out["hooks"] as! [String: Any]
        let groups = hooks["PreToolUse"] as! [[String: Any]]
        let ours = groups.first { ($0["hooks"] as? [[String: Any]])?.contains { $0["command"] as? String == cmd } == true }
        XCTAssertEqual(ours?["matcher"] as? String, "*")
    }

    func test_uninstall_removesOurs_keepsOthers() {
        let existing: [String: Any] = [
            "hooks": ["Stop": [["hooks": [["type": "command", "command": "/other/tool"]]]]]
        ]
        let installed = installedHooks(into: existing, command: cmd)
        let out = uninstalledHooks(from: installed, command: cmd)
        XCTAssertFalse(commands(out, "Stop").contains(cmd))
        XCTAssertTrue(commands(out, "Stop").contains("/other/tool"))
    }

    func test_uninstall_fromOnlyOurs_leavesNoEmptyHooksKey() {
        let installed = installedHooks(into: [:], command: cmd)
        let out = uninstalledHooks(from: installed, command: cmd)
        XCTAssertNil(out["hooks"])
    }

    func test_diskRoundTrip_installThenUninstall() throws {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("settings-\(UUID().uuidString).json")
        try Data("{}".utf8).write(to: url)
        try HookInstaller(settingsURL: url, command: cmd).install()
        var root = try JSONSerialization.jsonObject(with: Data(contentsOf: url)) as! [String: Any]
        XCTAssertTrue(commands(root, "Stop").contains(cmd))
        try HookInstaller(settingsURL: url, command: cmd).uninstall()
        root = try JSONSerialization.jsonObject(with: Data(contentsOf: url)) as! [String: Any]
        XCTAssertNil(root["hooks"])
    }
}
