import AppKit
import SwiftUI

/// Where Home is: a category, a page opened from it (album, playlist, artist, Liked Songs),
/// and the search field's focus requests.
@MainActor
@Observable
final class BrowseNavigation {
    var category: BrowseCategory {
        didSet { UserDefaults.standard.set(category.rawValue, forKey: Pref.browseCategory) }
    }
    /// Pages opened on top of the category (or of search results), last one showing.
    var path: [MediaItem] = []
    /// Bumped by ⌘F; the search field focuses when it changes.
    var focusSearch = 0
    /// Bumped when a category is picked; the search field lets go of focus. Buttons don't
    /// take focus on macOS, so without this an empty, focused field keeps search showing.
    var leaveSearch = 0

    init() {
        category = UserDefaults.standard.string(forKey: Pref.browseCategory).flatMap(BrowseCategory.init) ?? .forYou
    }

    func open(_ item: MediaItem) {
        path.append(item)
    }

    func back() {
        _ = path.popLast()
    }
}

enum BrowseCategory: String, CaseIterable, Identifiable {
    case forYou, library, liked, artists, recent, styles

    var id: Self { self }

    var title: String {
        switch self {
        case .forYou: "For You"
        case .library: "Library"
        case .liked: "Liked Songs"
        case .artists: "Artists"
        case .recent: "Recent"
        case .styles: "Styles"
        }
    }

    var icon: String {
        switch self {
        case .forYou: "sparkles"
        case .library: "books.vertical"
        case .liked: "heart"
        case .artists: "music.mic"
        case .recent: "clock"
        case .styles: "paintpalette"
        }
    }
}

// MARK: Covers

/// A cover in the style's shape (artists are always round), with a placeholder while it loads.
struct CoverImage: View {
    let item: MediaItem
    var cornerScale: CGFloat = 1

    @Environment(\.theme) private var theme

    var body: some View {
        Color.clear
            .aspectRatio(1, contentMode: .fit)
            .overlay {
                if item.kind == .collection {
                    LikedSongsArt()
                } else {
                    AsyncImage(url: item.imageURL, transaction: Transaction(animation: .smooth(duration: 0.35))) { phase in
                        if let image = phase.image {
                            image.resizable().aspectRatio(contentMode: .fill).transition(.opacity)
                        } else {
                            ZStack {
                                theme.foreground.opacity(0.08)
                                Image(systemName: Self.symbol(item.kind))
                                    .font(.system(size: 20, weight: theme.style.iconWeight))
                                    .foregroundStyle(theme.secondary)
                            }
                        }
                    }
                }
            }
            .clipShape(shape)
    }

    private var shape: AnyShape {
        item.kind == .artist ? AnyShape(Circle()) : AnyShape(ThumbnailShape(art: theme.style.art))
    }

    static func symbol(_ kind: MediaItem.Kind) -> String {
        switch kind {
        case .track: "music.note"
        case .album: "square.stack"
        case .playlist: "music.note.list"
        case .artist: "music.mic"
        case .collection: "heart.fill"
        }
    }
}

/// Liked Songs has no image in the API: a gradient in the theme's accent with a heart.
struct LikedSongsArt: View {
    @Environment(\.theme) private var theme

    var body: some View {
        GeometryReader { geometry in
            ZStack {
                LinearGradient(colors: [theme.accent, theme.accent.opacity(0.45)], startPoint: .topLeading, endPoint: .bottomTrailing)
                Image(systemName: "heart.fill")
                    .font(.system(size: geometry.size.width * 0.32, weight: .bold))
                    .foregroundStyle(.white)
                    .shadow(color: .black.opacity(0.2), radius: 6, y: 3)
            }
        }
    }
}

// MARK: Tiles and rows

/// A cover with name and subtitle. Click opens it (songs play); hover shows a play button
/// that plays it straight away.
struct MediaTile: View {
    let item: MediaItem
    var namespace: Namespace.ID?

    @Environment(SpotifyService.self) private var spotify
    @Environment(BrowseNavigation.self) private var navigation
    @Environment(\.theme) private var theme
    @State private var isHovering = false

