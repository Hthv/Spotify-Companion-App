import SwiftUI

struct TransportControls: View {
    enum Layout {
        /// One row: modes and transport left, library, lyrics and volume right.
        case wide
        /// Transport on one row, the rest under it, for the narrow lyrics column.
        case stacked
        /// Two centered rows, for centered styles.
        case centered
    }

    let layout: Layout
    let track: Track

    @Environment(SpotifyService.self) private var spotify
    @Environment(\.theme) private var theme
    @AppStorage(Pref.showLyrics) private var showLyrics = false
    @AppStorage(Pref.showModes) private var showModes = true
    @AppStorage(Pref.showVolume) private var showVolume = true
    @AppStorage(Pref.showLibrary) private var showLibrary = true

    var body: some View {
        switch layout {
        case .wide:
            HStack(spacing: Metrics.unit) {
                if showModes { shuffle }
                previous
                PlayPauseButton()
                next
                if showModes { repeatToggle }
                Spacer(minLength: Metrics.unit)
                secondary
            }
        case .centered:
            // Library on the left, transport in the middle, lyrics and volume on the right.
            HStack(spacing: Metrics.unit) {
                if showLibrary {
                    LikeButton(uri: track.id)
                    PlaylistButton(uri: track.id)
                }
                Spacer(minLength: Metrics.unit)
                HStack(spacing: Metrics.unit * 1.5) {
                    if showModes { shuffle }
                    previous
                    PlayPauseButton()
                    next
                    if showModes { repeatToggle }
                }
                .fixedSize()
                Spacer(minLength: Metrics.unit)
                lyricsToggle
                if showVolume { VolumeControl() }
            }
        case .stacked:
            VStack(spacing: Metrics.unit * 1.5) {
                HStack(spacing: 0) {
                    if showModes { shuffle }
                    Spacer(minLength: 0)
                    previous
                    PlayPauseButton().padding(.horizontal, Metrics.unit)
                    next
                    Spacer(minLength: 0)
                    if showModes { repeatToggle }
                }
                HStack(spacing: Metrics.unit) {
                    secondary
                }
            }
        }
    }

    @ViewBuilder
    private var secondary: some View {
        if showLibrary {
            LikeButton(uri: track.id)
            PlaylistButton(uri: track.id)
        }
        lyricsToggle
        if showVolume {
            // In the narrow column volume sits at the far end; in the wide row it stays with the rest.
            if layout == .stacked { Spacer(minLength: 0) }
            VolumeControl()
        }
    }

    private var shuffle: some View {
        ToggleIcon(systemName: "shuffle", label: "Shuffle", isOn: spotify.isShuffling) { spotify.toggleShuffle() }
    }

    private var repeatToggle: some View {
        ToggleIcon(systemName: "repeat", label: "Repeat", isOn: spotify.isRepeating) { spotify.toggleRepeat() }
    }

    private var previous: some View {
        IconButton(systemName: "backward.end.fill", label: "Previous track") { spotify.previousTrack() }
    }

    private var next: some View {
        IconButton(systemName: "forward.end.fill", label: "Next track") { spotify.nextTrack() }
    }

    private var lyricsToggle: some View {
        ToggleIcon(
            systemName: showLyrics ? "quote.bubble.fill" : "quote.bubble",
            label: showLyrics ? "Hide lyrics (⌘L)" : "Show lyrics (⌘L)",
            isOn: showLyrics
        ) {
            withAnimation(theme.style.motion) { showLyrics.toggle() }
        }
    }
}

struct PlayPauseButton: View {
    var diameter: CGFloat = 54

    @Environment(SpotifyService.self) private var spotify

    var body: some View {
        Button {
            spotify.playPause()
        } label: {
            ControlFace(diameter: diameter, isPlaying: spotify.isPlaying)
        }
        .buttonStyle(PressableStyle())
        .animation(.smooth(duration: 0.3), value: spotify.isPlaying)
        .help(spotify.isPlaying ? "Pause (Space)" : "Play (Space)")
        .accessibilityLabel(spotify.isPlaying ? "Pause" : "Play")
    }
}

