import SwiftUI

struct HeaderBar: View {
    @Binding var page: Page

    @Environment(\.theme) private var theme

    var body: some View {
        HStack(alignment: .center, spacing: Metrics.unit * 2) {
            BrandMark()
            PageNav(page: $page)
                .padding(.leading, Metrics.unit)
            Spacer(minLength: Metrics.unit)
            StyleButton()
            ColorButton()
            CustomizeButton()
            AccountButton()
        }
        .padding(.horizontal, Metrics.margin)
        .frame(height: 44)
    }
}

/// The app icon in miniature (a disc with an accent label, spinning while music plays),
/// with a wordmark for the styles that set one.
private struct BrandMark: View {
    @Environment(SpotifyService.self) private var spotify
    @Environment(\.theme) private var theme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var wordmark: String? {
        switch theme.style.id {
        case .swiss, .minimal: nil
        case .luxury: "Companion"
        case .ethereal: "companion"
        case .wabiSabi: "companion"
        case .y2k: "companion.exe"
        case .editorial: "The Companion"
        }
    }

    var body: some View {
        HStack(spacing: 10) {
            disc
            if let wordmark {
                Group {
                    if theme.style.id == .editorial {
                        Text(wordmark).font(theme.font(\.display, 17))
                    } else {
                        Text(wordmark).styledLabel(theme.style.id == .luxury ? 12 : 13)
                    }
                }
                .transition(.opacity.combined(with: .offset(x: -6)))
            }
        }
        .help("Spotify Companion")
        .accessibilityHidden(true)
    }

    private var disc: some View {
        let spinning = spotify.isPlaying && !reduceMotion
        return TimelineView(.animation(minimumInterval: 1 / 30, paused: !spinning)) { context in
            ZStack {
                Circle().fill(theme.foreground)
                Circle().fill(theme.accent).frame(width: 6, height: 6)
                // An off-center notch makes the rotation visible.
                Circle()
                    .fill(theme.background)
                    .frame(width: 2.5, height: 2.5)
                    .offset(x: 5)
            }
            .frame(width: 18, height: 18)
            // Paused, the timeline stops and the disc rests where it was.
            .rotationEffect(.degrees(context.date.timeIntervalSinceReferenceDate * 120))
        }
    }
}

/// Home and Player, with a marker that slides between them.
private struct PageNav: View {
    @Binding var page: Page

    @Environment(\.theme) private var theme
    @Namespace private var marker

    var body: some View {
        HStack(spacing: 2) {
            item(.home, icon: "house", label: "Home (⇧⌘H)")
            item(.player, icon: "play.square", label: "Player (⇧⌘P)")
        }
    }

    private func item(_ target: Page, icon: String, label: String) -> some View {
        let selected = page == target
        return Button {
            withAnimation(theme.style.motion) { page = target }
        } label: {
            VStack(spacing: 4) {
                Image(systemName: selected ? icon + ".fill" : icon)
                    .font(.system(size: 15, weight: theme.style.iconWeight == .ultraLight ? .light : theme.style.iconWeight))
                    .foregroundStyle(selected ? theme.accent : theme.foreground)
                    .frame(width: 32, height: 22)
                ZStack {
                    Color.clear
                    if selected {
                        Capsule()
                            .fill(theme.accent)
                            .matchedGeometryEffect(id: "marker", in: marker)
                    }
                }
                .frame(width: 16, height: 2)
            }
            .padding(.top, 6)
            .contentShape(Rectangle())
        }
        .buttonStyle(PressableStyle())
        .opacity(selected ? 1 : 0.6)
        .help(label)
        .accessibilityLabel(label)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }
}

/// A header control that opens a drop-down panel under itself.
private struct HeaderDropDown<Label: View, Panel: View>: View {
    let help: String
    @ViewBuilder let label: Label
    @ViewBuilder let panel: Panel

    @Environment(\.theme) private var theme
    @State private var isOpen = false
    @State private var isHovering = false

