import SwiftUI

/// The player page. The style decides the composition (cover beside a flush text column, or
/// everything on a centered axis); the user decides what shows (cover, lyrics, album, progress,
/// controls) and which side the cover sits on. Layouts morph into each other.
struct NowPlayingView: View {
    let track: Track

    @Environment(\.theme) private var theme
    @Environment(LyricsStore.self) private var lyrics
    @AppStorage(Pref.showLyrics) private var showLyrics = false
    @AppStorage(Pref.showArtwork) private var showArtwork = true
    @AppStorage(Pref.showProgress) private var showProgress = true
    @AppStorage(Pref.artworkTrailing) private var artworkTrailing = false
    @Namespace private var morph

    private var centered: Bool { theme.style.composition == .centered }

    /// Lyrics are on but there are none to show: the player keeps its cover layout and says why.
    private var lyricsNote: LyricsNote.Kind? {
        guard showLyrics else { return nil }
        if lyrics.state == .loaded(.notFound) { return .missing }
        if lyrics.isWaiting { return .loading }
        return nil
    }

    var body: some View {
        GeometryReader { geometry in
            Group {
                if showLyrics && lyricsNote == nil {
                    lyricsLayout(geometry.size)
                } else if centered {
                    centeredLayout(geometry.size)
                } else {
                    splitLayout(geometry.size)
                }
            }
            .frame(width: geometry.size.width, height: geometry.size.height, alignment: .topLeading)
        }
        .padding(Metrics.margin)
        .animation(theme.style.motion, value: showArtwork)
        .animation(theme.style.motion, value: showProgress)
        .animation(theme.style.motion, value: artworkTrailing)
        .animation(theme.style.motion, value: lyricsNote)
    }

    // MARK: Layouts

    /// Cover on one side, text column on the other, both the same height.
    private func splitLayout(_ size: CGSize) -> some View {
        let side = max(0, min(size.height, size.width * 0.46))
        let titleSize = showArtwork ? min(max(side * 0.12, 30), 60) : min(max(size.height * 0.13, 40), 92)
        // One row of controls needs about 440 pt; any narrower and it would push the column
        // (and the progress bar) past the window edge, so the controls take two rows instead.
        let column = showArtwork ? size.width - side - Metrics.gutter : size.width
        return HStack(alignment: .top, spacing: Metrics.gutter) {
            if showArtwork && !artworkTrailing { coverWithNote(side) }
            VStack(alignment: .leading, spacing: 0) {
                HStack(spacing: Metrics.unit * 1.5) {
                    EqualizerIcon()
                    if !showArtwork { note }
                    Spacer()
                    ShowInSpotifyButton()
                }
                Spacer(minLength: Metrics.unit * 2)
                title(size: titleSize, compact: false)
                Spacer(minLength: Metrics.unit * 2)
                progress
                TransportControls(layout: column < 440 ? .stacked : .wide, track: track)
                    .padding(.top, Metrics.unit * 2)
            }
            .frame(width: max(column, 0), height: showArtwork ? side : size.height)
            if showArtwork && artworkTrailing { coverWithNote(side) }
        }
        .frame(maxHeight: .infinity)
        .transition(.opacity)
    }

