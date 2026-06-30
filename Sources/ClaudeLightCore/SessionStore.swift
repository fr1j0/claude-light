import Foundation

public struct SessionStore {
    public let directory: URL

    public init(directory: URL) {
        self.directory = directory
    }

    public static func defaultDirectory() -> URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".claude-light", isDirectory: true)
            .appendingPathComponent("sessions", isDirectory: true)
    }

    public func fileURL(for sessionID: String) -> URL {
        directory.appendingPathComponent("\(sessionID).json")
    }

    public func write(_ session: Session) throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let data = try ClaudeLightJSON.encoder.encode(session)
        try data.write(to: fileURL(for: session.sessionID), options: .atomic)
    }

    public func delete(sessionID: String) throws {
        let url = fileURL(for: sessionID)
        if FileManager.default.fileExists(atPath: url.path) {
            try FileManager.default.removeItem(at: url)
        }
    }

    public func loadAll() throws -> [Session] {
        let fm = FileManager.default
        guard fm.fileExists(atPath: directory.path) else { return [] }
        let urls = try fm.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)
            .filter { $0.pathExtension == "json" }
        return urls.compactMap { url in
            guard let data = try? Data(contentsOf: url) else { return nil }
            return try? ClaudeLightJSON.decoder.decode(Session.self, from: data)
        }
    }
}
