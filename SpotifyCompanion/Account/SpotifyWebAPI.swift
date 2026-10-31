import Foundation

enum WebAPIError: LocalizedError, Equatable {
    case http(Int, String)
    case rateLimited(retryAfter: Int?, quotaExceeded: Bool)
    /// The refresh token was revoked or expired: sign in again.
    case sessionExpired

    var errorDescription: String? {
        switch self {
        case .http(403, let message) where message.localizedCaseInsensitiveContains("not registered"):
            "Add your Spotify account under User Management in the developer dashboard."
        case .http(_, let message): message
        case .rateLimited(_, true): "Spotify’s daily quota for this Client ID is used up."
        case .rateLimited(let seconds?, false): "Spotify asked to slow down. Try again in \(seconds) s."
        case .rateLimited: "Spotify asked to slow down. Try again shortly."
        case .sessionExpired: "Spotify sign-in expired. Connect again."
        }
    }
}

struct TokenResponse: Decodable, Sendable {
    let access_token: String
    let expires_in: Int
    let refresh_token: String?
}

/// Talks to api.spotify.com with a bearer token, refreshing it when it's about to expire
/// (or the API says it has) and storing each new refresh token in the keychain.
actor SpotifyWebAPI {
    static let refreshTokenKey = "spotify-refresh-token"

    let clientID: String
    private var accessToken: String?
    private var expiry = Date.distantPast
    private var refreshToken: String
    private var refreshTask: Task<String, Error>?

    private static let base = URL(string: "https://api.spotify.com/v1/")!
    private static let tokenURL = URL(string: "https://accounts.spotify.com/api/token")!

    init(clientID: String, refreshToken: String, accessToken: String? = nil, expiresIn: Int = 0) {
        self.clientID = clientID
        self.refreshToken = refreshToken
        self.accessToken = accessToken
        self.expiry = Date().addingTimeInterval(TimeInterval(expiresIn))
    }

    func send(_ method: String, _ path: String, query: [URLQueryItem] = [], json: Data? = nil) async throws -> Data {
        var components = URLComponents(url: Self.base.appendingPathComponent(path), resolvingAgainstBaseURL: false)!
        if !query.isEmpty {
            // Spotify URIs carry colons; encode them, keep commas as list separators.
            var allowed = CharacterSet.urlQueryAllowed
            allowed.remove(charactersIn: ":&=+")
            components.percentEncodedQuery = query
                .map { "\($0.name)=\($0.value?.addingPercentEncoding(withAllowedCharacters: allowed) ?? "")" }
                .joined(separator: "&")
        }
        var request = URLRequest(url: components.url!, timeoutInterval: 15)
        request.httpMethod = method
        if let json {
            request.httpBody = json
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        }

        for attempt in 0..<2 {
            request.setValue("Bearer \(try await validToken(forceRefresh: attempt > 0))", forHTTPHeaderField: "Authorization")
            let (data, response) = try await URLSession.shared.data(for: request)
            let status = (response as? HTTPURLResponse)?.statusCode ?? 0
            switch status {
            case 200..<300:
                return data
            case 401 where attempt == 0:
                continue
            case 429:
                let retryAfter = (response as? HTTPURLResponse)?.value(forHTTPHeaderField: "Retry-After").flatMap(Int.init)
                let quota = String(data: data, encoding: .utf8)?.contains("QUOTA_EXCEEDED") ?? false
                throw WebAPIError.rateLimited(retryAfter: retryAfter, quotaExceeded: quota)
            default:
                throw WebAPIError.http(status, Self.message(from: data) ?? HTTPURLResponse.localizedString(forStatusCode: status))
            }
        }
        throw WebAPIError.http(401, "Spotify rejected the sign-in.")
    }

    func decode<T: Decodable>(_ type: T.Type, _ method: String = "GET", _ path: String, query: [URLQueryItem] = []) async throws -> T {
        try JSONDecoder().decode(T.self, from: try await send(method, path, query: query))
    }

    private func validToken(forceRefresh: Bool) async throws -> String {
        if !forceRefresh, let accessToken, expiry.timeIntervalSinceNow > 60 { return accessToken }
        if let refreshTask { return try await refreshTask.value }
        // One refresh at a time; concurrent requests wait on it.
        let task = Task<String, Error> {
            defer { refreshTask = nil }
            let response = try await Self.token([
                "grant_type": "refresh_token", "refresh_token": refreshToken, "client_id": clientID,
            ])
            accessToken = response.access_token
            expiry = Date().addingTimeInterval(TimeInterval(response.expires_in))
            // Spotify may rotate the refresh token; the old one then stops working.
            if let rotated = response.refresh_token, rotated != refreshToken {
                refreshToken = rotated
                Keychain.write(rotated, for: Self.refreshTokenKey)
            }
            return response.access_token
        }
        refreshTask = task
        return try await task.value
    }

    static func exchange(code: String, verifier: String, clientID: String, redirectURI: String) async throws -> TokenResponse {
        try await token([
            "grant_type": "authorization_code",
            "code": code,
            "redirect_uri": redirectURI,
            "client_id": clientID,
            "code_verifier": verifier,
        ])
    }

    private static func token(_ form: [String: String]) async throws -> TokenResponse {
        var request = URLRequest(url: tokenURL, timeoutInterval: 15)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        var allowed = CharacterSet.alphanumerics
        allowed.insert(charactersIn: "-._~")
        request.httpBody = Data(form
            .map { "\($0.key)=\($0.value.addingPercentEncoding(withAllowedCharacters: allowed) ?? "")" }
            .joined(separator: "&").utf8)
        let (data, response) = try await URLSession.shared.data(for: request)
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        guard status == 200 else {
            let error = (try? JSONDecoder().decode([String: String].self, from: data)) ?? [:]
            if error["error"] == "invalid_grant", form["grant_type"] == "refresh_token" { throw WebAPIError.sessionExpired }
            throw WebAPIError.http(status, error["error_description"] ?? error["error"] ?? "Sign-in failed (\(status)).")
        }
        return try JSONDecoder().decode(TokenResponse.self, from: data)
    }

    /// `{"error": {"status": 403, "message": "…"}}`
    private static func message(from data: Data) -> String? {
        struct Body: Decodable {
            struct Inner: Decodable { let message: String? }
            let error: Inner?
        }
        return (try? JSONDecoder().decode(Body.self, from: data))?.error?.message
    }
}

