import SwiftUI

/// Playback position in the style's manner, from a Swiss hairline to a glossy Y2K tube.
/// Click or drag to seek; hover for the time under the pointer. Between polls the position
/// is extrapolated every frame, so it never steps.
struct ProgressBar: View {
    let duration: TimeInterval

    @Environment(SpotifyService.self) private var spotify
    @Environment(\.theme) private var theme
    @State private var scrubPosition: TimeInterval?
    @State private var isHovering = false
    /// Pointer position over the bar, for the time readout.
    @State private var pointerX: CGFloat?

    private var isActive: Bool { isHovering || scrubPosition != nil }

    var body: some View {
        TimelineView(.animation(minimumInterval: 1 / 60, paused: !spotify.isPlaying || scrubPosition != nil)) { context in
            let position = scrubPosition ?? spotify.position(at: context.date)
            VStack(spacing: Metrics.unit) {
                bar(fraction: duration > 0 ? position / duration : 0)
                HStack {
                    Text(Self.format(position))
                    Spacer()
                    Text("−" + Self.format(max(duration - position, 0)))
                }
                .font(theme.font(\.label, 11).monospacedDigit())
                .tracking(theme.style.id == .luxury ? 2 : 0.4)
                .foregroundStyle(theme.secondary)
            }
            .accessibilityElement()
            .accessibilityLabel("Playback position")
            .accessibilityValue("\(Self.format(position)) of \(Self.format(duration))")
            .accessibilityAdjustableAction { direction in
                switch direction {
                case .increment: spotify.seek(to: position + 10)
                case .decrement: spotify.seek(to: position - 10)
                @unknown default: break
                }
            }
        }
    }

    private func bar(fraction: Double) -> some View {
        GeometryReader { geometry in
            let width = geometry.size.width
            let clamped = min(max(fraction, 0), 1)
            track(fraction: clamped, width: width)
                .frame(maxHeight: .infinity)
                .contentShape(Rectangle())
                .gesture(
                    DragGesture(minimumDistance: 0)
                        .onChanged { value in
                            pointerX = value.location.x
                            scrubPosition = seconds(at: value.location.x, width: width)
                        }
                        .onEnded { value in
                            spotify.seek(to: seconds(at: value.location.x, width: width))
                            scrubPosition = nil
                        }
                )
                .onContinuousHover { phase in
                    switch phase {
                    case .active(let point):
                        pointerX = point.x
                        if !isHovering { withAnimation(.smooth(duration: 0.2)) { isHovering = true } }
                    case .ended:
                        if scrubPosition == nil { pointerX = nil }
                        withAnimation(.smooth(duration: 0.2)) { isHovering = false }
                    }
                }
                .overlay(alignment: .topLeading) {
                    // The time under the pointer, floating above the bar.
                    if let x = pointerX, isActive {
                        Text(Self.format(seconds(at: x, width: width)))
                            .font(theme.font(\.label, 11).monospacedDigit())
                            .foregroundStyle(theme.background)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 3)
                            .background(theme.foreground, in: RoundedRectangle(cornerRadius: min(theme.style.cornerRadius, 6)))
                            .fixedSize()
                            .position(x: min(max(x, 22), max(width - 22, 22)), y: -12)
                            .transition(.opacity)
                            .allowsHitTesting(false)
                    }
                }
                .animation(.smooth(duration: 0.2), value: scrubPosition != nil)
        }
        .frame(height: theme.style.progress == .glossy ? 18 : 14)
    }

    @ViewBuilder
    private func track(fraction: Double, width: CGFloat) -> some View {
        let filled = width * fraction
        switch theme.style.progress {
        case .hairline:
            ZStack(alignment: .leading) {
                Rectangle().fill(theme.rule)
                Rectangle().fill(theme.accent).frame(width: filled)
            }
            .frame(height: isActive ? 6 : 2)
        case .thin:
            let height: CGFloat = isActive ? 3 : 1.5
            ZStack(alignment: .leading) {
                Capsule().fill(theme.rule).frame(height: height)
                Capsule().fill(theme.foreground).frame(width: filled, height: height)
                Circle()
                    .fill(theme.foreground)
                    .frame(width: 9, height: 9)
                    .offset(x: filled - 4.5)
                    .scaleEffect(isActive ? 1 : 0)
            }
        case .gold:
            ZStack(alignment: .leading) {
                Rectangle().fill(theme.accent.opacity(0.3)).frame(height: 0.75)
                Rectangle().fill(theme.accent).frame(width: filled, height: isActive ? 2 : 1)
                Image(systemName: "diamond.fill")
                    .font(.system(size: isActive ? 10 : 7))
                    .foregroundStyle(theme.accent)
                    .offset(x: filled - (isActive ? 5 : 3.5))
            }
        case .soft:
            ZStack(alignment: .leading) {
                Capsule().fill(theme.foreground.opacity(0.14))
                Capsule()
                    .fill(LinearGradient(colors: [theme.accent.opacity(0.55), theme.accent], startPoint: .leading, endPoint: .trailing))
                    .frame(width: max(filled, 6))
                    .shadow(color: theme.accent.opacity(0.7), radius: 6)
            }
            .frame(height: isActive ? 7 : 4)
        case .brush:
            ZStack(alignment: .leading) {
                Capsule().fill(theme.foreground.opacity(0.12)).frame(height: 2)
                Capsule().fill(theme.accent.opacity(0.9)).frame(width: max(filled, 4), height: isActive ? 5 : 3.5)
                StyledArtwork.organicShape(12)
                    .fill(theme.foreground)
                    .frame(width: 12, height: 10)
                    .offset(x: filled - 6)
                    .scaleEffect(isActive ? 1 : 0.6)
            }
        case .glossy:
            ZStack(alignment: .leading) {
                Capsule().fill(theme.foreground.opacity(0.18))
                Capsule().strokeBorder(.white.opacity(0.7), lineWidth: 1)
                Capsule()
                    .fill(theme.accent)
                    .overlay(
                        Capsule()
                            .fill(LinearGradient(colors: [.white.opacity(0.7), .white.opacity(0)], startPoint: .top, endPoint: .center))
                            .padding(.horizontal, 3)
                            .padding(.top, 1)
                    )
                    .frame(width: max(filled, 12))
                    .padding(2)
            }
            .frame(height: isActive ? 16 : 12)
        case .ruled:
            ZStack(alignment: .leading) {
                Rectangle().fill(theme.foreground.opacity(0.25)).frame(height: 1)
                // Tick marks every tenth, like a printed scale.
                HStack(spacing: 0) {
                    ForEach(0..<11) { index in
                        Rectangle().fill(theme.foreground.opacity(0.4)).frame(width: 1, height: index % 5 == 0 ? 9 : 5)
                        if index < 10 { Spacer(minLength: 0) }
                    }
                }
                Rectangle().fill(theme.foreground).frame(width: filled, height: isActive ? 5 : 3)
                Rectangle().fill(theme.accent).frame(width: 2, height: 12).offset(x: filled - 1)
            }
        }
    }

    private func seconds(at x: CGFloat, width: CGFloat) -> TimeInterval {
        guard width > 0 else { return 0 }
        return min(max(Double(x / width), 0), 1) * duration
    }

    static func format(_ seconds: TimeInterval) -> String {
        let total = Int(seconds.rounded(.down))
        let (hours, minutes, secs) = (total / 3600, total / 60 % 60, total % 60)
        return hours > 0
            ? String(format: "%d:%02d:%02d", hours, minutes, secs)
            : String(format: "%d:%02d", minutes, secs)
    }
}
