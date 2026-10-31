import AppKit
import Observation

/// Downloads the current cover, extracts its palette for "Album Colors", and keeps a tiny
/// pre-blurred copy for "Album Blur".
@MainActor
@Observable
final class ArtworkStore {
    private(set) var image: NSImage?
    /// The URL `image` was loaded from; views key their crossfade on it.
    private(set) var imageURL: URL?
    private(set) var palette: Palette?
    private(set) var thumbnail: NSImage?

    private struct Entry {
        let image: NSImage
        let palette: Palette?
        let thumbnail: NSImage?
    }

    @ObservationIgnored private var requestedURL: URL?
    @ObservationIgnored private var task: Task<Void, Never>?
    @ObservationIgnored private var cache: [URL: Entry] = [:]

    func load(_ url: URL?) {
        guard url != requestedURL else { return }
        requestedURL = url
        task?.cancel()

        guard let url else {
            show(nil, from: nil)
            return
        }
        if let entry = cache[url] {
            show(entry, from: url)
            return
        }

        // Keep the previous cover on screen until the new one is ready, then crossfade.
        task = Task {
            do {
                let (data, _) = try await URLSession.shared.data(from: url)
                let (palette, small) = await Task.detached(priority: .userInitiated) {
                    (PaletteExtractor.palette(from: data), PaletteExtractor.blurredBackdrop(from: data))
                }.value
                guard !Task.isCancelled, let image = NSImage(data: data) else { return }
                let entry = Entry(image: image, palette: palette, thumbnail: small.map { NSImage(cgImage: $0, size: .zero) })
                if cache.count > 50 { cache.removeAll() }
                cache[url] = entry
                show(entry, from: url)
            } catch {
                // Offline or cancelled: leave the last cover in place.
            }
        }
    }

    private func show(_ entry: Entry?, from url: URL?) {
        image = entry?.image
        imageURL = url
        thumbnail = entry?.thumbnail
        if palette != entry?.palette { palette = entry?.palette }
    }
}
