import SwiftUI

/// The cover in the style's treatment: square, rounded, mounted in a gold frame, glowing,
/// irregular like a hand-cut print, chrome-bezeled, or captioned like a magazine figure.
struct StyledArtwork: View {
    let image: NSImage?
    let imageURL: URL?
    var caption: String?

    @Environment(\.theme) private var theme

    var body: some View {
        GeometryReader { geometry in
            let side = min(geometry.size.width, geometry.size.height)
            treated(side: side)
                .frame(width: geometry.size.width, height: geometry.size.height)
        }
    }

    @ViewBuilder
    private func treated(side: CGFloat) -> some View {
        let cover = ArtworkView(image: image, imageURL: imageURL)
        switch theme.style.art {
        case .square:
            cover
        case .rounded(let radius):
            cover
                .clipShape(RoundedRectangle(cornerRadius: radius, style: .continuous))
                .shadow(color: .black.opacity(0.14), radius: 18, y: 10)
        case .framed:
            cover
                .padding(side * 0.045)
                .overlay(Rectangle().strokeBorder(theme.accent.opacity(0.85), lineWidth: 0.75))
                .overlay(Rectangle().strokeBorder(theme.accent.opacity(0.35), lineWidth: 0.5).padding(side * 0.018))
        case .glow:
            cover
                .clipShape(RoundedRectangle(cornerRadius: side * 0.08, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: side * 0.08, style: .continuous).strokeBorder(.white.opacity(0.35), lineWidth: 0.75))
                .shadow(color: theme.accent.opacity(0.6), radius: side * 0.12)
        case .organic:
            cover
                .clipShape(Self.organicShape(side))
                .shadow(color: .black.opacity(0.16), radius: 14, x: 3, y: 8)
                .rotationEffect(.degrees(-1.4))
                .padding(side * 0.02)
        case .chrome:
            let shape = RoundedRectangle(cornerRadius: side * 0.09, style: .continuous)
            cover
                .clipShape(shape)
                .overlay {
                    // Gloss across the top half.
                    LinearGradient(colors: [.white.opacity(0.32), .white.opacity(0)], startPoint: .top, endPoint: .center)
                        .clipShape(shape)
                }
                .overlay(shape.strokeBorder(Self.chrome, lineWidth: max(side * 0.018, 3)))
                .shadow(color: theme.accent.opacity(0.9), radius: 0, x: side * 0.025, y: side * 0.025)
        case .captioned:
            cover
                .overlay(alignment: .bottomLeading) {
                    if let caption {
                        HStack(spacing: 6) {
                            Text("Fig. 1").foregroundStyle(theme.accent)
                            Text(caption).lineLimit(1)
                        }
                        .styledLabel(9)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 5)
                        .background(theme.background)
                        .foregroundStyle(theme.foreground)
                        .frame(maxWidth: side * 0.8, alignment: .leading)
                    }
                }
        }
    }

    nonisolated static func organicShape(_ side: CGFloat) -> UnevenRoundedRectangle {
        UnevenRoundedRectangle(
            topLeadingRadius: side * 0.14, bottomLeadingRadius: side * 0.035,
            bottomTrailingRadius: side * 0.17, topTrailingRadius: side * 0.045,
            style: .continuous
        )
    }

    static let chrome = LinearGradient(
        stops: [
            .init(color: .white, location: 0),
            .init(color: Color(white: 0.62), location: 0.35),
            .init(color: .white, location: 0.55),
            .init(color: Color(white: 0.5), location: 1),
        ],
        startPoint: .topLeading, endPoint: .bottomTrailing
    )
}

/// The style's clip for small covers (recently played, playlists).
struct ThumbnailShape: Shape {
    let art: ArtTreatment

    func path(in rect: CGRect) -> Path {
        let side = min(rect.width, rect.height)
        switch art {
        case .square, .framed, .captioned:
            return Rectangle().path(in: rect)
        case .rounded(let radius):
            return RoundedRectangle(cornerRadius: radius, style: .continuous).path(in: rect)
        case .glow, .chrome:
            return RoundedRectangle(cornerRadius: side * 0.12, style: .continuous).path(in: rect)
        case .organic:
            return StyledArtwork.organicShape(side).path(in: rect)
        }
    }
}

struct ArtworkView: View {
    let image: NSImage?
    let imageURL: URL?

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        // The cover fills the slot it's given and is cropped to it. As an overlay it can't
        // size the view: a filled wide or tall image would otherwise lay out wider or taller
        // than its slot and spill over the title.
        ArtworkPlaceholder()
            .overlay {
                if let image {
                    Image(nsImage: image)
                        .resizable()
                        .interpolation(.high)
                        .aspectRatio(contentMode: .fill)
                        .id(imageURL)
                        .transition(.asymmetric(
                            insertion: reduceMotion ? AnyTransition.opacity : .opacity.combined(with: .scale(scale: 1.04)),
                            removal: .opacity
                        ))
                }
            }
            .clipped()
        .animation(.smooth(duration: 0.6), value: imageURL)
        .accessibilityHidden(true)
    }
}

/// Shown while a cover loads or when a track has none: a circle on a field, nothing more.
struct ArtworkPlaceholder: View {
    @Environment(\.theme) private var theme

    var body: some View {
        GeometryReader { geometry in
            let side = geometry.size.width
            ZStack(alignment: .bottomTrailing) {
                Rectangle().fill(theme.foreground.opacity(0.1))
                Circle()
                    .fill(theme.accent)
                    .frame(width: side * 0.5, height: side * 0.5)
                    .padding(side * 0.1)
            }
        }
    }
}
