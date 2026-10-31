import SwiftUI

/// A greeting, what's playing, what played lately, and every style one click away.
/// All of it set in the current style, so switching styles here shows the change at once.
struct HomeView: View {
    @Binding var page: Page

    @Environment(SpotifyService.self) private var spotify
    @Environment(SpotifyAccount.self) private var account
    @Environment(\.theme) private var theme

    var body: some View {
        let style = theme.style
        ScrollView(.vertical, showsIndicators: false) {
            VStack(alignment: style.stackAlignment, spacing: Metrics.unit * 5) {
                Greeting()
                NowPlayingCard { withAnimation(style.motion) { page = .player } }
                    .frame(maxWidth: style.composition == .centered ? 620 : .infinity)
                HomeSection(title: "Recently played") {
                    RecentSection()
                }
                HomeSection(title: "Styles") {
                    StyleStrip()
                }
            }
            .padding(.horizontal, Metrics.margin)
            .padding(.vertical, Metrics.margin * 0.75)
            .frame(maxWidth: 1180)
            .frame(maxWidth: .infinity)
        }
        .task(id: spotify.track?.id) {
            // What's "recent" changes as songs finish.
            if account.isSignedIn { await account.loadRecent() }
        }
    }
}

private struct Greeting: View {
    @Environment(\.theme) private var theme

    var body: some View {
        let style = theme.style
        TimelineView(.everyMinute) { context in
            VStack(alignment: style.stackAlignment, spacing: Metrics.unit * 1.5) {
                Text(kicker(context.date))
                    .styledLabel()
                    .foregroundStyle(theme.accent)
                Text("\(greeting(context.date))\(Text(style.id == .y2k ? " ✦" : ".").foregroundStyle(theme.accent))")
                    .styledTitle(64)
                    .multilineTextAlignment(style.textAlignment)
                    .lineLimit(1)
                    .minimumScaleFactor(0.5)
                // Editorial's card brings its own double rule.
                if style.rule != .none && style.id != .editorial {
                    Rule().frame(maxWidth: style.composition == .centered ? 220 : .infinity)
                        .padding(.top, Metrics.unit)
                }
            }
            .frame(maxWidth: .infinity, alignment: style.frameAlignment)
        }
    }

    private func greeting(_ date: Date) -> String {
        let text = switch Calendar.current.component(.hour, from: date) {
        case 5..<12: "Good morning"
        case 12..<17: "Good afternoon"
        case 17..<22: "Good evening"
        default: "Good night"
        }
        return theme.style.labelCase == .lowercase ? text.lowercased() : text
    }

    private func kicker(_ date: Date) -> String {
        let day = date.formatted(.dateTime.weekday(.wide).day().month(.wide))
        switch theme.style.id {
        case .editorial:
            let issue = Calendar.current.ordinality(of: .day, in: .year, for: date) ?? 1
            return "Vol. \(Calendar.current.component(.year, from: date) - 2025) · No. \(issue) · \(day)"
        case .luxury:
            return "— \(day) —"
        case .y2k:
            return "> \(day)_"
        default:
            return day
        }
    }
}

private struct HomeSection<Content: View>: View {
    let title: String
    @ViewBuilder let content: Content

    @Environment(\.theme) private var theme

    var body: some View {
        VStack(alignment: theme.style.stackAlignment, spacing: Metrics.unit * 2) {
            Text(title).styledLabel()
            content
        }
        .frame(maxWidth: .infinity, alignment: theme.style.frameAlignment)
    }
}

// MARK: Now playing

private struct NowPlayingCard: View {
    let openPlayer: () -> Void

    @Environment(SpotifyService.self) private var spotify
    @Environment(ArtworkStore.self) private var artwork
    @Environment(\.theme) private var theme
    @State private var isHovering = false

