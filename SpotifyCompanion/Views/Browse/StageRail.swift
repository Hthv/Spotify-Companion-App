import SwiftUI

/// Home's categories down the side, like Stage Manager's window sets: each is a small stack of
/// its own covers, turned toward the content in perspective. Hovering straightens and fans the
/// stack; the chosen one stands flat and lit in the accent.
struct StageRail: View {
    @Environment(BrowseNavigation.self) private var navigation
    @Environment(SearchStore.self) private var search
    @Environment(\.theme) private var theme

    var body: some View {
        ScrollView(.vertical, showsIndicators: false) {
            VStack(spacing: Metrics.unit) {
                ForEach(BrowseCategory.allCases) { category in
                    StageStack(category: category, isSelected: navigation.category == category && navigation.path.isEmpty && !search.isActive) {
                        withAnimation(theme.style.motion) {
                            navigation.category = category
                            navigation.path = []
                            search.clear()
                        }
                        navigation.leaveSearch += 1
                    }
                }
            }
            .padding(.vertical, Metrics.unit * 2)
            .padding(.horizontal, Metrics.unit * 1.5)
        }
        .frame(width: 140)
    }
}

private struct StageStack: View {
    let category: BrowseCategory
    let isSelected: Bool
    let action: () -> Void

    @Environment(BrowseStore.self) private var browse
    @Environment(SpotifyAccount.self) private var account
    @Environment(\.theme) private var theme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var isHovering = false

    var body: some View {
        let lifted = isHovering || isSelected
        Button(action: action) {
            VStack(spacing: 6) {
                ZStack(alignment: .leading) {
                    // Back to front, each card further right and a little higher, so the
                    // ones behind show as a fan of edges.
                    ForEach(Array(cards.enumerated().reversed()), id: \.offset) { index, card in
                        StageCard(card: card)
                            .frame(width: 58, height: 58)
                            .rotation3DEffect(
                                .degrees(reduceMotion ? 0 : (lifted ? 10 : 34) - Double(index) * 3),
                                axis: (x: 0, y: 1, z: 0),
                                anchor: .leading,
                                perspective: 0.5
                            )
                            .scaleEffect(1 - CGFloat(index) * 0.1, anchor: .leading)
                            .offset(x: CGFloat(index) * (lifted ? 22 : 14), y: CGFloat(index) * (lifted ? -6 : -4))
                            .opacity(1 - Double(index) * 0.15)
                            .shadow(color: .black.opacity(lifted ? 0.3 : 0.18), radius: lifted ? 10 : 5, x: 2, y: lifted ? 7 : 3)
                    }
                }
                .frame(width: 108, height: 66, alignment: .leading)
                .scaleEffect(isSelected ? 1.05 : isHovering ? 1.03 : 1)
                Text(category.title)
                    .styledLabel(10)
                    .foregroundStyle(isSelected ? theme.accent : theme.secondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
            }
            .padding(.vertical, Metrics.unit)
            .padding(.horizontal, 4)
            .frame(maxWidth: .infinity)
            .background {
                RoundedRectangle(cornerRadius: max(theme.style.cornerRadius, 10), style: .continuous)
                    .fill(theme.foreground.opacity(isSelected ? 0.07 : isHovering ? 0.035 : 0))
            }
            .overlay(alignment: .leading) {
                Capsule()
                    .fill(theme.accent)
                    .frame(width: 3, height: isSelected ? 34 : 0)
                    .offset(x: -Metrics.unit * 1.5 + 1)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(PressableStyle())
        .foregroundStyle(theme.foreground)
        .onHover { hovering in withAnimation(.spring(duration: 0.45, bounce: 0.3)) { isHovering = hovering } }
        .animation(.spring(duration: 0.5, bounce: 0.25), value: isSelected)
        .help(category.title)
        .accessibilityLabel(category.title)
        .accessibilityAddTraits(isSelected ? [.isButton, .isSelected] : .isButton)
    }

    /// Up to three of the category's own covers, or its icon until there are some.
    private var cards: [StageCard.Content] {
        let items: [MediaItem] = switch category {
        case .forYou: browse.jumpBackIn.isEmpty ? browse.topArtists : browse.jumpBackIn
        case .library: browse.library.filter { $0.imageURL != nil }
        case .liked: browse.liked
        case .artists: browse.followedArtists.isEmpty ? browse.topArtists : browse.followedArtists
        case .recent: account.recent.map { MediaItem(uri: $0.uri, kind: .track, name: $0.name, subtitle: $0.artist, imageURL: $0.imageURL) }
        case .styles: []
        }
        if category == .styles {
            return [.style(.swiss), .style(.y2k), .style(.luxury)]
        }
        let covers = items.prefix(3).map { StageCard.Content.cover($0) }
        return covers.isEmpty ? [.icon(category.icon)] + (account.isSignedIn ? [.blank, .blank] : []) : covers
    }
}

private struct StageCard: View {
    enum Content {
        case cover(MediaItem), icon(String), style(StyleID), blank
    }

    let card: Content

    @Environment(\.theme) private var theme

    var body: some View {
        switch card {
        case .cover(let item):
            CoverImage(item: item)
        case .icon(let symbol):
            RoundedRectangle(cornerRadius: max(theme.style.cornerRadius, 6), style: .continuous)
                .fill(theme.foreground.opacity(0.08))
                .overlay {
                    Image(systemName: symbol)
                        .font(.system(size: 24, weight: theme.style.iconWeight))
                        .foregroundStyle(theme.accent)
                }
                .overlay(RoundedRectangle(cornerRadius: max(theme.style.cornerRadius, 6), style: .continuous).strokeBorder(theme.rule))
        case .style(let id):
            SwatchTile(theme: Theme(style: id.style, palette: id.style.palettes[0]), label: nil)
                .overlay(alignment: .bottomLeading) {
                    Text("Aa")
                        .font(id.style.fonts.display.font(20))
                        .foregroundStyle(Color(hex: id.style.palettes[0].foreground))
                        .padding(6)
                }
                .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
        case .blank:
            RoundedRectangle(cornerRadius: max(theme.style.cornerRadius, 6), style: .continuous)
                .fill(theme.foreground.opacity(0.05))
        }
    }
}
