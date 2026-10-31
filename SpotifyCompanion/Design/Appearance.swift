import Foundation
import Observation

/// The chosen style, and the color choice remembered separately for each style.
@MainActor
@Observable
final class Appearance {
    var styleID: StyleID {
        didSet { defaults.set(styleID.rawValue, forKey: Pref.style) }
    }

    private var colors: [StyleID: ColorChoice] = [:]
    @ObservationIgnored private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        styleID = defaults.string(forKey: Pref.style).flatMap(StyleID.init) ?? .swiss
        for style in StyleID.allCases {
            if let raw = defaults.string(forKey: ColorChoice.storageKey(for: style)) {
                colors[style] = ColorChoice(rawValue: raw)
            }
        }
        // Version 1 had one "theme" key: four Swiss colorways.
        if colors[.swiss] == nil, let old = defaults.string(forKey: "theme") {
            colors[.swiss] = ColorChoice(rawValue: old)
        }
    }

    /// The current style's color choice.
    var color: ColorChoice {
        get { color(for: styleID) }
        set { setColor(newValue, for: styleID) }
    }

    func color(for style: StyleID) -> ColorChoice {
        switch colors[style] {
        case .palette(let id)? where style.style.palettes.contains(where: { $0.id == id }):
            .palette(id)
        case .auto?: .auto
        case .albumBlur?: .albumBlur
        default: .palette(style.style.palettes[0].id)
        }
    }

    func setColor(_ choice: ColorChoice, for style: StyleID) {
        colors[style] = choice
        defaults.set(choice.rawValue, forKey: ColorChoice.storageKey(for: style))
    }

    func theme(palette: Palette?) -> Theme {
        .resolve(styleID, color, palette: palette)
    }
}
