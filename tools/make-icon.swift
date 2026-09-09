// Renders Resources/AppIcon.iconset/*.png for Tide and packs them into AppIcon.icns.
// Usage: swift tools/make-icon.swift  (run from the project root)
import AppKit

func render(_ px: Int) -> NSBitmapImageRep {
    let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: px, pixelsHigh: px, bitsPerSample: 8,
                               samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                               colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    let ctx = NSGraphicsContext(bitmapImageRep: rep)!
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = ctx
    let cg = ctx.cgContext
    let s = CGFloat(px) / 1024.0
    cg.scaleBy(x: s, y: s)

    // macOS icon grid: 824pt rounded square on a 1024 canvas.
    let tile = CGRect(x: 100, y: 100, width: 824, height: 824)
    let tilePath = NSBezierPath(roundedRect: tile, xRadius: 186, yRadius: 186)

    // Drop shadow under the tile
    cg.saveGState()
    cg.setShadow(offset: CGSize(width: 0, height: -14), blur: 40, color: NSColor.black.withAlphaComponent(0.28).cgColor)
    NSColor(srgbRed: 0.16, green: 0.42, blue: 0.93, alpha: 1).setFill()
    tilePath.fill()
    cg.restoreGState()

    // Blue gradient body
    cg.saveGState()
    tilePath.addClip()
    let body = NSGradient(colors: [NSColor(srgbRed: 0.42, green: 0.70, blue: 1.00, alpha: 1),
                                   NSColor(srgbRed: 0.18, green: 0.45, blue: 0.96, alpha: 1),
                                   NSColor(srgbRed: 0.10, green: 0.30, blue: 0.80, alpha: 1)])!
    body.draw(in: tile, angle: -90)

    // Liquid: two soft translucent waves across the lower half
    func wave(yBase: CGFloat, amp: CGFloat, phase: CGFloat, alpha: CGFloat) {
        let p = NSBezierPath()
        p.move(to: CGPoint(x: tile.minX, y: tile.minY))
        p.line(to: CGPoint(x: tile.minX, y: yBase))
        var x = tile.minX
        while x <= tile.maxX {
            let t = (x - tile.minX) / tile.width
            let y = yBase + sin(t * .pi * 2 + phase) * amp
            p.line(to: CGPoint(x: x, y: y)); x += 8
        }
        p.line(to: CGPoint(x: tile.maxX, y: tile.minY))
        p.close()
        NSColor.white.withAlphaComponent(alpha).setFill()
        p.fill()
    }
    wave(yBase: 330, amp: 34, phase: 0.6, alpha: 0.10)
    wave(yBase: 270, amp: 28, phase: 2.4, alpha: 0.14)

    // Glass sheen on the top edge
    let sheen = NSGradient(colors: [NSColor.white.withAlphaComponent(0.42), NSColor.white.withAlphaComponent(0.0)])!
    sheen.draw(in: CGRect(x: tile.minX, y: tile.midY, width: tile.width, height: tile.height / 2), angle: -90)
    cg.restoreGState()

    // The page: a white sheet, slightly tilted, with shadow
    cg.saveGState()
    let page = CGRect(x: 302, y: 236, width: 420, height: 560)
    let rot = CGAffineTransform(translationX: page.midX, y: page.midY).rotated(by: -0.06).translatedBy(x: -page.midX, y: -page.midY)
    cg.concatenate(rot)
    cg.setShadow(offset: CGSize(width: 0, height: -10), blur: 30, color: NSColor(srgbRed: 0.05, green: 0.15, blue: 0.45, alpha: 0.45).cgColor)
    let pagePath = NSBezierPath(roundedRect: page, xRadius: 34, yRadius: 34)
    NSColor(srgbRed: 0.98, green: 0.99, blue: 1.0, alpha: 1).setFill()
    pagePath.fill()
    cg.setShadow(offset: .zero, blur: 0, color: nil)

    // Text lines on the page: title, a highlighted line, body lines
    let ink = NSColor(srgbRed: 0.16, green: 0.40, blue: 0.90, alpha: 1)
    func line(_ y: CGFloat, _ w: CGFloat, _ h: CGFloat, color: NSColor) {
        NSBezierPath(roundedRect: CGRect(x: page.minX + 56, y: y, width: w, height: h), xRadius: h/2, yRadius: h/2).fill(color)
    }
    line(page.maxY - 118, 210, 30, color: ink)                                   // title
    // highlight bar (sky) behind a body line
    NSBezierPath(roundedRect: CGRect(x: page.minX + 48, y: page.maxY - 214, width: 268, height: 40), xRadius: 12, yRadius: 12)
        .fill(NSColor(srgbRed: 0.75, green: 0.88, blue: 1.0, alpha: 1))
    line(page.maxY - 204, 250, 18, color: ink.withAlphaComponent(0.55))
    line(page.maxY - 262, 300, 18, color: ink.withAlphaComponent(0.30))
    line(page.maxY - 310, 280, 18, color: ink.withAlphaComponent(0.30))
    line(page.maxY - 358, 220, 18, color: ink.withAlphaComponent(0.30))
    // bullet items
    for (i, w) in [(0, 190.0), (1, 160.0)] {
        let y = page.maxY - 420 - CGFloat(i) * 48
        NSBezierPath(ovalIn: CGRect(x: page.minX + 56, y: y + 3, width: 14, height: 14)).fill(ink.withAlphaComponent(0.6))
        NSBezierPath(roundedRect: CGRect(x: page.minX + 86, y: y, width: w, height: 18), xRadius: 9, yRadius: 9).fill(ink.withAlphaComponent(0.30))
    }
    cg.restoreGState()

    NSGraphicsContext.restoreGraphicsState()
    return rep
}
extension NSBezierPath { func fill(_ c: NSColor) { c.setFill(); fill() } }

let fm = FileManager.default
let set = URL(fileURLWithPath: "Resources/AppIcon.iconset")
try? fm.removeItem(at: set)
try! fm.createDirectory(at: set, withIntermediateDirectories: true)
for base in [16, 32, 128, 256, 512] {
    for scale in [1, 2] {
        let px = base * scale
        let name = scale == 1 ? "icon_\(base)x\(base).png" : "icon_\(base)x\(base)@2x.png"
        let rep = render(px)
        try! rep.representation(using: .png, properties: [:])!.write(to: set.appendingPathComponent(name))
    }
}
// also a 1024 preview for docs
try! render(1024).representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: "docs/icon.png"))
let task = Process()
task.executableURL = URL(fileURLWithPath: "/usr/bin/iconutil")
task.arguments = ["-c", "icns", set.path, "-o", "Resources/AppIcon.icns"]
try! task.run(); task.waitUntilExit()
print(task.terminationStatus == 0 ? "wrote Resources/AppIcon.icns" : "iconutil failed")
