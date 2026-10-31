import SwiftUI

/// The search field: its placeholder cycles through what you can look for, it glows in the
/// accent while focused, a shimmer runs under it while results load, and ⌘F focuses it.
struct SearchBar: View {
    var isFocused: FocusState<Bool>.Binding
    /// Arrow keys and Return, passed to the results.
    let onKey: (SearchKey) -> KeyPress.Result

    @Environment(SearchStore.self) private var search
    @Environment(SpotifyAccount.self) private var account
    @Environment(\.theme) private var theme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var isHovering = false

    private var shape: RoundedRectangle {
        RoundedRectangle(cornerRadius: theme.style.control == .glossyPill ? 22 : max(theme.style.cornerRadius, 4), style: .continuous)
    }

    var body: some View {
        @Bindable var search = search
        let focused = isFocused.wrappedValue
        HStack(spacing: Metrics.unit * 1.5) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 16, weight: theme.style.iconWeight == .ultraLight ? .light : theme.style.iconWeight))
                .foregroundStyle(focused ? theme.accent : theme.secondary)
                .symbolEffect(.bounce, value: search.resultQuery)
                .symbolEffect(.pulse, options: .repeating, isActive: search.isSearching)
                .rotationEffect(.degrees(focused ? -12 : 0))
                .scaleEffect(focused ? 1.12 : 1)
            ZStack(alignment: .leading) {
                if search.query.isEmpty {
                    CyclingPlaceholder(signedIn: account.isSignedIn)
                        .allowsHitTesting(false)
                }
                TextField("", text: $search.query)
                    .textFieldStyle(.plain)
                    .font(theme.font(\.body, 17))
                    .focused(isFocused)
                    .onSubmit { search.commit() }
                    .onKeyPress(.upArrow) { onKey(.up) }
                    .onKeyPress(.downArrow) { onKey(.down) }
                    .onKeyPress(.return) { onKey(.open) }
                    .onKeyPress(.escape) {
                        if search.query.isEmpty { isFocused.wrappedValue = false } else { search.clear() }
                        return .handled
                    }
                    .accessibilityLabel("Search Spotify")
            }
            if !search.query.isEmpty {
                Button {
                    withAnimation(.spring(duration: 0.35, bounce: 0.3)) { search.clear() }
                    isFocused.wrappedValue = true
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 15))
                        .foregroundStyle(theme.secondary)
                }
                .buttonStyle(PressableStyle())
                .transition(.scale(scale: 0.3).combined(with: .opacity))
                .help("Clear (Esc)")
            } else if !focused {
                Text("⌘F")
                    .font(theme.font(\.label, 11))
                    .foregroundStyle(theme.secondary)
                    .padding(.horizontal, 7)
                    .padding(.vertical, 3)
                    .overlay(RoundedRectangle(cornerRadius: 5).strokeBorder(theme.rule))
                    .transition(.opacity.combined(with: .scale(scale: 0.8)))
            }
        }
        .padding(.horizontal, Metrics.unit * 2)
        .frame(height: 46)
        .background(theme.foreground.opacity(focused ? 0.08 : isHovering ? 0.065 : 0.045), in: shape)
        .overlay(shape.strokeBorder(focused ? theme.accent : theme.rule, lineWidth: focused ? 1.5 : 1))
        .overlay(alignment: .bottom) {
            if search.isSearching { SearchShimmer().clipShape(shape).transition(.opacity) }
        }
        .shadow(color: theme.accent.opacity(focused ? 0.28 : 0), radius: focused ? 16 : 0)
        .scaleEffect(focused && !reduceMotion ? 1.008 : 1)
        .contentShape(shape)
        .onTapGesture { isFocused.wrappedValue = true }
        .onHover { isHovering = $0 }
        .animation(.spring(duration: 0.4, bounce: 0.35), value: focused)
        .animation(.spring(duration: 0.35, bounce: 0.3), value: search.query.isEmpty)
        .animation(.easeOut(duration: 0.2), value: search.isSearching)
    }
}

enum SearchKey { case up, down, open }

