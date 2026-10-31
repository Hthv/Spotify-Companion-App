import AppKit
import Observation
import os

/// Reads and controls the Spotify desktop app over AppleScript.
///
/// Polls every second, refreshes at once on Spotify's own `PlaybackStateChanged`
/// notification, and extrapolates the playback position between polls so the
/// progress bar can move every frame.
@MainActor
@Observable
final class SpotifyService {
    enum Connection: Equatable {
        case connecting, notInstalled, notRunning, permissionDenied, connected
    }

    static let bundleID = "com.spotify.client"

    private(set) var connection: Connection = .connecting
    private(set) var state: PlayerState = .stopped
    private(set) var track: Track?
    private(set) var volume = 0
    private(set) var isShuffling = false
    private(set) var isRepeating = false

    var isPlaying: Bool { state == .playing }

    /// Last known position and the moment it was true; `position(at:)` extrapolates from it.
    private var anchorPosition: TimeInterval = 0
    private var anchorDate = Date()

    @ObservationIgnored private let runner = AppleScriptRunner()
    @ObservationIgnored private let logger = Logger(subsystem: "com.hoventan.SpotifyCompanion", category: "Spotify")
    @ObservationIgnored private var pollTask: Task<Void, Never>?
    @ObservationIgnored private var observers: [(NotificationCenter, NSObjectProtocol)] = []
    /// Bumped by every command, so a poll that started before it can't undo its optimistic update.
    @ObservationIgnored private var commandGeneration = 0
    /// Preview instances show fixed data and never talk to Spotify.
    @ObservationIgnored private var isPreview = false
    @ObservationIgnored private var volumeBeforeMute: Int?

    /// Values a command just set locally, which polls must not undo while Spotify catches up.
    private struct Expected {
        var state: PlayerState?
        var position: TimeInterval?
        var volume: Int?
        var isShuffling: Bool?
        var isRepeating: Bool?
        var deadline = Date.distantPast
    }

    @ObservationIgnored private var expected = Expected()

    // MARK: Lifecycle

    func start() {
        guard pollTask == nil, !isPreview else { return }
        observe(DistributedNotificationCenter.default(), Notification.Name("com.spotify.client.PlaybackStateChanged"))
        observe(NSWorkspace.shared.notificationCenter, NSWorkspace.didLaunchApplicationNotification)
        observe(NSWorkspace.shared.notificationCenter, NSWorkspace.didTerminateApplicationNotification)

        pollTask = Task { [weak self] in
            while !Task.isCancelled {
                guard let self else { return }
                await self.refresh()
                try? await Task.sleep(for: self.connection == .connected ? .seconds(1) : .seconds(2))
            }
        }
    }

    func stop() {
        pollTask?.cancel()
        pollTask = nil
        for (center, token) in observers { center.removeObserver(token) }
        observers.removeAll()
    }

