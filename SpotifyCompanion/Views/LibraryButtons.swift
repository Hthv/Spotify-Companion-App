import SwiftUI

/// Window-level navigation that isn't worth persisting.
@MainActor
@Observable
final class Router {
    var isAccountShown = false
    /// A text field has focus, so bare-key shortcuts (Space, arrows) must leave keys alone.
    var isTyping = false
}

/// Heart: adds the track to Liked Songs, or takes it out. Asks to connect first if needed.
struct LikeButton: View {
    let uri: String

    @Environment(SpotifyAccount.self) private var account
    @Environment(Router.self) private var router

    private var isSaved: Bool { account.saved[uri] ?? false }

    var body: some View {
        ToggleIcon(
            systemName: isSaved ? "heart.fill" : "heart",
            label: isSaved ? "Remove from Liked Songs (⌥⇧B)" : "Add to Liked Songs (⌥⇧B)",
            isOn: isSaved
        ) {
            if account.isSignedIn { account.toggleSaved(uri) } else { router.isAccountShown = true }
        }
        .symbolEffect(.bounce, value: isSaved)
        .disabled(!SpotifyAccount.isLibraryTrack(uri))
        .task(id: uri) { account.checkSaved(uri) }
    }
}

/// Adds the track to one of the user's playlists, picked from a drop-down list.
struct PlaylistButton: View {
    let uri: String

    @Environment(SpotifyAccount.self) private var account
    @Environment(Router.self) private var router
    @Environment(\.theme) private var theme
    @State private var isShown = false

    var body: some View {
        IconButton(systemName: "text.badge.plus", label: "Add to playlist", size: 15) {
            if account.isSignedIn {
                account.loadPlaylists()
                isShown.toggle()
            } else {
                router.isAccountShown = true
            }
        }
        .disabled(!SpotifyAccount.isLibraryTrack(uri))
        .popover(isPresented: $isShown, arrowEdge: .bottom) {
            PlaylistPanel(uri: uri) { isShown = false }
                .themedPopover(theme)
        }
    }
}

private struct PlaylistPanel: View {
    let uri: String
    let dismiss: () -> Void

    @Environment(SpotifyAccount.self) private var account
    @Environment(\.theme) private var theme
    @State private var filter = ""
    @State private var added: String?

    private var shown: [Playlist] {
        let query = filter.trimmingCharacters(in: .whitespaces)
        return query.isEmpty ? account.playlists : account.playlists.filter { $0.name.localizedCaseInsensitiveContains(query) }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Metrics.unit) {
            HStack {
                Text("Add to playlist").styledLabel()
                Spacer()
                if account.isLoadingPlaylists { ProgressView().controlSize(.small) }
            }
            if account.playlists.count > 8 {
                HStack(spacing: 6) {
                    Image(systemName: "magnifyingglass").foregroundStyle(theme.secondary)
                    TextField("Filter", text: $filter).textFieldStyle(.plain)
                }
                .font(theme.font(\.body, 13))
                .padding(.horizontal, 10)
                .padding(.vertical, 7)
                .background(theme.foreground.opacity(0.06), in: RoundedRectangle(cornerRadius: min(theme.style.cornerRadius, 8)))
            }
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 2) {
                    ForEach(shown) { playlist in
                        PlaylistRow(playlist: playlist, isAdded: added == playlist.id) {
                            account.add(uri, to: playlist)
                            withAnimation(.spring(duration: 0.35, bounce: 0.4)) { added = playlist.id }
                            Task {
                                try? await Task.sleep(for: .seconds(0.7))
                                dismiss()
                            }
                        }
                    }
                }
            }
            .frame(maxHeight: 300)
            if shown.isEmpty, !account.isLoadingPlaylists {
                Label(filter.isEmpty ? "No playlists you can add to" : "No match", systemImage: "music.note.list")
                    .font(theme.font(\.body, 13))
                    .foregroundStyle(theme.secondary)
                    .padding(.vertical, Metrics.unit)
            }
        }
        .padding(Metrics.unit * 2)
        .frame(width: 290)
    }
}

private struct PlaylistRow: View {
    let playlist: Playlist
    let isAdded: Bool
    let action: () -> Void

    @Environment(\.theme) private var theme
    @State private var isHovering = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 10) {
                AsyncImage(url: playlist.imageURL) { image in
                    image.resizable().aspectRatio(contentMode: .fill)
                } placeholder: {
                    ZStack {
                        theme.foreground.opacity(0.08)
                        Image(systemName: "music.note.list").font(.system(size: 12)).foregroundStyle(theme.secondary)
                    }
                }
                .frame(width: 34, height: 34)
                .clipShape(ThumbnailShape(art: theme.style.art))
                VStack(alignment: .leading, spacing: 1) {
                    Text(playlist.name).font(theme.font(\.body, 13)).lineLimit(1)
                    if let total = playlist.total {
                        Text("\(total) songs").font(theme.font(\.body, 11)).foregroundStyle(theme.secondary)
                    }
                }
                Spacer(minLength: 4)
                Image(systemName: isAdded ? "checkmark.circle.fill" : "plus")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(isAdded ? theme.accent : theme.secondary)
                    .opacity(isAdded || isHovering ? 1 : 0)
                    .contentTransition(.symbolEffect(.replace))
            }
            .padding(6)
            .background(theme.foreground.opacity(isHovering ? 0.07 : 0), in: RoundedRectangle(cornerRadius: min(theme.style.cornerRadius, 8)))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .foregroundStyle(theme.foreground)
        .onHover { hovering in withAnimation(.easeOut(duration: 0.12)) { isHovering = hovering } }
    }
}

extension View {
    /// Popovers don't inherit the window's look on their own: give them the theme's colors.
    func themedPopover(_ theme: Theme) -> some View {
        self
            .environment(\.theme, theme)
            .foregroundStyle(theme.foreground)
            .tint(theme.accent)
            .background(theme.background, ignoresSafeAreaEdges: .all)
            .presentationBackground(theme.background)
            .environment(\.colorScheme, theme.colorScheme)
    }
}
