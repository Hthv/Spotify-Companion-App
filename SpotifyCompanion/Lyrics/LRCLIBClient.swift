import Foundation

enum LRCLIBError: Error, Equatable {
    /// 429: wait at least this many seconds before asking again.
    case rateLimited(retryAfter: TimeInterval)
}

/// Fetches lyrics from LRCLIB (lrclib.net), a free, keyless lyrics database.
struct LRCLIBClient: Sendable {
    private struct Record: Decodable {
        let duration: Double?
        let instrumental: Bool?
        let plainLyrics: String?
        let syncedLyrics: String?
    }

    private static let base = URL(string: "https://lrclib.net/api")!

    private static let session: URLSession = {
        let configuration = URLSessionConfiguration.default
        configuration.timeoutIntervalForRequest = 10
        // LRCLIB asks clients to identify themselves.
        let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "dev"
        configuration.httpAdditionalHeaders = ["User-Agent": "SpotifyCompanion/\(version) (macOS)"]
        return URLSession(configuration: configuration)
    }()

    /// Exact match first (cleaned title too), then a search. Throws on network errors, and when
    /// LRCLIB was too busy to give a trustworthy "not found".
    func lyrics(for track: Track) async throws -> Lyrics {
        let title = Self.cleanTitle(track.name)
        // /get is LRCLIB's expensive endpoint and the first to answer 503 under load;
        // when it's busy, skip straight to /search rather than waiting on it.
        var exactMatchWasBusy = false
        for name in title == track.name ? [title] : [track.name, title] {
            switch try await exactMatch(track, name: name) {
            case .found(let data):
                if let record = try? JSONDecoder().decode(Record.self, from: data) {
                    return Self.lyrics(from: record)
                }
                // A 200 we can't read is an overloaded server, not an answer.
                exactMatchWasBusy = true
            case .missing:
                continue
            case .busy:
                exactMatchWasBusy = true
            }
            if exactMatchWasBusy { break }
        }

        var candidates: [Record] = []
        for delay in [Duration.zero, .seconds(1), .seconds(2.5)] {
            try await Task.sleep(for: delay)
            switch try await search(title: title, artist: track.artist) {
            case .found(let data):
                // A 200 we can't read is an overloaded server, not an empty result.
                guard let decoded = try? JSONDecoder().decode([Record].self, from: data) else { continue }
                candidates = decoded
            case .missing:
                break
            case .busy:
                continue
            }
            if let best = Self.best(of: candidates, duration: track.duration) {
                return Self.lyrics(from: best)
            }
            if exactMatchWasBusy { throw URLError(.badServerResponse) }
            return .notFound
        }
        throw URLError(.badServerResponse)
    }

    private enum Response {
        case found(Data)
        case missing
        case busy
    }

    private func exactMatch(_ track: Track, name: String) async throws -> Response {
        // /get needs all four fields and matches duration within ±2 s.
        guard track.duration > 0, !track.artist.isEmpty else { return .missing }
        var components = URLComponents(url: Self.base.appendingPathComponent("get"), resolvingAgainstBaseURL: false)!
        components.queryItems = [
            URLQueryItem(name: "track_name", value: name),
            URLQueryItem(name: "artist_name", value: track.artist),
            URLQueryItem(name: "album_name", value: track.album),
            URLQueryItem(name: "duration", value: String(Int(track.duration.rounded()))),
        ]
        // A slow /get is as good as a busy one: search usually has the same record.
        do {
            return try await fetch(components.url!, timeout: 4)
        } catch let error as URLError where error.code == .timedOut {
            return .busy
        }
    }

    private func search(title: String, artist: String) async throws -> Response {
        var components = URLComponents(url: Self.base.appendingPathComponent("search"), resolvingAgainstBaseURL: false)!
        components.queryItems = [URLQueryItem(name: "track_name", value: title)]
        if !artist.isEmpty {
            components.queryItems?.append(URLQueryItem(name: "artist_name", value: artist))
        }
        return try await fetch(components.url!)
    }

    private func fetch(_ url: URL, timeout: TimeInterval = 10) async throws -> Response {
        let (data, response) = try await Self.session.data(for: URLRequest(url: url, timeoutInterval: timeout))
        let http = response as? HTTPURLResponse
        switch http?.statusCode {
        case 200: return .found(data)
        case 404: return .missing
        case 429:
            // LRCLIB requires waiting out Retry-After; never retry a 429 sooner.
            throw LRCLIBError.rateLimited(retryAfter: Self.retryAfter(http?.value(forHTTPHeaderField: "Retry-After")))
        default: return .busy
        }
    }

    /// Seconds from `Retry-After`, given as a number or an HTTP date; a minute if it's missing.
    static func retryAfter(_ value: String?, now: Date = Date()) -> TimeInterval {
        guard let value = value?.trimmingCharacters(in: .whitespaces), !value.isEmpty else { return 60 }
        if let seconds = TimeInterval(value) { return max(0, seconds) }
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(identifier: "GMT")
        formatter.dateFormat = "EEE, dd MMM yyyy HH:mm:ss zzz"
        guard let date = formatter.date(from: value) else { return 60 }
        return max(0, date.timeIntervalSince(now))
    }

    /// Closest duration wins, synced beats plain; anything more than 5 s off is another version.
    private static func best(of records: [Record], duration: TimeInterval) -> Record? {
        let usable = records.filter { record in
            let hasText = record.syncedLyrics?.isEmpty == false || record.plainLyrics?.isEmpty == false
            guard hasText || record.instrumental == true else { return false }
            guard duration > 0, let other = record.duration else { return true }
            return abs(other - duration) <= 5
        }
        return usable.min { a, b in
            let aSynced = a.syncedLyrics?.isEmpty == false, bSynced = b.syncedLyrics?.isEmpty == false
            if aSynced != bSynced { return aSynced }
            return abs((a.duration ?? 0) - duration) < abs((b.duration ?? 0) - duration)
        }
    }

    private static func lyrics(from record: Record) -> Lyrics {
        if record.instrumental == true { return .instrumental }
        if let synced = record.syncedLyrics {
            let lines = LRCParser.parse(synced)
            if lines.contains(where: { !$0.text.isEmpty }) { return .synced(lines) }
        }
        if let plain = record.plainLyrics?.trimmingCharacters(in: .whitespacesAndNewlines), !plain.isEmpty {
            return .plain(plain.components(separatedBy: .newlines))
        }
        return .notFound
    }

    /// "Song - Remastered 2011 (feat. X)" → "Song", which is how LRCLIB usually stores it.
    static func cleanTitle(_ name: String) -> String {
        var title = name
        if let dash = title.range(of: " - ") { title = String(title[..<dash.lowerBound]) }
        title = title.replacingOccurrences(
            of: #"\s*[\(\[](feat|ft|with)\.?\s[^\)\]]*[\)\]]"#,
            with: "",
            options: [.regularExpression, .caseInsensitive]
        )
        let trimmed = title.trimmingCharacters(in: .whitespaces)
        return trimmed.isEmpty ? name : trimmed
    }
}
