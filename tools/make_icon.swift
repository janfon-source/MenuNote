// Renders MenuNote/AppIcon.icns.  Run from MenuNoteMac/:  swift tools/make_icon.swift
import AppKit

let backTop = NSColor(red: 0.231, green: 0.459, blue: 0.894, alpha: 1)
let backBottom = NSColor(red: 0.137, green: 0.290, blue: 0.690, alpha: 1)
let paper = NSColor(red: 0.992, green: 0.984, blue: 0.957, alpha: 1)
let rule = NSColor(red: 0.722, green: 0.769, blue: 0.851, alpha: 1)
let pencil = NSColor(red: 0.973, green: 0.737, blue: 0.231, alpha: 1)
let wood = NSColor(red: 0.961, green: 0.851, blue: 0.690, alpha: 1)
let lead = NSColor(red: 0.188, green: 0.208, blue: 0.259, alpha: 1)
let eraser = NSColor(red: 0.906, green: 0.447, blue: 0.494, alpha: 1)

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

    // A sheet of ruled paper.
    let sheet = NSRect(x: s * 0.27, y: s * 0.2, width: s * 0.46, height: s * 0.58)
    paper.setFill()
    NSBezierPath(roundedRect: sheet, xRadius: s * 0.035, yRadius: s * 0.035).fill()
    rule.setFill()
    for i in 0..<5 {
        let y = sheet.maxY - s * 0.13 - CGFloat(i) * s * 0.085
        let w = i == 4 ? sheet.width * 0.4 : sheet.width - s * 0.12
        NSBezierPath(roundedRect: NSRect(x: sheet.minX + s * 0.06, y: y, width: w, height: s * 0.022),
                     xRadius: s * 0.011, yRadius: s * 0.011).fill()
    }

    // A pencil across the lower-right corner, pointing down-left.
    NSGraphicsContext.saveGraphicsState()
    let t = NSAffineTransform()
    t.translateX(by: s * 0.63, yBy: s * 0.36)
    t.rotate(byDegrees: 135)
    t.concat()
    let len = s * 0.36, w = s * 0.085
    pencil.setFill()
    NSRect(x: -len / 2, y: -w / 2, width: len, height: w).fill()
    eraser.setFill()
    NSBezierPath(roundedRect: NSRect(x: -len / 2 - s * 0.06, y: -w / 2, width: s * 0.07, height: w),
                 xRadius: s * 0.02, yRadius: s * 0.02).fill()
    let tip = NSBezierPath()
    tip.move(to: NSPoint(x: len / 2, y: -w / 2))
    tip.line(to: NSPoint(x: len / 2 + s * 0.09, y: 0))
    tip.line(to: NSPoint(x: len / 2, y: w / 2))
    tip.close()
    wood.setFill()
    tip.fill()
    let point = NSBezierPath()
    point.move(to: NSPoint(x: len / 2 + s * 0.06, y: -w * 0.17))
    point.line(to: NSPoint(x: len / 2 + s * 0.09, y: 0))
    point.line(to: NSPoint(x: len / 2 + s * 0.06, y: w * 0.17))
    point.close()
    lead.setFill()
    point.fill()
    NSGraphicsContext.restoreGraphicsState()

    NSGraphicsContext.restoreGraphicsState()
    return rep.representation(using: .png, properties: [:])!
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
