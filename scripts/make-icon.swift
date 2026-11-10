// Draws MathPeek's app icon and writes Resources/AppIcon.icns and docs/icon.png.
//
//   swift scripts/make-icon.swift
//
// A magnifying glass over the ± ÷ symbol, on a blue rounded square in the macOS icon grid.
import AppKit

let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
let canvas: CGFloat = 1024

func color(_ hex: UInt32, _ alpha: CGFloat = 1) -> CGColor {
    CGColor(srgbRed: CGFloat((hex >> 16) & 0xFF) / 255, green: CGFloat((hex >> 8) & 0xFF) / 255,
            blue: CGFloat(hex & 0xFF) / 255, alpha: alpha)
}

func gradient(_ colors: [CGColor]) -> CGGradient {
    CGGradient(colorsSpace: CGColorSpace(name: CGColorSpace.sRGB), colors: colors as CFArray, locations: nil)!
}

func drawIcon(in context: CGContext) {
    // Core Graphics' origin is bottom-left, so y grows upward here.
    // The body: 824 pt with a continuous-looking corner, per Apple's icon grid.
    let body = CGRect(x: 100, y: 100, width: 824, height: 824)
    let bodyPath = CGPath(roundedRect: body, cornerWidth: 186, cornerHeight: 186, transform: nil)

    context.saveGState()
    context.setShadow(offset: CGSize(width: 0, height: -12), blur: 28, color: color(0x000000, 0.35))
    context.addPath(bodyPath)
    context.setFillColor(color(0x000000))
    context.fillPath()
    context.restoreGState()

    // A deep blue square, lighter at the top.
    context.saveGState()
    context.addPath(bodyPath)
    context.clip()
    context.drawLinearGradient(gradient([color(0x38BDF8), color(0x2563EB), color(0x312E81)]),
                               start: CGPoint(x: body.midX, y: body.maxY),
                               end: CGPoint(x: body.midX, y: body.minY), options: [])

    // A magnifying glass: the handle, then the lens with the maths symbol inside it.
    let lens = CGPoint(x: 462, y: 566)
    let radius: CGFloat = 238
    context.setShadow(offset: CGSize(width: 0, height: -10), blur: 24, color: color(0x0B1033, 0.45))
    context.setLineCap(.round)
    context.setStrokeColor(color(0xF8FAFC))
    context.setLineWidth(92)
    let along = CGPoint(x: cos(-CGFloat.pi / 4), y: sin(-CGFloat.pi / 4))
    context.move(to: CGPoint(x: lens.x + along.x * (radius + 30), y: lens.y + along.y * (radius + 30)))
    context.addLine(to: CGPoint(x: lens.x + along.x * (radius + 250), y: lens.y + along.y * (radius + 250)))
    context.strokePath()

    let lensRect = CGRect(x: lens.x - radius, y: lens.y - radius, width: radius * 2, height: radius * 2)
    context.setFillColor(color(0xFFFFFF, 0.16))
    context.fillEllipse(in: lensRect)
    context.setLineWidth(58)
    context.strokeEllipse(in: lensRect)
    context.restoreGState()

    // The app's symbol, white, in the lens.
    let configuration = NSImage.SymbolConfiguration(pointSize: 210, weight: .semibold)
        .applying(NSImage.SymbolConfiguration(paletteColors: [.white]))
    if let symbol = NSImage(systemSymbolName: "plus.forwardslash.minus", accessibilityDescription: nil)?
        .withSymbolConfiguration(configuration) {
        let size = symbol.size
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(cgContext: context, flipped: false)
        symbol.draw(in: CGRect(x: lens.x - size.width / 2, y: lens.y - size.height / 2,
                               width: size.width, height: size.height))
        NSGraphicsContext.restoreGraphicsState()
    }
}

func png(size: Int) -> Data {
    let context = CGContext(data: nil, width: size, height: size, bitsPerComponent: 8, bytesPerRow: 0,
                            space: CGColorSpace(name: CGColorSpace.sRGB)!,
                            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
    context.scaleBy(x: CGFloat(size) / canvas, y: CGFloat(size) / canvas)
    context.interpolationQuality = .high
    drawIcon(in: context)
    let rep = NSBitmapImageRep(cgImage: context.makeImage()!)
    return rep.representation(using: .png, properties: [:])!
}

let iconset = FileManager.default.temporaryDirectory.appendingPathComponent("AppIcon.iconset")
try? FileManager.default.removeItem(at: iconset)
try FileManager.default.createDirectory(at: iconset, withIntermediateDirectories: true)
for points in [16, 32, 128, 256, 512] {
    try png(size: points).write(to: iconset.appendingPathComponent("icon_\(points)x\(points).png"))
    try png(size: points * 2).write(to: iconset.appendingPathComponent("icon_\(points)x\(points)@2x.png"))
}
try FileManager.default.createDirectory(at: root.appendingPathComponent("docs"), withIntermediateDirectories: true)
try png(size: 1024).write(to: root.appendingPathComponent("docs/icon.png"))

let iconutil = Process()
iconutil.executableURL = URL(fileURLWithPath: "/usr/bin/iconutil")
iconutil.arguments = ["-c", "icns", iconset.path, "-o", root.appendingPathComponent("Resources/AppIcon.icns").path]
try iconutil.run()
iconutil.waitUntilExit()
try? FileManager.default.removeItem(at: iconset)
print(iconutil.terminationStatus == 0 ? "Wrote Resources/AppIcon.icns and docs/icon.png" : "iconutil failed")
