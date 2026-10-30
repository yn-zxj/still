import Foundation

public struct AgentActivityStore {
    private struct Archive: Codable {
        var version: Int
        var sessions: [AgentActivitySession]
    }

    public let fileURL: URL

    public init(fileURL: URL) {
        self.fileURL = fileURL
    }

    public func load(retainingSince cutoff: Date) -> [AgentActivitySession] {
        guard let data = try? Data(contentsOf: fileURL),
              let archive = try? JSONDecoder().decode(Archive.self, from: data),
              archive.version == 1 else {
            return []
        }
        return archive.sessions.filter { session in
            (session.spans.last?.endedAt ?? .distantPast) >= cutoff
        }
    }

    public func save(_ sessions: [AgentActivitySession], retainingSince cutoff: Date) throws {
        let folder = fileURL.deletingLastPathComponent()
        try FileManager.default.createDirectory(
            at: folder,
            withIntermediateDirectories: true,
            attributes: [.posixPermissions: 0o700]
        )
        let archive = Archive(
            version: 1,
            sessions: sessions
                .filter { ($0.spans.last?.endedAt ?? .distantPast) >= cutoff }
                .sorted { ($0.spans.last?.endedAt ?? .distantPast) > ($1.spans.last?.endedAt ?? .distantPast) }
        )
        let data = try JSONEncoder().encode(archive)
        try data.write(to: fileURL, options: .atomic)
        try? FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: fileURL.path)
    }
}
