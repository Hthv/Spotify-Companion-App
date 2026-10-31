import Foundation

struct LyricLine: Equatable, Sendable, Codable {
    /// Seconds from the start of the track.
    let time: TimeInterval
    let text: String
}

enum Lyrics: Equatable, Sendable, Codable {
    /// Time-stamped lines, sorted by time.
    case synced([LyricLine])
    /// Lines without timing.
    case plain([String])
    case instrumental
    case notFound

    var summary: String {
        switch self {
        case .synced(let lines): "synced, \(lines.count) lines"
        case .plain(let lines): "plain, \(lines.count) lines"
        case .instrumental: "instrumental"
        case .notFound: "not found"
        }
    }
}

/// Parses LRC: `[mm:ss.xx] text`, several stamps per line allowed, plus an optional
/// `[offset:±ms]` tag where a positive offset makes lyrics appear earlier.
enum LRCParser {
    static func parse(_ lrc: String) -> [LyricLine] {
        var offset: TimeInterval = 0
        var lines: [LyricLine] = []

        for raw in lrc.split(whereSeparator: \.isNewline) {
            var rest = Substring(raw)
            var times: [TimeInterval] = []
            while rest.hasPrefix("["), let close = rest.firstIndex(of: "]") {
                let tag = rest[rest.index(after: rest.startIndex)..<close]
                rest = rest[rest.index(after: close)...]
                if let time = timestamp(tag) {
                    times.append(time)
                } else if tag.lowercased().hasPrefix("offset:"),
                          let milliseconds = Double(tag.dropFirst(7).trimmingCharacters(in: .whitespaces)) {
                    offset = milliseconds / 1000
                }
            }
            let text = rest.trimmingCharacters(in: .whitespaces)
            lines += times.map { LyricLine(time: $0, text: text) }
        }

        return lines
            .map { LyricLine(time: max(0, $0.time - offset), text: $0.text) }
            .sorted { $0.time < $1.time }
    }

    /// `mm:ss`, `mm:ss.xx` or `mm:ss:xx`; nil for metadata tags like `ar:Artist`.
    private static func timestamp(_ tag: Substring) -> TimeInterval? {
        let parts = tag.split(separator: ":", omittingEmptySubsequences: false)
        guard parts.count == 2 || parts.count == 3, let minutes = Int(parts[0]) else { return nil }
        if parts.count == 2 {
            guard let seconds = Double(parts[1]) else { return nil }
            return Double(minutes) * 60 + seconds
        }
        guard let seconds = Int(parts[1]), let hundredths = Int(parts[2]) else { return nil }
        return Double(minutes) * 60 + Double(seconds) + Double(hundredths) / 100
    }
}
