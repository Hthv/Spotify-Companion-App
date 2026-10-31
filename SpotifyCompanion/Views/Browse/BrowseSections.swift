import SwiftUI

/// The content for the category chosen in the rail.
struct CategoryView: View {
    let category: BrowseCategory
    let namespace: Namespace.ID
    let openPlayer: () -> Void

    var body: some View {
        switch category {
        case .forYou: ForYouSection(namespace: namespace, openPlayer: openPlayer)
        case .library: LibrarySection(namespace: namespace)
        case .liked: LikedSection()
        case .artists: ArtistsSection(namespace: namespace)
        case .recent: RecentPlaysSection()
        case .styles: StylesSection()
        }
    }
}

/// Shown in place of a section that needs the user signed in, or a permission they haven't
/// granted yet.
private struct SignInGate<Content: View>: View {
    let status: BrowseStore.Status
    let what: String
    @ViewBuilder let content: Content

    @Environment(SpotifyAccount.self) private var account
    @Environment(Router.self) private var router

    var body: some View {
        if !account.isSignedIn {
            BrowseMessage(icon: "person.crop.circle.badge.plus", title: "Connect your Spotify account",
                          detail: "\(what) come from your Spotify account.",
                          action: ("Connect", "link", { router.isAccountShown = true }))
        } else if status == .needsReconnect {
            BrowseMessage(icon: "arrow.triangle.2.circlepath", title: "Connect again to see \(what.lowercased())",
                          detail: "This needs a permission your current sign-in doesn’t include.",
                          action: ("Reconnect", "link", { account.signIn() }))
        } else if case .failed(let message) = status {
            BrowseMessage(icon: "wifi.exclamationmark", title: "Couldn’t load \(what.lowercased())", detail: message)
        } else {
            content
        }
    }
}

// MARK: For You

/// Built from the user's own listening, since Development Mode can't read Spotify's curated
/// playlists: what's playing, where they left off, top artists and songs this month, moods.
private struct ForYouSection: View {
    let namespace: Namespace.ID
    let openPlayer: () -> Void

    @Environment(BrowseStore.self) private var browse
    @Environment(BrowseNavigation.self) private var navigation
    @Environment(SpotifyAccount.self) private var account
    @Environment(\.theme) private var theme

    var body: some View {
        VStack(alignment: .leading, spacing: Metrics.unit * 5) {
            Greeting()
            NowPlayingCard(openPlayer: openPlayer)
            if !account.isSignedIn {
                SignInGate(status: .idle, what: "Recommendations") { EmptyView() }
            } else {
                if browse.status(.library) == .loading && browse.jumpBackIn.isEmpty {
                    VStack(alignment: .leading, spacing: Metrics.unit * 1.5) {
                        SectionTitle(title: "Jump back in")
                        LoadingShelf()
                    }
                } else if !browse.jumpBackIn.isEmpty {
                    Shelf(title: "Jump back in", items: browse.jumpBackIn, namespace: namespace)
                }
                SignInGate(status: browse.status(.top), what: "Your top artists and songs") {
                    if browse.status(.top) == .loading && browse.topArtists.isEmpty {
                        LoadingShelf(round: true)
                    } else {
                        if !browse.topArtists.isEmpty {
                            Shelf(title: "Your top artists", items: browse.topArtists, tileWidth: 140,
                                  showAll: { withAnimation(theme.style.motion) { navigation.category = .artists } }, namespace: namespace)
                        }
                        if !browse.topTracks.isEmpty {
                            OnRepeat(songs: Array(browse.topTracks.prefix(10)))
                        }
                    }
                }
            }
            MoodGrid(title: "Moods and genres")
            VStack(alignment: .leading, spacing: Metrics.unit * 1.5) {
                SectionTitle(title: "Recently played") {
                    withAnimation(theme.style.motion) { navigation.category = .recent }
                }
                RecentSection(compact: true)
            }
        }
        .onAppear {
            browse.load(.library)
            browse.load(.top)
        }
    }
}

/// Top songs this month in two columns.
private struct OnRepeat: View {
    let songs: [MediaItem]

    var body: some View {
        VStack(alignment: .leading, spacing: Metrics.unit * 1.5) {
            SectionTitle(title: "On repeat")
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 300), spacing: Metrics.unit * 2)], spacing: 2) {
                ForEach(Array(songs.enumerated()), id: \.element.id) { index, song in
                    SongRow(item: song, index: index, showsAlbum: false)
                        .staggered(index)
                }
            }
        }
    }
}

// MARK: Library

enum LibraryFilter: String, CaseIterable, Identifiable {
    case all = "All", playlists = "Playlists", albums = "Albums", artists = "Artists"
    var id: Self { self }
}

enum LibrarySort: String, CaseIterable, Identifiable {
    case recents = "Recents", added = "Recently added", alphabetical = "Alphabetical", creator = "Creator"
    var id: Self { self }
}