/// "Search songs" → "artists" → "albums" → "playlists", each word rolling up into place.
private struct CyclingPlaceholder: View {
    let signedIn: Bool

    @Environment(\.theme) private var theme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private static let words = ["songs", "artists", "albums", "playlists", "moods"]

    var body: some View {
        if !signedIn {
            Text("Connect Spotify to search").font(theme.font(\.body, 17)).foregroundStyle(theme.secondary)
        } else {
            TimelineView(.periodic(from: .now, by: 2.2)) { context in
                let index = Int(context.date.timeIntervalSinceReferenceDate / 2.2) % Self.words.count
                HStack(spacing: 5) {
                    Text("Search")
                    Text(Self.words[index])
                        .foregroundStyle(theme.accent.opacity(0.85))
                        .id(index)
                        .transition(reduceMotion ? .opacity : .asymmetric(
                            insertion: .push(from: .bottom).combined(with: .opacity),
                            removal: .push(from: .bottom).combined(with: .opacity)
                        ))
                }
                .font(theme.font(\.body, 17))
                .foregroundStyle(theme.secondary)
                .animation(.spring(duration: 0.55, bounce: 0.3), value: index)
            }
        }
    }
}

/// A band of accent light sweeping along the bottom edge.
private struct SearchShimmer: View {
    @Environment(\.theme) private var theme

    var body: some View {
        TimelineView(.animation) { context in
            let phase = context.date.timeIntervalSinceReferenceDate.truncatingRemainder(dividingBy: 1.1) / 1.1
            GeometryReader { geometry in
                LinearGradient(colors: [theme.accent.opacity(0), theme.accent, theme.accent.opacity(0)], startPoint: .leading, endPoint: .trailing)
                    .frame(width: geometry.size.width * 0.35, height: 2)
                    .offset(x: (geometry.size.width * 1.35) * phase - geometry.size.width * 0.35, y: geometry.size.height - 2)
            }
        }
        .allowsHitTesting(false)
    }
}

// MARK: Results

/// Everything under the field while searching: scope chips, then a top result, songs, artists,
/// albums and playlists, rising in one after another. With an empty field: recent searches and
/// moods to start from.
struct SearchPanel: View {
    /// Index into `flat` picked with the arrow keys.
    @Binding var selection: Int?
    var namespace: Namespace.ID

    @Environment(SearchStore.self) private var search
    @Environment(SpotifyAccount.self) private var account
    @Environment(Router.self) private var router
    @Environment(\.theme) private var theme
    @Namespace private var chips
    @Namespace private var highlight

