import SwiftUI

/// Full-window message for every state that isn't "playing": an icon, big type
/// bottom-left, at most one action.
struct StatusView: View {
    let screen: RootView.Screen

    @Environment(SpotifyService.self) private var spotify
    @Environment(\.theme) private var theme

    private struct Content {
        let icon: String
        let headline: String
        let detail: String?
        var action: (title: String, icon: String, run: @MainActor (SpotifyService) -> Void)?
    }

    private var content: Content {
        switch screen {
        case .notInstalled:
            Content(icon: "questionmark.app", headline: "Spotify isn’t\ninstalled", detail: "Install the Spotify desktop app.")
        case .permissionDenied:
            Content(
                icon: "lock",
                headline: "Allow\naccess",
                detail: "Privacy & Security › Automation › Spotify",
                action: ("Settings", "gearshape", { $0.openAutomationSettings() })
            )
        case .idle:
            Content(icon: "music.note", headline: "Nothing\nplaying", detail: nil)
        case .notRunning, .connecting, .nowPlaying:
            Content(
                icon: "powerplug",
                headline: "Spotify isn’t\nrunning",
                detail: nil,
                action: ("Open Spotify", "arrow.up.forward.app", { $0.openSpotify() })
            )
        }
    }

    var body: some View {
        let content = content
        let style = theme.style
        VStack(alignment: style.stackAlignment, spacing: Metrics.unit * 3) {
            Image(systemName: content.icon)
                .font(.system(size: 30, weight: style.iconWeight == .bold ? .semibold : style.iconWeight))
                .foregroundStyle(theme.accent)
                .symbolEffect(.bounce, value: screen)
            Text("\(content.headline)\(Text(".").foregroundStyle(theme.accent))")
                .styledTitle(72)
                .multilineTextAlignment(style.textAlignment)
                .minimumScaleFactor(0.5)
            if let detail = content.detail {
                Text(detail)
                    .font(theme.font(\.body, 15))
                    .foregroundStyle(theme.secondary)
            }
            if let action = content.action {
                ActionButton(title: action.title, icon: action.icon) { action.run(spotify) }
                    .padding(.top, Metrics.unit)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: style.composition == .centered ? .center : .bottomLeading)
        .padding(Metrics.margin)
    }
}

struct ActionButton: View {
    let title: String
    let icon: String
    let action: () -> Void

    @Environment(\.theme) private var theme
    @State private var isHovering = false

    private var shape: RoundedRectangle {
        RoundedRectangle(cornerRadius: theme.style.control == .glossyPill ? 22 : theme.style.cornerRadius, style: .continuous)
    }

    var body: some View {
        Button(action: action) {
            HStack(spacing: Metrics.unit) {
                Image(systemName: icon)
                Text(title)
                Image(systemName: "arrow.right")
                    .offset(x: isHovering ? 4 : 0)
            }
            .font(theme.font(\.label, 13))
            .tracking(theme.style.labelTracking * 0.5)
            .textCase(theme.style.labelCase)
            .foregroundStyle(isHovering ? theme.background : theme.foreground)
            .padding(.horizontal, Metrics.unit * 2)
            .padding(.vertical, Metrics.unit * 1.5)
            .background(isHovering ? theme.foreground : .clear, in: shape)
            .overlay(shape.strokeBorder(theme.style.id == .luxury ? theme.accent : theme.foreground, lineWidth: theme.style.id == .luxury ? 0.75 : 1.5))
            .contentShape(Rectangle())
        }
        .buttonStyle(PressableStyle())
        .onHover { hovering in
            withAnimation(.smooth(duration: 0.2)) { isHovering = hovering }
        }
    }
}