    private func observe(_ center: NotificationCenter, _ name: Notification.Name) {
        let token = center.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.scheduleRefresh() }
        }
        observers.append((center, token))
    }

    private func scheduleRefresh() {
        Task { await refresh() }
    }

    // MARK: Reading

    /// Playback position at `date`, extrapolated while playing.
    func position(at date: Date) -> TimeInterval {
        guard let track else { return 0 }
        let elapsed = state == .playing ? max(0, date.timeIntervalSince(anchorDate)) : 0
        let position = anchorPosition + elapsed
        return track.duration > 0 ? min(position, track.duration) : position
    }

    func refresh() async {
        guard Self.isRunning else {
            setConnection(Self.isInstalled ? .notRunning : .notInstalled)
            clearPlayback()
            return
        }

        let generation = commandGeneration
        do {
            let snapshot = try await runner.run(PlayerSnapshot.script, cache: true) {
                try PlayerSnapshot(descriptor: $0)
            }
            guard generation == commandGeneration else { return }
            apply(snapshot)
        } catch let error as AppleScriptError where error.isPermissionDenied {
            setConnection(.permissionDenied)
            clearPlayback()
        } catch {
            logger.error("Refresh failed: \(String(describing: error), privacy: .public)")
        }
    }

    private func apply(_ snapshot: PlayerSnapshot) {
        guard snapshot.isRunning else {
            setConnection(.notRunning)
            clearPlayback()
            return
        }
        setConnection(.connected)

        let predicted = position(at: snapshot.capturedAt)
        let trackChanged = track != snapshot.track
        if trackChanged { expected = Expected() }

        // Right after a command Spotify can still report the old value for a moment.
        // Keep the optimistic value until Spotify agrees or the hold expires.
        let holding = Date() < expected.deadline
        let acceptState = Self.accept(snapshot.state, &expected.state, holding: holding)
        let acceptPosition = Self.accept(snapshot.position, &expected.position, holding: holding) {
            abs($0 - $1) < 1.5
        }

        let stateChanged = acceptState && state != snapshot.state

        // Observation fires on every assignment, so only write what changed.
        if trackChanged { track = snapshot.track }
        if stateChanged { state = snapshot.state }
        if Self.accept(snapshot.volume, &expected.volume, holding: holding), volume != snapshot.volume {
            volume = snapshot.volume
        }
        if Self.accept(snapshot.isShuffling, &expected.isShuffling, holding: holding), isShuffling != snapshot.isShuffling {
            isShuffling = snapshot.isShuffling
        }
        if Self.accept(snapshot.isRepeating, &expected.isRepeating, holding: holding), isRepeating != snapshot.isRepeating {
            isRepeating = snapshot.isRepeating
        }

        if trackChanged || stateChanged {
            logger.info("\(snapshot.state.rawValue, privacy: .public): \(snapshot.track?.name ?? "-", privacy: .public) at \(snapshot.position, format: .fixed(precision: 1), privacy: .public)s")
        }

        // Re-anchor only on real drift; tiny corrections would make the bar jitter.
        if acceptState, acceptPosition,
           trackChanged || stateChanged || abs(predicted - snapshot.position) > 0.35 {
            anchorPosition = snapshot.position
            anchorDate = snapshot.capturedAt
        }
    }

    /// Whether a polled value may replace the local one. While `holding`, a value that
    /// disagrees with the expectation is stale; one that agrees clears the expectation.
    private nonisolated static func accept<T>(
        _ polled: T,
        _ expectation: inout T?,
        holding: Bool,
        matches: (T, T) -> Bool
    ) -> Bool {
        guard holding, let wanted = expectation else {
            expectation = nil
            return true
        }
        if matches(polled, wanted) {
            expectation = nil
            return true
        }
        return false
    }

    private nonisolated static func accept<T: Equatable>(_ polled: T, _ expectation: inout T?, holding: Bool) -> Bool {
        accept(polled, &expectation, holding: holding) { $0 == $1 }
    }

    /// Starts a hold window for the values a command just changed locally.
    private func expect(_ change: (inout Expected) -> Void) {
        change(&expected)
        expected.deadline = Date().addingTimeInterval(1.2)
    }

    private func setConnection(_ new: Connection) {
        guard connection != new else { return }
        logger.info("Connection: \(String(describing: new), privacy: .public)")
        connection = new
    }

    private func clearPlayback() {
        if track != nil { track = nil }
        if state != .stopped { state = .stopped }
        if anchorPosition != 0 { anchorPosition = 0 }
    }

    // MARK: Controls

    func playPause() {
        guard connection == .connected else { return }
        let now = Date()
        anchorPosition = position(at: now)
        anchorDate = now
        state = isPlaying ? .paused : .playing
        expect { $0.state = state }
        send("playpause")
    }

    func nextTrack() {
        guard connection == .connected else { return }
        send("next track")
    }

    func previousTrack() {
        guard connection == .connected else { return }
        send("previous track")
    }

    func seek(to seconds: TimeInterval) {
        guard connection == .connected, let track else { return }
        let target = min(max(seconds, 0), track.duration)
        anchorPosition = target
        anchorDate = Date()
        expect { $0.position = target }
        // String(format:) is locale-independent, so the decimal separator is always ".".
        send("set player position to \(String(format: "%.3f", target))")
    }

    func seek(by seconds: TimeInterval) {
        seek(to: position(at: Date()) + seconds)
    }

    func setVolume(_ value: Int) {
        guard connection == .connected else { return }
        let clamped = min(max(value, 0), 100)
        guard clamped != volume else { return }
        if clamped > 0 { volumeBeforeMute = nil }
        volume = clamped
        expect { $0.volume = clamped }
        send("set sound volume to \(clamped)")
    }

    func changeVolume(by step: Int) {
        setVolume(volume + step)
    }

    /// Mutes, or restores the volume from before muting.
    func toggleMute() {
        if volume > 0 {
            let previous = volume
            setVolume(0)
            volumeBeforeMute = previous
        } else {
            setVolume(volumeBeforeMute ?? 50)
        }
    }

    func toggleShuffle() {
        guard connection == .connected else { return }
        isShuffling.toggle()
        expect { $0.isShuffling = isShuffling }
        send("set shuffling to \(isShuffling)")
    }

    func toggleRepeat() {
        guard connection == .connected else { return }
        isRepeating.toggle()
        expect { $0.isRepeating = isRepeating }
        send("set repeating to \(isRepeating)")
    }

    /// Starts a track by URI, e.g. from the recently played list.
    func play(uri: String) {
        // The URI goes into AppleScript source, so only let through what a Spotify URI can contain.
        guard uri.hasPrefix("spotify:"), uri.allSatisfy({ $0.isASCII && ($0.isLetter || $0.isNumber || $0 == ":") }) else { return }
        expect { $0.state = .playing }
        send("play track \"\(uri)\"")
    }

    private func send(_ command: String) {
        guard !isPreview else { return }
        commandGeneration += 1
        let source = """
        if application id "\(Self.bundleID)" is running then
            tell application id "\(Self.bundleID)" to \(command)
        end if
        """
        Task {
            do {
                try await runner.run(source) { _ in }
                logger.info("Sent '\(command, privacy: .public)'")
            } catch let error as AppleScriptError where error.isPermissionDenied {
                setConnection(.permissionDenied)
            } catch {
                logger.error("Command '\(command, privacy: .public)' failed: \(String(describing: error), privacy: .public)")
            }
            await refresh()
        }
    }

    // MARK: Spotify app

    static var isRunning: Bool {
        !NSRunningApplication.runningApplications(withBundleIdentifier: bundleID).isEmpty
    }

    static var isInstalled: Bool {
        NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) != nil
    }

    /// Brings the Spotify window to the front.
    func showSpotify() {
        NSRunningApplication.runningApplications(withBundleIdentifier: Self.bundleID).first?.activate()
    }

    func openSpotify() {
        guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: Self.bundleID) else { return }
        NSWorkspace.shared.openApplication(at: url, configuration: NSWorkspace.OpenConfiguration(), completionHandler: nil)
    }

    func openAutomationSettings() {
        guard let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Automation") else { return }
        NSWorkspace.shared.open(url)
    }
}

#if DEBUG
extension SpotifyService {
    /// A service frozen in one state, for SwiftUI previews.
    static func preview(
        _ connection: Connection = .connected,
        track: Track? = .preview,
        state: PlayerState = .playing,
        position: TimeInterval = 83
    ) -> SpotifyService {
        let service = SpotifyService()
        service.isPreview = true
        if connection == .connected {
            service.apply(PlayerSnapshot(state: track == nil ? .stopped : state, track: track, position: position, volume: 70, isShuffling: true))
        } else {
            service.connection = connection
        }
        return service
    }
}

extension Track {
    static let preview = Track(
        id: "spotify:track:preview",
        name: "Grotesk in Red and Black",
        artist: "Josef Müller-Brockmann",
        album: "Grid Systems",
        artworkURL: nil,
        duration: 247
    )
}
#endif
