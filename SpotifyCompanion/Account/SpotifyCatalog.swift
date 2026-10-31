import Foundation

/// A song, album, playlist or artist from the Web API, flattened to what the browse views show.
/// Playing one goes through AppleScript with its URI, so anything with a URI is playable, even
/// when the API won't list its contents (Spotify's own playlists, for example).
struct MediaItem: Identifiable, Hashable, Sendable {
    enum Kind: String, Sendable {
        case track, album, playlist, artist
        /// Liked Songs.
        case collection
    }

    let uri: String
    let kind: Kind
    let name: String
    /// Artists for songs and albums, the owner for playlists, "Artist" for artists.
    let subtitle: String
    let imageURL: URL?
    var duration: TimeInterval?
    /// The album a song is on, so it can play in that context.
    var albumURI: String?
    var albumName: String?
    /// Playlists only: the API lists songs only for playlists the user owns or collaborates on.
    var isEditable = false
    var addedAt: Date?
    var lastPlayed: Date?
    /// Albums: the year it came out; playlists and Liked Songs: how many songs.
    var detail: String?

    var id: String { uri }

    /// The id part of `spotify:album:abc`.
    var spotifyID: String { uri.split(separator: ":").last.map(String.init) ?? uri }

    /// Liked Songs as a playable context; the API reports plays from it under this URI.
    static func likedSongs(userID: String, count: Int?) -> MediaItem {
        MediaItem(uri: "spotify:user:\(userID):collection", kind: .collection, name: "Liked Songs",
                  subtitle: "Playlist", imageURL: nil, detail: count.map { "\($0) songs" })
    }
}

/// Web API calls for browsing, all GETs the February 2026 Development Mode rules still allow.
extension SpotifyWebAPI {
    /// One page of each kind. Development Mode caps `limit` at 10 per type.
    func search(_ query: String, types: [MediaItem.Kind], offset: Int = 0) async throws -> [MediaItem.Kind: [MediaItem]] {
        let response = try await decode(APISearch.self, "GET", "search", query: [
            URLQueryItem(name: "q", value: query),
            URLQueryItem(name: "type", value: types.map(\.rawValue).joined(separator: ",")),
            URLQueryItem(name: "limit", value: "10"),
            URLQueryItem(name: "offset", value: String(offset)),
        ])
        return [
            .track: response.tracks?.items.compactMap { $0?.item } ?? [],
            .artist: response.artists?.items.compactMap { $0?.item } ?? [],
            .album: response.albums?.items.compactMap { $0?.item } ?? [],
            .playlist: response.playlists?.items.compactMap { $0?.item(userID: nil) } ?? [],
        ]
    }

    func savedAlbums(max: Int = 200) async throws -> [MediaItem] {
        try await pages(max: max) { offset in
            let page = try await self.decode(APISavedPage<APIAlbum>.self, "GET", "me/albums", query: Self.page(offset))
            return (page.items.map { saved in
                var item = saved.object.item
                item.addedAt = APIDate.parse(saved.added_at)
                return item
            }, page.next != nil)
        }
    }

    func playlists(userID: String, max: Int = 200) async throws -> [MediaItem] {
        try await pages(max: max) { offset in
            let page = try await self.decode(APIPage<APIPlaylist>.self, "GET", "me/playlists", query: Self.page(offset))
            return (page.items.compactMap { $0?.item(userID: userID) }, page.next != nil)
        }
    }

    func likedSongs(max: Int = 250) async throws -> (songs: [MediaItem], total: Int) {
        var total = 0
        let songs = try await pages(max: max) { offset in
            let page = try await self.decode(APISavedPage<APITrack>.self, "GET", "me/tracks", query: Self.page(offset))
            total = page.total ?? total
            return (page.items.map { saved in
                var item = saved.object.item
                item.addedAt = APIDate.parse(saved.added_at)
                return item
            }, page.next != nil)
        }
        return (songs, Swift.max(total, songs.count))
    }

