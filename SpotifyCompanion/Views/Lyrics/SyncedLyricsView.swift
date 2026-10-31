import AppKit
import SwiftUI

/// A lyric line, or an instrumental gap shown as breathing dots.
struct LyricItem: Identifiable, Equatable {
    enum Kind: Equatable {
        case line(String)
        case interlude
    }

    let id: Int
    let start: TimeInterval
    let end: TimeInterval
    let kind: Kind

    /// Empty LRC lines become interludes when the gap is long enough to notice;
    /// an intro before the first line gets one too.
    static func items(from lines: [LyricLine], duration: TimeInterval) -> [LyricItem] {
        var items: [LyricItem] = []
        func add(_ start: TimeInterval, _ end: TimeInterval, _ kind: Kind) {
            items.append(LyricItem(id: items.count, start: start, end: end, kind: kind))
        }

        if let first = lines.first, first.time >= 3 {
            add(0, first.time, .interlude)
        }
        for (index, line) in lines.enumerated() {
            let end = index + 1 < lines.count ? lines[index + 1].time : max(duration, line.time + 4)
            if line.text.isEmpty {
                if end - line.time >= 3 { add(line.time, end, .interlude) }
            } else {
                add(line.time, end, .line(line.text))
            }
        }
        return items
    }

    /// The last item that has started; lines light up a beat early, as they're read ahead.
    static func activeIndex(in items: [LyricItem], at position: TimeInterval) -> Int? {
        let target = position + 0.2
        var low = 0, high = items.count
        while low < high {
            let mid = (low + high) / 2
            if items[mid].start <= target { low = mid + 1 } else { high = mid }
        }
        return low == 0 ? nil : low - 1
    }
}

/// Apple Music style synced lyrics: the current line sits a third of the way down in full
/// color, the rest dim and soften with distance, and lines follow with a staggered spring.
/// Scroll to look around (blur lifts while you do); click any line to jump there.
struct SyncedLyricsView: View {
    let items: [LyricItem]

    @Environment(SpotifyService.self) private var spotify
    @Environment(\.theme) private var theme
    @State private var scroll = LyricsScrollModel()
    @State private var heights: [Int: CGFloat] = [:]

    private let spacing: CGFloat = 6

    var body: some View {
        GeometryReader { geometry in
            TimelineView(.animation(minimumInterval: 1 / 30, paused: !spotify.isPlaying)) { context in
                let position = spotify.position(at: context.date)
                lyrics(active: LyricItem.activeIndex(in: items, at: position), position: position, now: context.date, size: geometry.size)
            }
        }
        .clipped()
        // Clipping hides lines scrolled past the panel but leaves them clickable; without
        // this, earlier lines sitting under the header swallow clicks meant for it (and
        // seek back to themselves).
        .contentShape(Rectangle())
        .mask(LyricsFade())
        .onHover { scroll.isHovering = $0 }
        .onAppear { scroll.install() }
        .onDisappear { scroll.uninstall() }
        .transition(.opacity)
    }

    private func lyrics(active: Int?, position: TimeInterval, now: Date, size: CGSize) -> some View {
        let anchor = size.height * 0.3
        let activeTop = (0..<(active ?? 0)).reduce(CGFloat(0)) { $0 + (heights[$1] ?? 0) + spacing }
        let total = items.indices.reduce(CGFloat(0)) { $0 + (heights[$1] ?? 0) + spacing }
        let follow = anchor - activeTop
        // Manual scrolling may go from the first line at the anchor to the last line at the top.
        let range = (anchor - total)...anchor
        let offset = min(max(follow + scroll.manualOffset, range.lowerBound), range.upperBound)
        let fontSize = min(max(size.width * 0.065, 22), 36)

        return VStack(alignment: theme.style.lyricAlignment, spacing: spacing) {
            ForEach(items) { item in
                let distance = active.map { item.id - $0 } ?? item.id + 1
                LyricRow(
                    item: item,
                    distance: distance,
                    softened: !scroll.isScrolling,
                    progress: distance == 0 ? (position - item.start) / max(item.end - item.start, 0.1) : 0,
                    now: item.kind == .interlude && distance == 0 ? now : .distantPast,
                    fontSize: fontSize
                )
                .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { height in
                    // The first measurement lands at once; later ones (new type, a resize)
                    // move with the style's motion, in step with the lines resizing.
                    if heights.count >= items.count {
                        withAnimation(theme.style.motion) { heights[item.id] = height }
                    } else {
                        heights[item.id] = height
                    }
                }
                .offset(y: offset)
                // A new current line glides, with lines below following a little later like
                // a wave. Re-measured lines don't use this spring (see onGeometryChange), so
                // the lyrics never sweep in from the top.
                .animation(
                    scroll.isScrolling ? nil : .spring(response: 0.7, dampingFraction: 0.86)
                        .delay(distance > 0 ? Double(min(distance, 8)) * 0.035 : 0),
                    value: active
                )
            }
        }
        // Until every line has a height the offset is a guess; show nothing rather than a jump.
        .opacity(heights.count >= items.count ? 1 : 0)
        .frame(width: size.width, alignment: Alignment(horizontal: theme.style.lyricAlignment, vertical: .top))
        .fixedSize(horizontal: false, vertical: true)
        .frame(width: size.width, height: size.height, alignment: .top)
        .onChange(of: [range.lowerBound - follow, range.upperBound - follow], initial: true) { _, bounds in
            scroll.range = bounds[0]...bounds[1]
        }
    }
}