    /// One axis: cover, title, progress, controls, all centered. The cover takes whatever
    /// height the rest leaves.
    private func centeredLayout(_ size: CGSize) -> some View {
        let titleSize = showArtwork ? min(max(size.height * 0.055, 24), 40) : min(max(size.height * 0.11, 36), 80)
        return VStack(spacing: 0) {
            if showArtwork {
                // The note sits above the cover; the cover takes whatever height is left.
                // Spacing tightens while it shows, so the cover gives up as little as possible.
                note.padding(.bottom, Metrics.unit)
                InteractiveArtwork(caption: track.album)
                    .aspectRatio(1, contentMode: .fit)
                    .frame(maxWidth: min(size.width * 0.42, 440), maxHeight: .infinity)
                    .matchedGeometryEffect(id: "artwork", in: morph)
                    .transition(.scale(scale: 0.9).combined(with: .opacity))
                    .padding(.bottom, Metrics.unit * (lyricsNote == nil ? 3 : 2))
            } else {
                Spacer(minLength: 0)
                EqualizerIcon().padding(.bottom, Metrics.unit * 2)
                note.padding(.bottom, Metrics.unit * 2.5)
            }
            title(size: titleSize, compact: false)
                .frame(maxWidth: 640)
                .layoutPriority(1)
            VStack(spacing: Metrics.unit * 1.5) {
                progress
                TransportControls(layout: .centered, track: track)
            }
            .frame(maxWidth: 560)
            .padding(.top, Metrics.unit * 3)
            .layoutPriority(1)
            if !showArtwork { Spacer(minLength: 0) }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .overlay(alignment: .topTrailing) { ShowInSpotifyButton() }
        .transition(.opacity)
    }

    /// A narrow player column beside full-height lyrics.
    private func lyricsLayout(_ size: CGSize) -> some View {
        let column = min(size.width * 0.34, 360)
        // Leave room under the cover for title, progress and two rows of controls.
        let side = max(0, min(column, size.height - 230))
        return HStack(alignment: .top, spacing: Metrics.gutter * 1.5) {
            if artworkTrailing { LyricsPanel(track: track) }
            VStack(alignment: centered ? .center : .leading, spacing: 0) {
                if showArtwork { artwork(side) }
                HStack(alignment: .firstTextBaseline) {
                    title(size: showArtwork ? 22 : 34, compact: true)
                    if !centered { EqualizerIcon() }
                }
                .padding(.top, showArtwork ? Metrics.unit * 2.5 : 0)
                Spacer(minLength: Metrics.unit * 2)
                progress
                TransportControls(layout: .stacked, track: track)
                    .padding(.top, Metrics.unit * 1.5)
            }
            .frame(width: column)
            if !artworkTrailing { LyricsPanel(track: track) }
        }
        .transition(.opacity)
    }

    // MARK: Pieces

    private func artwork(_ side: CGFloat) -> some View {
        InteractiveArtwork(caption: track.album)
            .frame(width: side, height: side)
            .matchedGeometryEffect(id: "artwork", in: morph)
            .transition(.scale(scale: 0.9).combined(with: .opacity))
    }

    /// The cover in its side × side slot. With a lyrics note, the note sits on top and the
    /// cover shrinks a little to fit under it, giving the text column the width it frees.
    @ViewBuilder
    private func coverWithNote(_ side: CGFloat) -> some View {
        if lyricsNote == nil {
            artwork(side)
        } else {
            VStack(alignment: artworkTrailing ? .trailing : .leading, spacing: Metrics.unit) {
                note
                InteractiveArtwork(caption: track.album)
                    .aspectRatio(1, contentMode: .fit)
                    .matchedGeometryEffect(id: "artwork", in: morph)
            }
            .frame(width: side, height: side, alignment: Alignment(horizontal: artworkTrailing ? .trailing : .leading, vertical: .top))
            .transition(.scale(scale: 0.9).combined(with: .opacity))
        }
    }

    @ViewBuilder
    private var note: some View {
        if let lyricsNote {
            LyricsNote(kind: lyricsNote)
        }
    }

    private func title(size: CGFloat, compact: Bool) -> some View {
        TrackTitle(track: track, size: size, compact: compact)
            .matchedGeometryEffect(id: "title", in: morph, properties: .position)
    }

    @ViewBuilder
    private var progress: some View {
        if showProgress {
            ProgressBar(duration: track.duration)
                .matchedGeometryEffect(id: "progress", in: morph)
                .transition(.opacity)
        }
    }
}

/// Title, artist and album, set in the style's voice: Swiss grotesk, Didot with tracked
/// small caps, a magazine kicker and byline, lowercase Gill Sans, and so on.
private struct TrackTitle: View {
    let track: Track
    let size: CGFloat
    let compact: Bool

    @Environment(\.theme) private var theme
    @AppStorage(Pref.showAlbum) private var showAlbum = true

    var body: some View {
        let style = theme.style
        VStack(alignment: style.stackAlignment, spacing: compact ? 4 : Metrics.unit) {
            if !compact, let kicker {
                Reveal(key: track.id, order: 0) {
                    Text(kicker).styledLabel().foregroundStyle(theme.accent)
                }
            }
            Reveal(key: track.id, order: 0) {
                Text(track.name)
                    .styledTitle(size)
                    .multilineTextAlignment(style.textAlignment)
                    .lineLimit(compact ? 2 : 3)
                    .minimumScaleFactor(0.5)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Reveal(key: track.id, order: 1) {
                artist
                    .lineLimit(1)
            }
            if !compact && showAlbum {
                Rule()
                    .frame(maxWidth: style.composition == .centered ? 160 : .infinity)
                    .padding(.vertical, Metrics.unit * 1.5)
                Reveal(key: track.id, order: 2) {
                    album
                }
                .transition(.opacity)
            }
        }
    }

    /// A small line above the title, for the styles that print one.
    private var kicker: String? {
        switch theme.style.id {
        case .editorial: "Now playing"
        case .luxury: "Now playing"
        case .y2k: "★ now playing ★"
        default: nil
        }
    }

    @ViewBuilder
    private var artist: some View {
        let style = theme.style
        let artistSize = compact ? 15 : 22
        switch style.id {
        case .luxury:
            Text(track.artist).styledLabel(compact ? 11 : 14)
        case .editorial:
            Text("By \(Text(track.artist).font(theme.font(\.display, CGFloat(artistSize) * 0.9)))")
                .font(theme.font(\.emphasis, CGFloat(artistSize) * 0.9))
                .foregroundStyle(compact ? theme.secondary : theme.foreground)
        case .wabiSabi, .ethereal:
            Text(track.artist.lowercased())
                .font(theme.font(\.body, CGFloat(artistSize)))
                .foregroundStyle(theme.secondary)
        default:
            Text(track.artist)
                .font(theme.font(\.body, CGFloat(artistSize)))
                .foregroundStyle(compact ? theme.secondary : theme.foreground)
        }
    }

    @ViewBuilder
    private var album: some View {
        let style = theme.style
        switch style.id {
        case .luxury, .editorial, .wabiSabi:
            Text(track.album)
                .font(theme.font(\.emphasis, 16))
                .foregroundStyle(theme.secondary)
                .lineLimit(1)
        default:
            HStack(spacing: Metrics.unit) {
                Image(systemName: "opticaldisc")
                    .font(.system(size: 13, weight: style.iconWeight))
                    .foregroundStyle(theme.secondary)
                Text(track.album)
                    .font(theme.font(\.emphasis, 15))
                    .lineLimit(1)
            }
            .help("Album")
        }
    }
}

/// A small chip saying why the lyrics aren't showing.
struct LyricsNote: View {
    enum Kind: Equatable {
        /// Still trying; retries run in the background for up to a minute.
        case loading
        /// LRCLIB has none for this track, or a minute passed without any.
        case missing
    }