/// The play/pause button's body in the style's shape: a solid disc, a thin ring, twin gold
/// rings, frosted glass, a river pebble, a glossy candy pill, or a square block.
struct ControlFace: View {
    let diameter: CGFloat
    let isPlaying: Bool

    @Environment(\.theme) private var theme

    var body: some View {
        let style = theme.style
        ZStack {
            switch style.control {
            case .solidCircle:
                Circle().fill(theme.foreground)
                glyph(theme.background)
            case .outlineCircle:
                Circle().strokeBorder(theme.foreground.opacity(0.85), lineWidth: 1)
                glyph(theme.foreground, outline: true)
            case .doubleRing:
                Circle().strokeBorder(theme.accent, lineWidth: 0.75)
                Circle().strokeBorder(theme.accent.opacity(0.45), lineWidth: 0.5).padding(diameter * 0.08)
                glyph(theme.accent, outline: true)
            case .glass:
                Circle().fill(.ultraThinMaterial)
                Circle().fill(theme.accent.opacity(0.18))
                Circle().strokeBorder(.white.opacity(0.6), lineWidth: 0.75)
                glyph(theme.foreground)
            case .pebble:
                StyledArtwork.organicShape(diameter).fill(theme.foreground)
                    .rotationEffect(.degrees(-8))
                glyph(theme.background)
            case .glossyPill:
                let pill = RoundedRectangle(cornerRadius: diameter / 2, style: .continuous)
                pill.fill(theme.accent)
                pill.fill(LinearGradient(colors: [.clear, .black.opacity(0.25)], startPoint: .top, endPoint: .bottom))
                RoundedRectangle(cornerRadius: diameter * 0.25, style: .continuous)
                    .fill(LinearGradient(colors: [.white.opacity(0.75), .white.opacity(0)], startPoint: .top, endPoint: .bottom))
                    .padding(.horizontal, diameter * 0.18)
                    .padding(.top, 3)
                    .padding(.bottom, diameter * 0.5)
                pill.strokeBorder(.white.opacity(0.8), lineWidth: 1.5)
                glyph(.white).shadow(color: .black.opacity(0.25), radius: 0, y: 1)
            case .square:
                Rectangle().fill(theme.foreground)
                glyph(theme.background)
            }
        }
        .frame(width: style.control == .glossyPill ? diameter * 1.45 : diameter, height: diameter)
        .shadow(color: style.control == .glass ? theme.accent.opacity(0.35) : .clear, radius: 16)
        .contentShape(Rectangle())
    }

    private func glyph(_ color: Color, outline: Bool = false) -> some View {
        Image(systemName: isPlaying ? (outline ? "pause" : "pause.fill") : (outline ? "play" : "play.fill"))
            .font(.system(size: diameter * 0.37, weight: outline ? .light : .bold))
            .foregroundStyle(color)
            .contentTransition(.symbolEffect(.replace))
            // The play triangle's visual center sits left of its bounds.
            .offset(x: isPlaying ? 0 : diameter * 0.04)
    }
}

struct IconButton: View {
    let systemName: String
    let label: String
    var size: CGFloat = 17
    let action: () -> Void

    @Environment(\.theme) private var theme
    @State private var isHovering = false

    var body: some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: size, weight: theme.style.iconWeight))
                .frame(width: 36, height: 36)
                .contentShape(Rectangle())
        }
        .buttonStyle(PressableStyle())
        .opacity(isHovering ? 1 : 0.72)
        .scaleEffect(isHovering ? 1.08 : 1)
        .onHover { hovering in
            withAnimation(.spring(duration: 0.25, bounce: 0.4)) { isHovering = hovering }
        }
        .help(label)
        .accessibilityLabel(label)
    }
}

/// An icon that turns accent-colored, with a dot beneath, when on.
struct ToggleIcon: View {
    let systemName: String
    let label: String
    let isOn: Bool
    let action: () -> Void

    @Environment(\.theme) private var theme
    @State private var isHovering = false

