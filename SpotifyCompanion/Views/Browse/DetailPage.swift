import AppKit
import SwiftUI

/// An album, playlist, artist or Liked Songs, opened from a tile or a search result: a large
/// header with a play button, then its songs (or an artist's releases).
struct DetailPage: View {
    let item: MediaItem
    let namespace: Namespace.ID

    @Environment(SpotifyAccount.self) private var account
    @Environment(BrowseStore.self) private var browse
    @Environment(\.theme) private var theme
    @State private var header: MediaItem?
    @State private var songs: [MediaItem]?
    @State private var releases: [MediaItem] = []
    @State private var error: String?
    @State private var isLoading = true

    var body: some View {
        VStack(alignment: .leading, spacing: Metrics.unit * 3) {
            DetailHeader(item: header ?? item, namespace: namespace)
            content
        }
        .task(id: item.uri) { await load() }
    }

    @ViewBuilder
    private var content: some View {
        if let error {
            BrowseMessage(icon: "wifi.exclamationmark", title: "Couldn’t load this", detail: error)
        } else {
            switch item.kind {
            case .artist:
                VStack(alignment: .leading, spacing: Metrics.unit * 1.5) {
                    SectionTitle(title: "Releases")
                    if isLoading && releases.isEmpty { LoadingShelf() } else { TileGrid(items: releases, namespace: namespace) }
                }
            case .playlist where !isLoading && songs == nil:
                BrowseMessage(icon: "lock", title: "Spotify only shares song lists for your own playlists",
                              detail: "Play it from here, or open it in Spotify to see the songs.",
                              action: ("Open in Spotify", "arrow.up.forward.app", {
                                  if let url = URL(string: item.uri) { NSWorkspace.shared.open(url) }
                              }))
            case .collection:
                SongList(songs: browse.liked, context: item.uri, isLoading: browse.status(.liked) == .loading)
            default:
                SongList(songs: songs ?? [], context: item.kind == .track ? nil : item.uri, isLoading: isLoading,
                         showsCover: item.kind != .album)
            }
        }
    }

    private func load() async {
        guard let api = account.api else {
            isLoading = false
            return
        }
        isLoading = true
        do {
            switch item.kind {
            case .album:
                let result = try await api.album(item.spotifyID)
                header = result.album
                songs = result.songs
            case .artist:
                let result = try await api.artist(item.spotifyID)
                header = result.artist
                releases = result.releases
            case .playlist:
                let result = try await api.playlist(item.spotifyID, userID: account.userID)
                header = result.playlist
                songs = result.songs
            case .collection:
                browse.load(.liked)
            case .track:
                break
            }
            error = nil
        } catch {
            // Spotify's own playlists answer 404 to Development Mode apps; they still play.
            if item.kind == .playlist, case WebAPIError.http(404, _) = error {
                songs = nil
            } else {
                self.error = error.localizedDescription
            }
        }
        isLoading = false
    }
}

/// Large cover, what it is, name, by whom, details, and play / open-in-Spotify buttons.
struct DetailHeader: View {
    let item: MediaItem
    let namespace: Namespace.ID?

    @Environment(SpotifyService.self) private var spotify
    @Environment(\.theme) private var theme

    var body: some View {
        HStack(alignment: .bottom, spacing: Metrics.unit * 3) {
            cover
                .frame(width: 190, height: 190)
                .shadow(color: .black.opacity(0.25), radius: 20, y: 10)
            VStack(alignment: .leading, spacing: Metrics.unit) {
                Text(kind).styledLabel().foregroundStyle(theme.accent)
                Text(item.name)
                    .styledTitle(44)
                    .lineLimit(2)
                    .minimumScaleFactor(0.5)
                    .fixedSize(horizontal: false, vertical: true)
                Text(line)
                    .font(theme.font(\.body, 14))
                    .foregroundStyle(theme.secondary)
                    .lineLimit(1)
                HStack(spacing: Metrics.unit * 1.5) {
                    Button { spotify.play(uri: item.uri) } label: {
                        ControlFace(diameter: 50, isPlaying: false)
                    }
                    .buttonStyle(PressableStyle())
                    .disabled(spotify.connection != .connected)
                    .help("Play \(item.name)")
                    if item.kind != .collection, let url = URL(string: item.uri) {
                        IconButton(systemName: "arrow.up.forward.app", label: "Open in Spotify", size: 16) {
                            NSWorkspace.shared.open(url)
                        }
                    }
                }
                .padding(.top, Metrics.unit)
            }
            Spacer(minLength: 0)
        }
    }

    @ViewBuilder
    private var cover: some View {
        if let namespace {
            CoverImage(item: item).matchedGeometryEffect(id: "cover-\(item.uri)", in: namespace)
        } else {
            CoverImage(item: item)
        }
    }

    private var kind: String {
        switch item.kind {
        case .album: "Album"
        case .playlist, .collection: "Playlist"
        case .artist: "Artist"
        case .track: "Song"
        }
    }

    private var line: String {
        switch item.kind {
        case .artist: item.detail ?? ""
        case .playlist: ["By \(item.subtitle)", item.detail].compactMap { $0 }.joined(separator: " · ")
        case .collection: item.detail ?? "Your liked songs"
        default: [item.subtitle, item.detail].compactMap { $0 }.filter { !$0.isEmpty }.joined(separator: " · ")
        }
    }
}
