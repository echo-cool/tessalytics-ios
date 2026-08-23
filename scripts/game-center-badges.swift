// Renders the Game Center achievement badges: 512x512, opaque, no alpha.
import AppKit
import Foundation
import ImageIO

struct Badge { let file: String; let symbol: String; let top: NSColor; let bottom: NSColor }

// The app's own palette. Category decides the colour so twelve badges read as a
// set rather than twelve unrelated icons: red for distance, green for energy,
// amber for time, steel for the car's own record.
let accent   = (NSColor(srgbRed: 0.80, green: 0.00, blue: 0.00, alpha: 1),
                NSColor(srgbRed: 0.53, green: 0.00, blue: 0.00, alpha: 1))
let positive = (NSColor(srgbRed: 0.13, green: 0.62, blue: 0.36, alpha: 1),
                NSColor(srgbRed: 0.06, green: 0.36, blue: 0.21, alpha: 1))
let warning  = (NSColor(srgbRed: 0.85, green: 0.47, blue: 0.09, alpha: 1),
                NSColor(srgbRed: 0.55, green: 0.27, blue: 0.03, alpha: 1))
let steel    = (NSColor(srgbRed: 0.33, green: 0.36, blue: 0.42, alpha: 1),
                NSColor(srgbRed: 0.16, green: 0.18, blue: 0.22, alpha: 1))

let badges: [Badge] = [
    Badge(file: "firstDrive",     symbol: "car.fill",                  top: steel.0,    bottom: steel.1),
    Badge(file: "distance1000",   symbol: "road.lanes",                top: accent.0,   bottom: accent.1),
    Badge(file: "distance10000",  symbol: "globe.europe.africa.fill",  top: accent.0,   bottom: accent.1),
    Badge(file: "distance100000", symbol: "infinity",                  top: accent.0,   bottom: accent.1),
    Badge(file: "longDrive300",   symbol: "arrow.left.and.right",      top: accent.0,   bottom: accent.1),
    Badge(file: "charges100",     symbol: "bolt.fill",                 top: positive.0, bottom: positive.1),
    Badge(file: "energy1000",     symbol: "bolt.batteryblock.fill",    top: positive.0, bottom: positive.1),
    Badge(file: "streak7",        symbol: "calendar",                  top: warning.0,  bottom: warning.1),
    Badge(file: "night10",        symbol: "moon.stars.fill",           top: steel.0,    bottom: steel.1),
    Badge(file: "places25",       symbol: "map.fill",                  top: warning.0,  bottom: warning.1),
    Badge(file: "versions10",     symbol: "shippingbox.fill",          top: steel.0,    bottom: steel.1),
    Badge(file: "health90",       symbol: "heart.text.square.fill",    top: positive.0, bottom: positive.1),
]

let side = 512.0
let outDir = URL(fileURLWithPath: CommandLine.arguments[1])
try? FileManager.default.createDirectory(at: outDir, withIntermediateDirectories: true)

/// The symbol as a CGImage, used below as a mask so the glyph can be filled
/// white regardless of how the symbol itself is coloured.
func glyph(_ name: String, points: CGFloat) -> CGImage? {
    let config = NSImage.SymbolConfiguration(pointSize: points, weight: .semibold)
    guard let image = NSImage(systemSymbolName: name, accessibilityDescription: nil)?
        .withSymbolConfiguration(config) else { return nil }
    var rect = NSRect(origin: .zero, size: image.size)
    return image.cgImage(forProposedRect: &rect, context: nil, hints: nil)
}

func components(_ color: NSColor) -> [CGFloat] {
    let c = color.usingColorSpace(.sRGB) ?? color
    return [c.redComponent, c.greenComponent, c.blueComponent, 1]
}

for badge in badges {
    // Opaque by construction: Game Center rejects an alpha channel, and
    // `noneSkipLast` writes a PNG with none.
    guard let ctx = CGContext(
        data: nil, width: Int(side), height: Int(side), bitsPerComponent: 8, bytesPerRow: 0,
        space: CGColorSpace(name: CGColorSpace.sRGB)!,
        bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue
    ) else { fatalError("no context") }

    let space = CGColorSpace(name: CGColorSpace.sRGB)!
    if let gradient = CGGradient(
        colorSpace: space,
        colorComponents: components(badge.top) + components(badge.bottom),
        locations: [0, 1], count: 2
    ) {
        ctx.drawLinearGradient(
            gradient, start: CGPoint(x: 0, y: side), end: CGPoint(x: 0, y: 0), options: []
        )
    }

    // A rounded rule inside the edge, so the badge reads as a badge.
    let inset = side * 0.11
    let ring = CGPath(
        roundedRect: CGRect(x: inset, y: inset, width: side - inset * 2, height: side - inset * 2),
        cornerWidth: side * 0.22, cornerHeight: side * 0.22, transform: nil
    )
    ctx.setStrokeColor(CGColor(gray: 1, alpha: 0.24))
    ctx.setLineWidth(side * 0.013)
    ctx.addPath(ring)
    ctx.strokePath()

    if let mask = glyph(badge.symbol, points: side * 0.34) {
        let aspect = CGFloat(mask.width) / CGFloat(mask.height)
        let limit = side * 0.44
        let drawn = aspect >= 1
            ? CGSize(width: limit, height: limit / aspect)
            : CGSize(width: limit * aspect, height: limit)
        let rect = CGRect(
            x: (side - drawn.width) / 2, y: (side - drawn.height) / 2,
            width: drawn.width, height: drawn.height
        )
        ctx.saveGState()
        ctx.clip(to: rect, mask: mask)
        ctx.setFillColor(CGColor(gray: 1, alpha: 1))
        ctx.fill(rect)
        ctx.restoreGState()
    } else {
        FileHandle.standardError.write("missing symbol \(badge.symbol)\n".data(using: .utf8)!)
    }

    guard let image = ctx.makeImage() else { fatalError("no image") }
    let url = outDir.appendingPathComponent("\(badge.file).png")
    guard let dest = CGImageDestinationCreateWithURL(url as CFURL, "public.png" as CFString, 1, nil)
    else { fatalError("no destination") }
    CGImageDestinationAddImage(dest, image, nil)
    guard CGImageDestinationFinalize(dest) else { fatalError("write failed") }
    let bytes = (try? FileManager.default.attributesOfItem(atPath: url.path)[.size] as? Int) ?? 0
    print("\(badge.file).png  \(image.width)x\(image.height)  \((bytes ?? 0) / 1024) KB")
}
