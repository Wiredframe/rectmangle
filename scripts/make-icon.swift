// Draws the app icon (1024 px) as a PNG: swift scripts/make-icon.swift <target.png>
import AppKit

let size: CGFloat = 1024
let image = NSImage(size: NSSize(width: size, height: size), flipped: false) { rect in
    // macOS grid: 824 px tile with a 100 px margin, corner radius about 185 px.
    let tile = rect.insetBy(dx: 100, dy: 100)
    let path = NSBezierPath(roundedRect: tile, xRadius: 185, yRadius: 185)

    NSGraphicsContext.saveGraphicsState()
    let shadow = NSShadow()
    shadow.shadowColor = NSColor.black.withAlphaComponent(0.25)
    shadow.shadowBlurRadius = 24
    shadow.shadowOffset = NSSize(width: 0, height: -10)
    shadow.set()
    NSColor.white.setFill()
    path.fill()
    NSGraphicsContext.restoreGraphicsState()

    NSGradient(colors: [NSColor(calibratedRed: 1.0, green: 0.62, blue: 0.30, alpha: 1),
                        NSColor(calibratedRed: 0.93, green: 0.33, blue: 0.20, alpha: 1)])!
        .draw(in: path, angle: -90)

    // A screen with the window snapped to its left half.
    let screen = NSRect(x: rect.midX - 260, y: rect.midY - 190, width: 520, height: 380)
    let frame = NSBezierPath(roundedRect: screen, xRadius: 48, yRadius: 48)
    NSColor.white.withAlphaComponent(0.3).setFill()
    frame.fill()
    let inner = screen.insetBy(dx: 30, dy: 30)
    let half = NSRect(x: inner.minX, y: inner.minY, width: (inner.width - 24) / 2, height: inner.height)
    NSColor.white.setFill()
    NSBezierPath(roundedRect: half, xRadius: 22, yRadius: 22).fill()
    frame.lineWidth = 30
    NSColor.white.setStroke()
    frame.setClip()
    frame.stroke()
    return true
}

let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: Int(size), pixelsHigh: Int(size), bitsPerSample: 8,
                           samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB,
                           bytesPerRow: 0, bitsPerPixel: 0)!
NSGraphicsContext.saveGraphicsState()
NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
image.draw(in: NSRect(x: 0, y: 0, width: size, height: size))
NSGraphicsContext.restoreGraphicsState()
try! rep.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: CommandLine.arguments[1]))