    var body: some View {
        Button {
            isOpen.toggle()
        } label: {
            label
                .padding(.horizontal, 8)
                .frame(height: 30)
                .background(
                    theme.foreground.opacity(isOpen ? 0.1 : (isHovering ? 0.06 : 0)),
                    in: RoundedRectangle(cornerRadius: min(theme.style.cornerRadius, 8), style: .continuous)
                )
                .contentShape(Rectangle())
        }
        .buttonStyle(PressableStyle())
        .onHover { hovering in withAnimation(.easeOut(duration: 0.15)) { isHovering = hovering } }
        .help(help)
        .accessibilityLabel(help)
        .popover(isPresented: $isOpen, arrowEdge: .bottom) {
            panel.themedPopover(theme)
        }
    }
}

private struct Chevron: View {
    @Environment(\.theme) private var theme

    var body: some View {
        Image(systemName: "chevron.down")
            .font(.system(size: 9, weight: .bold))
            .foregroundStyle(theme.secondary)
    }
}

// MARK: Style

private struct StyleButton: View {
    @Environment(Appearance.self) private var appearance
    @Environment(\.theme) private var theme

    var body: some View {
        HeaderDropDown(help: "Style") {
            HStack(spacing: 6) {
                Image(systemName: "textformat")
                    .font(.system(size: 12, weight: .semibold))
                Text(theme.style.name)
                    .styledLabel(10)
                    .lineLimit(1)
                    .contentTransition(.opacity)
                Chevron()
            }
        } panel: {
            StylePanel()
        }
    }
}

/// Every style, each name set in its own typeface beside a tile in its own colors.
private struct StylePanel: View {
    @Environment(Appearance.self) private var appearance
    @Environment(ArtworkStore.self) private var artwork
    @Environment(\.theme) private var theme

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text("Style").styledLabel().padding(.horizontal, 8).padding(.bottom, 6)
            ForEach(Array(StyleID.allCases.enumerated()), id: \.element) { index, id in
                StyleRow(
                    preview: .resolve(id, appearance.color(for: id), palette: artwork.palette),
                    isSelected: appearance.styleID == id,
                    shortcut: index + 1
                ) {
                    withAnimation(id.style.motion) { appearance.styleID = id }
                }
            }
        }
        .padding(Metrics.unit * 1.5)
        .frame(width: 340)
    }
}

private struct StyleRow: View {
    let preview: Theme
    let isSelected: Bool
    let shortcut: Int
    let action: () -> Void

    @Environment(\.theme) private var theme
    @State private var isHovering = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 12) {
                SwatchTile(theme: preview, label: "Aa")
                    .frame(width: 52, height: 38)
                VStack(alignment: .leading, spacing: 2) {
                    Text(preview.style.name)
                        .font(preview.style.fonts.display.font(16))
                        .lineLimit(1)
                    Text(preview.style.summary)
                        .font(theme.font(\.body, 11))
                        .foregroundStyle(theme.secondary)
                        .lineLimit(1)
                }
                Spacer(minLength: 4)
                if isSelected {
                    Image(systemName: "checkmark")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundStyle(theme.accent)
                        .transition(.scale.combined(with: .opacity))
                } else {
                    Text("⌘\(shortcut)")
                        .font(.system(size: 11, weight: .medium).monospacedDigit())
                        .foregroundStyle(theme.secondary)
                        .opacity(isHovering ? 1 : 0)
                }
            }
            .padding(8)
            .background(
                theme.foreground.opacity(isSelected ? 0.08 : (isHovering ? 0.05 : 0)),
                in: RoundedRectangle(cornerRadius: min(theme.style.cornerRadius, 8), style: .continuous)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .foregroundStyle(theme.foreground)
        .onHover { hovering in withAnimation(.easeOut(duration: 0.12)) { isHovering = hovering } }
        .animation(.spring(duration: 0.3, bounce: 0.4), value: isSelected)
        .accessibilityLabel(preview.style.name)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}

// MARK: Color

private struct ColorButton: View {
    @Environment(\.theme) private var theme

