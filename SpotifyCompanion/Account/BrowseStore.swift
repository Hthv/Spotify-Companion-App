import Foundation
import Observation
import os

/// What Home's categories show: the user's library, Liked Songs, followed and top artists,
/// top songs, and what they played lately grouped by album or playlist. Loaded when Home asks,
/// and again only after a few minutes, to stay well inside Development Mode quotas.
@MainActor
@Observable
final class BrowseStore {
    enum Status: Equatable {
        case idle, loading, loaded
        case failed(String)
        /// Signed in before the app asked for this permission: connect again to grant it.
        case needsReconnect
    }

    enum Part: Hashable { case library, liked, top }

    /// Playlists, albums and followed artists, with Liked Songs first.
    private(set) var library: [MediaItem] = []
    private(set) var liked: [MediaItem] = []
    private(set) var likedTotal: Int?
    private(set) var followedArtists: [MediaItem] = []
    private(set) var topArtists: [MediaItem] = []
    private(set) var topTracks: [MediaItem] = []
    /// Albums and playlists from recent plays, most recent first.
    private(set) var jumpBackIn: [MediaItem] = []
    private(set) var status: [Part: Status] = [:]

    @ObservationIgnored private let account: SpotifyAccount
    @ObservationIgnored private var loadedAt: [Part: Date] = [:]
    @ObservationIgnored private let logger = Logger(subsystem: "com.hoventan.SpotifyCompanion", category: "Account")

    init(account: SpotifyAccount) {
        self.account = account
    }

    func status(_ part: Part) -> Status { status[part] ?? .idle }

    /// Loads `part` unless it loaded in the last five minutes (or is loading now).
    func load(_ part: Part, force: Bool = false) {
        guard let api = account.api, let userID = account.userID else { return }
        if status(part) == .loading { return }
        // Asking again can't help until the user reconnects, which resets this.
        if !force, status(part) == .needsReconnect { return }
        if !force, let at = loadedAt[part], Date().timeIntervalSince(at) < 300, status(part) == .loaded { return }
        status[part] = .loading
        Task {
            do {
                switch part {
                case .library: try await loadLibrary(api, userID: userID)
                case .liked: try await loadLiked(api)
                case .top: try await loadTop(api)
                }
                status[part] = .loaded
                loadedAt[part] = Date()
                logger.info("Browse \(String(describing: part), privacy: .public): \(self.summary(part), privacy: .public)")
            } catch {
                logger.error("Browse \(String(describing: part), privacy: .public) failed: \(error.localizedDescription, privacy: .public)")
                status[part] = Self.isMissingScope(error) ? .needsReconnect : .failed(error.localizedDescription)
            }
        }
    }

    /// Forgets everything, e.g. after signing out.
    func reset() {
        library = []; liked = []; likedTotal = nil; followedArtists = []
        topArtists = []; topTracks = []; jumpBackIn = []
        status = [:]; loadedAt = [:]
    }

    private func loadLibrary(_ api: SpotifyWebAPI, userID: String) async throws {
        async let playlists = api.playlists(userID: userID)
        async let albums = api.savedAlbums()
        async let plays = api.recentPlays()
        // Followed artists need a permission older sign-ins don't have; the rest still loads.
        async let artists = try? api.followedArtists()
        let (lists, saved, recent) = try await (playlists, albums, plays)
        followedArtists = await artists ?? []

        // When each album or playlist last played, from the plays the API remembers (50).
        var lastPlayed: [String: Date] = [:]
        for play in recent {
            guard let uri = play.contextURI, let at = play.playedAt else { continue }
            if lastPlayed[uri] == nil { lastPlayed[uri] = at }
        }
        let liked = MediaItem.likedSongs(userID: userID, count: likedTotal)
        var items = ([liked] + lists + saved + followedArtists).map { item in
            var item = item
            item.lastPlayed = lastPlayed[item.uri]
            return item
        }
        // Remove duplicates (an artist can be both followed and in a playlist's owner field, etc.).
        var seen = Set<String>()
        items = items.filter { seen.insert($0.uri).inserted }
        library = items

        // Jump back in: recent contexts, in order, as library items where we have them and
        // built from the song's album otherwise.
        let byURI = Dictionary(items.map { ($0.uri, $0) }, uniquingKeysWith: { a, _ in a })
        var contexts: [MediaItem] = []
        var added = Set<String>()
        for play in recent {
            let uri = play.contextURI ?? play.track.albumURI
            guard let uri, added.insert(uri).inserted else { continue }
            if let known = byURI[uri] {
                contexts.append(known)
            } else if uri == play.track.albumURI, let name = play.track.albumName {
                contexts.append(MediaItem(uri: uri, kind: .album, name: name, subtitle: play.track.subtitle,
                                          imageURL: play.track.imageURL, lastPlayed: play.playedAt))
            }
            if contexts.count == 12 { break }
        }
        jumpBackIn = contexts
    }

