import Foundation
import Observation
import os

/// Lyrics for the current track, fetched only while the lyrics view is open.
@MainActor
@Observable
final class LyricsStore {
    enum State: Equatable {
        case idle, loading, loaded(Lyrics), failed
    }

    private(set) var state: State = .idle
    /// A first try that's taking more than a moment; the player shows the cover meanwhile.
    private(set) var isSlow = false

    /// No lyrics yet, and not about to arrive: a slow first try, or retrying after a failure.
    var isWaiting: Bool { state == .failed || (state == .loading && isSlow) }

    @ObservationIgnored private let lookup: @Sendable (Track) async throws -> Lyrics
    @ObservationIgnored private let disk: LyricsDiskCache
    @ObservationIgnored private let slowAfter: Duration
    @ObservationIgnored private let giveUpAfter: Duration

    init(
        disk: LyricsDiskCache = LyricsDiskCache(),
        lookup: @escaping @Sendable (Track) async throws -> Lyrics = LRCLIBClient().lyrics,
        slowAfter: Duration = .seconds(3),
        giveUpAfter: Duration = .seconds(60)
    ) {
        self.disk = disk
        self.lookup = lookup
        self.slowAfter = slowAfter
        self.giveUpAfter = giveUpAfter
    }

    @ObservationIgnored private let logger = Logger(subsystem: "com.hoventan.SpotifyCompanion", category: "Lyrics")
    @ObservationIgnored private var trackID: String?
    @ObservationIgnored private var task: Task<Void, Never>?
    @ObservationIgnored private var watchdog: Task<Void, Never>?
    @ObservationIgnored private var cache: [String: Lyrics] = [:]
    /// Preview stores keep their sample lyrics and never fetch.
    @ObservationIgnored private var isPreview = false

    /// Pass nil to stop (lyrics hidden or nothing playing).
    func load(for track: Track?) {
        guard !isPreview, track?.id != trackID else { return }
        trackID = track?.id
        task?.cancel()
        watchdog?.cancel()
        isSlow = false

        guard let track else {
            state = .idle
            return
        }
        if let cached = cache[track.id] {
            state = .loaded(cached)
            return
        }

        state = .loading
        watchdog = Task {
            try? await Task.sleep(for: slowAfter)
            guard !Task.isCancelled else { return }
            isSlow = true
            // A minute with nothing to show: stop and say there are none. Not cached, so the
            // next time this track plays (or lyrics are toggled) it's tried again.
            try? await Task.sleep(for: giveUpAfter - slowAfter)
            guard !Task.isCancelled else { return }
            task?.cancel()
            state = .loaded(.notFound)
            logger.info("No lyrics for '\(track.name, privacy: .public)' after a minute; giving up")
        }
        task = Task {
            if let stored = await disk.read(track.id) {
                guard !Task.isCancelled else { return }
                remember(stored, for: track)
                return
            }
            // Network failures aren't cached; keep trying with backoff (until the watchdog's
            // minute is up) so they appear if LRCLIB is reachable again.
            var delay = Self.firstRetryDelay
            while !Task.isCancelled {
                do {
                    let lyrics = try await lookup(track)
                    guard !Task.isCancelled else { return }
                    remember(lyrics, for: track)
                    await disk.write(lyrics, for: track.id)
                    logger.info("Lyrics for '\(track.name, privacy: .public)': \(lyrics.summary, privacy: .public)")
                    return
                } catch {
                    guard !Task.isCancelled else { return }
                    state = .failed
                    let wait = Self.retryDelay(after: error, backoff: delay)
                    logger.error("Lyrics failed, retrying in \(wait, privacy: .public): \(error.localizedDescription, privacy: .public)")
                    try? await Task.sleep(for: wait)
                    delay = min(delay * 2, Self.maxRetryDelay)
                }
            }
        }
    }

    private func remember(_ lyrics: Lyrics, for track: Track) {
        watchdog?.cancel()
        if cache.count > 100 { cache.removeAll() }
        cache[track.id] = lyrics
        state = .loaded(lyrics)
    }

    /// The backoff, or longer if LRCLIB asked for it, plus up to 30% jitter so clients
    /// throttled together don't come back together.
    static func retryDelay(after error: Error, backoff: Duration) -> Duration {
        var wait = backoff
        if case LRCLIBError.rateLimited(let seconds) = error {
            wait = max(wait, .seconds(seconds))
        }
        return wait + wait * Double.random(in: 0...0.3)
    }

    private static let firstRetryDelay = Duration.seconds(10)
    private static let maxRetryDelay = Duration.seconds(60)
}

#if DEBUG
extension LyricsStore {
    /// A store holding sample synced lyrics, for SwiftUI previews.
    static func preview(_ lyrics: Lyrics = .sample) -> LyricsStore {
        let store = LyricsStore()
        store.state = .loaded(lyrics)
        store.isPreview = true
        return store
    }
}

extension Lyrics {
    static let sample = Lyrics.synced(LRCParser.parse("""
    [00:08.00]Lines in red on a field of white
    [00:12.50]Every letter set flush left
    [00:17.00]The grid holds still while the music moves
    [00:21.50]
    [00:29.00]Helvetica hums the second verse
    [00:33.50]Ragged right and never centred
    [00:38.00]Black ink drying on the page
    [00:42.50]Until the chorus comes around again
    [00:47.00]Bold, and only bold
    """))
}
#endif