    var body: some View {
        Button {
            if item.kind == .track { spotify.play(uri: item.uri, in: item.albumURI) } else { navigation.open(item) }
        } label: {
            VStack(alignment: item.kind == .artist ? .center : .leading, spacing: 7) {
                cover
                    .overlay(alignment: .bottomTrailing) {
                        PlayBadge(item: item, isShown: isHovering).padding(8)
                    }
                    .scaleEffect(isHovering ? 1.035 : 1)
                    .shadow(color: .black.opacity(isHovering ? 0.18 : 0), radius: 12, y: 8)
                Text(item.name)
                    .font(theme.font(\.display, 14))
                    .lineLimit(1)
                Text(caption)
                    .font(theme.font(\.body, 12))
                    .foregroundStyle(theme.secondary)
                    .lineLimit(1)
            }
            .frame(maxWidth: .infinity, alignment: item.kind == .artist ? .center : .leading)
            .contentShape(Rectangle())
        }
        .buttonStyle(PressableStyle())
        .foregroundStyle(theme.foreground)
        .onHover { hovering in withAnimation(.spring(duration: 0.3, bounce: 0.3)) { isHovering = hovering } }
        .mediaMenu(item)
        .help(item.name)
        .accessibilityLabel("\(item.name), \(item.subtitle)")
    }

    @ViewBuilder
    private var cover: some View {
        if let namespace {
            CoverImage(item: item).matchedGeometryEffect(id: "cover-\(item.uri)", in: namespace)
        } else {
            CoverImage(item: item)
        }
    }

    private var caption: String {
        switch item.kind {
        case .album: [item.detail, item.subtitle].compactMap { $0 }.filter { !$0.isEmpty }.joined(separator: " · ")
        case .playlist: "By \(item.subtitle)"
        case .collection: item.detail ?? "Playlist"
        default: item.subtitle
        }
    }
}

/// The round play button that springs up over a cover on hover.
struct PlayBadge: View {
    let item: MediaItem
    let isShown: Bool
    var diameter: CGFloat = 38

    @Environment(SpotifyService.self) private var spotify

    var body: some View {
        Button {
            spotify.play(uri: item.uri, in: item.kind == .track ? item.albumURI : nil)
        } label: {
            ControlFace(diameter: diameter, isPlaying: false)
                .shadow(color: .black.opacity(0.25), radius: 8, y: 4)
        }
        .buttonStyle(PressableStyle())
        .scaleEffect(isShown ? 1 : 0.5)
        .offset(y: isShown ? 0 : 10)
        .opacity(isShown ? 1 : 0)
        .allowsHitTesting(isShown)
        .disabled(spotify.connection != .connected)
        .help("Play \(item.name)")
    }
}

/// A song in a list: number (a play icon on hover), cover, title and artist, album, length.
/// Click plays it, in `context` when there is one.
struct SongRow: View {
    let item: MediaItem
    var index: Int?
    var context: String?
    var showsCover = true
    var showsAlbum = true
    var isSelected = false

    @Environment(SpotifyService.self) private var spotify
    @Environment(\.theme) private var theme
    @State private var isHovering = false

    private var isCurrent: Bool { spotify.track?.id == item.uri }