    private func loadLiked(_ api: SpotifyWebAPI) async throws {
        let (songs, total) = try await api.likedSongs()
        liked = songs
        likedTotal = total
        if let index = library.firstIndex(where: { $0.kind == .collection }) {
            library[index].detail = "\(total) songs"
        }
    }

    private func loadTop(_ api: SpotifyWebAPI) async throws {
        async let artists = api.topArtists()
        async let tracks = api.topTracks()
        (topArtists, topTracks) = try await (artists, tracks)
    }

    private func summary(_ part: Part) -> String {
        switch part {
        case .library: "\(library.count) items, \(followedArtists.count) followed artists, \(jumpBackIn.count) recent contexts"
        case .liked: "\(liked.count) of \(likedTotal ?? 0) songs"
        case .top: "\(topArtists.count) artists, \(topTracks.count) songs"
        }
    }

    static func isMissingScope(_ error: Error) -> Bool {
        if case WebAPIError.http(403, let message) = error {
            return message.localizedCaseInsensitiveContains("scope")
        }
        return false
    }
}

/// Search as you type: waits for a pause, cancels stale requests, keeps the last few results
/// so going back over a query is instant, and remembers recent searches.
@MainActor
@Observable
final class SearchStore {
    enum Scope: String, CaseIterable, Identifiable {
        case top = "Top", songs = "Songs", artists = "Artists", albums = "Albums", playlists = "Playlists"
        var id: Self { self }

        var kind: MediaItem.Kind? {
            switch self {
            case .top: nil
            case .songs: .track
            case .artists: .artist
            case .albums: .album
            case .playlists: .playlist
            }
        }
    }

    var query = "" {
        didSet { if query != oldValue { schedule() } }
    }
    var scope: Scope = .top {
        didSet { if scope != oldValue { schedule(immediately: true) } }
    }
    private(set) var results: [MediaItem.Kind: [MediaItem]] = [:]
    /// The query `results` belong to.
    private(set) var resultQuery = ""
    private(set) var isSearching = false
    private(set) var canLoadMore = false
    private(set) var error: String?
    private(set) var recent: [String]

    var trimmed: String { query.trimmingCharacters(in: .whitespacesAndNewlines) }
    var isActive: Bool { !trimmed.isEmpty }

    /// The best single match: an artist whose name matches the query, else the first song.
    var topResult: MediaItem? {
        let artists = results[.artist] ?? []
        if let artist = artists.first(where: { $0.name.localizedCaseInsensitiveCompare(resultQuery) == .orderedSame })
            ?? artists.first(where: { $0.name.lowercased().hasPrefix(resultQuery.lowercased()) }) {
            return artist
        }
        return results[.track]?.first ?? results[.album]?.first ?? artists.first
    }

    var isEmptyResult: Bool { !isSearching && error == nil && resultQuery == trimmed && results.values.allSatisfy(\.isEmpty) }

    @ObservationIgnored private let account: SpotifyAccount
    @ObservationIgnored private var task: Task<Void, Never>?
    @ObservationIgnored private var cache: [String: [MediaItem.Kind: [MediaItem]]] = [:]
    @ObservationIgnored private let debounce: Duration
    private static let recentKey = "recentSearches"

    init(account: SpotifyAccount, debounce: Duration = .milliseconds(280)) {
        self.account = account
        self.debounce = debounce
        recent = UserDefaults.standard.stringArray(forKey: Self.recentKey) ?? []
    }

    /// Saves the current query to recent searches (on Return, or opening a result).
    func commit() {
        let text = trimmed
        guard !text.isEmpty else { return }
        recent.removeAll { $0.localizedCaseInsensitiveCompare(text) == .orderedSame }
        recent.insert(text, at: 0)
        recent = Array(recent.prefix(8))
        UserDefaults.standard.set(recent, forKey: Self.recentKey)
    }

    func forget(_ text: String) {
        recent.removeAll { $0 == text }
        UserDefaults.standard.set(recent, forKey: Self.recentKey)
    }

    func clear() {
        query = ""
        scope = .top
    }

    /// The next page of the current scope (10 at a time is all Development Mode allows).
    func loadMore() {
        guard let kind = scope.kind, let api = account.api, canLoadMore, !isSearching else { return }
        let text = resultQuery
        let offset = results[kind]?.count ?? 0
        isSearching = true
        task = Task {
            defer { isSearching = false }
            guard let page = try? await api.search(text, types: [kind], offset: offset), !Task.isCancelled else { return }
            let more = page[kind] ?? []
            results[kind, default: []] += more
            canLoadMore = more.count == 10
        }
    }

