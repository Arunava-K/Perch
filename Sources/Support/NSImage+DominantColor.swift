import AppKit
import SwiftUI

extension NSImage {
    /// A vivid accent color sampled from the image — the average color, with its
    /// saturation/brightness boosted so it reads as an accent (album-art glow,
    /// equalizer tint, etc.). Returns nil if the image can't be sampled.
    func accentColor() -> NSColor? {
        guard let tiff = tiffRepresentation,
              let source = NSBitmapImageRep(data: tiff)?.cgImage else { return nil }

        // Average the image down to a single pixel.
        let space = CGColorSpaceCreateDeviceRGB()
        let bitmapInfo = CGImageAlphaInfo.premultipliedLast.rawValue
        guard let ctx = CGContext(data: nil, width: 1, height: 1, bitsPerComponent: 8,
                                  bytesPerRow: 4, space: space, bitmapInfo: bitmapInfo),
              let data = { () -> UnsafeMutableRawPointer? in
                  ctx.interpolationQuality = .medium
                  ctx.draw(source, in: CGRect(x: 0, y: 0, width: 1, height: 1))
                  return ctx.data
              }() else { return nil }

        let p = data.bindMemory(to: UInt8.self, capacity: 4)
        let r = CGFloat(p[0]) / 255, g = CGFloat(p[1]) / 255, b = CGFloat(p[2]) / 255

        let base = NSColor(srgbRed: r, green: g, blue: b, alpha: 1)
        var h: CGFloat = 0, s: CGFloat = 0, v: CGFloat = 0, a: CGFloat = 0
        base.getHue(&h, saturation: &s, brightness: &v, alpha: &a)
        // Punch up muted album-art averages into a usable accent.
        return NSColor(hue: h,
                       saturation: min(1, s * 1.7 + 0.12),
                       brightness: max(0.62, min(1, v + 0.1)),
                       alpha: 1)
    }
}
