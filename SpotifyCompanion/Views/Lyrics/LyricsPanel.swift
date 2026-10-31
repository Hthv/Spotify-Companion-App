import SwiftUI

/// Lyrics for the current track in whatever form LRCLIB has them, with icon-led empty states.
/// When there are none, or they're slow to come, the player hides this panel and shows a
/// `LyricsNote` beside the cover instead.
struct LyricsPanel: View {
    let track: Track

    @Environment(LyricsStore.self) private var store
    @Environment(\.theme) private var theme

    var body: some View {
        ZStack(alignment: .topLeading) {
            switch store.state {
            case .idle, .loading, .failed:
                LyricsMessage(icon: "ellipsis", text: nil, animated: true)
            case .loaded(.synced(let lines)):
                SyncedLyricsView(items: LyricItem.items(from: lines, duration: track.duration))
            case .loaded(.plain(let lines)):
                PlainLyricsView(lines: lines)
            case .loaded(.instrumental):
                LyricsMessage(icon: "pianokeys", text: "Instrumental")
            case .loaded(.notFound):
                LyricsMessage(icon: "text.badge.xmark", text: "No lyrics")
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .animation(theme.style.motion, value: store.state)
    }
}

private struct LyricsMessage: View {
    let icon: String
    let text: String?
    var animated = false

    @Environment(\.theme) private var theme

    var body: some View {
        VStack(alignment: theme.style.lyricAlignment, spacing: Metrics.unit * 2) {
            Image(systemName: icon)
                .font(.system(size: 34, weight: theme.style.iconWeight == .bold ? .semibold : theme.style.iconWeight))
                .symbolEffect(.variableColor.iterative, options: .repeating, isActive: animated)
            if let text {
                Text(text).font(theme.font(\.lyric, 22))
            }
        }
        .foregroundStyle(theme.secondary)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: Alignment(horizontal: theme.style.lyricAlignment, vertical: .center))
        .transition(.opacity)
    }
}

/// Unsynced lyrics: a plain scrolling column, with an icon saying there's no timing.
private struct PlainLyricsView: View {
    let lines: [String]
    @Environment(\.theme) private var theme

    var body: some View {
        ScrollView(.vertical, showsIndicators: false) {
            VStack(alignment: theme.style.lyricAlignment, spacing: 10) {
                Image(systemName: "clock.badge.xmark")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(theme.secondary)
                    .help("These lyrics aren’t time-synced")
                    .padding(.bottom, Metrics.unit)
                ForEach(Array(lines.enumerated()), id: \.offset) { _, line in
                    Text(line.isEmpty ? " " : line)
                        .font(theme.font(\.lyric, 24))
                        .multilineTextAlignment(theme.style.lyricTextAlignment)
                        .opacity(0.8)
                        .frame(maxWidth: .infinity, alignment: Alignment(horizontal: theme.style.lyricAlignment, vertical: .center))
                }
            }
            .padding(.vertical, Metrics.unit * 4)
        }
        .mask(LyricsFade())
        .transition(.opacity)
    }
}

/// Soft top and bottom edges, so lines dissolve rather than clip.
struct LyricsFade: View {
    var body: some View {
        LinearGradient(
            stops: [
                .init(color: .clear, location: 0),
                .init(color: .black, location: 0.12),
                .init(color: .black, location: 0.82),
                .init(color: .clear, location: 1),
            ],
            startPoint: .top,
            endPoint: .bottom
        )
    }
}