    func followedArtists(max: Int = 200) async throws -> [MediaItem] {
        var found: [MediaItem] = []
        var after: String?
        repeat {
            var query = [URLQueryItem(name: "type", value: "artist"), URLQueryItem(name: "limit", value: "50")]
            if let after { query.append(URLQueryItem(name: "after", value: after)) }
            let page = try await decode(APIFollowed.self, "GET", "me/following", query: query)
            found += page.artists.items.map(\.item)
            after = page.artists.next == nil ? nil : page.artists.cursors?.after
        } while after != nil && found.count < max
        return found
    }

    func topArtists() async throws -> [MediaItem] {
        try await decode(APIPage<APIArtist>.self, "GET", "me/top/artists", query: Self.top).items.compactMap { $0?.item }
    }

    func topTracks() async throws -> [MediaItem] {
        try await decode(APIPage<APITrack>.self, "GET", "me/top/tracks", query: Self.top).items.compactMap { $0?.item }
    }

    /// The last 50 plays, newest first, each with the album or playlist it played from.
    func recentPlays() async throws -> [(track: MediaItem, contextURI: String?, playedAt: Date?)] {
        let page = try await decode(APIRecent.self, "GET", "me/player/recently-played", query: [URLQueryItem(name: "limit", value: "50")])
        return page.items.compactMap { play in
            guard let track = play.track else { return nil }
            return (track.item, play.context?.uri, APIDate.parse(play.played_at))
        }
    }

    func album(_ id: String) async throws -> (album: MediaItem, songs: [MediaItem]) {
        let album = try await decode(APIAlbum.self, "GET", "albums/\(id)")
        let header = album.item
        let songs = (album.tracks?.items ?? []).map { track in
            var item = track.item
            item.albumURI = header.uri
            item.albumName = header.name
            return item
        }
        return (header, songs)
    }

    func artist(_ id: String) async throws -> (artist: MediaItem, releases: [MediaItem]) {
        async let artist = decode(APIArtist.self, "GET", "artists/\(id)")
        async let releases = decode(APIPage<APIAlbum>.self, "GET", "artists/\(id)/albums", query: [
            URLQueryItem(name: "include_groups", value: "album,single,compilation"),
            URLQueryItem(name: "limit", value: "30"),
        ])
        return try await (artist.item, releases.items.compactMap { $0?.item })
    }

    /// Songs only come back for playlists the user owns or collaborates on; others are metadata.
    func playlist(_ id: String, userID: String?) async throws -> (playlist: MediaItem, songs: [MediaItem]?) {
        let playlist = try await decode(APIPlaylist.self, "GET", "playlists/\(id)")
        let songs = (playlist.items?.items ?? playlist.tracks?.items)?.compactMap { $0.track?.item }
        return (playlist.item(userID: userID), songs)
    }

    // MARK: Paging

    private static func page(_ offset: Int) -> [URLQueryItem] {
        [URLQueryItem(name: "limit", value: "50"), URLQueryItem(name: "offset", value: String(offset))]
    }

    private static let top = [URLQueryItem(name: "time_range", value: "short_term"), URLQueryItem(name: "limit", value: "20")]

    private func pages(max: Int, _ load: (Int) async throws -> ([MediaItem], Bool)) async throws -> [MediaItem] {
        var found: [MediaItem] = []
        var more = true
        while more && found.count < max {
            let (items, hasNext) = try await load(found.count)
            found += items
            more = hasNext && !items.isEmpty
        }
        return found
    }
}

// MARK: Response shapes

enum APIDate {
    nonisolated(unsafe) private static let withFraction: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }()
    nonisolated(unsafe) private static let plain = ISO8601DateFormatter()

    static func parse(_ string: String?) -> Date? {
        guard let string else { return nil }
        return withFraction.date(from: string) ?? plain.date(from: string)
    }
}

struct APIPage<Item: Decodable & Sendable>: Decodable, Sendable {
    let items: [Item?]
    let next: String?
}

struct APISavedPage<Object: Decodable & Sendable>: Decodable, Sendable {
    struct Saved: Decodable, Sendable {
        let added_at: String?
        let object: Object

        enum CodingKeys: String, CodingKey { case added_at, album, track }

        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            added_at = try container.decodeIfPresent(String.self, forKey: .added_at)
            // Saved albums wrap an `album`, saved songs a `track`.
            object = try container.decodeIfPresent(Object.self, forKey: .album) ?? container.decode(Object.self, forKey: .track)
        }
    }
    let items: [Saved]
    let next: String?
    let total: Int?
}

