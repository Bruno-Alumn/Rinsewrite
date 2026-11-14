import AppKit
import SwiftUI

/// The teal of the app icon's water (#14A3B8). Everything else uses system colors.
extension Color {
    static let rinseTeal = Color(red: 0.078, green: 0.639, blue: 0.722)
}

/// The menu bar icon: two lines of text and a drop of water, drawn as a
/// template image so macOS tints it for light and dark menu bars. While
/// Rinsewrite can't rinse (no access, model loading) it's drawn fainter.
enum MenuBarIcon {
    static let ready = make(alpha: 1)
    static let waiting = make(alpha: 0.45)

    private static func make(alpha: CGFloat) -> NSImage {
        let image = NSImage(size: NSSize(width: 18, height: 18), flipped: false) { _ in
            NSColor.black.withAlphaComponent(alpha).set()
            // Lines of text, bottom left.
            for (y, width) in [(4.0, 9.0), (8.0, 6.5), (12.0, 8.0)] as [(CGFloat, CGFloat)] {
                NSBezierPath(roundedRect: NSRect(x: 1.5, y: y, width: width, height: 1.8), xRadius: 0.9, yRadius: 0.9).fill()
            }
            // A drop, right.
            let cx: CGFloat = 13.6, cy: CGFloat = 6.4, r: CGFloat = 3.3
            let drop = NSBezierPath()
            drop.move(to: NSPoint(x: cx, y: cy + r * 2.75))
            drop.curve(to: NSPoint(x: cx - r, y: cy),
                       controlPoint1: NSPoint(x: cx - r * 0.35, y: cy + r * 1.9),
                       controlPoint2: NSPoint(x: cx - r, y: cy + r * 0.9))
            drop.appendArc(withCenter: NSPoint(x: cx, y: cy), radius: r, startAngle: 180, endAngle: 360)
            drop.curve(to: NSPoint(x: cx, y: cy + r * 2.75),
                       controlPoint1: NSPoint(x: cx + r, y: cy + r * 0.9),
                       controlPoint2: NSPoint(x: cx + r * 0.35, y: cy + r * 1.9))
            drop.close()
            drop.fill()
            return true
        }
        image.isTemplate = true
        image.accessibilityDescription = "Rinsewrite"
        return image
    }
}
