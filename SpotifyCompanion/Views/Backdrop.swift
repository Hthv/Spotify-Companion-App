import AppKit
import SwiftUI

/// Everything behind the content: the style's color field (flat, gradient or blurred cover)
/// and its ornament (gold frame, light orbs, paper grain, sparkles).
struct BackdropView: View {
    /// Height of the header; the luxury frame sits below it, clear of the window buttons.
    let headerHeight: CGFloat

    @Environment(\.theme) private var theme
    @Environment(ArtworkStore.self) private var artwork

    var body: some View {
        ZStack {
            theme.background
            switch theme.backdrop {
            case .flat:
                EmptyView()
            case .gradient(let start, let end):
                LinearGradient(colors: [start, end], startPoint: .topLeading, endPoint: .bottomTrailing)
                    .transition(.opacity)
            case .albumBlur:
                AlbumBlurBackground(image: artwork.thumbnail, key: artwork.imageURL)
                    .transition(.opacity)
            }
        }
        .ignoresSafeArea()
        // The ornament stays inside the safe area, so the gold frame starts under the header
        // rather than under the window buttons.
        .overlay { OrnamentLayer(headerHeight: headerHeight) }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

/// The pre-blurred cover, blown up to fill the window, slowly turning.
private struct AlbumBlurBackground: View {
    let image: NSImage?
    let key: URL?

    @Environment(\.theme) private var theme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var turned = false

    var body: some View {
        GeometryReader { geometry in
            let side = max(geometry.size.width, geometry.size.height) * 1.5
            ZStack {
                if let image {
                    Image(nsImage: image)
                        .resizable()
                        .interpolation(.high)
                        .frame(width: side, height: side)
                        .id(key)
                        .transition(.opacity.animation(.easeInOut(duration: 1.2)))
                }
            }
            .rotationEffect(.degrees(turned ? 360 : 0))
            .frame(width: geometry.size.width, height: geometry.size.height)
            .clipped()
            .overlay {
                // A scrim, heavier at the bottom where controls sit.
                LinearGradient(colors: [.black.opacity(0.3), .black.opacity(0.5)], startPoint: .top, endPoint: .bottom)
            }
        }
        .onAppear { updateMotion() }
        .onChange(of: theme.ambientMotion) { updateMotion() }
    }

    private func updateMotion() {
        let moving = theme.ambientMotion && !reduceMotion
        if moving {
            withAnimation(.linear(duration: 160).repeatForever(autoreverses: false)) { turned = true }
        } else {
            withAnimation(.smooth(duration: 1)) { turned = false }
        }
    }
}

private struct OrnamentLayer: View {
    let headerHeight: CGFloat
    @Environment(\.theme) private var theme

    var body: some View {
        switch theme.style.ornament {
        case .none:
            EmptyView()
        case .goldFrame:
            GoldFrame()
                .padding(.top, headerHeight + 14)
                .padding([.horizontal, .bottom], 14)
                .transition(.opacity)
        case .orbs:
            LightOrbs().ignoresSafeArea().transition(.opacity)
        case .grain:
            ZStack {
                Enso()
                PaperGrain(opacity: theme.colorScheme == .dark ? 0.09 : 0.11)
            }
            .ignoresSafeArea()
            .transition(.opacity)
        case .sparkles:
            Sparkles().ignoresSafeArea().transition(.opacity)
        case .columns:
            PaperGrain(opacity: 0.05).ignoresSafeArea().transition(.opacity)
        }
    }
}

/// A double gold hairline with a diamond at each corner, like a printed invitation.
private struct GoldFrame: View {
    @Environment(\.theme) private var theme

    var body: some View {
        ZStack {
            Rectangle().strokeBorder(theme.accent.opacity(0.5), lineWidth: 0.75)
            Rectangle().strokeBorder(theme.accent.opacity(0.25), lineWidth: 0.5).padding(5)
        }
        .overlay {
            GeometryReader { geometry in
                ForEach(0..<4) { corner in
                    Image(systemName: "diamond.fill")
                        .font(.system(size: 7))
                        .foregroundStyle(theme.accent)
                        .position(
                            x: corner % 2 == 0 ? 0 : geometry.size.width,
                            y: corner < 2 ? 0 : geometry.size.height
                        )
                }
            }
        }
    }
}

/// Large soft lights drifting slowly behind the glass.
private struct LightOrbs: View {
    @Environment(\.theme) private var theme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var drift = false

    var body: some View {
        GeometryReader { geometry in
            let size = geometry.size
            let unit = max(size.width, size.height)
            let colors: [Color] = [theme.accent.opacity(0.55), theme.foreground.opacity(0.18), theme.accent.opacity(0.32)]
            let anchors: [(CGFloat, CGFloat, CGFloat)] = [(0.18, 0.25, 0.55), (0.82, 0.3, 0.45), (0.6, 0.9, 0.6)]
            let moves: [(CGFloat, CGFloat)] = [(0.08, 0.06), (-0.06, 0.08), (-0.07, -0.05)]
            ZStack {
                ForEach(0..<3) { index in
                    let (x, y, scale) = anchors[index]
                    // A radial falloff looks like a blurred disc without a live blur pass.
                    Circle()
                        .fill(RadialGradient(colors: [colors[index], colors[index].opacity(0)], center: .center, startRadius: 0, endRadius: unit * scale / 2))
                        .frame(width: unit * scale, height: unit * scale)
                        .position(x: size.width * x, y: size.height * y)
                        .offset(
                            x: drift ? size.width * moves[index].0 : 0,
                            y: drift ? size.height * moves[index].1 : 0
                        )
                        .animation(
                            .easeInOut(duration: 11 + Double(index) * 3).repeatForever(autoreverses: true),
                            value: drift
                        )
                }
            }
        }
        .onAppear { drift = theme.ambientMotion && !reduceMotion }
        .onChange(of: theme.ambientMotion) { _, moving in drift = moving && !reduceMotion }
    }
}

/// Fine paper fibre: a tile of noise, generated once.
private struct PaperGrain: View {
    let opacity: Double
    @Environment(\.theme) private var theme

    private static let tile: NSImage = {
        let side = 180
        let image = NSImage(size: NSSize(width: side, height: side))
        image.lockFocus()
        var generator = SystemRandomNumberGenerator()
        for _ in 0..<(side * side / 3) {
            let shade = CGFloat.random(in: 0...1, using: &generator)
            NSColor(white: shade, alpha: CGFloat.random(in: 0.2...0.9, using: &generator)).setFill()
            NSRect(x: Int.random(in: 0..<side, using: &generator), y: Int.random(in: 0..<side, using: &generator), width: 1, height: 1).fill()
        }
        image.unlockFocus()
        return image
    }()

    var body: some View {
        Image(nsImage: Self.tile)
            .resizable(resizingMode: .tile)
            .opacity(opacity)
            .blendMode(theme.colorScheme == .dark ? .screen : .multiply)
    }
}

/// A single brushed circle, left open: the Zen ensō, faint in the corner.
private struct Enso: View {
    @Environment(\.theme) private var theme

    var body: some View {
        GeometryReader { geometry in
            let side = min(geometry.size.width, geometry.size.height) * 0.75
            ZStack {
                Circle()
                    .trim(from: 0.03, to: 0.9)
                    .stroke(theme.accent.opacity(0.09), style: StrokeStyle(lineWidth: side * 0.07, lineCap: .round))
                Circle()
                    .trim(from: 0.08, to: 0.7)
                    .stroke(theme.accent.opacity(0.05), style: StrokeStyle(lineWidth: side * 0.03, lineCap: .round))
                    .padding(side * 0.03)
            }
            .rotationEffect(.degrees(-70))
            .frame(width: side, height: side)
            .position(x: geometry.size.width - side * 0.18, y: geometry.size.height - side * 0.12)
        }
    }
}

/// Four-point stars that twinkle in and out at their own pace.
private struct Sparkles: View {
    @Environment(\.theme) private var theme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var twinkle = false

    /// x, y (fractions of the window), size, period.
    private static let stars: [(CGFloat, CGFloat, CGFloat, Double)] = [
        (0.06, 0.2, 22, 1.8), (0.93, 0.16, 16, 2.4), (0.88, 0.62, 28, 2.1), (0.12, 0.82, 14, 2.9),
        (0.5, 0.07, 12, 1.6), (0.72, 0.9, 18, 2.6), (0.35, 0.94, 10, 2.2), (0.97, 0.88, 12, 3.1),
    ]

    var body: some View {
        GeometryReader { geometry in
            ForEach(Self.stars.indices, id: \.self) { index in
                let (x, y, size, period) = Self.stars[index]
                Image(systemName: "sparkle")
                    .font(.system(size: size, weight: .bold))
                    .foregroundStyle(index.isMultiple(of: 2) ? theme.foreground : theme.accent)
                    .shadow(color: theme.foreground.opacity(0.7), radius: 6)
                    .scaleEffect(twinkle ? 1 : 0.45)
                    .opacity(twinkle ? 0.95 : 0.35)
                    .rotationEffect(.degrees(twinkle ? 20 : 0))
                    .animation(.easeInOut(duration: period).repeatForever(autoreverses: true).delay(Double(index) * 0.3), value: twinkle)
                    .position(x: geometry.size.width * x, y: geometry.size.height * y)
            }
        }
        .onAppear { twinkle = theme.ambientMotion && !reduceMotion }
        .onChange(of: theme.ambientMotion) { _, moving in twinkle = moving && !reduceMotion }
    }
}