    var body: some View {
        HeaderDropDown(help: "Colors") {
            HStack(spacing: 6) {
                SwatchTile(theme: theme, label: nil)
                    .frame(width: 18, height: 18)
                    .clipShape(Circle())
                    .overlay(Circle().strokeBorder(theme.rule, lineWidth: 1))
                Chevron()
            }
        } panel: {
            ColorPanel()
        }
    }
}

/// The current style's palettes, then the two that come from the cover.
private struct ColorPanel: View {
    @Environment(Appearance.self) private var appearance
    @Environment(ArtworkStore.self) private var artwork
    @Environment(\.theme) private var theme

    var body: some View {
        let style = theme.style
        VStack(alignment: .leading, spacing: Metrics.unit * 1.5) {
            HStack {
                Text("Colors").styledLabel()
                Spacer()
                Text(style.name).font(style.fonts.display.font(12)).foregroundStyle(theme.secondary)
            }
            LazyVGrid(columns: Array(repeating: GridItem(.fixed(84), spacing: 10), count: 3), spacing: 12) {
                ForEach(ColorChoice.all(for: style), id: \.self) { choice in
                    ColorTile(
                        choice: choice,
                        preview: .resolve(style.id, choice, palette: artwork.palette),
                        isSelected: appearance.color == choice
                    ) {
                        withAnimation(.smooth(duration: 0.7)) { appearance.color = choice }
                    }
                }
            }
        }
        .padding(Metrics.unit * 2)
    }
}

private struct ColorTile: View {
    let choice: ColorChoice
    let preview: Theme
    let isSelected: Bool
    let action: () -> Void

    @Environment(\.theme) private var theme
    @State private var isHovering = false

    var body: some View {
        Button(action: action) {
            VStack(spacing: 6) {
                SwatchTile(theme: preview, label: "Aa")
                    .frame(width: 84, height: 56)
                    .overlay(alignment: .topTrailing) {
                        if let badge {
                            Image(systemName: badge)
                                .font(.system(size: 9, weight: .bold))
                                .foregroundStyle(preview.foreground)
                                .padding(5)
                        }
                    }
                    .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: 6, style: .continuous)
                            .strokeBorder(theme.foreground.opacity(0.15), lineWidth: 1)
                    )
                    .padding(3)
                    .overlay(
                        RoundedRectangle(cornerRadius: 9, style: .continuous)
                            .strokeBorder(theme.accent, lineWidth: isSelected ? 2 : 0)
                    )
                    .scaleEffect(isHovering ? 1.05 : 1)
                Text(choice.title(in: preview.style))
                    .font(theme.font(\.body, 11))
                    .foregroundStyle(isSelected ? theme.foreground : theme.secondary)
                    .lineLimit(1)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(PressableStyle())
        .onHover { hovering in withAnimation(.spring(duration: 0.3, bounce: 0.4)) { isHovering = hovering } }
        .animation(.spring(duration: 0.3, bounce: 0.3), value: isSelected)
        .help(choice.title(in: preview.style))
        .accessibilityLabel(choice.title(in: preview.style))
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    private var badge: String? {
        switch choice {
        case .palette: nil
        case .auto: "wand.and.stars"
        case .albumBlur: "drop.fill"
        }
    }
}

/// A miniature of a theme: its backdrop, "Aa" in its display face, an accent dot.
struct SwatchTile: View {
    let theme: Theme
    let label: String?

    @Environment(ArtworkStore.self) private var artwork

