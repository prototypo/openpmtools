// Draws Resources/AppIcon.icns. Run from the repo root: swift scripts/make-icon.swift
// Adapted from FrequentFinder's scripts/make-icon.swift.
import AppKit

/// One square PNG on the macOS icon grid: a rounded 824/1024 body with a three-column board on it.
func render(_ px: Int) -> Data {
    guard let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: px, pixelsHigh: px, bitsPerSample: 8,
                               samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                               colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0) else { fatalError("could not create bitmap") }
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    let s = CGFloat(px) / 1024
    let body = NSRect(x: 100 * s, y: 100 * s, width: 824 * s, height: 824 * s)
    guard let gradient = NSGradient(starting: NSColor(srgbRed: 0.25, green: 0.78, blue: 0.62, alpha: 1),
                                    ending: NSColor(srgbRed: 0.05, green: 0.50, blue: 0.45, alpha: 1))
    else { fatalError("could not create gradient") }
    gradient.draw(in: NSBezierPath(roundedRect: body, xRadius: 185 * s, yRadius: 185 * s), angle: -90)
    // Three columns holding 3, 2 and 1 cards, top-aligned.
    let colW: CGFloat = 196, gap: CGFloat = 38, top: CGFloat = 790, bottom: CGFloat = 234
    for (i, cards) in [3, 2, 1].enumerated() {
        let x = 180 + CGFloat(i) * (colW + gap)
        NSColor(white: 1, alpha: 0.25).setFill()
        NSBezierPath(roundedRect: NSRect(x: x * s, y: bottom * s, width: colW * s, height: (top - bottom) * s),
                     xRadius: 30 * s, yRadius: 30 * s).fill()
        NSColor.white.setFill()
        for c in 0..<cards {
            let y = top - 24 - CGFloat(c + 1) * 130 - CGFloat(c) * 24
            NSBezierPath(roundedRect: NSRect(x: (x + 20) * s, y: (y + 24) * s, width: (colW - 40) * s, height: 106 * s),
                         xRadius: 18 * s, yRadius: 18 * s).fill()
        }
    }
    NSGraphicsContext.restoreGraphicsState()
    guard let png = rep.representation(using: .png, properties: [:]) else { fatalError("could not encode PNG") }
    return png
}

let iconset = URL(fileURLWithPath: "build/AppIcon.iconset")
try? FileManager.default.removeItem(at: iconset)
try FileManager.default.createDirectory(at: iconset, withIntermediateDirectories: true)
for size in [16, 32, 128, 256, 512] {
    try render(size).write(to: iconset.appendingPathComponent("icon_\(size)x\(size).png"))
    try render(size * 2).write(to: iconset.appendingPathComponent("icon_\(size)x\(size)@2x.png"))
}
let iconutil = Process()
iconutil.executableURL = URL(fileURLWithPath: "/usr/bin/iconutil")
iconutil.arguments = ["-c", "icns", iconset.path, "-o", "Resources/AppIcon.icns"]
try iconutil.run()
iconutil.waitUntilExit()
print(iconutil.terminationStatus == 0 ? "Wrote Resources/AppIcon.icns" : "iconutil failed")