private struct LyricRow: View {
    let item: LyricItem
    /// 0 for the current line, negative above, positive below.
    let distance: Int
    let softened: Bool
    let progress: Double
    let now: Date
    let fontSize: CGFloat

    @Environment(SpotifyService.self) private var spotify
    @Environment(\.theme) private var theme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var isHovering = false

    private var isActive: Bool { distance == 0 }

    var body: some View {
        switch item.kind {
        case .line(let text):
            let alignment = theme.style.lyricAlignment
            Text(text)
                .font(theme.font(\.lyric, fontSize))
                .tracking(-fontSize * 0.01)
                .multilineTextAlignment(theme.style.lyricTextAlignment)
                .foregroundStyle(theme.foreground)
                .shadow(color: isActive && theme.style.titleEffect == .glow ? theme.accent.opacity(0.6) : .clear, radius: 12)
                .opacity(isActive ? 1 : (isHovering ? 0.65 : 0.28))
                .blur(radius: softened && !reduceMotion ? min(Double(abs(distance)) * 0.8, 3) : 0)
                .scaleEffect(isActive ? 1 : 0.96, anchor: alignment == .center ? .center : .leading)
                .frame(maxWidth: .infinity, alignment: Alignment(horizontal: alignment, vertical: .center))
                .padding(.vertical, 8)
                .padding(.horizontal, 12)
                .background(
                    RoundedRectangle(cornerRadius: max(theme.style.cornerRadius, 4), style: .continuous)
                        .fill(theme.foreground.opacity(isHovering ? 0.07 : 0))
                )
                .contentShape(Rectangle())
                .onHover { hovering in
                    withAnimation(.easeOut(duration: 0.15)) { isHovering = hovering }
                }
                .onTapGesture { spotify.seek(to: item.start) }
                .animation(.smooth(duration: 0.5), value: isActive)
                .animation(.smooth(duration: 0.4), value: softened)
                .accessibilityAddTraits(isActive ? [.isButton, .isSelected] : .isButton)
                .help("Play from here")
        case .interlude:
            InterludeDots(progress: progress, now: now, isActive: isActive, size: fontSize * 0.36)
                .padding(.horizontal, 12)
                .frame(maxWidth: .infinity, alignment: Alignment(horizontal: theme.style.lyricAlignment, vertical: .center))
        }
    }
}

/// Three dots that fill in turn across an instrumental gap, breathing, then shrink away
/// just before the next line.
private struct InterludeDots: View {
    let progress: Double
    let now: Date
    let isActive: Bool
    let size: CGFloat

    @Environment(\.theme) private var theme

    var body: some View {
        let breath = 1 + 0.08 * sin(now.timeIntervalSinceReferenceDate * .pi * 2 / 2.4)
        let ending = progress > 0.9
        HStack(spacing: size * 0.8) {
            ForEach(0..<3) { index in
                Circle()
                    .fill(theme.foreground)
                    .frame(width: size, height: size)
                    .opacity(0.25 + 0.75 * min(max(progress * 3 - Double(index), 0), 1))
            }
        }
        .scaleEffect(isActive ? (ending ? 0.6 : breath) : 0.4, anchor: theme.style.lyricAlignment == .center ? .center : .leading)
        .opacity(isActive && !ending ? 1 : 0)
        .frame(height: isActive ? size * 3 : 0)
        .animation(.smooth(duration: 0.45), value: isActive)
        .animation(.smooth(duration: 0.3), value: ending)
        .accessibilityHidden(true)
    }
}

/// Scroll-wheel handling for the hand-laid-out lyrics: a manual offset on top of the
/// follow position, which springs back a moment after the wheel stops.
@MainActor
@Observable
final class LyricsScrollModel {
    private(set) var manualOffset: CGFloat = 0
    private(set) var isScrolling = false
    var isHovering = false
    /// How far a manual offset may move from the follow position.
    @ObservationIgnored var range: ClosedRange<CGFloat> = -.greatestFiniteMagnitude ... .greatestFiniteMagnitude

    @ObservationIgnored private var monitor: Any?
    @ObservationIgnored private var resetTask: Task<Void, Never>?

    func install() {
        guard monitor == nil else { return }
        monitor = NSEvent.addLocalMonitorForEvents(matching: .scrollWheel) { [weak self] event in
            // Line-based wheels report a few units per notch; trackpads report points.
            let delta = event.scrollingDeltaY * (event.hasPreciseScrollingDeltas ? 1 : 12)
            MainActor.assumeIsolated { self?.scrolled(by: delta) }
            return event
        }
    }

    func uninstall() {
        if let monitor { NSEvent.removeMonitor(monitor) }
        monitor = nil
        resetTask?.cancel()
    }

    private func scrolled(by delta: CGFloat) {
        guard isHovering, delta != 0 else { return }
        manualOffset = min(max(manualOffset + delta, range.lowerBound), range.upperBound)
        if !isScrolling { isScrolling = true }
        resetTask?.cancel()
        resetTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(2.5))
            guard !Task.isCancelled, let self else { return }
            withAnimation(.smooth(duration: 0.8)) {
                self.manualOffset = 0
                self.isScrolling = false
            }
        }
    }
}