    var body: some View {
        Button {
            spotify.play(uri: item.uri, in: context ?? item.albumURI)
        } label: {
            HStack(spacing: Metrics.unit * 1.5) {
                if let index {
                    ZStack {
                        Text("\(index + 1)")
                            .font(theme.font(\.body, 13).monospacedDigit())
                            .foregroundStyle(isCurrent ? theme.accent : theme.secondary)
                            .opacity(isHovering ? 0 : 1)
                        Image(systemName: "play.fill")
                            .font(.system(size: 11))
                            .opacity(isHovering ? 1 : 0)
                            .scaleEffect(isHovering ? 1 : 0.4)
                    }
                    .frame(width: 26)
                }
                if showsCover {
                    CoverImage(item: item).frame(width: 40, height: 40)
                }
                VStack(alignment: .leading, spacing: 2) {
                    Text(item.name)
                        .font(theme.font(\.display, 14))
                        .foregroundStyle(isCurrent ? theme.accent : theme.foreground)
                        .lineLimit(1)
                    Text(item.subtitle)
                        .font(theme.font(\.body, 12))
                        .foregroundStyle(theme.secondary)
                        .lineLimit(1)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                if showsAlbum, let album = item.albumName {
                    Text(album)
                        .font(theme.font(\.body, 12))
                        .foregroundStyle(theme.secondary)
                        .lineLimit(1)
                        .frame(maxWidth: 220, alignment: .leading)
                }
                if isCurrent {
                    EqualizerIcon()
                }
                Text(Self.time(item.duration))
                    .font(theme.font(\.body, 12).monospacedDigit())
                    .foregroundStyle(theme.secondary)
                    .frame(width: 44, alignment: .trailing)
            }
            .padding(.horizontal, Metrics.unit)
            .padding(.vertical, 6)
            .background(
                RoundedRectangle(cornerRadius: min(theme.style.cornerRadius, 8), style: .continuous)
                    .fill(theme.foreground.opacity(isSelected ? 0.11 : isHovering ? 0.06 : 0))
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .foregroundStyle(theme.foreground)
        .onHover { hovering in withAnimation(.easeOut(duration: 0.14)) { isHovering = hovering } }
        .mediaMenu(item, context: context)
        .help("Play \(item.name)")
        .accessibilityLabel("Play \(item.name) by \(item.subtitle)")
    }

    static func time(_ seconds: TimeInterval?) -> String {
        guard let seconds, seconds > 0 else { return "" }
        let total = Int(seconds.rounded())
        return String(format: "%d:%02d", total / 60, total % 60)
    }
}

// MARK: Sections

/// A titled horizontal row of tiles that scrolls sideways, with an optional "Show all".
struct Shelf: View {
    let title: String
    let items: [MediaItem]
    var tileWidth: CGFloat = 150
    var showAll: (() -> Void)?
    var namespace: Namespace.ID?

    @Environment(\.theme) private var theme

    var body: some View {
        VStack(alignment: .leading, spacing: Metrics.unit * 1.5) {
            SectionTitle(title: title, action: showAll)
            ScrollView(.horizontal, showsIndicators: false) {
                LazyHStack(alignment: .top, spacing: Metrics.unit * 2) {
                    ForEach(Array(items.enumerated()), id: \.element.id) { index, item in
                        MediaTile(item: item, namespace: namespace)
                            .frame(width: tileWidth)
                            .staggered(index)
                    }
                }
                .padding(.vertical, Metrics.unit)
                .padding(.horizontal, 4)
            }
            .scrollClipDisabled()
        }
    }
}

/// A grid of tiles that reflows with the window.
struct TileGrid: View {
    let items: [MediaItem]
    var minimum: CGFloat = 140
    var namespace: Namespace.ID?

    var body: some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: minimum, maximum: minimum * 1.45), spacing: Metrics.unit * 2.5, alignment: .top)],
                  alignment: .leading, spacing: Metrics.unit * 3) {
            ForEach(Array(items.enumerated()), id: \.element.id) { index, item in
                MediaTile(item: item, namespace: namespace)
                    .staggered(index)
            }
        }
    }
}

struct SectionTitle: View {
    let title: String
    var action: (() -> Void)?

    @Environment(\.theme) private var theme

    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            Text(title).styledTitle(22)
            Spacer()
            if let action {
                Button("Show all", action: action)
                    .buttonStyle(.plain)
                    .font(theme.font(\.label, 11))
                    .textCase(theme.style.labelCase)
                    .tracking(theme.style.labelTracking * 0.5)
                    .foregroundStyle(theme.secondary)
            }
        }
    }
}

/// An icon, a line of text and an optional button, for empty and error states.
struct BrowseMessage: View {
    let icon: String
    let title: String
    var detail: String?
    var action: (title: String, icon: String, run: () -> Void)?

    @Environment(\.theme) private var theme