    /// Results in keyboard order: top result, then songs, artists, albums, playlists.
    static func flat(_ search: SearchStore) -> [MediaItem] {
        let order: [MediaItem.Kind] = [.track, .artist, .album, .playlist]
        if let kind = search.scope.kind { return search.results[kind] ?? [] }
        var items: [MediaItem] = search.topResult.map { [$0] } ?? []
        for kind in order {
            items += (search.results[kind] ?? []).prefix(kind == .track ? 5 : 8).filter { $0.uri != search.topResult?.uri }
        }
        return items
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Metrics.unit * 3) {
            if !account.isSignedIn {
                BrowseMessage(icon: "person.crop.circle.badge.plus", title: "Connect your Spotify account to search",
                              detail: "Search uses Spotify’s Web API, which needs you signed in.",
                              action: ("Connect", "link", { router.isAccountShown = true }))
            } else if search.isActive {
                scopeChips
                results
            } else {
                StartPanel()
            }
        }
    }

    private var scopeChips: some View {
        @Bindable var search = search
        return HStack(spacing: Metrics.unit) {
            ForEach(SearchStore.Scope.allCases) { scope in
                let isOn = search.scope == scope
                Button {
                    withAnimation(.spring(duration: 0.4, bounce: 0.3)) { search.scope = scope }
                    selection = nil
                } label: {
                    Text(scope.rawValue)
                        .font(theme.font(\.label, 12))
                        .textCase(theme.style.labelCase)
                        .tracking(theme.style.labelTracking * 0.4)
                        .foregroundStyle(isOn ? theme.background : theme.foreground)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 7)
                        .background {
                            if isOn {
                                Capsule().fill(theme.foreground).matchedGeometryEffect(id: "chip", in: chips)
                            } else {
                                Capsule().strokeBorder(theme.rule)
                            }
                        }
                        .contentShape(Capsule())
                }
                .buttonStyle(PressableStyle())
            }
        }
    }

    @ViewBuilder
    private var results: some View {
        let flat = Self.flat(search)
        if let error = search.error {
            BrowseMessage(icon: "wifi.exclamationmark", title: "Search didn’t go through", detail: error)
        } else if search.isEmptyResult {
            VStack(spacing: Metrics.unit) {
                Image(systemName: "magnifyingglass").font(.system(size: 30, weight: theme.style.iconWeight)).foregroundStyle(theme.accent)
                    .symbolEffect(.bounce, value: search.resultQuery)
                Text("No results for “\(search.resultQuery)”").font(theme.font(\.display, 18))
                Text("Check the spelling, or try fewer words.").font(theme.font(\.body, 13)).foregroundStyle(theme.secondary)
            }
            .frame(maxWidth: .infinity)
            .padding(.top, Metrics.unit * 6)
            .transition(.opacity.combined(with: .scale(scale: 0.95)))
        } else if search.scope == .top {
            topLayout(flat)
                .id(search.resultQuery)
        } else {
            scopedList(flat)
                .id("\(search.scope.rawValue)|\(search.resultQuery)")
        }
    }

    private func selected(_ item: MediaItem, in flat: [MediaItem]) -> Bool {
        selection.map { flat.indices.contains($0) && flat[$0].uri == item.uri } ?? false
    }

    private func topLayout(_ flat: [MediaItem]) -> some View {
        VStack(alignment: .leading, spacing: Metrics.unit * 4) {
            HStack(alignment: .top, spacing: Metrics.unit * 3) {
                if let top = search.topResult {
                    VStack(alignment: .leading, spacing: Metrics.unit * 1.5) {
                        SectionTitle(title: "Top result")
                        TopResultCard(item: top, isSelected: selected(top, in: flat), namespace: namespace)
                    }
                    .frame(width: 300)
                    .staggered(0)
                }
                let songs = (search.results[.track] ?? []).filter { $0.uri != search.topResult?.uri }.prefix(5)
                if !songs.isEmpty {
                    VStack(alignment: .leading, spacing: Metrics.unit * 1.5) {
                        SectionTitle(title: "Songs") { withAnimation(.spring(duration: 0.4)) { search.scope = .songs } }
                        VStack(spacing: 2) {
                            ForEach(Array(songs.enumerated()), id: \.element.id) { index, song in
                                SongRow(item: song, showsAlbum: false, isSelected: selected(song, in: flat))
                                    .staggered(index + 1)
                            }
                        }
                    }
                    .frame(maxWidth: .infinity)
                }
            }
            ForEach([MediaItem.Kind.artist, .album, .playlist], id: \.self) { kind in
                let items = (search.results[kind] ?? []).filter { $0.uri != search.topResult?.uri }
                if !items.isEmpty {
                    SelectableShelf(title: Self.title(kind), items: Array(items.prefix(8)), selectedURI: selection.flatMap { flat.indices.contains($0) ? flat[$0].uri : nil },
                                    namespace: namespace) {
                        withAnimation(.spring(duration: 0.4)) { search.scope = Self.scope(kind) }
                    }
                }
            }
        }
    }

    @ViewBuilder
    private func scopedList(_ items: [MediaItem]) -> some View {
        VStack(alignment: .leading, spacing: Metrics.unit * 2) {
            if search.scope == .songs {
                VStack(spacing: 2) {
                    ForEach(Array(items.enumerated()), id: \.element.id) { index, song in
                        SongRow(item: song, index: index, isSelected: selection == index)
                            .staggered(index % 10)
                    }
                }
            } else {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 140, maximum: 200), spacing: Metrics.unit * 2.5, alignment: .top)],
                          alignment: .leading, spacing: Metrics.unit * 3) {
                    ForEach(Array(items.enumerated()), id: \.element.id) { index, item in
                        MediaTile(item: item, namespace: namespace)
                            .padding(6)
                            .background(SelectionGlow(isOn: selection == index, namespace: highlight))
                            .staggered(index % 10)
                    }
                }
            }
            if search.canLoadMore {
                HStack {
                    Spacer()
                    ActionButton(title: search.isSearching ? "Loading" : "More results", icon: "ellipsis") { search.loadMore() }
                    Spacer()
                }
                .padding(.top, Metrics.unit)
            }
        }
    }

    static func title(_ kind: MediaItem.Kind) -> String {
        switch kind {
        case .track: "Songs"
        case .artist: "Artists"
        case .album: "Albums"
        case .playlist: "Playlists"
        case .collection: "Liked Songs"
        }
    }

    static func scope(_ kind: MediaItem.Kind) -> SearchStore.Scope {
        switch kind {
        case .track: .songs
        case .artist: .artists
        case .album: .albums
        case .playlist, .collection: .playlists
        }
    }
}

