import Foundation
import Observation

struct SavedSession: Identifiable, Codable {
    var id = UUID()
    var createdAt: Date
    var mediaURL: URL?
    var mediaName: String
    var segments: [TranscriptSegment]
    var starred: [Int]
    var processedOutput: String
    var promptText: String
}

@MainActor
@Observable
final class SessionStore {
    private(set) var sessions: [SavedSession] = []

    private var directory: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("ClipOtter/sessions", isDirectory: true)
    }

    init() {
        migrateLegacyDirectory()
        loadAll()
    }

    /// Move sessions saved under the pre-rename "Transcript/sessions" folder into
    /// the new location, once, if the new folder doesn't exist yet.
    private func migrateLegacyDirectory() {
        let fm = FileManager.default
        let legacy = fm.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Transcript/sessions", isDirectory: true)
        guard fm.fileExists(atPath: legacy.path),
              !fm.fileExists(atPath: directory.path) else { return }
        try? fm.createDirectory(at: directory.deletingLastPathComponent(), withIntermediateDirectories: true)
        try? fm.moveItem(at: legacy, to: directory)
    }

    func save(_ session: SavedSession) {
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let url = directory.appendingPathComponent("\(session.id.uuidString).json")
        if let data = try? JSONEncoder().encode(session) {
            try? data.write(to: url, options: .atomic)
        }
        if let idx = sessions.firstIndex(where: { $0.id == session.id }) {
            sessions[idx] = session
        } else {
            sessions.insert(session, at: 0)
        }
    }

    func delete(_ session: SavedSession) {
        let url = directory.appendingPathComponent("\(session.id.uuidString).json")
        try? FileManager.default.removeItem(at: url)
        sessions.removeAll { $0.id == session.id }
    }

    private func loadAll() {
        guard let files = try? FileManager.default.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: nil,
            options: .skipsHiddenFiles
        ) else { return }
        let decoder = JSONDecoder()
        sessions = files
            .filter { $0.pathExtension == "json" }
            .compactMap { try? decoder.decode(SavedSession.self, from: Data(contentsOf: $0)) }
            .sorted { $0.createdAt > $1.createdAt }
    }
}
