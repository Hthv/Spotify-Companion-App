import CryptoKit
import Foundation

/// Lyrics already fetched, kept on disk so they still show during an LRCLIB outage and after
/// a relaunch. One small JSON file per track, named by a hash of the track ID (local-file IDs
/// can hold any character). "Not found" is never stored, so lyrics added to LRCLIB later
/// still turn up.
actor LyricsDiskCache {
    private let directory: URL

    init(directory: URL = LyricsDiskCache.defaultDirectory) {
        self.directory = directory
    }

    nonisolated static var defaultDirectory: URL {
        URL.applicationSupportDirectory
            .appending(path: Bundle.main.bundleIdentifier ?? "com.hoventan.SpotifyCompanion", directoryHint: .isDirectory)
            .appending(path: "Lyrics", directoryHint: .isDirectory)
    }

    func read(_ trackID: String) -> Lyrics? {
        guard let data = try? Data(contentsOf: file(for: trackID)) else { return nil }
        return try? JSONDecoder().decode(Lyrics.self, from: data)
    }

    func write(_ lyrics: Lyrics, for trackID: String) {
        guard lyrics != .notFound else { return }
        do {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            try JSONEncoder().encode(lyrics).write(to: file(for: trackID), options: .atomic)
        } catch {
            // A cache miss next time is the only cost.
        }
    }

    private func file(for trackID: String) -> URL {
        let digest = SHA256.hash(data: Data(trackID.utf8)).map { String(format: "%02x", $0) }.joined()
        return directory.appending(path: "\(digest).json")
    }
}