/// Everything saved, like Spotify's Your Library: filter by kind, sort, grid or list.
private struct LibrarySection: View {
    let namespace: Namespace.ID

    @Environment(BrowseStore.self) private var browse
    @Environment(\.theme) private var theme
    @AppStorage(Pref.libraryFilter) private var filter: LibraryFilter = .all
    @AppStorage(Pref.librarySort) private var sort: LibrarySort = .recents
    @AppStorage(Pref.libraryGrid) private var grid = true
    @Namespace private var chips

    private var items: [MediaItem] {
        let kept = browse.library.filter { item in
            switch filter {
            case .all: true
            case .playlists: item.kind == .playlist || item.kind == .collection
            case .albums: item.kind == .album
            case .artists: item.kind == .artist
            }
        }
        return Self.sorted(kept, by: sort)
    }

    /// Recents: played lately first (from the last 50 plays), then newest saved. Liked Songs
    /// stays on top, as in Spotify.
    static func sorted(_ items: [MediaItem], by sort: LibrarySort) -> [MediaItem] {
        let indexed = Array(items.enumerated())
        let ordered: [(offset: Int, element: MediaItem)] = switch sort {
        case .recents:
            indexed.sorted { a, b in
                switch (a.element.lastPlayed, b.element.lastPlayed) {
                case let (x?, y?): x > y
                case (_?, nil): true
                case (nil, _?): false
                case (nil, nil): (a.element.addedAt ?? .distantPast, b.offset) > (b.element.addedAt ?? .distantPast, a.offset)
                }
            }
        case .added:
            indexed.sorted { ($0.element.addedAt ?? .distantPast, $1.offset) > ($1.element.addedAt ?? .distantPast, $0.offset) }
        case .alphabetical:
            indexed.sorted { $0.element.name.localizedStandardCompare($1.element.name) == .orderedAscending }
        case .creator:
            indexed.sorted { $0.element.subtitle.localizedStandardCompare($1.element.subtitle) == .orderedAscending }
        }
        let list = ordered.map(\.element)
        return list.filter { $0.kind == .collection } + list.filter { $0.kind != .collection }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Metrics.unit * 3) {
            HStack(alignment: .firstTextBaseline) {
                Text("Your Library").styledTitle(34)
                Spacer()
                Menu {
                    Picker("Sort by", selection: $sort) {
                        ForEach(LibrarySort.allCases) { Text($0.rawValue).tag($0) }
                    }
                    .pickerStyle(.inline)
                } label: {
                    Label(sort.rawValue, systemImage: "arrow.up.arrow.down")
                        .font(theme.font(\.body, 13))
                }
                .menuStyle(.borderlessButton)
                .fixedSize()
                IconButton(systemName: grid ? "list.bullet" : "square.grid.2x2", label: grid ? "Show as list" : "Show as grid", size: 15) {
                    withAnimation(.spring(duration: 0.45, bounce: 0.2)) { grid.toggle() }
                }
            }
            HStack(spacing: Metrics.unit) {
                ForEach(LibraryFilter.allCases) { option in
                    let isOn = filter == option
                    Button {
                        withAnimation(.spring(duration: 0.4, bounce: 0.3)) { filter = option }
                    } label: {
                        Text(option.rawValue)
                            .font(theme.font(\.label, 12))
                            .textCase(theme.style.labelCase)
                            .tracking(theme.style.labelTracking * 0.4)
                            .foregroundStyle(isOn ? theme.background : theme.foreground)
                            .padding(.horizontal, 14)
                            .padding(.vertical, 7)
                            .background {
                                if isOn {
                                    Capsule().fill(theme.foreground).matchedGeometryEffect(id: "filter", in: chips)
                                } else {
                                    Capsule().strokeBorder(theme.rule)
                                }
                            }
                            .contentShape(Capsule())
                    }
                    .buttonStyle(PressableStyle())
                }
            }
            SignInGate(status: browse.status(.library), what: "Your playlists and albums") {
                if browse.status(.library) == .loading && browse.library.isEmpty {
                    LoadingShelf()
                } else if items.isEmpty {
                    BrowseMessage(icon: "books.vertical", title: "Nothing here yet",
                                  detail: "Save albums, follow artists or make playlists in Spotify and they’ll show up here.")
                } else if grid {
                    TileGrid(items: items, namespace: namespace)
                        .id("\(filter.rawValue)\(sort.rawValue)")
                } else {
                    LazyVStack(spacing: 2) {
                        ForEach(Array(items.enumerated()), id: \.element.id) { index, item in
                            LibraryRow(item: item).staggered(index % 16)
                        }
                    }
                    .id("\(filter.rawValue)\(sort.rawValue)list")
                }
            }
        }
        .onAppear {
            browse.load(.library)
            browse.load(.liked)
        }
    }
}

/// A compact library line: cover, name, kind and owner, when it last played.
private struct LibraryRow: View {
    let item: MediaItem

    @Environment(BrowseNavigation.self) private var navigation
    @Environment(\.theme) private var theme
    @State private var isHovering = false

