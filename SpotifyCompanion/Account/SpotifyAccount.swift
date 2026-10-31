import AppKit
import Observation
import os

struct Playlist: Identifiable, Equatable, Sendable {
    let id: String
    let name: String
    let imageURL: URL?
    let total: Int?
}

struct RecentTrack: Identifiable, Equatable, Sendable {
    let uri: String
    let name: String
    let artist: String
    let imageURL: URL?
    var id: String { uri }
}

/// A short message that floats up from the bottom of the window, then goes away.
struct Notice: Identifiable, Equatable {
    let id = UUID()
    let icon: String
    let text: String
    var isError = false
}

/// The user's Spotify account over the Web API: sign-in, Liked Songs, playlists and
/// recently played. Playback itself stays on AppleScript.
///
/// Needs a Client ID from the user's own app at developer.spotify.com, with
/// `redirectURI` registered on it.
@MainActor
@Observable
final class SpotifyAccount {
    enum Status: Equatable {
        case signedOut
        case signingIn
        case signedIn(name: String)
        case failed(String)
    }

    nonisolated static let callbackPort: UInt16 = 43821
    nonisolated static let redirectURI = "http://127.0.0.1:\(callbackPort)/callback"
    static let scopes = [
        "user-library-read", "user-library-modify",
        "playlist-read-private", "playlist-read-collaborative",
        "playlist-modify-public", "playlist-modify-private",
        "user-read-recently-played",
        // Home's Artists and For You categories.
        "user-follow-read", "user-top-read",
    ]
    private static let clientIDKey = "spotifyClientID"

    private(set) var status: Status = .signedOut
    var clientID: String {
        didSet { UserDefaults.standard.set(clientID.trimmingCharacters(in: .whitespacesAndNewlines), forKey: Self.clientIDKey) }
    }

    /// Whether each track URI is in Liked Songs; missing while unknown.
    private(set) var saved: [String: Bool] = [:]
    /// Playlists the user can add to: their own and collaborative ones.
    private(set) var playlists: [Playlist] = []
    private(set) var isLoadingPlaylists = false
    private(set) var recent: [RecentTrack] = []
    private(set) var notice: Notice?

    var isSignedIn: Bool { if case .signedIn = status { true } else { false } }

    @ObservationIgnored private(set) var api: SpotifyWebAPI?
    @ObservationIgnored private(set) var userID: String?
    @ObservationIgnored private var signInTask: Task<Void, Never>?
    @ObservationIgnored private var noticeTask: Task<Void, Never>?
    @ObservationIgnored private var playlistsLoadedAt = Date.distantPast
    @ObservationIgnored private let logger = Logger(subsystem: "com.hoventan.SpotifyCompanion", category: "Account")
    @ObservationIgnored private var isPreview = false

    init() {
        clientID = UserDefaults.standard.string(forKey: Self.clientIDKey) ?? ""
    }

    /// Only Spotify tracks can be liked or added; local files and ads can't.
    static func isLibraryTrack(_ uri: String?) -> Bool {
        uri?.hasPrefix("spotify:track:") == true
    }

    // MARK: Sign-in

    /// Picks up the session saved in the keychain, if any.
    func restore() {
        guard !isPreview, api == nil, !clientID.isEmpty else { return }
        let clientID = clientID
        signInTask?.cancel()
        signInTask = Task {
            // Off the main thread: this read waits on any keychain prompt.
            guard let token = await Keychain.read(SpotifyWebAPI.refreshTokenKey),
                  !Task.isCancelled, api == nil else { return }
            status = .signingIn
            await finishSignIn(SpotifyWebAPI(clientID: clientID, refreshToken: token))
        }
    }