    var body: some View {
        Group {
            if spotify.connection == .connected, let track = spotify.track {
                playing(track)
            } else {
                message
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .styledCard(padding: Metrics.unit * 2)
        .animation(theme.style.motion, value: spotify.track?.id)
    }

    private func playing(_ track: Track) -> some View {
        HStack(spacing: Metrics.unit * 2) {
            StyledArtwork(image: artwork.image, imageURL: artwork.imageURL)
                .frame(width: 92, height: 92)
                .clipShape(ThumbnailShape(art: theme.style.art))
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 8) {
                    EqualizerIcon()
                    Text(spotify.isPlaying ? "Now playing" : "Paused").styledLabel(10).foregroundStyle(theme.secondary)
                }
                Reveal(key: track.id) {
                    Text(track.name)
                        .styledTitle(24)
                        .lineLimit(1)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                Text(track.artist)
                    .font(theme.font(\.body, 14))
                    .foregroundStyle(theme.secondary)
                    .lineLimit(1)
                MiniProgress(duration: track.duration).padding(.top, 4)
            }
            .contentShape(Rectangle())
            .onTapGesture(perform: openPlayer)
            PlayPauseButton(diameter: 46)
            IconButton(systemName: "forward.end.fill", label: "Next track") { spotify.nextTrack() }
            IconButton(systemName: "arrow.up.right", label: "Open player", size: 15, action: openPlayer)
        }
    }

    private var message: some View {
        let (icon, text, action): (String, String, (String, () -> Void)?) = switch spotify.connection {
        case .connecting: ("ellipsis", "Looking for Spotify", nil)
        case .notInstalled: ("questionmark.app", "Spotify isn’t installed", nil)
        case .notRunning: ("powerplug", "Spotify isn’t running", ("Open Spotify", { spotify.openSpotify() }))
        case .permissionDenied: ("lock", "Allow access under Privacy & Security › Automation", ("Settings", { spotify.openAutomationSettings() }))
        case .connected: ("music.note", "Nothing playing", nil)
        }
        return HStack(spacing: Metrics.unit * 2) {
            Image(systemName: icon)
                .font(.system(size: 22, weight: .semibold))
                .foregroundStyle(theme.accent)
                .frame(width: 44)
            Text(text).font(theme.font(\.display, 20))
            Spacer(minLength: Metrics.unit)
            if let action {
                ActionButton(title: action.0, icon: "arrow.up.forward.app", action: action.1)
            }
        }
        .padding(.vertical, Metrics.unit)
    }
}

private struct MiniProgress: View {
    let duration: TimeInterval

    @Environment(SpotifyService.self) private var spotify
    @Environment(\.theme) private var theme

    var body: some View {
        TimelineView(.animation(minimumInterval: 1 / 10, paused: !spotify.isPlaying)) { context in
            let fraction = duration > 0 ? min(max(spotify.position(at: context.date) / duration, 0), 1) : 0
            GeometryReader { geometry in
                ZStack(alignment: .leading) {
                    Capsule().fill(theme.rule)
                    Capsule().fill(theme.accent).frame(width: geometry.size.width * fraction)
                }
            }
            .frame(height: 3)
        }
        .accessibilityHidden(true)
    }
}

// MARK: Recently played

private struct RecentSection: View {
    @Environment(SpotifyAccount.self) private var account
    @Environment(Router.self) private var router
    @Environment(\.theme) private var theme

    var body: some View {
        if !account.isSignedIn {
            HStack(spacing: Metrics.unit * 2) {
                Image(systemName: "person.crop.circle.badge.plus")
                    .font(.system(size: 26, weight: .regular))
                    .foregroundStyle(theme.accent)
                VStack(alignment: .leading, spacing: 4) {
                    Text("Connect your Spotify account").font(theme.font(\.display, 18))
                    Text("See what you played lately, like songs and add them to playlists.")
                        .font(theme.font(\.body, 13))
                        .foregroundStyle(theme.secondary)
                }
                Spacer(minLength: Metrics.unit)
                ActionButton(title: "Connect", icon: "link") { router.isAccountShown = true }
            }
            .styledCard()
            .frame(maxWidth: theme.style.composition == .centered ? 620 : .infinity)
        } else if account.recent.isEmpty {
            Label("Nothing played lately", systemImage: "clock")
                .font(theme.font(\.body, 14))
                .foregroundStyle(theme.secondary)
        } else {
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 128, maximum: 180), spacing: Metrics.unit * 2.5)], spacing: Metrics.unit * 3) {
                ForEach(account.recent) { track in
                    RecentTile(track: track)
                }
            }
        }
    }
}

