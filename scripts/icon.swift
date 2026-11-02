import AppKit
let directory = CommandLine.arguments[1]
try FileManager.default.createDirectory(atPath: directory, withIntermediateDirectories: true)
for size in [16, 32, 128, 256, 512] {
    for scale in [1, 2] {
        let pixels = size * scale
        let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: pixels, pixelsHigh: pixels, bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: bitmap)
        let transform = AffineTransform(scale: Double(pixels) / 512)
        (transform as NSAffineTransform).concat()
        NSColor(calibratedRed: 0.96, green: 0.96, blue: 0.98, alpha: 1).setFill()
        NSBezierPath(roundedRect: NSRect(x: 0, y: 0, width: 512, height: 512), xRadius: 112, yRadius: 112).fill()
        NSColor(calibratedRed: 0.204, green: 0.212, blue: 0.373, alpha: 1).setFill()
        let p = NSBezierPath()
        p.move(to: NSPoint(x: 125, y: 138))
        p.curve(to: NSPoint(x: 103, y: 286), controlPoint1: NSPoint(x: 28, y: 138), controlPoint2: NSPoint(x: 24, y: 273))
        p.curve(to: NSPoint(x: 293, y: 333), controlPoint1: NSPoint(x: 115, y: 393), controlPoint2: NSPoint(x: 242, y: 407))
        p.curve(to: NSPoint(x: 437, y: 264), controlPoint1: NSPoint(x: 374, y: 385), controlPoint2: NSPoint(x: 446, y: 321))
        p.curve(to: NSPoint(x: 420, y: 138), controlPoint1: NSPoint(x: 515, y: 238), controlPoint2: NSPoint(x: 478, y: 138))
        p.close(); p.fill()
        for (text, y, fontSize) in [("CO₂", 256.0, 30.0), ("750", 166.0, 78.0)] {
            let s = NSAttributedString(string: text, attributes: [.font: NSFont.systemFont(ofSize: fontSize, weight: .bold), .foregroundColor: NSColor.white])
            s.draw(at: NSPoint(x: 267 - s.size().width / 2, y: y))
        }
        NSGraphicsContext.restoreGraphicsState()
        let suffix = scale == 2 ? "@2x" : ""
        let path = "\(directory)/icon_\(size)x\(size)\(suffix).png"
        try bitmap.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: path))
    }
}