    var body: some View {
        HStack(spacing: Metrics.unit * 2) {
            Image(systemName: icon)
                .font(.system(size: 24, weight: theme.style.iconWeight))
                .foregroundStyle(theme.accent)
                .frame(width: 40)
            VStack(alignment: .leading, spacing: 4) {
                Text(title).font(theme.font(\.display, 17))
                if let detail {
                    Text(detail).font(theme.font(\.body, 13)).foregroundStyle(theme.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            Spacer(minLength: Metrics.unit)
            if let action {
                ActionButton(title: action.title, icon: action.icon, action: action.run)
            }
        }
        .styledCard()
    }
}

/// A row of shimmering placeholder tiles while a section loads.
struct LoadingShelf: View {
    var count = 6
    var round = false

    @Environment(\.theme) private var theme

    var body: some View {
        TimelineView(.animation(minimumInterval: 1 / 30)) { context in
            let phase = context.date.timeIntervalSinceReferenceDate.truncatingRemainder(dividingBy: 1.4) / 1.4
            HStack(spacing: Metrics.unit * 2) {
                ForEach(0..<count, id: \.self) { index in
                    VStack(alignment: .leading, spacing: 8) {
                        Group {
                            if round { Circle() } else { ThumbnailShape(art: theme.style.art) }
                        }
                        .aspectRatio(1, contentMode: .fit)
                        RoundedRectangle(cornerRadius: 3).frame(height: 10).padding(.trailing, 30)
                        RoundedRectangle(cornerRadius: 3).frame(height: 8).padding(.trailing, 60)
                    }
                    .frame(width: 140)
                    .foregroundStyle(theme.foreground.opacity(0.06 + 0.05 * sin((phase - Double(index) * 0.1) * .pi * 2).magnitude))
                }
            }
        }
        .accessibilityLabel("Loading")
    }
}

extension View {
    /// Rises into place, sharpening from a blur, a beat after the item before it.
    func staggered(_ index: Int) -> some View {
        modifier(Staggered(index: index))
    }
}

private struct Staggered: ViewModifier {
    let index: Int

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var shown = false

    func body(content: Content) -> some View {
        content
            .opacity(shown ? 1 : 0)
            .offset(y: shown || reduceMotion ? 0 : 14)
            .blur(radius: shown || reduceMotion ? 0 : 6)
            .onAppear {
                withAnimation(.spring(duration: 0.55, bounce: 0.25).delay(Double(min(index, 14)) * 0.035)) { shown = true }
            }
    }
}

// MARK: Context menu

extension View {
    /// Right-click: play, open, like, add to a playlist, open in Spotify, copy link.
    func mediaMenu(_ item: MediaItem, context: String? = nil) -> some View {
        modifier(MediaMenu(item: item, context: context))
    }
}

private struct MediaMenu: ViewModifier {
    let item: MediaItem
    let context: String?

    @Environment(SpotifyService.self) private var spotify
    @Environment(SpotifyAccount.self) private var account
    @Environment(BrowseNavigation.self) private var navigation

    func body(content: Content) -> some View {
        content.contextMenu {
            Button("Play", systemImage: "play.fill") {
                spotify.play(uri: item.uri, in: item.kind == .track ? (context ?? item.albumURI) : nil)
            }
            if item.kind != .track {
                Button("Open", systemImage: "arrow.right.circle") { navigation.open(item) }
            } else if let album = item.albumURI, let name = item.albumName {
                Button("Go to Album", systemImage: "square.stack") {
                    navigation.open(MediaItem(uri: album, kind: .album, name: name, subtitle: item.subtitle, imageURL: item.imageURL))
                }
            }
            if item.kind == .track, account.isSignedIn {
                Divider()
                let saved = account.saved[item.uri] == true
                Button(saved ? "Remove from Liked Songs" : "Add to Liked Songs", systemImage: saved ? "heart.slash" : "heart") {
                    account.toggleSaved(item.uri)
                }
                if !account.playlists.isEmpty {
                    Menu("Add to Playlist") {
                        ForEach(account.playlists) { playlist in
                            Button(playlist.name) { account.add(item.uri, to: playlist) }
                        }
                    }
                }
            }
            Divider()
            if let url = URL(string: item.uri), item.kind != .collection {
                Button("Open in Spotify", systemImage: "arrow.up.forward.app") { NSWorkspace.shared.open(url) }
            }
            if let link = item.webLink {
                Button("Copy Link", systemImage: "link") {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(link.absoluteString, forType: .string)
                }
            }
        }
    }
}

extension MediaItem {
    /// open.spotify.com link, for sharing.
    var webLink: URL? {
        guard kind != .collection else { return nil }
        return URL(string: "https://open.spotify.com/\(kind.rawValue)/\(spotifyID)")
    }
}
