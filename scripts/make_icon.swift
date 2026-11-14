// Draw the Rinsewrite app icon: lines of text on a rounded square of
// clear water, with a drop rinsing across them.
//
// Run via: swift scripts/make_icon.swift Resources/AppIcon.icns [docs/logo.png]
//
// Drawn in code, so there's no source artwork to keep in sync. Writes every
// size iconutil expects, and optionally a 512 px PNG for the README.

import AppKit

let canvas: CGFloat = 1024
let body = CGRect(x: 100, y: 100, width: 824, height: 824)
let cornerRadius: CGFloat = 185

let args = CommandLine.arguments
guard args.count >= 2 else {
    print("usage: make_icon.swift <AppIcon.icns> [preview.png]")
    exit(1)
}

func color(_ hex: UInt32, _ alpha: CGFloat = 1) -> NSColor {
    NSColor(srgbRed: CGFloat((hex >> 16) & 0xFF) / 255, green: CGFloat((hex >> 8) & 0xFF) / 255,
            blue: CGFloat(hex & 0xFF) / 255, alpha: alpha)
}

func drop(center: CGPoint, radius r: CGFloat) -> NSBezierPath {
    let path = NSBezierPath()
    let tip = CGPoint(x: center.x, y: center.y + r * 2.6)
    path.move(to: tip)
    path.curve(to: CGPoint(x: center.x - r, y: center.y),
               controlPoint1: CGPoint(x: center.x - r * 0.3, y: center.y + r * 1.8),
               controlPoint2: CGPoint(x: center.x - r, y: center.y + r * 0.95))
    path.appendArc(withCenter: center, radius: r, startAngle: 180, endAngle: 360)
    path.curve(to: tip,
               controlPoint1: CGPoint(x: center.x + r, y: center.y + r * 0.95),
               controlPoint2: CGPoint(x: center.x + r * 0.3, y: center.y + r * 1.8))
    path.close()
    return path
}

func draw() {
    let tile = NSBezierPath(roundedRect: body, xRadius: cornerRadius, yRadius: cornerRadius)

    // Soft shadow under the tile, as on every macOS icon.
    NSGraphicsContext.saveGraphicsState()
    let shadow = NSShadow()
    shadow.shadowColor = NSColor(white: 0, alpha: 0.3)
    shadow.shadowOffset = NSSize(width: 0, height: -10)
    shadow.shadowBlurRadius = 24
    shadow.set()
    color(0x0B7C94).setFill()
    tile.fill()
    NSGraphicsContext.restoreGraphicsState()

    NSGraphicsContext.saveGraphicsState()
    tile.addClip()
    NSGradient(starting: color(0x3FD3E3), ending: color(0x0A6F88))!.draw(in: body, angle: -90)
    // A wave of lighter water across the lower third.
    let wave = NSBezierPath()
    wave.move(to: CGPoint(x: body.minX, y: body.minY + 250))
    wave.curve(to: CGPoint(x: body.maxX, y: body.minY + 300),
               controlPoint1: CGPoint(x: body.minX + 280, y: body.minY + 360),
               controlPoint2: CGPoint(x: body.maxX - 300, y: body.minY + 170))
    wave.line(to: CGPoint(x: body.maxX, y: body.minY))
    wave.line(to: CGPoint(x: body.minX, y: body.minY))
    wave.close()
    color(0xFFFFFF, 0.12).setFill()
    wave.fill()

    // Lines of text, rinsed clean.
    color(0xFFFFFF).setFill()
    for (y, width) in [(640.0, 420.0), (520.0, 330.0), (400.0, 380.0)] as [(CGFloat, CGFloat)] {
        NSBezierPath(roundedRect: CGRect(x: 230, y: y, width: width, height: 64), xRadius: 32, yRadius: 32).fill()
    }

    // The drop, with a highlight.
    NSGraphicsContext.saveGraphicsState()
    let dropShadow = NSShadow()
    dropShadow.shadowColor = NSColor(white: 0, alpha: 0.18)
    dropShadow.shadowOffset = NSSize(width: 0, height: -8)
    dropShadow.shadowBlurRadius = 18
    dropShadow.set()
    let main = drop(center: CGPoint(x: 700, y: 330), radius: 120)
    color(0xFFFFFF).setFill()
    main.fill()
    NSGraphicsContext.restoreGraphicsState()
    color(0x3FD3E3, 0.55).setFill()
    NSBezierPath(ovalIn: CGRect(x: 640, y: 290, width: 52, height: 90)).fill()

    // Two small bubbles.
    color(0xFFFFFF, 0.85).setFill()
    NSBezierPath(ovalIn: CGRect(x: 820, y: 560, width: 44, height: 44)).fill()
    NSBezierPath(ovalIn: CGRect(x: 770, y: 650, width: 26, height: 26)).fill()
    NSGraphicsContext.restoreGraphicsState()
}

func render(size: Int) -> NSBitmapImageRep {
    let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: size, pixelsHigh: size, bitsPerSample: 8,
                               samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                               colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    rep.size = NSSize(width: canvas, height: canvas)
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    NSGraphicsContext.current?.imageInterpolation = .high
    draw()
    NSGraphicsContext.restoreGraphicsState()
    return rep
}

let work = FileManager.default.temporaryDirectory.appendingPathComponent("Rinsewrite-\(UUID().uuidString).iconset")
try! FileManager.default.createDirectory(at: work, withIntermediateDirectories: true)
for base in [16, 32, 128, 256, 512] {
    for scale in [1, 2] {
        let name = scale == 1 ? "icon_\(base)x\(base).png" : "icon_\(base)x\(base)@2x.png"
        try! render(size: base * scale).representation(using: .png, properties: [:])!
            .write(to: work.appendingPathComponent(name))
    }
}
let iconutil = Process()
iconutil.executableURL = URL(fileURLWithPath: "/usr/bin/iconutil")
iconutil.arguments = ["-c", "icns", work.path, "-o", args[1]]
try! iconutil.run()
iconutil.waitUntilExit()
try? FileManager.default.removeItem(at: work)
print(args[1])
if args.count >= 3 {
    try! render(size: 512).representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: args[2]))
    print(args[2])
}
