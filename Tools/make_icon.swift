import Foundation
import CoreGraphics
import ImageIO
import UniformTypeIdentifiers

// Pulse app icon: an ECG line in heart red on black, 1024x1024.
// Usage: swift make_icon.swift <output.png>

let out = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "AppIcon.png"
let size = 1024

let cs = CGColorSpace(name: CGColorSpace.sRGB)!
let ctx = CGContext(
    data: nil, width: size, height: size,
    bitsPerComponent: 8, bytesPerRow: 0, space: cs,
    bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
)!

// Heart red (#FF3B5C)
func red(_ alpha: CGFloat) -> CGColor {
    CGColor(srgbRed: 1.0, green: 0.231, blue: 0.361, alpha: alpha)
}

// Background: pure black
ctx.setFillColor(CGColor(srgbRed: 0, green: 0, blue: 0, alpha: 1))
ctx.fill(CGRect(x: 0, y: 0, width: size, height: size))

// The pulse line: flat – high peak – deep dip – flat.
// Coordinates y-up, baseline just below center for optical balance.
let base: CGFloat = 496
let path = CGMutablePath()
path.move(to: CGPoint(x: 138, y: base))
path.addLine(to: CGPoint(x: 400, y: base))
path.addLine(to: CGPoint(x: 472, y: base + 308))  // Peak
path.addLine(to: CGPoint(x: 548, y: base - 212))  // deep dip
path.addLine(to: CGPoint(x: 600, y: base))
path.addLine(to: CGPoint(x: 886, y: base))

ctx.setLineWidth(50)
ctx.setLineCap(.round)
ctx.setLineJoin(.round)
ctx.setStrokeColor(red(1))

// Pass 1: Neon-Glow
ctx.setShadow(offset: .zero, blur: 90, color: red(0.85))
ctx.addPath(path)
ctx.strokePath()

// Pass 2: crisp core without shadow
ctx.setShadow(offset: .zero, blur: 0, color: nil)
ctx.addPath(path)
ctx.strokePath()

let img = ctx.makeImage()!
let dest = CGImageDestinationCreateWithURL(
    URL(fileURLWithPath: out) as CFURL,
    UTType.png.identifier as CFString, 1, nil
)!
CGImageDestinationAddImage(dest, img, nil)
guard CGImageDestinationFinalize(dest) else { fatalError("Could not write PNG") }
print("OK: \(out)")
