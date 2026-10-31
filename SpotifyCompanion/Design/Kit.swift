import SwiftUI

/// Spacing shared by every style: an 8 pt unit and the window margins built from it.
enum Metrics {
    static let unit: CGFloat = 8
    static let margin: CGFloat = unit * 6
    static let gutter: CGFloat = unit * 5
}

extension View {
    /// The style's small caption: its label face, case and tracking.
    func styledLabel(_ size: CGFloat = 11) -> some View {
        modifier(StyledLabel(size: size))
    }

    /// The style's headline treatment: display face, tracking and any glow or chrome.
    func styledTitle(_ size: CGFloat) -> some View {
        modifier(StyledTitle(size: size))
    }
}

private struct StyledLabel: ViewModifier {
    let size: CGFloat
    @Environment(\.theme) private var theme

    func body(content: Content) -> some View {
        content
            .font(theme.font(\.label, size))
            .tracking(theme.style.labelTracking)
            .textCase(theme.style.labelCase)
    }
}

private struct StyledTitle: ViewModifier {
    let size: CGFloat
    @Environment(\.theme) private var theme

    func body(content: Content) -> some View {
        let styled = content
            .font(theme.font(\.display, size * theme.style.titleScale))
            .tracking(size * theme.style.titleTracking)
        switch theme.style.titleEffect {
        case .none:
            styled
        case .glow:
            styled.shadow(color: theme.accent.opacity(0.55), radius: size * 0.35)
        case .chrome:
            styled
                .foregroundStyle(LinearGradient(
                    stops: [
                        .init(color: theme.foreground, location: 0),
                        .init(color: theme.foreground.opacity(0.62), location: 0.48),
                        .init(color: theme.foreground, location: 0.52),
                        .init(color: theme.foreground.opacity(0.85), location: 1),
                    ],
                    startPoint: .top, endPoint: .bottom
                ))
                // Hard offset shadow, the Y2K way.
                .shadow(color: theme.accent.opacity(0.9), radius: 0, x: 0, y: max(size * 0.04, 1.5))
        }
    }
}

/// A divider in the style's manner: hairline, gold ornament, fading line, newspaper double rule,
/// or nothing at all.
struct Rule: View {
    @Environment(\.theme) private var theme

    var body: some View {
        switch theme.style.rule {
        case .hairline:
            Rectangle().fill(theme.rule).frame(height: 1)
        case .none:
            Color.clear.frame(height: 1)
        case .fade:
            LinearGradient(
                colors: [theme.foreground.opacity(0), theme.foreground.opacity(0.3), theme.foreground.opacity(0)],
                startPoint: .leading, endPoint: .trailing
            )
            .frame(height: 1)
        case .double:
            VStack(spacing: 2) {
                Rectangle().frame(height: 2)
                Rectangle().frame(height: 1)
            }
            .foregroundStyle(theme.foreground.opacity(0.85))
        case .ornament:
            HStack(spacing: 10) {
                Rectangle().frame(height: 1)
                Image(systemName: "diamond.fill").font(.system(size: 6))
                Rectangle().frame(height: 1)
            }
            .foregroundStyle(theme.accent.opacity(0.75))
            .frame(height: 8)
        }
    }
}

/// Springs down on press.
struct PressableStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.9 : 1)
            .animation(.spring(duration: 0.3, bounce: 0.45), value: configuration.isPressed)
    }
}

/// Text that moves into place when `key` changes, the old value fading out underneath.
/// How far it travels, and whether it sharpens out of a blur, comes from the style.
struct Reveal<Content: View>: View {
    let key: String
    /// Position in a group; each step adds a short delay so lines arrive one after another.
    var order = 0
    @ViewBuilder let content: Content

    @Environment(\.theme) private var theme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        let style = theme.style
        ZStack(alignment: Alignment(horizontal: style.stackAlignment, vertical: .top)) {
            content
                .id(key)
                .transition(.asymmetric(
                    insertion: (reduceMotion ? AnyTransition.opacity : .opacity
                        .combined(with: .offset(y: style.revealOffset))
                        .combined(with: .modifier(active: BlurEffect(radius: style.revealBlur), identity: BlurEffect(radius: 0))))
                        .animation(style.motion.delay(0.1 + Double(order) * 0.06)),
                    removal: .opacity.animation(.easeOut(duration: 0.18))
                ))
        }
        .frame(maxWidth: .infinity, alignment: style.frameAlignment)
        .animation(style.motion, value: key)
    }
}

private struct BlurEffect: ViewModifier {
    let radius: CGFloat
    func body(content: Content) -> some View { content.blur(radius: radius) }
}

extension View {
    /// A surface for grouped content (cards, popover rows, toasts) in the style's manner.
    func styledCard(padding: CGFloat = Metrics.unit * 2) -> some View {
        modifier(StyledCard(padding: padding))
    }
}

private struct StyledCard: ViewModifier {
    let padding: CGFloat
    @Environment(\.theme) private var theme

    func body(content: Content) -> some View {
        let radius = theme.style.cornerRadius
        let shape = RoundedRectangle(cornerRadius: radius, style: .continuous)
        let padded = content.padding(padding)
        switch theme.style.id {
        case .swiss:
            padded.background(theme.foreground.opacity(0.05), in: Rectangle())
        case .minimal:
            padded.background(theme.foreground.opacity(0.04), in: shape)
        case .luxury:
            padded.overlay(Rectangle().strokeBorder(theme.accent.opacity(0.55), lineWidth: 0.75))
        case .ethereal:
            // Shadows go on the shape alone; on the whole card they'd ghost every glyph.
            padded
                .background {
                    shape.fill(.ultraThinMaterial)
                        .shadow(color: theme.accent.opacity(0.18), radius: 24, y: 8)
                }
                .overlay(shape.strokeBorder(.white.opacity(0.45), lineWidth: 0.75))
        case .wabiSabi:
            padded.background(
                theme.foreground.opacity(0.06),
                in: UnevenRoundedRectangle(topLeadingRadius: radius * 1.6, bottomLeadingRadius: radius * 0.4,
                                           bottomTrailingRadius: radius * 1.9, topTrailingRadius: radius * 0.6, style: .continuous)
            )
        case .y2k:
            padded
                .background {
                    ZStack {
                        shape.fill(theme.accent.opacity(0.85)).offset(x: 4, y: 4)
                        shape.fill(theme.background)
                        shape.fill(LinearGradient(colors: [.white.opacity(0.42), .white.opacity(0.12)], startPoint: .top, endPoint: .bottom))
                    }
                }
                .overlay(shape.strokeBorder(.white.opacity(0.75), lineWidth: 1.5))
        case .editorial:
            padded.overlay(alignment: .top) { Rule() }
        }
    }
}
