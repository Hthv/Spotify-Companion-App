import CoreGraphics
import CoreImage
import Foundation
import ImageIO

/// An sRGB color with components in 0...1.
struct RGB: Equatable, Sendable {
    var r: Double
    var g: Double
    var b: Double

    static let ink = RGB(r: 0.067, g: 0.067, b: 0.067)
    static let paper = RGB(r: 0.949, g: 0.945, b: 0.925)

    /// WCAG relative luminance.
    var luminance: Double {
        func linear(_ c: Double) -> Double { c <= 0.04045 ? c / 12.92 : pow((c + 0.055) / 1.055, 2.4) }
        return 0.2126 * linear(r) + 0.7152 * linear(g) + 0.0722 * linear(b)
    }

    var saturation: Double {
        let high = max(r, g, b), low = min(r, g, b)
        return high == 0 ? 0 : (high - low) / high
    }

    /// WCAG contrast ratio, 1...21.
    func contrast(with other: RGB) -> Double {
        let l1 = luminance, l2 = other.luminance
        return (max(l1, l2) + 0.05) / (min(l1, l2) + 0.05)
    }
}

/// The colors the "Auto" theme is built from.
struct Palette: Equatable, Sendable {
    /// The most common color in the artwork.
    var background: RGB
    /// A vivid color that stands out against `background`, if the artwork has one.
    var accent: RGB?
}

enum PaletteExtractor {
    /// The cover shrunk, blurred until only its light remains, and a little more saturated:
    /// the "Album Blur" backdrop, computed once per cover rather than blurred live every frame.
    static func blurredBackdrop(from data: Data) -> CGImage? {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil),
              let small = CGImageSourceCreateThumbnailAtIndex(source, 0, [
                  kCGImageSourceCreateThumbnailFromImageAlways: true,
                  kCGImageSourceThumbnailMaxPixelSize: 160,
              ] as CFDictionary)
        else { return nil }
        let input = CIImage(cgImage: small)
        let blurred = input
            .clampedToExtent()
            .applyingGaussianBlur(sigma: 22)
            .applyingFilter("CIColorControls", parameters: [kCIInputSaturationKey: 1.35])
            .cropped(to: input.extent)
        return CIContext(options: [.useSoftwareRenderer: false]).createCGImage(blurred, from: input.extent)
    }

    static func palette(from data: Data) -> Palette? {
        let side = 32
        guard let source = CGImageSourceCreateWithData(data as CFData, nil),
              let thumbnail = CGImageSourceCreateThumbnailAtIndex(source, 0, [
                  kCGImageSourceCreateThumbnailFromImageAlways: true,
                  kCGImageSourceThumbnailMaxPixelSize: side * 2,
              ] as CFDictionary),
              let space = CGColorSpace(name: CGColorSpace.sRGB)
        else { return nil }

        var pixels = [UInt8](repeating: 0, count: side * side * 4)
        let drawn = pixels.withUnsafeMutableBytes { buffer -> Bool in
            guard let context = CGContext(
                data: buffer.baseAddress, width: side, height: side,
                bitsPerComponent: 8, bytesPerRow: side * 4, space: space,
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
            ) else { return false }
            context.interpolationQuality = .medium
            context.draw(thumbnail, in: CGRect(x: 0, y: 0, width: side, height: side))
            return true
        }
        guard drawn else { return nil }

        // Quantize to 3 bits per channel (512 buckets) and average each bucket.
        struct Bucket { var count = 0, r = 0, g = 0, b = 0 }
        var buckets: [Int: Bucket] = [:]
        for i in stride(from: 0, to: pixels.count, by: 4) where pixels[i + 3] > 200 {
            let r = Int(pixels[i]), g = Int(pixels[i + 1]), b = Int(pixels[i + 2])
            let key = (r >> 5) << 6 | (g >> 5) << 3 | (b >> 5)
            buckets[key, default: Bucket()].count += 1
            buckets[key]!.r += r
            buckets[key]!.g += g
            buckets[key]!.b += b
        }

        let total = Double(buckets.values.reduce(0) { $0 + $1.count })
        guard total > 0 else { return nil }

        let swatches = buckets.values.map { bucket in
            let n = Double(bucket.count) * 255
            return (color: RGB(r: Double(bucket.r) / n, g: Double(bucket.g) / n, b: Double(bucket.b) / n),
                    share: Double(bucket.count) / total)
        }
        guard let background = swatches.max(by: { $0.share < $1.share })?.color else { return nil }

        // Favor saturated colors that cover a real part of the cover and read against the background.
        let accent = swatches
            .filter { $0.share >= 0.01 && $0.color.saturation > 0.3 && $0.color.contrast(with: background) >= 3 }
            .max { $0.color.saturation * $0.share.squareRoot() < $1.color.saturation * $1.share.squareRoot() }?
            .color

        return Palette(background: background, accent: accent)
    }
}