    var body: some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: 15, weight: theme.style.iconWeight == .ultraLight ? .light : theme.style.iconWeight))
                .contentTransition(.symbolEffect(.replace))
                .foregroundStyle(isOn ? theme.accent : theme.foreground)
                .frame(width: 32, height: 32)
                .overlay(alignment: .bottom) {
                    Circle()
                        .fill(theme.accent)
                        .frame(width: 4, height: 4)
                        .scaleEffect(isOn ? 1 : 0)
                        .offset(y: 2)
                }
                .contentShape(Rectangle())
        }
        .buttonStyle(PressableStyle())
        .opacity(isOn || isHovering ? 1 : 0.58)
        .scaleEffect(isHovering ? 1.08 : 1)
        .onHover { hovering in
            withAnimation(.spring(duration: 0.25, bounce: 0.4)) { isHovering = hovering }
        }
        .animation(.spring(duration: 0.35, bounce: 0.4), value: isOn)
        .help(label)
        .accessibilityLabel(label)
        .accessibilityAddTraits(isOn ? .isSelected : [])
    }
}

/// Speaker icon (click to mute); hover it and a slider slides out. Drags are throttled so
/// Spotify gets a steady trickle of updates rather than one per pixel.
private struct VolumeControl: View {
    @Environment(SpotifyService.self) private var spotify
    @State private var lastSent = Date.distantPast
    @State private var isExpanded = false

    private var symbol: String {
        switch spotify.volume {
        case 0: "speaker.slash.fill"
        case ..<34: "speaker.wave.1.fill"
        case ..<67: "speaker.wave.2.fill"
        default: "speaker.wave.3.fill"
        }
    }

    var body: some View {
        HStack(spacing: 4) {
            IconButton(systemName: symbol, label: spotify.volume == 0 ? "Unmute" : "Mute", size: 14) {
                spotify.toggleMute()
            }
            .contentTransition(.symbolEffect(.replace))
            .animation(.smooth(duration: 0.25), value: symbol)
            LineSlider(value: Double(spotify.volume) / 100) { value in
                let now = Date()
                guard now.timeIntervalSince(lastSent) > 0.08 else { return }
                lastSent = now
                spotify.setVolume(Int((value * 100).rounded()))
            } onCommit: { value in
                spotify.setVolume(Int((value * 100).rounded()))
            }
            .frame(width: isExpanded ? 84 : 0)
            .opacity(isExpanded ? 1 : 0)
            .accessibilityElement()
            .accessibilityLabel("Volume")
            .accessibilityValue("\(spotify.volume) percent")
            .accessibilityAdjustableAction { direction in
                switch direction {
                case .increment: spotify.changeVolume(by: 10)
                case .decrement: spotify.changeVolume(by: -10)
                @unknown default: break
                }
            }
        }
        .contentShape(Rectangle())
        .onHover { hovering in
            withAnimation(.spring(duration: 0.4, bounce: 0.2)) { isExpanded = hovering }
        }
    }
}

/// A line that thickens under the pointer; drag or click to set.
struct LineSlider: View {
    /// 0...1.
    let value: Double
    let onChange: (Double) -> Void
    let onCommit: (Double) -> Void

    @Environment(\.theme) private var theme
    @State private var dragValue: Double?
    @State private var isHovering = false

    var body: some View {
        GeometryReader { geometry in
            let width = max(geometry.size.width, 1)
            let shown = dragValue ?? value
            ZStack(alignment: .leading) {
                Capsule().fill(theme.rule)
                Capsule()
                    .fill(theme.foreground)
                    .frame(width: width * min(max(shown, 0), 1))
            }
            .frame(height: isHovering || dragValue != nil ? 5 : 2)
            .frame(maxHeight: .infinity)
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { drag in
                        let new = min(max(drag.location.x / width, 0), 1)
                        dragValue = new
                        onChange(new)
                    }
                    .onEnded { drag in
                        onCommit(min(max(drag.location.x / width, 0), 1))
                        dragValue = nil
                    }
            )
            .onHover { hovering in
                withAnimation(.smooth(duration: 0.2)) { isHovering = hovering }
            }
            .animation(.smooth(duration: 0.2), value: dragValue != nil)
        }
        .frame(height: 16)
    }
}
