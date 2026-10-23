// Renders MenuNote/AppIcon.icns.  Run from MenuNoteMac/:  swift tools/make_icon.swift
// With a path (swift tools/make_icon.swift preview.png), writes a 512px preview there instead.
import AppKit

// Warm and bright: a note at hand, not a document to sit down to.
let backTop = NSColor(red: 1.000, green: 0.749, blue: 0.290, alpha: 1)
let backBottom = NSColor(red: 0.969, green: 0.537, blue: 0.137, alpha: 1)
let note = NSColor(red: 1.000, green: 0.992, blue: 0.957, alpha: 1)
let fold = NSColor(red: 0.929, green: 0.878, blue: 0.788, alpha: 1)
let ink = NSColor(red: 0.851, green: 0.400, blue: 0.075, alpha: 1)

func render(_ px: Int) -> Data {
    let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: px, pixelsHigh: px,
                               bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                               colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    let s = CGFloat(px)

    // macOS icon grid: ~10% transparent margin around a rounded square.
    let body = NSRect(x: s * 0.1, y: s * 0.1, width: s * 0.8, height: s * 0.8)
    let bg = NSBezierPath(roundedRect: body, xRadius: s * 0.18, yRadius: s * 0.18)
    NSGradient(starting: backTop, ending: backBottom)!.draw(in: bg, angle: -90)

    // A note, a corner turned up, ready to write on.
    let sheet = NSRect(x: s * 0.27, y: s * 0.21, width: s * 0.46, height: s * 0.58)
    let corner = s * 0.12
    let page = NSBezierPath()
    page.move(to: NSPoint(x: sheet.minX, y: sheet.maxY))
    page.line(to: NSPoint(x: sheet.maxX, y: sheet.maxY))
    page.line(to: NSPoint(x: sheet.maxX, y: sheet.minY + corner))
    page.line(to: NSPoint(x: sheet.maxX - corner, y: sheet.minY))
    page.line(to: NSPoint(x: sheet.minX, y: sheet.minY))
    page.close()
    NSGraphicsContext.saveGraphicsState()
    let shadow = NSShadow()
    shadow.shadowColor = NSColor.black.withAlphaComponent(0.22)
    shadow.shadowOffset = NSSize(width: 0, height: -s * 0.012)
    shadow.shadowBlurRadius = s * 0.03
    shadow.set()
    note.setFill()
    page.fill()
    NSGraphicsContext.restoreGraphicsState()
    let flap = NSBezierPath()
    flap.move(to: NSPoint(x: sheet.maxX, y: sheet.minY + corner))
    flap.line(to: NSPoint(x: sheet.maxX - corner, y: sheet.minY + corner))
    flap.line(to: NSPoint(x: sheet.maxX - corner, y: sheet.minY))
    flap.close()
    fold.setFill()
    flap.fill()

    // A single quick stroke of handwriting.
    let scribble = NSBezierPath()
    scribble.move(to: NSPoint(x: s * 0.34, y: s * 0.54))
    scribble.curve(to: NSPoint(x: s * 0.46, y: s * 0.54), controlPoint1: NSPoint(x: s * 0.37, y: s * 0.64), controlPoint2: NSPoint(x: s * 0.42, y: s * 0.44))
    scribble.curve(to: NSPoint(x: s * 0.58, y: s * 0.54), controlPoint1: NSPoint(x: s * 0.50, y: s * 0.64), controlPoint2: NSPoint(x: s * 0.54, y: s * 0.44))
    scribble.curve(to: NSPoint(x: s * 0.66, y: s * 0.56), controlPoint1: NSPoint(x: s * 0.61, y: s * 0.61), controlPoint2: NSPoint(x: s * 0.64, y: s * 0.59))
    scribble.lineWidth = s * 0.036
    scribble.lineCapStyle = .round
    scribble.lineJoinStyle = .round
    ink.setStroke()
    scribble.stroke()

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
