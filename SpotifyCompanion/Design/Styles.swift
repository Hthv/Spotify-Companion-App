import SwiftUI

/// A whole design language: type, shapes, controls, ornament, motion and its own palettes.
enum StyleID: String, CaseIterable, Identifiable, Sendable {
    case swiss, minimal, luxury, ethereal, wabiSabi, y2k, editorial

    var id: Self { self }
    var style: DesignStyle { DesignStyle.all[self]! }
}

enum FontSpec: Equatable, Sendable {
    /// A PostScript name, e.g. "Didot-Italic".
    case named(String)
    case system(Font.Weight, Font.Design)

    func font(_ size: CGFloat) -> Font {
        switch self {
        case .named(let name): .custom(name, fixedSize: size)
        case .system(let weight, let design): .system(size: size, weight: weight, design: design)
        }
    }
}

struct FontSet: Equatable, Sendable {
    /// Track titles and big headlines.
    var display: FontSpec
    /// Artist names, card text.
    var body: FontSpec
    /// Album names and secondary lines (italic in the serif styles).
    var emphasis: FontSpec
    /// Small captions and kickers.
    var label: FontSpec
    var lyric: FontSpec
}

enum Composition: Equatable, Sendable {
    /// Cover beside a flush text column.
    case split
    /// Everything stacked on a centered axis.
    case centered
}

enum ArtTreatment: Equatable, Sendable {
    case square
    case rounded(CGFloat)
    /// A hairline frame set off from the cover, like a mount.
    case framed
    /// Large radius with a colored halo.
    case glow
    /// Uneven corners and a slight tilt.
    case organic
    /// Rounded with a metallic bezel.
    case chrome
    /// Square with a figure caption underneath.
    case captioned
}

enum ControlShape: Equatable, Sendable {
    case solidCircle, outlineCircle, doubleRing, glass, pebble, glossyPill, square
}

enum ProgressLook: Equatable, Sendable {
    case hairline, thin, gold, soft, brush, glossy, ruled
}

enum RuleLook: Equatable, Sendable {
    case hairline, none, ornament, fade, double
}

enum Ornament: Equatable, Sendable {
    case none, goldFrame, orbs, grain, sparkles, columns
}

enum TitleEffect: Equatable, Sendable {
    case none, glow, chrome
}

struct StylePalette: Identifiable, Equatable, Sendable {
    let id: String
    let name: String
    let background: UInt32
    let foreground: UInt32
    let accent: UInt32
    /// Optional second background color; draws a diagonal gradient.
    var backgroundEnd: UInt32?
    var isDark: Bool
}

struct DesignStyle: Identifiable, Equatable, Sendable {
    let id: StyleID
    let name: String
    /// One line on what the style is, for the picker.
    let summary: String
    let fonts: FontSet
    /// Title letter-spacing as a fraction of the point size.
    var titleTracking: CGFloat = 0
    var labelTracking: CGFloat = 1.4
    var labelCase: Text.Case? = .uppercase
    var titleScale: CGFloat = 1
    var titleEffect: TitleEffect = .none
    var composition: Composition = .split
    var art: ArtTreatment = .square
    var control: ControlShape = .solidCircle
    var iconWeight: Font.Weight = .bold
    var progress: ProgressLook = .hairline
    var rule: RuleLook = .hairline
    var ornament: Ornament = .none
    var cornerRadius: CGFloat = 0
    var lyricAlignment: HorizontalAlignment = .leading
    /// How entering text moves: distance, and whether it sharpens from a blur.
    var revealOffset: CGFloat = 18
    var revealBlur: CGFloat = 0
    var motion: Animation = .smooth(duration: 0.5)
    let palettes: [StylePalette]

    static func == (a: DesignStyle, b: DesignStyle) -> Bool { a.id == b.id }

    var textAlignment: TextAlignment { composition == .centered ? .center : .leading }
    var frameAlignment: Alignment { composition == .centered ? .center : .leading }
    var stackAlignment: HorizontalAlignment { composition == .centered ? .center : .leading }
    var lyricTextAlignment: TextAlignment { lyricAlignment == .center ? .center : .leading }
}

extension DesignStyle {
    static let all: [StyleID: DesignStyle] = Dictionary(
        uniqueKeysWithValues: [swiss, minimal, luxury, ethereal, wabiSabi, y2k, editorial].map { ($0.id, $0) }
    )