    var body: some View {
        Button { navigation.open(item) } label: {
            HStack(spacing: Metrics.unit * 1.5) {
                CoverImage(item: item).frame(width: 48, height: 48)
                VStack(alignment: .leading, spacing: 3) {
                    Text(item.name).font(theme.font(\.display, 15)).lineLimit(1)
                    Text(kindLine).font(theme.font(\.body, 12)).foregroundStyle(theme.secondary).lineLimit(1)
                }
                Spacer()
                if let played = item.lastPlayed {
                    Text(played, format: .relative(presentation: .named))
                        .font(theme.font(\.body, 12))
                        .foregroundStyle(theme.secondary)
                }
                PlayBadge(item: item, isShown: isHovering, diameter: 30)
            }
            .padding(6)
            .background(RoundedRectangle(cornerRadius: min(theme.style.cornerRadius, 8), style: .continuous)
                .fill(theme.foreground.opacity(isHovering ? 0.06 : 0)))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .foregroundStyle(theme.foreground)
        .onHover { hovering in withAnimation(.easeOut(duration: 0.15)) { isHovering = hovering } }
        .mediaMenu(item)
    }

    private var kindLine: String {
        switch item.kind {
        case .playlist: "Playlist · \(item.subtitle)"
        case .album: "Album · \(item.subtitle)"
        case .artist: "Artist"
        case .collection: "Playlist · \(item.detail ?? "Liked Songs")"
        case .track: item.subtitle
        }
    }
}

// MARK: Liked Songs

private struct LikedSection: View {
    @Environment(BrowseStore.self) private var browse
    @Environment(SpotifyAccount.self) private var account

    var body: some View {
        let collection = MediaItem.likedSongs(userID: account.userID ?? "me", count: browse.likedTotal)
        VStack(alignment: .leading, spacing: Metrics.unit * 3) {
            DetailHeader(item: collection, namespace: nil)
            SignInGate(status: browse.status(.liked), what: "Your liked songs") {
                SongList(songs: browse.liked, context: collection.uri, isLoading: browse.status(.liked) == .loading,
                         empty: "Songs you like in Spotify show up here.")
            }
        }
        .onAppear { browse.load(.liked) }
    }
}

// MARK: Artists

private struct ArtistsSection: View {
    let namespace: Namespace.ID

    @Environment(BrowseStore.self) private var browse

    var body: some View {
        VStack(alignment: .leading, spacing: Metrics.unit * 4) {
            Text("Artists").styledTitle(34)
            SignInGate(status: browse.status(.top), what: "Your top artists") {
                if !browse.topArtists.isEmpty {
                    // No shared cover animation here: a followed artist below may be the same one.
                    Shelf(title: "Top this month", items: browse.topArtists, tileWidth: 130)
                }
            }
            SignInGate(status: browse.status(.library), what: "Artists you follow") {
                VStack(alignment: .leading, spacing: Metrics.unit * 1.5) {
                    SectionTitle(title: "Following")
                    if browse.status(.library) == .loading && browse.followedArtists.isEmpty {
                        LoadingShelf(round: true)
                    } else if browse.followedArtists.isEmpty {
                        BrowseMessage(icon: "music.mic", title: "No followed artists yet",
                                      detail: "Follow artists in Spotify to keep them here.")
                    } else {
                        TileGrid(items: browse.followedArtists, minimum: 130, namespace: namespace)
                    }
                }
            }
        }
        .onAppear {
            browse.load(.library)
            browse.load(.top)
        }
    }
}

// MARK: Recent

private struct RecentPlaysSection: View {
    var body: some View {
        VStack(alignment: .leading, spacing: Metrics.unit * 3) {
            Text("Recently played").styledTitle(34)
            RecentSection(compact: false)
        }
    }
}

// MARK: Styles

private struct StylesSection: View {
    var body: some View {
        VStack(alignment: .leading, spacing: Metrics.unit * 3) {
            Text("Styles").styledTitle(34)
            StyleStrip()
        }
    }
}

// MARK: Song list

/// Numbered songs, or a shimmer while they load.
struct SongList: View {
    let songs: [MediaItem]
    var context: String?
    var isLoading = false
    var empty = "No songs"
    var showsCover = true

    @Environment(\.theme) private var theme

    var body: some View {
        if isLoading && songs.isEmpty {
            VStack(spacing: 8) {
                ForEach(0..<6, id: \.self) { _ in
                    RoundedRectangle(cornerRadius: 4).fill(theme.foreground.opacity(0.06)).frame(height: 44)
                }
            }
        } else if songs.isEmpty {
            Text(empty).font(theme.font(\.body, 14)).foregroundStyle(theme.secondary)
        } else {
            LazyVStack(spacing: 2) {
                ForEach(Array(songs.enumerated()), id: \.element.id) { index, song in
                    SongRow(item: song, index: index, context: context, showsCover: showsCover)
                        .staggered(index % 20)
                }
            }
        }
    }
}