    var body: some View {
        GeometryReader { geometry in
            ZStack(alignment: .bottomLeading) {
                theme.background
                switch theme.backdrop {
                case .flat:
                    EmptyView()
                case .gradient(let start, let end):
                    LinearGradient(colors: [start, end], startPoint: .topLeading, endPoint: .bottomTrailing)
                case .albumBlur:
                    if let image = artwork.thumbnail {
                        Image(nsImage: image)
                            .resizable()
                            .scaledToFill()
                            .frame(width: geometry.size.width * 1.4, height: geometry.size.height * 1.4)
                            .frame(width: geometry.size.width, height: geometry.size.height)
                            .clipped()
                    }
                    Color.black.opacity(0.35)
                }
                if let label {
                    Text(label)
                        .font(theme.style.fonts.display.font(geometry.size.height * 0.36))
                        .foregroundStyle(theme.foreground)
                        .padding(.leading, geometry.size.width * 0.12)
                        .padding(.bottom, geometry.size.height * 0.12)
                }
                Circle()
                    .fill(theme.accent)
                    .frame(width: geometry.size.height * 0.22, height: geometry.size.height * 0.22)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomTrailing)
                    .padding(geometry.size.height * 0.14)
            }
        }
    }
}

// MARK: Customize

private struct CustomizeButton: View {
    var body: some View {
        HeaderDropDown(help: "Customize layout") {
            Image(systemName: "slider.horizontal.3")
                .font(.system(size: 14, weight: .semibold))
        } panel: {
            CustomizePanel()
        }
    }
}

/// Turn parts of the window on and off, move the cover, change the text size.
struct CustomizePanel: View {
    @Environment(\.theme) private var theme
    @AppStorage(Pref.showArtwork) private var showArtwork = true
    @AppStorage(Pref.showLyrics) private var showLyrics = false
    @AppStorage(Pref.showAlbum) private var showAlbum = true
    @AppStorage(Pref.showProgress) private var showProgress = true
    @AppStorage(Pref.showModes) private var showModes = true
    @AppStorage(Pref.showVolume) private var showVolume = true
    @AppStorage(Pref.showLibrary) private var showLibrary = true
    @AppStorage(Pref.showEqualizer) private var showEqualizer = true
    @AppStorage(Pref.ambientMotion) private var ambientMotion = true
    @AppStorage(Pref.artworkTrailing) private var artworkTrailing = false
    @AppStorage(Pref.textSize) private var textSize: TextSize = .medium

    var body: some View {
        VStack(alignment: .leading, spacing: Metrics.unit * 2) {
            Text("Show").styledLabel()
            LazyVGrid(columns: Array(repeating: GridItem(.fixed(78), spacing: 8), count: 3), spacing: 8) {
                PrefTile(icon: "photo", filled: true, title: "Cover", isOn: $showArtwork)
                PrefTile(icon: "quote.bubble", filled: true, title: "Lyrics", isOn: $showLyrics)
                PrefTile(icon: "opticaldisc", filled: true, title: "Album", isOn: $showAlbum)
                PrefTile(icon: "slider.horizontal.below.rectangle", title: "Progress", isOn: $showProgress)
                PrefTile(icon: "shuffle", title: "Shuffle", isOn: $showModes)
                PrefTile(icon: "speaker.wave.2", filled: true, title: "Volume", isOn: $showVolume)
                PrefTile(icon: "heart", filled: true, title: "Like & Add", isOn: $showLibrary)
                PrefTile(icon: "chart.bar", filled: true, title: "Equalizer", isOn: $showEqualizer)
                PrefTile(icon: "sparkles", title: "Ambient", isOn: $ambientMotion)
            }
            HStack(alignment: .top, spacing: Metrics.unit * 3) {
                VStack(alignment: .leading, spacing: Metrics.unit) {
                    Text("Cover side").styledLabel()
                    Segmented(
                        options: [(false, "rectangle.lefthalf.inset.filled", "Left"), (true, "rectangle.righthalf.inset.filled", "Right")],
                        selection: $artworkTrailing
                    )
                }
                VStack(alignment: .leading, spacing: Metrics.unit) {
                    Text("Text size").styledLabel()
                    Segmented(
                        options: [(.small, "textformat.size.smaller", "Small"), (.medium, "textformat.size", "Medium"), (.large, "textformat.size.larger", "Large")],
                        selection: $textSize
                    )
                }
            }
            Button {
                withAnimation(theme.style.motion) {
                    for key in Pref.layoutKeys { UserDefaults.standard.removeObject(forKey: key) }
                }
            } label: {
                Label("Reset layout", systemImage: "arrow.counterclockwise")
                    .font(theme.font(\.body, 12))
                    .foregroundStyle(theme.secondary)
            }
            .buttonStyle(.plain)
        }
        .padding(Metrics.unit * 2)
        .frame(width: 282)
    }
}

