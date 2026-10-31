import Foundation

struct AppleScriptError: Error, Sendable, CustomStringConvertible {
    let code: Int
    let message: String

    init(code: Int, message: String) {
        self.code = code
        self.message = message
    }

    init(_ info: NSDictionary) {
        code = (info[NSAppleScript.errorNumber] as? NSNumber)?.intValue ?? -1
        message = info[NSAppleScript.errorMessage] as? String ?? "Unknown AppleScript error"
    }

    /// The user denied Automation access to Spotify (errAEEventNotPermitted),
    /// or it can't be asked for right now (errAEEventWouldRequireUserConsent).
    var isPermissionDenied: Bool { code == -1743 || code == -1744 }

    var description: String { "AppleScript error \(code): \(message)" }
}

/// Runs AppleScript on a private serial queue so a slow or hung Spotify never blocks the UI.
final class AppleScriptRunner: @unchecked Sendable {
    private let queue = DispatchQueue(label: "SpotifyCompanion.AppleScript", qos: .userInitiated)
    /// Compiled scripts keyed by source. Only touched on `queue`.
    private var compiled: [String: NSAppleScript] = [:]

    /// Executes `source` and converts the reply with `parse`, both on the script queue.
    /// Pass `cache: true` for scripts that run repeatedly, so they compile once.
    func run<T: Sendable>(
        _ source: String,
        cache: Bool = false,
        parse: @escaping @Sendable (NSAppleEventDescriptor) throws -> T
    ) async throws -> T {
        try await withCheckedThrowingContinuation { continuation in
            queue.async {
                continuation.resume(with: Result { try parse(self.execute(source, cache: cache)) })
            }
        }
    }

    private func execute(_ source: String, cache: Bool) throws -> NSAppleEventDescriptor {
        let script: NSAppleScript
        if let cached = compiled[source] {
            script = cached
        } else {
            guard let fresh = NSAppleScript(source: source) else {
                throw AppleScriptError(code: -2700, message: "Could not create script")
            }
            var error: NSDictionary?
            guard fresh.compileAndReturnError(&error) else {
                throw error.map(AppleScriptError.init) ?? AppleScriptError(code: -2700, message: "Could not compile script")
            }
            if cache { compiled[source] = fresh }
            script = fresh
        }

        var error: NSDictionary?
        let result = script.executeAndReturnError(&error)
        if let error { throw AppleScriptError(error) }
        return result
    }
}