/// A shelf whose tiles light up when the arrow keys land on them.
private struct SelectableShelf: View {
    let title: String
    let items: [MediaItem]
    let selectedURI: String?
    let namespace: Namespace.ID
    let showAll: () -> Void

    @Namespace private var highlight

    var body: some View {
        VStack(alignment: .leading, spacing: Metrics.unit * 1.5) {
            SectionTitle(title: title, action: showAll)
            ScrollViewReader { proxy in
                ScrollView(.horizontal, showsIndicators: false) {
                    LazyHStack(alignment: .top, spacing: Metrics.unit * 1.5) {
                        ForEach(Array(items.enumerated()), id: \.element.id) { index, item in
                            MediaTile(item: item, namespace: namespace)
                                .frame(width: 140)
                                .padding(6)
                                .background(SelectionGlow(isOn: selectedURI == item.uri, namespace: highlight))
                                .id(item.uri)
                                .staggered(index + 2)
                        }
                    }
                    .padding(.vertical, 4)
                }
                .scrollClipDisabled()
                .onChange(of: selectedURI) { _, uri in
                    if let uri, items.contains(where: { $0.uri == uri }) {
                        withAnimation(.spring(duration: 0.4)) { proxy.scrollTo(uri, anchor: .center) }
                    }
                }
            }
        }
    }
}

/// The keyboard selection's backdrop, which slides from tile to tile.
private struct SelectionGlow: View {
    let isOn: Bool
    let namespace: Namespace.ID

    @Environment(\.theme) private var theme

    var body: some View {
        if isOn {
            RoundedRectangle(cornerRadius: max(theme.style.cornerRadius, 8), style: .continuous)
                .fill(theme.foreground.opacity(0.09))
                .overlay(RoundedRectangle(cornerRadius: max(theme.style.cornerRadius, 8), style: .continuous).strokeBorder(theme.accent.opacity(0.6)))
                .matchedGeometryEffect(id: "selection", in: namespace)
        }
    }
}

/// The best match, large: cover, name, what it is, and a play button that rises on hover.
private struct TopResultCard: View {
    let item: MediaItem
    let isSelected: Bool
    let namespace: Namespace.ID

    @Environment(SpotifyService.self) private var spotify
    @Environment(BrowseNavigation.self) private var navigation
    @Environment(SearchStore.self) private var search
    @Environment(\.theme) private var theme
    @State private var isHovering = false