    func signIn() {
        let clientID = clientID.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !isPreview, !clientID.isEmpty else { return }
        signInTask?.cancel()
        status = .signingIn

        signInTask = Task {
            let pkce = PKCE()
            var components = URLComponents(string: "https://accounts.spotify.com/authorize")!
            components.queryItems = [
                URLQueryItem(name: "response_type", value: "code"),
                URLQueryItem(name: "client_id", value: clientID),
                URLQueryItem(name: "scope", value: Self.scopes.joined(separator: " ")),
                URLQueryItem(name: "redirect_uri", value: Self.redirectURI),
                URLQueryItem(name: "code_challenge_method", value: "S256"),
                URLQueryItem(name: "code_challenge", value: pkce.challenge),
                URLQueryItem(name: "state", value: pkce.state),
            ]
            do {
                let server = OAuthCallbackServer()
                let callback = Task { try await server.waitForCallback(port: Self.callbackPort) }
                // Give the listener a moment to bind before the browser can come back.
                try await Task.sleep(for: .milliseconds(150))
                NSWorkspace.shared.open(components.url!)

                // Five minutes to finish in the browser.
                let timeout = Task {
                    try await Task.sleep(for: .seconds(300))
                    callback.cancel()
                }
                defer { timeout.cancel() }
                let query = try await withTaskCancellationHandler {
                    try await callback.value
                } onCancel: {
                    callback.cancel()
                }

                guard query["state"] == pkce.state else { throw WebAPIError.http(400, "Sign-in reply didn’t match. Try again.") }
                guard let code = query["code"] else {
                    throw WebAPIError.http(400, query["error"] == "access_denied" ? "Access wasn’t granted." : "Sign-in failed: \(query["error"] ?? "no code").")
                }
                let tokens = try await SpotifyWebAPI.exchange(code: code, verifier: pkce.verifier, clientID: clientID, redirectURI: Self.redirectURI)
                guard let refresh = tokens.refresh_token else { throw WebAPIError.http(400, "Spotify returned no refresh token.") }
                Keychain.write(refresh, for: SpotifyWebAPI.refreshTokenKey)
                await finishSignIn(SpotifyWebAPI(clientID: clientID, refreshToken: refresh, accessToken: tokens.access_token, expiresIn: tokens.expires_in))
                NSApp.activate()
            } catch is CancellationError {
                if status == .signingIn { status = .signedOut }
            } catch {
                fail(error)
            }
        }
    }

    func cancelSignIn() {
        signInTask?.cancel()
        signInTask = nil
        if status == .signingIn { status = api == nil ? .signedOut : status }
    }

    func signOut() {
        signInTask?.cancel()
        Keychain.delete(SpotifyWebAPI.refreshTokenKey)
        api = nil
        userID = nil
        saved = [:]
        playlists = []
        recent = []
        playlistsLoadedAt = .distantPast
        status = .signedOut
    }

    private func finishSignIn(_ api: SpotifyWebAPI) async {
        do {
            let user = try await api.decode(APIUser.self, "GET", "me")
            guard !Task.isCancelled else { return }
            self.api = api
            userID = user.id
            status = .signedIn(name: user.display_name ?? user.id)
            logger.info("Signed in to Spotify")
            await loadRecent()
        } catch {
            fail(error)
        }
    }

    private func fail(_ error: Error) {
        logger.error("Account: \(error.localizedDescription, privacy: .public)")
        if error as? WebAPIError == .sessionExpired { signOut() }
        status = .failed(error.localizedDescription)
    }

    // MARK: Liked Songs

    /// Looks up whether `uri` is liked, once per track.
    func checkSaved(_ uri: String?) {
        guard let uri, Self.isLibraryTrack(uri), saved[uri] == nil, let api else { return }
        Task {
            do {
                let data = try await api.send("GET", "me/library/contains", query: [URLQueryItem(name: "uris", value: uri)])
                if let flag = try JSONDecoder().decode([Bool].self, from: data).first { saved[uri] = flag }
            } catch {
                logger.error("Library check failed: \(error.localizedDescription, privacy: .public)")
            }
        }
    }

    /// Likes or unlikes at once on screen; puts it back if Spotify says no.
    func toggleSaved(_ uri: String) {
        guard Self.isLibraryTrack(uri), let api else { return }
        let wasSaved = saved[uri] ?? false
        saved[uri] = !wasSaved
        Task {
            do {
                _ = try await api.send(wasSaved ? "DELETE" : "PUT", "me/library", query: [URLQueryItem(name: "uris", value: uri)])
                post(Notice(icon: wasSaved ? "heart.slash" : "heart.fill", text: wasSaved ? "Removed from Liked Songs" : "Added to Liked Songs"))
            } catch {
                saved[uri] = wasSaved
                post(Notice(icon: "exclamationmark.triangle", text: error.localizedDescription, isError: true))
            }
        }
    }

