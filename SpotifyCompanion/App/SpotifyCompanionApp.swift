import SwiftUI

@main
struct SpotifyCompanionApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @State private var spotify = SpotifyService()
    @State private var artwork = ArtworkStore()
    @State private var lyrics = LyricsStore()
    @State private var account = SpotifyAccount()
    @State private var appearance = Appearance()

    var body: some Scene {
        Window("Spotify Companion", id: "main") {
            RootView()
                .environment(spotify)
                .environment(artwork)
                .environment(lyrics)
                .environment(account)
                .environment(appearance)
                .frame(minWidth: 820, minHeight: 520)
        }
        .windowStyle(.hiddenTitleBar)
        .windowResizability(.contentMinSize)
        .defaultSize(width: 1000, height: 640)
        .commands {
            PlaybackCommands(spotify: spotify, account: account)
            ViewCommands(appearance: appearance)
        }
    }
}

/// Shortcuts mirror Spotify's own where it has them.
private struct PlaybackCommands: Commands {
    let spotify: SpotifyService
    let account: SpotifyAccount

    var body: some Commands {
        CommandMenu("Playback") {
            Button(spotify.isPlaying ? "Pause" : "Play") { spotify.playPause() }
                .keyboardShortcut(.space, modifiers: [])
            Button("Next") { spotify.nextTrack() }
                .keyboardShortcut(.rightArrow, modifiers: .command)
            Button("Previous") { spotify.previousTrack() }
                .keyboardShortcut(.leftArrow, modifiers: .command)
            Divider()
            Button("Forward 10 Seconds") { spotify.seek(by: 10) }
                .keyboardShortcut(.rightArrow, modifiers: .shift)
            Button("Back 10 Seconds") { spotify.seek(by: -10) }
                .keyboardShortcut(.leftArrow, modifiers: .shift)
            Divider()
            Button("Volume Up") { spotify.changeVolume(by: 10) }
                .keyboardShortcut(.upArrow, modifiers: .command)
            Button("Volume Down") { spotify.changeVolume(by: -10) }
                .keyboardShortcut(.downArrow, modifiers: .command)
            Button(spotify.volume == 0 ? "Unmute" : "Mute") { spotify.toggleMute() }
                .keyboardShortcut(.downArrow, modifiers: [.command, .option])
            Divider()
            Toggle("Shuffle", isOn: Binding(get: { spotify.isShuffling }, set: { _ in spotify.toggleShuffle() }))
                .keyboardShortcut("s", modifiers: .command)
            Toggle("Repeat", isOn: Binding(get: { spotify.isRepeating }, set: { _ in spotify.toggleRepeat() }))
                .keyboardShortcut("r", modifiers: .command)
            Divider()
            let uri = spotify.track?.id
            Button(account.saved[uri ?? ""] == true ? "Remove from Liked Songs" : "Add to Liked Songs") {
                if let uri { account.toggleSaved(uri) }
            }
            .keyboardShortcut("b", modifiers: [.option, .shift])
            .disabled(!account.isSignedIn || !SpotifyAccount.isLibraryTrack(uri))
        }
    }
}

private struct ViewCommands: Commands {
    let appearance: Appearance
    @AppStorage(Pref.page) private var page: Page = .home
    @AppStorage(Pref.showLyrics) private var showLyrics = false
    @AppStorage(Pref.showArtwork) private var showArtwork = true

    var body: some Commands {
        CommandGroup(before: .toolbar) {
            Button("Home") { withAnimation(appearance.styleID.style.motion) { page = .home } }
                .keyboardShortcut("h", modifiers: [.command, .shift])
            Button("Player") { withAnimation(appearance.styleID.style.motion) { page = .player } }
                .keyboardShortcut("p", modifiers: [.command, .shift])
            Divider()
            Button(showLyrics ? "Hide Lyrics" : "Show Lyrics") {
                withAnimation(appearance.styleID.style.motion) { showLyrics.toggle() }
            }
            .keyboardShortcut("l", modifiers: .command)
            Button(showArtwork ? "Hide Cover" : "Show Cover") {
                withAnimation(appearance.styleID.style.motion) { showArtwork.toggle() }
            }
            .keyboardShortcut("a", modifiers: [.command, .shift])
            Divider()
            ForEach(Array(StyleID.allCases.enumerated()), id: \.element) { index, id in
                Toggle(id.style.name, isOn: Binding(
                    get: { appearance.styleID == id },
                    set: { isOn in
                        if isOn { withAnimation(id.style.motion) { appearance.styleID = id } }
                    }
                ))
                .keyboardShortcut(KeyEquivalent(Character(String(index + 1))), modifiers: .command)
            }
            Divider()
        }
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { true }
}
