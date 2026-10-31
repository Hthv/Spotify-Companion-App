import Foundation

/// UserDefaults keys for everything the user can change about the window.
/// Each `@AppStorage` that reads one uses the default noted here.
enum Pref {
    /// `StyleID`, default `.swiss`. Colors are per style, under `ColorChoice.storageKey(for:)`.
    static let style = "style"
    /// `Page`, default `.home`.
    static let page = "page"
    /// Default false.
    static let showLyrics = "showLyrics"
    // The rest default to true.
    static let showArtwork = "showArtwork"
    static let showAlbum = "showAlbum"
    static let showProgress = "showProgress"
    /// Shuffle and repeat.
    static let showModes = "showModes"
    static let showVolume = "showVolume"
    /// Like and add-to-playlist buttons.
    static let showLibrary = "showLibrary"
    static let showEqualizer = "showEqualizer"
    static let ambientMotion = "ambientMotion"
    /// Default false: cover on the leading side.
    static let artworkTrailing = "artworkTrailing"
    /// `TextSize`, default `.medium`.
    static let textSize = "textSize"

    /// Every layout key, for "Reset".
    static let layoutKeys = [
        showLyrics, showArtwork, showAlbum, showProgress, showModes, showVolume,
        showLibrary, showEqualizer, ambientMotion, artworkTrailing, textSize,
    ]
}

enum Page: String, Sendable {
    case home, player
}

enum TextSize: String, CaseIterable, Identifiable, Sendable {
    case small, medium, large

    var id: Self { self }

    var scale: CGFloat {
        switch self {
        case .small: 0.86
        case .medium: 1
        case .large: 1.18
        }
    }
}