    private func schedule(immediately: Bool = false) {
        task?.cancel()
        let text = trimmed
        guard !text.isEmpty else {
            results = [:]; resultQuery = ""; error = nil; isSearching = false; canLoadMore = false
            return
        }
        let key = "\(scope.rawValue)|\(text.lowercased())"
        if let cached = cache[key] {
            results = cached; resultQuery = text; error = nil; isSearching = false
            canLoadMore = scope.kind.map { (cached[$0]?.count ?? 0) == 10 } ?? false
            return
        }
        guard let api = account.api else { return }
        isSearching = true
        let scope = scope
        task = Task {
            if !immediately { try? await Task.sleep(for: debounce) }
            guard !Task.isCancelled else { return }
            do {
                let types: [MediaItem.Kind] = scope.kind.map { [$0] } ?? [.track, .artist, .album, .playlist]
                let found = try await api.search(text, types: types)
                guard !Task.isCancelled else { return }
                Logger(subsystem: "com.hoventan.SpotifyCompanion", category: "Account")
                    .info("Search (\(scope.rawValue, privacy: .public)): \(found.values.map(\.count).reduce(0, +)) results")
                if cache.count > 40 { cache.removeAll() }
                cache[key] = found
                results = found
                resultQuery = text
                error = nil
                canLoadMore = scope.kind.map { (found[$0]?.count ?? 0) == 10 } ?? false
            } catch {
                guard !Task.isCancelled else { return }
                self.error = error.localizedDescription
            }
            isSearching = false
        }
    }
}

#if DEBUG
import SwiftUI

extension BrowseStore {
    /// A store filled with made-up library data, for SwiftUI previews.
    static func preview(account: SpotifyAccount, images: [URL] = []) -> BrowseStore {
        let store = BrowseStore(account: account)
        var next = 0
        func item(_ n: Int, _ kind: MediaItem.Kind, _ name: String, _ by: String, detail: String? = nil) -> MediaItem {
            defer { next += 1 }
            return MediaItem(uri: "spotify:\(kind.rawValue):preview\(n)", kind: kind, name: name, subtitle: by,
                             imageURL: images.isEmpty ? nil : images[next % images.count], detail: detail)
        }
        let artists = ["Josef Müller-Brockmann", "Wim Crouwel", "Paula Scher", "Massimo Vignelli", "Otl Aicher", "Karl Gerstner"]
            .enumerated().map { item($0.offset, .artist, $0.element, "Artist") }
        let albums = ["Grid Systems", "New Alphabet", "Signal Red", "Univers 55", "Akzidenz", "Black on White"]
            .enumerated().map { item($0.offset, .album, $0.element, artists[$0.offset].name, detail: "Album · 19\(60 + $0.offset)") }
        let playlists = ["Late Night Grids", "Running", "Shared with Bea", "Focus Flow"]
            .enumerated().map { item($0.offset, .playlist, $0.element, "Preview", detail: "\(20 + $0.offset * 7) songs") }
        let songs = (0..<12).map { n in
            var song = item(n, .track, ["Helvetica Hum", "Flush Left", "Ragged Right", "Bold Only", "Kerning", "Swiss Rain"][n % 6] + (n > 5 ? " (Live)" : ""),
                            artists[n % artists.count].name)
            song.duration = TimeInterval(160 + n * 13)
            song.albumName = albums[n % albums.count].name
            return song
        }
        store.library = [MediaItem.likedSongs(userID: "preview", count: 128)] + playlists + albums + Array(artists.prefix(3))
        store.liked = songs
        store.likedTotal = 128
        store.followedArtists = artists
        store.topArtists = artists.reversed()
        store.topTracks = songs
        store.jumpBackIn = Array((albums.prefix(3) + playlists.prefix(3)).shuffled())
        store.status = [.library: .loaded, .liked: .loaded, .top: .loaded]
        return store
    }
}

extension View {
    /// Navigation, browse and search stores for previews.
    func browsePreviews(signedIn: Bool = true) -> some View {
        let account = SpotifyAccount.preview(signedIn: signedIn)
        return self
            .environment(Router())
            .environment(BrowseNavigation())
            .environment(signedIn ? BrowseStore.preview(account: account) : BrowseStore(account: account))
            .environment(SearchStore(account: account))
    }
}
#endif

#if DEBUG
extension SearchStore {
    /// Shows `results` for `query` without searching, for previews.
    func preview(query: String, results: [MediaItem.Kind: [MediaItem]], scope: Scope = .top) {
        task?.cancel()
        self.query = query
        self.scope = scope
        task?.cancel()
        self.results = results
        resultQuery = query.trimmingCharacters(in: .whitespacesAndNewlines)
        isSearching = false
        error = nil
    }
}
#endif