    let kind: Kind

    @Environment(\.theme) private var theme

    var body: some View {
        HStack(spacing: 7) {
            Image(systemName: kind == .loading ? "ellipsis.message" : "quote.bubble")
                .font(.system(size: 12, weight: theme.style.iconWeight))
                .symbolEffect(.variableColor.iterative, options: .repeating, isActive: kind == .loading)
            Text(kind == .loading ? "Loading lyrics automatically…" : "No lyrics provided for this song")
                .styledLabel(10)
                .lineLimit(1)
        }
        .foregroundStyle(theme.accent)
        .padding(.horizontal, 4)
        .styledCard(padding: 6)
        // In a narrow window the text truncates before it pushes anything else around.
        .layoutPriority(1)
        .id(kind)
        .transition(.opacity.combined(with: .scale(scale: 0.92)))
        .accessibilityElement(children: .combine)
    }
}

/// The cover doubles as a play/pause button: hover to reveal it, click to toggle.
private struct InteractiveArtwork: View {
    let caption: String

    @Environment(SpotifyService.self) private var spotify
    @Environment(ArtworkStore.self) private var artwork
    @State private var isHovering = false

    var body: some View {
        StyledArtwork(image: artwork.image, imageURL: artwork.imageURL, caption: caption)
            .overlay {
                ControlFace(diameter: 72, isPlaying: spotify.isPlaying)
                    .scaleEffect(isHovering ? 1 : 0.6)
                    .opacity(isHovering ? 1 : 0)
            }
            .scaleEffect(isHovering ? 1.015 : 1)
            .contentShape(Rectangle())
            .onHover { hovering in
                withAnimation(.spring(duration: 0.35, bounce: 0.3)) { isHovering = hovering }
            }
            .onTapGesture { spotify.playPause() }
            .accessibilityElement()
            .accessibilityLabel(spotify.isPlaying ? "Pause" : "Play")
            .accessibilityAddTraits(.isButton)
    }
}

/// Four bars that dance while playing and settle when paused.
struct EqualizerIcon: View {
    @Environment(SpotifyService.self) private var spotify
    @Environment(\.theme) private var theme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @AppStorage(Pref.showEqualizer) private var showEqualizer = true

    private static let speeds = [5.1, 7.3, 4.2, 6.4]
    private static let phases = [0.0, 1.3, 2.1, 0.7]

    var body: some View {
        if showEqualizer {
            let animating = spotify.isPlaying && !reduceMotion
            TimelineView(.animation(minimumInterval: 1 / 30, paused: !animating)) { context in
                let time = context.date.timeIntervalSinceReferenceDate
                HStack(alignment: .bottom, spacing: 2) {
                    ForEach(0..<4) { bar in
                        let level = animating ? 0.25 + 0.75 * abs(sin(time * Self.speeds[bar] + Self.phases[bar])) : 0.25
                        RoundedRectangle(cornerRadius: theme.style.cornerRadius > 0 ? 1.5 : 0)
                            .fill(spotify.isPlaying ? theme.accent : theme.secondary)
                            .frame(width: 3, height: 14 * level)
                    }
                }
                .frame(height: 14, alignment: .bottom)
            }
            .animation(.smooth(duration: 0.3), value: spotify.isPlaying)
            .help(spotify.isPlaying ? "Playing" : "Paused")
            .accessibilityLabel(spotify.isPlaying ? "Playing" : "Paused")
        }
    }
}

private struct ShowInSpotifyButton: View {
    @Environment(SpotifyService.self) private var spotify

    var body: some View {
        IconButton(systemName: "arrow.up.forward.app", label: "Show in Spotify", size: 15) {
            spotify.showSpotify()
        }
    }
}
