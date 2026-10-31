import AppKit
import SwiftUI

/// A style's color option: one of its palettes, colors taken from the cover, or the cover
/// itself blurred into the background.
enum ColorChoice: Hashable, Sendable {
    case palette(String)
    case auto
    case albumBlur

    init(rawValue: String) {
        switch rawValue {
        case "auto": self = .auto
        case "blur": self = .albumBlur
        default: self = .palette(rawValue)
        }
    }

    var rawValue: String {
        switch self {
        case .palette(let id): id
        case .auto: "auto"
        case .albumBlur: "blur"
        }
    }

    /// The UserDefaults key holding the color choice for one style, so each style keeps its own.
    static func storageKey(for style: StyleID) -> String { "color.\(style.rawValue)" }

    static func all(for style: DesignStyle) -> [ColorChoice] {
        style.palettes.map { .palette($0.id) } + [.auto, .albumBlur]
    }

    func title(in style: DesignStyle) -> String {
        switch self {
        case .palette(let id): style.palettes.first { $0.id == id }?.name ?? style.palettes[0].name
        case .auto: "Album Colors"
        case .albumBlur: "Album Blur"
        }
    }
}

/// What sits behind everything.
enum Backdrop: Equatable {
    case flat
    /// Diagonal, top-leading to bottom-trailing.
    case gradient(Color, Color)
    /// The cover, heavily blurred, under a dark scrim.
    case albumBlur
}

/// A style with its colors resolved: what every view reads from the environment.
struct Theme: Equatable {
    var style: DesignStyle
    var background: Color
    var foreground: Color
    var secondary: Color
    var accent: Color
    var rule: Color
    var backdrop: Backdrop
    /// Drives the window chrome (traffic lights, menus) to match the background.
    var colorScheme: ColorScheme
    /// User's text size preference, 0.85...1.2.
    var textScale: CGFloat = 1
    /// Ambient decoration may move (orbs drift, sparkles twinkle).
    var ambientMotion = true

    init(
        style: DesignStyle, background: Color, foreground: Color, accent: Color,
        backdrop: Backdrop = .flat, colorScheme: ColorScheme
    ) {
        self.style = style
        self.background = background
        self.foreground = foreground
        self.secondary = foreground.opacity(0.62)
        self.accent = accent
        self.rule = foreground.opacity(0.16)
        self.backdrop = backdrop
        self.colorScheme = colorScheme
    }

    func font(_ role: KeyPath<FontSet, FontSpec>, _ size: CGFloat) -> Font {
        style.fonts[keyPath: role].font(size * textScale)
    }

    static func resolve(_ styleID: StyleID, _ choice: ColorChoice, palette: Palette?) -> Theme {
        let style = styleID.style
        switch choice {
        case .palette(let id):
            return Theme(style: style, palette: style.palettes.first { $0.id == id } ?? style.palettes[0])
        case .auto:
            return auto(style, from: palette)
        case .albumBlur:
            return albumBlur(style, from: palette)
        }
    }

    init(style: DesignStyle, palette: StylePalette) {
        let background = Color(hex: palette.background)
        self.init(
            style: style,
            background: background,
            foreground: Color(hex: palette.foreground),
            accent: Color(hex: palette.accent),
            backdrop: palette.backgroundEnd.map { .gradient(background, Color(hex: $0)) } ?? .flat,
            colorScheme: palette.isDark ? .dark : .light
        )
    }

    /// Flat background from the cover's dominant color, ink or paper text, whichever reads
    /// better, and the cover's most vivid color as accent.
    private static func auto(_ style: DesignStyle, from palette: Palette?) -> Theme {
        guard let palette else { return Theme(style: style, palette: style.palettes[0]) }
        let background = palette.background
        let foreground: RGB = background.contrast(with: .ink) >= background.contrast(with: .paper) ? .ink : .paper
        let backdrop: Backdrop = style.palettes[0].backgroundEnd == nil
            ? .flat
            // Gradient styles get a gradient into the accent, kept faint so text still reads.
            : .gradient(Color(rgb: background), Color(rgb: background.mixed(with: palette.accent ?? foreground, 0.25)))
        return Theme(
            style: style,
            background: Color(rgb: background),
            foreground: Color(rgb: foreground),
            accent: Color(rgb: palette.accent ?? foreground),
            backdrop: backdrop,
            colorScheme: foreground == .ink ? .light : .dark
        )
    }

    /// White type over the darkened, blurred cover; the accent is the cover's vivid color,
    /// lifted so it reads on the scrim.
    private static func albumBlur(_ style: DesignStyle, from palette: Palette?) -> Theme {
        let base = palette?.background ?? RGB(r: 0.12, g: 0.12, b: 0.13)
        let accent = (palette?.accent).map { $0.luminance < 0.35 ? $0.mixed(with: .white, 0.45) : $0 } ?? .white
        var theme = Theme(
            style: style,
            // Used for glyphs set on solid controls and as the fallback before a cover loads.
            background: Color(rgb: base.mixed(with: .black, 0.45)),
            foreground: .white,
            accent: Color(rgb: accent),
            backdrop: .albumBlur,
            colorScheme: .dark
        )
        theme.secondary = .white.opacity(0.7)
        theme.rule = .white.opacity(0.22)
        return theme
    }
}

extension RGB {
    static let white = RGB(r: 1, g: 1, b: 1)
    static let black = RGB(r: 0, g: 0, b: 0)

    /// Linear blend toward `other`; 0 keeps self, 1 gives other.
    func mixed(with other: RGB, _ amount: Double) -> RGB {
        RGB(r: r + (other.r - r) * amount, g: g + (other.g - g) * amount, b: b + (other.b - b) * amount)
    }
}

extension Color {
    init(hex: UInt32) {
        self.init(
            .sRGB,
            red: Double((hex >> 16) & 0xFF) / 255,
            green: Double((hex >> 8) & 0xFF) / 255,
            blue: Double(hex & 0xFF) / 255
        )
    }

    init(rgb: RGB) {
        self.init(.sRGB, red: rgb.r, green: rgb.g, blue: rgb.b)
    }
}

extension EnvironmentValues {
    @Entry var theme: Theme = Theme(style: .swiss, palette: DesignStyle.swiss.palettes[0])
}