    static let swiss = DesignStyle(
        id: .swiss,
        name: "Swiss Design",
        summary: "Grid, grotesque type, flat signal color",
        fonts: FontSet(
            display: .named("HelveticaNeue-Bold"),
            body: .named("HelveticaNeue-Medium"),
            emphasis: .named("HelveticaNeue"),
            label: .named("HelveticaNeue-Bold"),
            lyric: .named("HelveticaNeue-Bold")
        ),
        titleTracking: -0.025,
        palettes: [
            StylePalette(id: "zurich", name: "Zürich", background: 0xF2F1EC, foreground: 0x111111, accent: 0xDA291C, isDark: false),
            StylePalette(id: "basel", name: "Basel", background: 0x111111, foreground: 0xF2F1EC, accent: 0xE8352B, isDark: true),
            StylePalette(id: "bern", name: "Bern", background: 0xDA291C, foreground: 0xFFFFFF, accent: 0x111111, isDark: true),
        ]
    )

    static let minimal = DesignStyle(
        id: .minimal,
        name: "Minimalism",
        summary: "Quiet, centered, nothing extra",
        fonts: FontSet(
            display: .system(.light, .default),
            body: .system(.regular, .default),
            emphasis: .system(.light, .default),
            label: .system(.medium, .default),
            lyric: .system(.semibold, .default)
        ),
        titleTracking: -0.01,
        labelTracking: 0.6,
        labelCase: nil,
        titleScale: 0.8,
        composition: .centered,
        art: .rounded(6),
        control: .outlineCircle,
        iconWeight: .light,
        progress: .thin,
        rule: .none,
        cornerRadius: 8,
        lyricAlignment: .center,
        revealOffset: 8,
        motion: .easeInOut(duration: 0.6),
        palettes: [
            StylePalette(id: "paper", name: "Paper", background: 0xFAFAF9, foreground: 0x1A1A1A, accent: 0x1A1A1A, isDark: false),
            StylePalette(id: "graphite", name: "Graphite", background: 0x1C1C1E, foreground: 0xEDEDED, accent: 0xEDEDED, isDark: true),
            StylePalette(id: "sand", name: "Sand", background: 0xEFEBE4, foreground: 0x3B3631, accent: 0x8C7B66, isDark: false),
        ]
    )

    static let luxury = DesignStyle(
        id: .luxury,
        name: "Luxury Typography",
        summary: "High-contrast serifs, gold hairlines",
        fonts: FontSet(
            display: .named("Didot"),
            body: .named("Baskerville"),
            emphasis: .named("Baskerville-Italic"),
            label: .named("Didot"),
            lyric: .named("Didot")
        ),
        labelTracking: 4.5,
        titleScale: 1.05,
        composition: .centered,
        art: .framed,
        control: .doubleRing,
        iconWeight: .ultraLight,
        progress: .gold,
        rule: .ornament,
        ornament: .goldFrame,
        lyricAlignment: .center,
        revealOffset: 10,
        motion: .easeInOut(duration: 0.9),
        palettes: [
            StylePalette(id: "noir", name: "Noir & Gold", background: 0x0B0B0C, foreground: 0xF3EBDD, accent: 0xC9A55C, isDark: true),
            StylePalette(id: "ivory", name: "Ivory", background: 0xF6F1E7, foreground: 0x1B1B1B, accent: 0xA8843F, isDark: false),
            StylePalette(id: "emerald", name: "Emerald", background: 0x0F2A22, foreground: 0xEFE6D2, accent: 0xC9A55C, isDark: true),
            StylePalette(id: "bordeaux", name: "Bordeaux", background: 0x3A0D16, foreground: 0xF2E6D8, accent: 0xD4AF6A, isDark: true),
        ]
    )

    static let ethereal = DesignStyle(
        id: .ethereal,
        name: "Ethereal",
        summary: "Soft light, glass and drifting color",
        fonts: FontSet(
            display: .named("AvenirNext-UltraLight"),
            body: .named("AvenirNext-Regular"),
            emphasis: .named("AvenirNext-Italic"),
            label: .named("AvenirNext-Medium"),
            lyric: .named("AvenirNext-DemiBold")
        ),
        titleTracking: 0.02,
        labelTracking: 2.5,
        labelCase: .lowercase,
        titleScale: 1.1,
        titleEffect: .glow,
        composition: .centered,
        art: .glow,
        control: .glass,
        iconWeight: .light,
        progress: .soft,
        rule: .fade,
        ornament: .orbs,
        cornerRadius: 18,
        lyricAlignment: .center,
        revealOffset: 6,
        revealBlur: 10,
        motion: .spring(duration: 1.0, bounce: 0.1),
        palettes: [
            StylePalette(id: "lavender", name: "Lavender Mist", background: 0xE9E4FF, foreground: 0x3E3A5C, accent: 0x9B87F5, backgroundEnd: 0xFCE8F3, isDark: false),
            StylePalette(id: "dawn", name: "Dawn", background: 0xFFE9DF, foreground: 0x5A3D4A, accent: 0xF28CA8, backgroundEnd: 0xFFD6E8, isDark: false),
            StylePalette(id: "aurora", name: "Aurora", background: 0x0E1630, foreground: 0xE8F1FF, accent: 0x8EF0D6, backgroundEnd: 0x1B3A4B, isDark: true),
        ]
    )