// MARK: Response shapes (only the fields the app reads)

struct APIUser: Decodable, Sendable {
    let id: String
    let display_name: String?
}

struct APIImage: Decodable, Sendable {
    let url: String
    let width: Int?
}

struct APIPlaylistPage: Decodable, Sendable {
    struct Item: Decodable, Sendable {
        struct Owner: Decodable, Sendable { let id: String }
        /// Renamed from `tracks` in February 2026; both decoded so either shape works.
        struct ItemsRef: Decodable, Sendable { let total: Int? }
        let id: String
        let name: String
        let owner: Owner
        let collaborative: Bool?
        let images: [APIImage]?
        let items: ItemsRef?
        let tracks: ItemsRef?
    }
    let items: [Item?]
    let next: String?
}

struct APIRecentlyPlayed: Decodable, Sendable {
    struct Item: Decodable, Sendable {
        struct TrackObject: Decodable, Sendable {
            struct Artist: Decodable, Sendable { let name: String }
            struct Album: Decodable, Sendable {
                let name: String?
                let images: [APIImage]?
            }
            let uri: String
            let name: String
            let artists: [Artist]
            let album: Album?
        }
        let track: TrackObject?
    }
    let items: [Item]
}

/// Picks the smallest image at least `minimum` px wide, else the largest there is.
func bestImageURL(_ images: [APIImage]?, minimum: Int = 160) -> URL? {
    guard let images, !images.isEmpty else { return nil }
    let sorted = images.sorted { ($0.width ?? 0) < ($1.width ?? 0) }
    let pick = sorted.first { ($0.width ?? 0) >= minimum } ?? sorted.last!
    return URL(string: pick.url)
}
