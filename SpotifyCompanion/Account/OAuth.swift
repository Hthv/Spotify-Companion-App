import CryptoKit
import Foundation
import Network

/// Authorization Code with PKCE, the flow Spotify recommends for apps that can't keep a secret.
struct PKCE: Sendable {
    let verifier: String
    let challenge: String
    let state: String

    init() {
        verifier = Self.random(64)
        challenge = Data(SHA256.hash(data: Data(verifier.utf8))).base64URLEncoded
        state = Self.random(24)
    }

    /// Characters from the unreserved set RFC 7636 allows in a verifier.
    private static func random(_ length: Int) -> String {
        let alphabet = Array("ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-._~")
        var bytes = [UInt8](repeating: 0, count: length)
        _ = SecRandomCopyBytes(kSecRandomDefault, length, &bytes)
        return String(bytes.map { alphabet[Int($0) % alphabet.count] })
    }
}

extension Data {
    var base64URLEncoded: String {
        base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }
}

/// Listens on 127.0.0.1 for the one browser redirect that carries the authorization code.
/// Spotify requires loopback redirects to use an IP literal, not "localhost".
final class OAuthCallbackServer: @unchecked Sendable {
    enum Failure: LocalizedError {
        case portInUse
        var errorDescription: String? { "Port \(SpotifyAccount.callbackPort) is in use by another app." }
    }

    // Everything below is touched only on `queue`.
    private let queue = DispatchQueue(label: "com.hoventan.SpotifyCompanion.oauth")
    private var listener: NWListener?
    private var continuation: CheckedContinuation<[String: String], Error>?
    private var isFinished = false

    /// Waits for `GET /callback?...` and returns its query parameters.
    func waitForCallback(port: UInt16) async throws -> [String: String] {
        try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                queue.async { self.start(port: port, continuation: continuation) }
            }
        } onCancel: {
            queue.async { self.finish(.failure(CancellationError())) }
        }
    }

    private func start(port: UInt16, continuation: CheckedContinuation<[String: String], Error>) {
        guard !isFinished else {
            continuation.resume(throwing: CancellationError())
            return
        }
        self.continuation = continuation
        do {
            let parameters = NWParameters.tcp
            parameters.allowLocalEndpointReuse = true
            parameters.requiredLocalEndpoint = .hostPort(host: .ipv4(.loopback), port: NWEndpoint.Port(rawValue: port)!)
            let listener = try NWListener(using: parameters)
            listener.stateUpdateHandler = { [weak self] state in
                if case .failed(let error) = state {
                    let inUse: Bool = if case .posix(.EADDRINUSE) = error { true } else { false }
                    self?.finish(.failure(inUse ? Failure.portInUse : error))
                }
            }
            listener.newConnectionHandler = { [weak self] connection in self?.handle(connection) }
            listener.start(queue: queue)
            self.listener = listener
        } catch {
            finish(.failure(error))
        }
    }

    private func handle(_ connection: NWConnection) {
        connection.start(queue: queue)
        connection.receive(minimumIncompleteLength: 1, maximumLength: 16_384) { [weak self] data, _, _, _ in
            guard let self else { return }
            let request = data.flatMap { String(data: $0, encoding: .utf8) } ?? ""
            // "GET /callback?code=…&state=… HTTP/1.1"
            let target = request.split(separator: " ", maxSplits: 2).dropFirst().first.map(String.init) ?? ""
            guard let components = URLComponents(string: target), components.path == "/callback" else {
                self.respond(connection, status: "404 Not Found", body: "")
                return
            }
            var query: [String: String] = [:]
            for item in components.queryItems ?? [] { query[item.name] = item.value ?? "" }
            let succeeded = query["code"] != nil
            self.respond(connection, status: "200 OK", body: Self.page(succeeded: succeeded))
            self.finish(.success(query))
        }
    }

    private func respond(_ connection: NWConnection, status: String, body: String) {
        let response = "HTTP/1.1 \(status)\r\nContent-Type: text/html; charset=utf-8\r\nContent-Length: \(body.utf8.count)\r\nConnection: close\r\n\r\n\(body)"
        connection.send(content: Data(response.utf8), completion: .contentProcessed { _ in connection.cancel() })
    }

    private func finish(_ result: Result<[String: String], Error>) {
        guard !isFinished else { return }
        isFinished = true
        listener?.cancel()
        listener = nil
        continuation?.resume(with: result)
        continuation = nil
    }

    private static func page(succeeded: Bool) -> String {
        let message = succeeded ? "Connected. You can close this tab." : "Spotify didn’t grant access. You can close this tab."
        return """
        <!doctype html><meta charset="utf-8"><title>Spotify Companion</title>
        <body style="font:600 28px -apple-system,Helvetica;margin:15vh 10vw;background:#F2F1EC;color:#111">
        <div style="width:24px;height:24px;border-radius:50%;background:#DA291C;margin-bottom:24px"></div>\(message)</body>
        """
    }
}
