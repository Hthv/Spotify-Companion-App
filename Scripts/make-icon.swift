// Draws the app icon into the asset catalog at every size macOS needs.
// Usage: swift Scripts/make-icon.swift SpotifyCompanion/Assets.xcassets/AppIcon.appiconset
import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

let outputDirectory = URL(fileURLWithPath: CommandLine.arguments[1])
let space = CGColorSpace(name: CGColorSpace.sRGB)!

func color(_ hex: UInt32) -> CGColor {
    CGColor(
        colorSpace: space,
        components: [CGFloat((hex >> 16) & 0xFF) / 255, CGFloat((hex >> 8) & 0xFF) / 255, CGFloat(hex & 0xFF) / 255, 1]
    )!
}

/// Swiss poster in miniature: paper field, a black disc with a red label, flush-left lines of type.
func draw(pixels: Int) -> CGImage {
    let context = CGContext(
        data: nil, width: pixels, height: pixels, bitsPerComponent: 8, bytesPerRow: 0, space: space,
        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
    )!
    let scale = CGFloat(pixels) / 1024
    context.scaleBy(x: scale, y: scale)

    // macOS icon grid: 824pt body inset 100pt, continuous-ish corners.
    let body = CGRect(x: 100, y: 100, width: 824, height: 824)
    let shape = CGPath(roundedRect: body, cornerWidth: 185, cornerHeight: 185, transform: nil)
    context.addPath(shape)
    context.setFillColor(color(0xF2F1EC))
    context.fillPath()

    context.addPath(shape)
    context.clip()

    // Disc, pushed off-center toward the lower left, as on a Müller-Brockmann poster.
    context.setFillColor(color(0x111111))
    context.fillEllipse(in: CGRect(x: 170, y: 170, width: 520, height: 520))
    context.setFillColor(color(0xDA291C))
    context.fillEllipse(in: CGRect(x: 375, y: 375, width: 110, height: 110))

    // Flush-left lines of "type", top right: title in red, then two in black.
    context.fill(CGRect(x: 620, y: 770, width: 200, height: 40))
    context.setFillColor(color(0x111111))
    context.fill(CGRect(x: 620, y: 720, width: 140, height: 16))
    context.fill(CGRect(x: 620, y: 690, width: 170, height: 16))

    return context.makeImage()!
}

let sizes: [(name: String, pixels: Int)] = [
    ("icon_16x16.png", 16), ("icon_16x16@2x.png", 32),
    ("icon_32x32.png", 32), ("icon_32x32@2x.png", 64),
    ("icon_128x128.png", 128), ("icon_128x128@2x.png", 256),
    ("icon_256x256.png", 256), ("icon_256x256@2x.png", 512),
    ("icon_512x512.png", 512), ("icon_512x512@2x.png", 1024),
]

for (name, pixels) in sizes {
    let url = outputDirectory.appendingPathComponent(name)
    let destination = CGImageDestinationCreateWithURL(url as CFURL, UTType.png.identifier as CFString, 1, nil)!
    CGImageDestinationAddImage(destination, draw(pixels: pixels), nil)
    guard CGImageDestinationFinalize(destination) else { fatalError("Could not write \(name)") }
}
print("Wrote \(sizes.count) icons to \(outputDirectory.path)")
