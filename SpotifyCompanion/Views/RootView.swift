import SwiftUI

struct RootView: View {
    enum Screen: Hashable {
        case connecting, notInstalled, notRunning, permissionDenied, idle, nowPlaying
    }

    @Environment(SpotifyService.self) private var spotify
    @Environment(ArtworkStore.self) private var artwork
    @Environment(LyricsStore.self) private var lyrics
    @Environment(SpotifyAccount.self) private var account
    @Environment(Appearance.self) private var appearance
    @AppStorage(Pref.page) private var page: Page = .home
    @AppStorage(Pref.showLyrics) private var showLyrics = false
    @AppStorage(Pref.textSize) private var textSize: TextSize = .medium
    @AppStorage(Pref.ambientMotion) private var ambientMotion = true
    @Environment(Router.self) private var router

    private var theme: Theme {
        var theme = appearance.theme(palette: artwork.palette)
        theme.textScale = textSize.scale
        theme.ambientMotion = ambientMotion
        return theme
    }

    private var screen: Screen {
        switch spotify.connection {
        case .connecting: .connecting
        case .notInstalled: .notInstalled
        case .notRunning: .notRunning
        case .permissionDenied: .permissionDenied
        case .connected: spotify.track == nil ? .idle : .nowPlaying
        }
    }

    /// Lyrics are only fetched while they're on screen.
    private var lyricsTrack: Track? {
        showLyrics && page == .player && screen == .nowPlaying ? spotify.track : nil
    }

    var body: some View {
        let theme = theme
        @Bindable var router = router
        VStack(spacing: 0) {
            HeaderBar(page: $page)
            Rule()
            ZStack {
                switch page {
                case .home:
                    HomeView(page: $page)
                        .transition(pageTransition(leading: true))
                case .player:
                    player
                        .transition(pageTransition(leading: false))
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .clipped()
        }
        .overlay(alignment: .bottom) { NoticeToast() }
        .background { BackdropView(headerHeight: 44) }
        .foregroundStyle(theme.foreground)
        .tint(theme.accent)
        .environment(\.theme, theme)
        .environment(router)
        .preferredColorScheme(theme.colorScheme)
        .animation(theme.style.motion, value: theme)
        .animation(theme.style.motion, value: page)
        .sheet(isPresented: $router.isAccountShown) {
            AccountView()
                .environment(\.theme, theme)
                .environment(account)
                .environment(router)
                .preferredColorScheme(theme.colorScheme)
        }
        .task {
            spotify.start()
            account.restore()
        }
        .onChange(of: spotify.track?.artworkURL, initial: true) { _, url in
            artwork.load(url)
        }
        .onChange(of: lyricsTrack, initial: true) { _, track in
            lyrics.load(for: track)
        }
    }

    @ViewBuilder
    private var player: some View {
        ZStack {
            switch screen {
            case .connecting:
                Color.clear
            case .nowPlaying:
                if let track = spotify.track {
                    NowPlayingView(track: track)
                        .transition(.opacity)
                }
            case .notInstalled, .notRunning, .permissionDenied, .idle:
                StatusView(screen: screen)
                    .id(screen)
                    .transition(.opacity)
            }
        }
        .animation(theme.style.motion, value: screen)
    }

    /// Home sits to the left of the player; pages slide a little toward where they live.
    private func pageTransition(leading: Bool) -> AnyTransition {
        .asymmetric(
            insertion: .opacity.combined(with: .offset(x: leading ? -24 : 24)),
            removal: .opacity
        )
    }
}

#if DEBUG
#Preview("Now Playing") {
    RootView()
        .environment(SpotifyService.preview())
        .environment(ArtworkStore())
        .environment(LyricsStore.preview())
        .environment(SpotifyAccount.preview())
        .environment(Appearance())
        .browsePreviews()
        .frame(width: 980, height: 640)
}

#Preview("Not running") {
    RootView()
        .environment(SpotifyService.preview(.notRunning))
        .environment(ArtworkStore())
        .environment(LyricsStore())
        .environment(SpotifyAccount.preview(signedIn: false))
        .environment(Appearance())
        .browsePreviews(signedIn: false)
        .frame(width: 980, height: 640)
}
#endif
