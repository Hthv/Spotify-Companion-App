import Foundation

struct Track: Equatable, Sendable {
    let id: String
    let name: String
    let artist: String
    let album: String
    let artworkURL: URL?
    /// Seconds.
    let duration: TimeInterval
}

enum PlayerState: String, Sendable {
    case playing, paused, stopped
}

/// One reading of Spotify's player, taken at `capturedAt`.
struct PlayerSnapshot: Sendable {
    var isRunning = true
    var state: PlayerState = .stopped
    var track: Track?
    /// Seconds.
    var position: TimeInterval = 0
    var volume = 0
    var isShuffling = false
    var isRepeating = false
    var capturedAt = Date()
}

extension PlayerSnapshot {
    /// Reads everything in one round trip. The `is running` check keeps the script
    /// from relaunching Spotify if it quits between our own check and this call.
    static let script = """
    if application id "com.spotify.client" is running then
        tell application id "com.spotify.client"
            with timeout of 3 seconds
                if player state is playing then
                    set playerState to "playing"
                else if player state is paused then
                    set playerState to "paused"
                else
                    return {"stopped"}
                end if
                set t to current track
                return {playerState, id of t, name of t, artist of t, album of t, artwork url of t, duration of t, player position, sound volume, shuffling, repeating}
            end timeout
        end tell
    else
        return {"not running"}
    end if
    """

    init(descriptor list: NSAppleEventDescriptor) throws {
        let capturedAt = Date()
        switch list.string(at: 1) {
        case "not running":
            self.init(isRunning: false, capturedAt: capturedAt)
        case "stopped":
            self.init(capturedAt: capturedAt)
        case let head? where (head == "playing" || head == "paused") && list.numberOfItems >= 11:
            let track = Track(
                id: list.string(at: 2) ?? "",
                name: list.string(at: 3) ?? "Unknown",
                artist: list.string(at: 4) ?? "",
                album: list.string(at: 5) ?? "",
                artworkURL: list.string(at: 6).flatMap(Self.artworkURL(from:)),
                duration: (list.double(at: 7) ?? 0) / 1000 // Spotify reports milliseconds
            )
            self.init(
                state: head == "playing" ? .playing : .paused,
                track: track,
                position: list.double(at: 8) ?? 0,
                volume: Int((list.double(at: 9) ?? 0).rounded()),
                isShuffling: list.bool(at: 10),
                isRepeating: list.bool(at: 11),
                capturedAt: capturedAt
            )
        default:
            throw AppleScriptError(code: -1, message: "Unexpected reply from Spotify")
        }
    }

    private static func artworkURL(from string: String) -> URL? {
        guard !string.isEmpty, var components = URLComponents(string: string) else { return nil }
        // App Transport Security blocks plain http; Spotify's image CDN serves both.
        if components.scheme == "http" { components.scheme = "https" }
        return components.url
    }
}

private extension NSAppleEventDescriptor {
    func string(at index: Int) -> String? { item(at: index)?.stringValue }
    func double(at index: Int) -> Double? { item(at: index)?.doubleValue }
    func bool(at index: Int) -> Bool { item(at: index)?.booleanValue ?? false }

    /// 1-based, like AppleScript lists. `missing value` comes back as nil.
    private func item(at index: Int) -> NSAppleEventDescriptor? {
        guard index <= numberOfItems, let item = atIndex(index), !item.isMissingValue else { return nil }
        return item
    }

    var isMissingValue: Bool {
        descriptorType == fourCharCode("type") && typeCodeValue == fourCharCode("msng")
    }
}

private func fourCharCode(_ string: String) -> OSType {
    string.utf8.reduce(OSType(0)) { ($0 << 8) | OSType($1) }
}