    var body: some View {
        Button {
            search.commit()
            if item.kind == .track { spotify.play(uri: item.uri, in: item.albumURI) } else { navigation.open(item) }
        } label: {
            VStack(alignment: .leading, spacing: Metrics.unit * 1.5) {
                CoverImage(item: item)
                    .frame(width: 104, height: 104)
                    .matchedGeometryEffect(id: "cover-\(item.uri)", in: namespace)
                    .shadow(color: .black.opacity(0.2), radius: 12, y: 6)
                    .rotation3DEffect(.degrees(isHovering ? -6 : 0), axis: (x: 0, y: 1, z: 0), perspective: 0.6)
                Text(item.name)
                    .styledTitle(28)
                    .lineLimit(2)
                    .minimumScaleFactor(0.6)
                HStack(spacing: 8) {
                    Text(item.kind == .track ? "Song" : SearchPanel.title(item.kind).dropLast().description)
                        .styledLabel(10)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .background(theme.foreground.opacity(0.1), in: Capsule())
                    if item.kind != .artist {
                        Text(item.subtitle).font(theme.font(\.body, 13)).foregroundStyle(theme.secondary).lineLimit(1)
                    }
                }
            }
            .padding(Metrics.unit * 2.5)
            .frame(maxWidth: .infinity, minHeight: 230, alignment: .topLeading)
            .background(
                RoundedRectangle(cornerRadius: max(theme.style.cornerRadius, 8), style: .continuous)
                    .fill(theme.foreground.opacity(isSelected ? 0.12 : isHovering ? 0.09 : 0.05))
            )
            .overlay(
                RoundedRectangle(cornerRadius: max(theme.style.cornerRadius, 8), style: .continuous)
                    .strokeBorder(isSelected ? theme.accent.opacity(0.7) : .clear, lineWidth: 1.5)
            )
            .overlay(alignment: .bottomTrailing) {
                PlayBadge(item: item, isShown: isHovering || isSelected, diameter: 50).padding(Metrics.unit * 2)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(PressableStyle())
        .foregroundStyle(theme.foreground)
        .onHover { hovering in withAnimation(.spring(duration: 0.4, bounce: 0.3)) { isHovering = hovering } }
        .mediaMenu(item)
    }
}

/// With an empty field: recent searches to pick up again, and moods to start from.
private struct StartPanel: View {
    @Environment(SearchStore.self) private var search
    @Environment(\.theme) private var theme

    var body: some View {
        VStack(alignment: .leading, spacing: Metrics.unit * 4) {
            if !search.recent.isEmpty {
                VStack(alignment: .leading, spacing: Metrics.unit * 1.5) {
                    SectionTitle(title: "Recent searches")
                    FlowRow(spacing: Metrics.unit) {
                        ForEach(Array(search.recent.enumerated()), id: \.element) { index, text in
                            RecentChip(text: text)
                                .staggered(index)
                        }
                    }
                }
            }
            MoodGrid()
        }
    }
}

private struct RecentChip: View {
    let text: String

    @Environment(SearchStore.self) private var search
    @Environment(\.theme) private var theme
    @State private var isHovering = false

    var body: some View {
        HStack(spacing: 6) {
            Button {
                withAnimation(.spring(duration: 0.4)) { search.query = text }
            } label: {
                Label(text, systemImage: "clock.arrow.circlepath")
                    .font(theme.font(\.body, 13))
            }
            .buttonStyle(.plain)
            Button {
                withAnimation(.spring(duration: 0.35, bounce: 0.3)) { search.forget(text) }
            } label: {
                Image(systemName: "xmark").font(.system(size: 9, weight: .bold))
            }
            .buttonStyle(.plain)
            .opacity(isHovering ? 0.8 : 0.3)
            .help("Remove from recent searches")
        }
        .foregroundStyle(theme.foreground)
        .padding(.horizontal, 12)
        .padding(.vertical, 7)
        .background(theme.foreground.opacity(isHovering ? 0.09 : 0.05), in: Capsule())
        .scaleEffect(isHovering ? 1.04 : 1)
        .onHover { hovering in withAnimation(.spring(duration: 0.3, bounce: 0.4)) { isHovering = hovering } }
        .transition(.scale(scale: 0.5).combined(with: .opacity))
    }
}

/// Moods and genres as colored cards; picking one searches playlists for it.
struct MoodGrid: View {
    var title = "Browse moods"

    @Environment(SearchStore.self) private var search
    @Environment(\.theme) private var theme

    static let moods: [(name: String, icon: String, hue: Double)] = [
        ("Chill", "leaf", 0.42), ("Focus", "brain.head.profile", 0.6), ("Workout", "figure.run", 0.02),
        ("Party", "party.popper", 0.85), ("Sleep", "moon.stars", 0.68), ("Throwback", "clock.arrow.circlepath", 0.1),
        ("Indie", "guitars", 0.33), ("Jazz", "music.quarternote.3", 0.12), ("Lo-fi", "headphones", 0.55),
        ("K-Pop", "sparkles", 0.92), ("Acoustic", "music.note", 0.08), ("Rainy day", "cloud.rain", 0.58),
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: Metrics.unit * 1.5) {
            SectionTitle(title: title)
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 150, maximum: 240), spacing: Metrics.unit * 1.5)], spacing: Metrics.unit * 1.5) {
                ForEach(Array(Self.moods.enumerated()), id: \.element.name) { index, mood in
                    MoodCard(name: mood.name, icon: mood.icon, hue: mood.hue) {
                        withAnimation(.spring(duration: 0.45, bounce: 0.3)) {
                            search.query = mood.name
                            search.scope = .playlists
                        }
                    }
                    .staggered(index)
                }
            }
        }
    }
}