private struct PrefTile: View {
    let icon: String
    /// Whether the symbol has a ".fill" variant to show when on.
    var filled = false
    let title: String
    @Binding var isOn: Bool

    @Environment(\.theme) private var theme
    @State private var isHovering = false

    var body: some View {
        Button {
            withAnimation(theme.style.motion) { isOn.toggle() }
        } label: {
            VStack(spacing: 6) {
                Image(systemName: isOn && filled ? icon + ".fill" : icon)
                    .font(.system(size: 17, weight: .medium))
                    .symbolRenderingMode(.hierarchical)
                    .foregroundStyle(isOn ? theme.accent : theme.secondary)
                    .contentTransition(.symbolEffect(.replace))
                    .frame(height: 22)
                Text(title)
                    .font(theme.font(\.body, 11))
                    .lineLimit(1)
                    .foregroundStyle(isOn ? theme.foreground : theme.secondary)
            }
            .frame(width: 78, height: 62)
            .background(
                theme.foreground.opacity(isOn ? 0.09 : (isHovering ? 0.05 : 0.02)),
                in: RoundedRectangle(cornerRadius: min(max(theme.style.cornerRadius, 4), 10), style: .continuous)
            )
            .overlay(
                RoundedRectangle(cornerRadius: min(max(theme.style.cornerRadius, 4), 10), style: .continuous)
                    .strokeBorder(isOn ? theme.accent.opacity(0.6) : theme.rule, lineWidth: 1)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(PressableStyle())
        .onHover { hovering in withAnimation(.easeOut(duration: 0.12)) { isHovering = hovering } }
        .help(isOn ? "Hide \(title.lowercased())" : "Show \(title.lowercased())")
        .accessibilityLabel(title)
        .accessibilityAddTraits(isOn ? .isSelected : [])
    }
}

/// Icon-only segmented control.
private struct Segmented<Value: Hashable>: View {
    let options: [(Value, String, String)]
    @Binding var selection: Value

    @Environment(\.theme) private var theme
    @Namespace private var marker

    var body: some View {
        HStack(spacing: 2) {
            ForEach(Array(options.enumerated()), id: \.offset) { _, option in
                let (value, icon, label) = option
                let selected = selection == value
                Button {
                    withAnimation(theme.style.motion) { selection = value }
                } label: {
                    Image(systemName: icon)
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(selected ? theme.background : theme.foreground)
                        .frame(width: 34, height: 26)
                        .background {
                            if selected {
                                RoundedRectangle(cornerRadius: min(theme.style.cornerRadius, 6), style: .continuous)
                                    .fill(theme.foreground)
                                    .matchedGeometryEffect(id: "marker", in: marker)
                            }
                        }
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .help(label)
                .accessibilityLabel(label)
                .accessibilityAddTraits(selected ? .isSelected : [])
            }
        }
        .padding(2)
        .background(theme.foreground.opacity(0.06), in: RoundedRectangle(cornerRadius: min(theme.style.cornerRadius, 8) + 2, style: .continuous))
    }
}

// MARK: Account

private struct AccountButton: View {
    @Environment(SpotifyAccount.self) private var account
    @Environment(Router.self) private var router
    @Environment(\.theme) private var theme

    var body: some View {
        IconButton(
            systemName: account.isSignedIn ? "person.crop.circle.fill" : "person.crop.circle.badge.plus",
            label: account.isSignedIn ? "Spotify account" : "Connect Spotify account",
            size: 16
        ) {
            router.isAccountShown = true
        }
        .overlay(alignment: .topTrailing) {
            if account.status == .signingIn {
                Circle().fill(theme.accent).frame(width: 6, height: 6).offset(x: -6, y: 7)
            }
        }
    }
}
