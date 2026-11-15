// Build the Rinsewrite app icon from packaging/icon-source.png: the artwork
// fitted to the macOS icon grid (an 824 px tile on a 1024 px canvas) with
// the standard shadow.
//
// Run via: swift scripts/make_icon.swift packaging/icon-source.png Resources/AppIcon.icns [docs/logo.png]
//
// Writes every size iconutil expects, and optionally a 512 px PNG for the README.

import AppKit

let canvas: CGFloat = 1024
let body = CGRect(x: 100, y: 100, width: 824, height: 824)
let cornerRadius: CGFloat = 185

let args = CommandLine.arguments
guard args.count >= 3 else {
    print("usage: make_icon.swift <source.png> <AppIcon.icns> [preview.png]")
    exit(1)
}

let source = NSImage(contentsOfFile: args[1])!

func draw() {
    let tile = NSBezierPath(roundedRect: body, xRadius: cornerRadius, yRadius: cornerRadius)

    // Soft shadow under the tile, as on every macOS icon.
    NSGraphicsContext.saveGraphicsState()
    let shadow = NSShadow()
    shadow.shadowColor = NSColor(white: 0, alpha: 0.3)
    shadow.shadowOffset = NSSize(width: 0, height: -10)
    shadow.shadowBlurRadius = 24
    shadow.set()
    NSColor(srgbRed: 0.99, green: 0.94, blue: 0.85, alpha: 1).setFill()
    tile.fill()
    NSGraphicsContext.restoreGraphicsState()

    // The artwork, clipped to the macOS tile shape. Its own rounded corners
    // are smaller than the tile's, so they fall outside the clip.
    NSGraphicsContext.saveGraphicsState()
    tile.addClip()
    source.draw(in: body, from: .zero, operation: .sourceOver, fraction: 1)
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
iconutil.arguments = ["-c", "icns", work.path, "-o", args[2]]
try! iconutil.run()
iconutil.waitUntilExit()
try? FileManager.default.removeItem(at: work)
print(args[2])
if args.count >= 4 {
    try! render(size: 512).representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: args[3]))
    print(args[3])
}
