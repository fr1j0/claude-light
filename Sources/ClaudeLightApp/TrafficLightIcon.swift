import AppKit
import ClaudeLightCore

/// Draws the fat traffic-light menu-bar glyph: a rounded-rectangle outline
/// housing with three squared bar lamps. Exactly one bar is lit; the rest are
/// dimmed `mono`. Non-template so the lit color survives in the menu bar.
enum TrafficLightIcon {
    /// Fixed glyph size in points (fat aspect, fits the ~18pt menu-bar height).
    static let size = NSSize(width: 15, height: 18)

    static func image(lamp: IconLamp, litAlpha: CGFloat, mono: NSColor) -> NSImage {
        let image = NSImage(size: size)
        image.lockFocus()

        let stroke: CGFloat = 1.6
        let housing = NSRect(origin: .zero, size: size).insetBy(dx: stroke/2 + 0.5, dy: stroke/2 + 0.5)
        let radius = housing.width * 0.30
        let outline = NSBezierPath(roundedRect: housing, xRadius: radius, yRadius: radius)
        outline.lineWidth = stroke
        mono.setStroke()
        outline.stroke()

        let lamps: [IconLamp] = [.red, .orange, .green]   // top → bottom
        let innerTop = housing.maxY - housing.width * 0.20
        let innerBot = housing.minY + housing.width * 0.20
        let span = innerTop - innerBot
        let centers = [innerTop, (innerTop + innerBot) / 2, innerBot]
        let barW = housing.width * 0.60
        let barH = span / 3 * 0.78
        let barR = barH * 0.22

        for i in 0..<3 {
            let rect = NSRect(x: housing.midX - barW/2, y: centers[i] - barH/2, width: barW, height: barH)
            let isLit = lamps[i] == lamp
            let fill = isLit ? litColor(lamps[i]).withAlphaComponent(litAlpha)
                             : mono.withAlphaComponent(0.28)
            fill.setFill()
            NSBezierPath(roundedRect: rect, xRadius: barR, yRadius: barR).fill()
        }

        image.unlockFocus()
        image.isTemplate = false
        return image
    }

    private static func litColor(_ lamp: IconLamp) -> NSColor {
        switch lamp {
        case .red:    return NSColor(srgbRed: 1.00, green: 0.23, blue: 0.19, alpha: 1)
        case .orange: return NSColor(srgbRed: 1.00, green: 0.58, blue: 0.00, alpha: 1)
        case .green:  return NSColor(srgbRed: 0.20, green: 0.78, blue: 0.35, alpha: 1)
        case .off:    return .clear
        }
    }
}