struct APIArtistRef: Decodable, Sendable {
    let name: String
    let uri: String?
}

struct APITrack: Decodable, Sendable {
    struct AlbumRef: Decodable, Sendable {
        let uri: String?
        let name: String?
        let images: [APIImage]?
    }
    let uri: String
    let name: String
    let duration_ms: Int?
    let artists: [APIArtistRef]?
    let album: AlbumRef?

    var item: MediaItem {
        MediaItem(
            uri: uri, kind: .track, name: name,
            subtitle: artists?.map(\.name).joined(separator: ", ") ?? "",
            imageURL: bestImageURL(album?.images, minimum: 120),
            duration: duration_ms.map { TimeInterval($0) / 1000 },
            albumURI: album?.uri, albumName: album?.name
        )
    }
}

struct APIAlbum: Decodable, Sendable {
    struct Tracks: Decodable, Sendable { let items: [APITrack] }
    let uri: String
    let name: String
    let artists: [APIArtistRef]?
    let images: [APIImage]?
    let release_date: String?
    let album_type: String?
    let total_tracks: Int?
    let tracks: Tracks?

    var item: MediaItem {
        let year = release_date.map { String($0.prefix(4)) }
        let type = album_type.map { $0 == "album" ? "Album" : $0.capitalized }
        return MediaItem(
            uri: uri, kind: .album, name: name,
            subtitle: artists?.map(\.name).joined(separator: ", ") ?? "",
            imageURL: bestImageURL(images, minimum: 300),
            detail: [type, year].compactMap { $0 }.joined(separator: " · ")
        )
    }
}

struct APIArtist: Decodable, Sendable {
    let uri: String
    let name: String
    let images: [APIImage]?
    let genres: [String]?

    var item: MediaItem {
        MediaItem(uri: uri, kind: .artist, name: name, subtitle: "Artist", imageURL: bestImageURL(images, minimum: 300),
                  detail: genres?.prefix(2).joined(separator: ", "))
    }
}

struct APIPlaylist: Decodable, Sendable {
    struct Owner: Decodable, Sendable {
        let id: String
        let display_name: String?
    }
    struct Entries: Decodable, Sendable {
        struct Entry: Decodable, Sendable {
            let item: APITrack?
            let trackObject: APITrack?
            var track: APITrack? { item ?? trackObject }

            enum CodingKeys: String, CodingKey { case item, trackObject = "track" }
        }
        let total: Int?
        let items: [Entry]?
    }
    let uri: String
    let name: String
    let owner: Owner?
    let collaborative: Bool?
    let images: [APIImage]?
    /// Renamed from `tracks` in February 2026; both decoded so either shape works.
    let items: Entries?
    let tracks: Entries?

    func item(userID: String?) -> MediaItem {
        let total = (items ?? tracks)?.total
        return MediaItem(
            uri: uri, kind: .playlist, name: name,
            subtitle: owner?.display_name ?? owner?.id ?? "Playlist",
            imageURL: bestImageURL(images, minimum: 300),
            isEditable: userID != nil && (owner?.id == userID || collaborative == true),
            detail: total.map { "\($0) songs" }
        )
    }
}

private struct APISearch: Decodable, Sendable {
    struct Section<Item: Decodable & Sendable>: Decodable, Sendable { let items: [Item?] }
    let tracks: Section<APITrack>?
    let artists: Section<APIArtist>?
    let albums: Section<APIAlbum>?
    let playlists: Section<APIPlaylist>?
}

private struct APIFollowed: Decodable, Sendable {
    struct Artists: Decodable, Sendable {
        struct Cursors: Decodable, Sendable { let after: String? }
        let items: [APIArtist]
        let next: String?
        let cursors: Cursors?
    }
    let artists: Artists
}

private struct APIRecent: Decodable, Sendable {
    struct Play: Decodable, Sendable {
        struct Context: Decodable, Sendable { let uri: String? }
        let track: APITrack?
        let played_at: String?
        let context: Context?
    }
    let items: [Play]
}