    static let wabiSabi = DesignStyle(
        id: .wabiSabi,
        name: "Wabi Sabi",
        summary: "Earth tones, paper grain, gentle imperfection",
        fonts: FontSet(
            display: .named("HoeflerText-Regular"),
            body: .named("GillSans-Light"),
            emphasis: .named("HoeflerText-Italic"),
            label: .named("GillSans"),
            lyric: .named("HoeflerText-Regular")
        ),
        labelTracking: 1.2,
        labelCase: .lowercase,
        titleScale: 0.95,
        art: .organic,
        control: .pebble,
        iconWeight: .regular,
        progress: .brush,
        rule: .hairline,
        ornament: .grain,
        cornerRadius: 14,
        revealOffset: 12,
        motion: .easeInOut(duration: 0.8),
        palettes: [
            StylePalette(id: "clay", name: "Clay", background: 0xE9E1D3, foreground: 0x3E342B, accent: 0xA0623E, isDark: false),
            StylePalette(id: "moss", name: "Moss", background: 0xDCDCCB, foreground: 0x2F3326, accent: 0x6E7B4E, isDark: false),
            StylePalette(id: "stone", name: "Stone", background: 0xD6D3CE, foreground: 0x33312E, accent: 0x7D756B, isDark: false),
            StylePalette(id: "sumi", name: "Sumi", background: 0x1E1C1A, foreground: 0xE6DFD3, accent: 0xB08D57, isDark: true),
        ]
    )

    static let y2k = DesignStyle(
        id: .y2k,
        name: "Y2K Aesthetic",
        summary: "Chrome, gloss, bubbles and sparkles",
        fonts: FontSet(
            display: .named("ArialRoundedMTBold"),
            body: .system(.semibold, .rounded),
            emphasis: .system(.medium, .rounded),
            label: .named("Menlo-Bold"),
            lyric: .named("ArialRoundedMTBold")
        ),
        titleTracking: -0.01,
        labelTracking: 1,
        titleScale: 1.05,
        titleEffect: .chrome,
        composition: .centered,
        art: .chrome,
        control: .glossyPill,
        iconWeight: .heavy,
        progress: .glossy,
        rule: .none,
        ornament: .sparkles,
        cornerRadius: 22,
        lyricAlignment: .center,
        revealOffset: 26,
        motion: .spring(duration: 0.55, bounce: 0.45),
        palettes: [
            StylePalette(id: "cyber", name: "Cyber Pink", background: 0xFF6FD8, foreground: 0xFFFFFF, accent: 0xFFF35C, backgroundEnd: 0x7B6CFF, isDark: true),
            StylePalette(id: "bubblegum", name: "Bubblegum", background: 0xFFD1F0, foreground: 0x4A2A6A, accent: 0xFF4FB8, backgroundEnd: 0xC9F2FF, isDark: false),
            StylePalette(id: "matrix", name: "Matrix", background: 0x050A05, foreground: 0xB6FF6B, accent: 0x39FF14, backgroundEnd: 0x0F2A12, isDark: true),
            StylePalette(id: "ice", name: "Ice Chrome", background: 0xE4ECF7, foreground: 0x1C2433, accent: 0x3D7BFF, backgroundEnd: 0xA9B8CC, isDark: false),
        ]
    )

    static let editorial = DesignStyle(
        id: .editorial,
        name: "Editorial Design",
        summary: "Magazine spread: serif headlines, kickers, rules",
        fonts: FontSet(
            display: .system(.black, .serif),
            body: .named("Charter-Roman"),
            emphasis: .named("Charter-Italic"),
            label: .named("Futura-Bold"),
            lyric: .system(.bold, .serif)
        ),
        titleTracking: -0.02,
        labelTracking: 2,
        titleScale: 1.1,
        art: .captioned,
        control: .square,
        iconWeight: .semibold,
        progress: .ruled,
        rule: .double,
        ornament: .columns,
        revealOffset: 14,
        motion: .smooth(duration: 0.6),
        palettes: [
            StylePalette(id: "newsprint", name: "Newsprint", background: 0xF4F0E6, foreground: 0x141414, accent: 0xC8102E, isDark: false),
            StylePalette(id: "sunday", name: "Sunday", background: 0xFBF6EA, foreground: 0x1D2A44, accent: 0xB5532E, isDark: false),
            StylePalette(id: "night", name: "Night Edition", background: 0x151515, foreground: 0xEDE7DA, accent: 0xE0B04B, isDark: true),
        ]
    )
}
