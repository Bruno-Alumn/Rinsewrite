import AppKit
import SwiftUI

/// The blue of the app icon's mark (#001BC4). Everything else uses system colors.
extension Color {
    static let rinseBlue = Color(red: 0, green: 0.106, blue: 0.769)
}

/// The menu bar icon: the app icon's mark (a round stroke curling up into a
/// tail), drawn as a template image so macOS tints it for light and dark menu
/// bars. While Rinsewrite can't rinse (no access, model loading) it's drawn
/// fainter.
enum MenuBarIcon {
    static let ready = make(alpha: 1)
    static let waiting = make(alpha: 0.45)

    private static func make(alpha: CGFloat) -> NSImage {
        let image = NSImage(size: NSSize(width: 18, height: 18), flipped: false) { _ in
            NSColor.black.withAlphaComponent(alpha).set()
            // The round body; its left edge runs on into the tail.
            NSBezierPath(ovalIn: NSRect(x: 4, y: 0.99, width: 9.86, height: 9.86)).fill()
            let tail = NSBezierPath()
            tail.move(to: NSPoint(x: 5.3, y: 5.9))
            tail.curve(to: NSPoint(x: 11.3, y: 15.1),
                       controlPoint1: NSPoint(x: 5.3, y: 10.6),
                       controlPoint2: NSPoint(x: 8.6, y: 13.6))
            tail.lineWidth = 2.6
            tail.lineCapStyle = .round
            tail.stroke()
            return true
        }
        image.isTemplate = true
        image.accessibilityDescription = "Rinsewrite"
        return image
    }
}