private struct MoodCard: View {
    let name: String
    let icon: String
    let hue: Double
    let action: () -> Void

    @Environment(\.theme) private var theme
    @State private var isHovering = false

    var body: some View {
        let base = Color(hue: hue, saturation: 0.55, brightness: theme.colorScheme == .dark ? 0.55 : 0.82)
        Button(action: action) {
            ZStack(alignment: .topLeading) {
                LinearGradient(colors: [base, Color(hue: (hue + 0.08).truncatingRemainder(dividingBy: 1), saturation: 0.6, brightness: theme.colorScheme == .dark ? 0.4 : 0.66)],
                               startPoint: .topLeading, endPoint: .bottomTrailing)
                Text(name)
                    .font(theme.font(\.display, 18))
                    .foregroundStyle(.white)
                    .shadow(color: .black.opacity(0.2), radius: 2, y: 1)
                    .padding(12)
                Image(systemName: icon)
                    .font(.system(size: 40, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.85))
                    .rotationEffect(.degrees(isHovering ? 0 : 18))
                    .scaleEffect(isHovering ? 1.15 : 1)
                    .offset(x: isHovering ? -6 : 0, y: isHovering ? -4 : 0)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomTrailing)
                    .padding(10)
            }
            .frame(height: 92)
            .clipShape(RoundedRectangle(cornerRadius: max(theme.style.cornerRadius, 6), style: .continuous))
            .rotation3DEffect(.degrees(isHovering ? 4 : 0), axis: (x: 1, y: -1, z: 0), perspective: 0.5)
            .shadow(color: base.opacity(isHovering ? 0.45 : 0), radius: 14, y: 8)
            .scaleEffect(isHovering ? 1.03 : 1)
            .contentShape(Rectangle())
        }
        .buttonStyle(PressableStyle())
        .onHover { hovering in withAnimation(.spring(duration: 0.4, bounce: 0.35)) { isHovering = hovering } }
        .help("Find \(name) playlists")
    }
}

/// Lays children out left to right, wrapping onto new lines.
struct FlowRow: Layout {
    var spacing: CGFloat = 8

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let width = proposal.width ?? .infinity
        var x: CGFloat = 0, y: CGFloat = 0, line: CGFloat = 0, widest: CGFloat = 0
        for view in subviews {
            let size = view.sizeThatFits(.unspecified)
            if x > 0, x + size.width > width { x = 0; y += line + spacing; line = 0 }
            x += size.width + spacing
            widest = max(widest, x - spacing)
            line = max(line, size.height)
        }
        return CGSize(width: min(widest, width), height: y + line)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var x = bounds.minX, y = bounds.minY, line: CGFloat = 0
        for view in subviews {
            let size = view.sizeThatFits(.unspecified)
            if x > bounds.minX, x + size.width > bounds.maxX { x = bounds.minX; y += line + spacing; line = 0 }
            view.place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(size))
            x += size.width + spacing
            line = max(line, size.height)
        }
    }
}
