// Renders MenuNote/AppIcon.icns.  Run from MenuNoteMac/:  swift tools/make_icon.swift
// With a path (swift tools/make_icon.swift preview.png), writes a 512px preview there instead.
import AppKit

// Warm and bright: a note at hand, not a document to sit down to.
let backTop = NSColor(red: 1.000, green: 0.749, blue: 0.290, alpha: 1)
let backBottom = NSColor(red: 0.969, green: 0.537, blue: 0.137, alpha: 1)

/// The same pen as the menu bar icon (StatusIcon in AppDelegate.swift), in its 18-point box.
func glyph() {
    NSGraphicsContext.saveGraphicsState()
    defer { NSGraphicsContext.restoreGraphicsState() }
    let turn = NSAffineTransform()
    turn.translateX(by: 9, yBy: 9)
    turn.rotate(byDegrees: -45)
    turn.concat()
    let width: CGFloat = 4.4
    NSBezierPath(roundedRect: NSRect(x: -width / 2, y: -4.2, width: width, height: 14.4), xRadius: 1.1, yRadius: 1.1).fill()
    let tip = NSBezierPath()
    tip.move(to: NSPoint(x: -width / 2, y: -3.6))
    tip.line(to: NSPoint(x: 0, y: -10.6))
    tip.line(to: NSPoint(x: width / 2, y: -3.6))
    tip.close()
    tip.fill()
    NSGraphicsContext.current?.compositingOperation = .clear
    NSBezierPath(rect: NSRect(x: -width, y: 6.0, width: width * 2, height: 1.1)).fill()    // the band
    NSBezierPath(rect: NSRect(x: -width, y: -4.4, width: width * 2, height: 1.0)).fill()   // where the tip meets the body
}

func render(_ px: Int) -> Data {
    let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: px, pixelsHigh: px,
                               bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                               colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    let s = CGFloat(px)

    // macOS icon grid: ~10% transparent margin around a rounded square.
    let body = NSRect(x: s * 0.1, y: s * 0.1, width: s * 0.8, height: s * 0.8)
    let square = NSBezierPath(roundedRect: body, xRadius: s * 0.18, yRadius: s * 0.18)
    NSGradient(starting: backTop, ending: backBottom)!.draw(in: square, angle: -90)

    // The menu bar icon's shape, white, filling the middle of the square. It's drawn on a layer of
    // its own, so the parts it cuts out show the square through rather than leaving holes.
    let layer = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: px, pixelsHigh: px,
                                 bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                                 colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: layer)
    let place = NSAffineTransform()
    place.translateX(by: s * 0.5, yBy: s * 0.5)
    place.scale(by: s * 0.56 / 18)
    place.translateX(by: -9, yBy: -9)
    place.concat()
    NSColor.white.set()
    glyph()
    NSGraphicsContext.restoreGraphicsState()
    let shadow = NSShadow()
    shadow.shadowColor = backBottom.withAlphaComponent(0.45)
    shadow.shadowOffset = NSSize(width: 0, height: -s * 0.012)
    shadow.shadowBlurRadius = s * 0.02
    NSGraphicsContext.saveGraphicsState()
    shadow.set()
    layer.draw(in: NSRect(x: 0, y: 0, width: s, height: s), from: .zero, operation: .sourceOver, fraction: 1, respectFlipped: false, hints: nil)
    NSGraphicsContext.restoreGraphicsState()

    NSGraphicsContext.restoreGraphicsState()
    return rep.representation(using: .png, properties: [:])!
}

if CommandLine.arguments.count > 1 {
    try! render(512).write(to: URL(fileURLWithPath: CommandLine.arguments[1]))
    exit(0)
}

let fm = FileManager.default
let iconset = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("MenuNote.iconset")
try? fm.removeItem(at: iconset)
try! fm.createDirectory(at: iconset, withIntermediateDirectories: true)
for base in [16, 32, 128, 256, 512] {
    try! render(base).write(to: iconset.appendingPathComponent("icon_\(base)x\(base).png"))
    try! render(base * 2).write(to: iconset.appendingPathComponent("icon_\(base)x\(base)@2x.png"))
}

let out = URL(fileURLWithPath: "MenuNote/AppIcon.icns")
let p = Process()
p.executableURL = URL(fileURLWithPath: "/usr/bin/iconutil")
p.arguments = ["-c", "icns", iconset.path, "-o", out.path]
try! p.run()
p.waitUntilExit()
print(p.terminationStatus == 0 ? "Wrote \(out.path)" : "iconutil failed")