    // MARK: Playlists

    /// Refreshes the addable playlists at most once a minute.
    func loadPlaylists(force: Bool = false) {
        guard let api, let userID, !isLoadingPlaylists,
              force || Date().timeIntervalSince(playlistsLoadedAt) > 60 else { return }
        isLoadingPlaylists = true
        Task {
            defer { isLoadingPlaylists = false }
            do {
                var found: [Playlist] = []
                var offset = 0
                // Up to 200 playlists, 50 at a time.
                for _ in 0..<4 {
                    let page = try await api.decode(APIPlaylistPage.self, "GET", "me/playlists", query: [
                        URLQueryItem(name: "limit", value: "50"),
                        URLQueryItem(name: "offset", value: String(offset)),
                    ])
                    found += page.items.compactMap { $0 }
                        .filter { $0.owner.id == userID || $0.collaborative == true }
                        .map { Playlist(id: $0.id, name: $0.name, imageURL: bestImageURL($0.images, minimum: 60), total: ($0.items ?? $0.tracks)?.total) }
                    guard page.next != nil else { break }
                    offset += 50
                }
                playlists = found
                playlistsLoadedAt = Date()
            } catch {
                post(Notice(icon: "exclamationmark.triangle", text: error.localizedDescription, isError: true))
            }
        }
    }

    func add(_ uri: String, to playlist: Playlist) {
        guard Self.isLibraryTrack(uri), let api else { return }
        Task {
            do {
                let body = try JSONSerialization.data(withJSONObject: ["uris": [uri]])
                _ = try await api.send("POST", "playlists/\(playlist.id)/items", json: body)
                post(Notice(icon: "text.badge.checkmark", text: "Added to \(playlist.name)"))
            } catch {
                post(Notice(icon: "exclamationmark.triangle", text: error.localizedDescription, isError: true))
            }
        }
    }

    // MARK: Recently played

    func loadRecent() async {
        guard let api else { return }
        do {
            let page = try await api.decode(APIRecentlyPlayed.self, "GET", "me/player/recently-played", query: [
                URLQueryItem(name: "limit", value: "30"),
            ])
            var seen = Set<String>()
            recent = page.items.compactMap(\.track)
                .filter { seen.insert($0.uri).inserted }
                .prefix(12)
                .map { track in
                    RecentTrack(
                        uri: track.uri,
                        name: track.name,
                        artist: track.artists.map(\.name).joined(separator: ", "),
                        imageURL: bestImageURL(track.album?.images, minimum: 200)
                    )
                }
        } catch {
            logger.error("Recently played failed: \(error.localizedDescription, privacy: .public)")
        }
    }

    // MARK: Notices

    func post(_ notice: Notice) {
        self.notice = notice
        noticeTask?.cancel()
        noticeTask = Task {
            try? await Task.sleep(for: .seconds(notice.isError ? 4.5 : 2.6))
            guard !Task.isCancelled else { return }
            self.notice = nil
        }
    }
}

#if DEBUG
extension SpotifyAccount {
    /// An account with fixed data that never touches the network.
    static func preview(signedIn: Bool = true) -> SpotifyAccount {
        let account = SpotifyAccount()
        account.isPreview = true
        guard signedIn else { return account }
        account.status = .signedIn(name: "Preview")
        account.saved = [Track.preview.id: true]
        account.playlists = [
            Playlist(id: "1", name: "Late Night Grids", imageURL: nil, total: 42),
            Playlist(id: "2", name: "Running", imageURL: nil, total: 18),
            Playlist(id: "3", name: "Shared with Bea", imageURL: nil, total: 77),
        ]
        account.recent = [
            ("Akzidenz", "Berthold"), ("Neue Haas", "Max Miedinger"), ("Univers 55", "Adrian Frutiger"),
            ("Bauhaus Morning", "Herbert Bayer"), ("Grid Systems", "Josef Müller-Brockmann"), ("Red Square", "El Lissitzky"),
        ].enumerated().map { index, item in
            RecentTrack(uri: "spotify:track:preview\(index)", name: item.0, artist: item.1, imageURL: nil)
        }
        return account
    }
}
#endif