private struct RecentTile: View {
    let track: RecentTrack

    @Environment(SpotifyService.self) private var spotify
    @Environment(\.theme) private var theme
    @State private var isHovering = false

    var body: some View {
        Button {
            spotify.play(uri: track.uri)
        } label: {
            VStack(alignment: .leading, spacing: 8) {
                // A square slot with the cover laid over it, so a wide or tall cover is cropped
                // rather than widening the tile.
                Color.clear
                    .aspectRatio(1, contentMode: .fit)
                    .overlay {
                        AsyncImage(url: track.imageURL, transaction: Transaction(animation: .smooth(duration: 0.4))) { phase in
                            if let image = phase.image {
                                image.resizable().aspectRatio(contentMode: .fill).transition(.opacity)
                            } else {
                                ArtworkPlaceholder()
                            }
                        }
                    }
                    .clipped()
                .clipShape(ThumbnailShape(art: theme.style.art))
                .overlay {
                    ControlFace(diameter: 40, isPlaying: false)
                        .scaleEffect(isHovering ? 1 : 0.6)
                        .opacity(isHovering ? 1 : 0)
                }
                .scaleEffect(isHovering ? 1.03 : 1)
                Text(track.name)
                    .font(theme.font(\.display, 14))
                    .lineLimit(1)
                Text(track.artist)
                    .font(theme.font(\.body, 12))
                    .foregroundStyle(theme.secondary)
                    .lineLimit(1)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(PressableStyle())
        .foregroundStyle(theme.foreground)
        .disabled(spotify.connection != .connected)
        .onHover { hovering in withAnimation(.spring(duration: 0.3, bounce: 0.3)) { isHovering = hovering } }
        .help("Play \(track.name)")
        .accessibilityLabel("Play \(track.name) by \(track.artist)")
    }
}

// MARK: Styles

/// One card per style, in its own type and colors. Click to switch the whole window.
private struct StyleStrip: View {
    @Environment(Appearance.self) private var appearance
    @Environment(ArtworkStore.self) private var artwork
    @Environment(\.theme) private var theme

    var body: some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 132, maximum: 200), spacing: Metrics.unit * 1.5)], spacing: Metrics.unit * 1.5) {
            ForEach(StyleID.allCases) { id in
                StyleCard(
                    preview: .resolve(id, appearance.color(for: id), palette: artwork.palette),
                    isSelected: appearance.styleID == id
                ) {
                    withAnimation(id.style.motion) { appearance.styleID = id }
                }
            }
        }
    }
}

private struct StyleCard: View {
    let preview: Theme
    let isSelected: Bool
    let action: () -> Void

    @Environment(\.theme) private var theme
    @State private var isHovering = false

    var body: some View {
        Button(action: action) {
            ZStack(alignment: .bottomLeading) {
                SwatchTile(theme: preview, label: nil)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Aa")
                        .font(preview.style.fonts.display.font(30))
                    Text(preview.style.name)
                        .font(preview.style.fonts.label.font(10))
                        .tracking(preview.style.labelTracking * 0.6)
                        .textCase(preview.style.labelCase)
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                }
                .foregroundStyle(preview.foreground)
                .padding(12)
                // Clear of the accent dot in the corner.
                .padding(.trailing, 22)
            }
            .frame(height: 96)
            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .strokeBorder(isSelected ? theme.accent : theme.rule, lineWidth: isSelected ? 2.5 : 1)
            )
            .scaleEffect(isHovering ? 1.04 : 1)
            .shadow(color: .black.opacity(isHovering ? 0.15 : 0), radius: 10, y: 6)
            .contentShape(Rectangle())
        }
        .buttonStyle(PressableStyle())
        .onHover { hovering in withAnimation(.spring(duration: 0.3, bounce: 0.35)) { isHovering = hovering } }
        .help(preview.style.summary)
        .accessibilityLabel(preview.style.name)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}
