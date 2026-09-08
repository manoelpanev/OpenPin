// Draws the OpenPin app icon (a floating pushpin on a teal squircle) into an .iconset folder plus a 512 px PNG.
// Usage: swiftc -O -o make-icon scripts/make-icon.swift && ./make-icon <output directory>
import AppKit

func squircle(in rect: CGRect) -> NSBezierPath {
    NSBezierPath(roundedRect: rect, xRadius: rect.width * 0.2237, yRadius: rect.height * 0.2237)
}

func draw(size s: CGFloat) -> NSBitmapImageRep {
    let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: Int(s), pixelsHigh: Int(s), bitsPerSample: 8, samplesPerPixel: 4,
                               hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    let context = NSGraphicsContext.current!.cgContext
    // macOS icons leave a transparent margin around the squircle.
    let inset = s * 0.0977
    let plate = CGRect(x: inset, y: inset, width: s - 2 * inset, height: s - 2 * inset)
    let shape = squircle(in: plate)
    context.saveGState()
    shape.addClip()
    NSGradient(colors: [NSColor(red: 0.16, green: 0.62, blue: 0.54, alpha: 1), NSColor(red: 0.05, green: 0.36, blue: 0.31, alpha: 1)])!
        .draw(in: plate, angle: -90)
    // Soft light from the top.
    NSGradient(colorsAndLocations: (NSColor(white: 1, alpha: 0.20), 0), (NSColor(white: 1, alpha: 0), 0.6))!
        .draw(in: plate, angle: -90)
    // Floating ring: the bubble the pin lives in.
    let ringRect = plate.insetBy(dx: plate.width * 0.20, dy: plate.height * 0.20)
    let ring = NSBezierPath(ovalIn: ringRect)
    ring.lineWidth = s * 0.028
    NSColor(white: 1, alpha: 0.16).setStroke()
    ring.stroke()
    NSColor(white: 1, alpha: 0.07).setFill()
    ring.fill()
    context.restoreGState()

    // Pushpin, drawn upright then tilted.
    let pin = NSBezierPath()
    let cx = plate.midX, top = plate.maxY - plate.height * 0.20
    let u = plate.height
    pin.append(NSBezierPath(roundedRect: CGRect(x: cx - 0.17 * u, y: top - 0.10 * u, width: 0.34 * u, height: 0.10 * u), xRadius: 0.03 * u, yRadius: 0.03 * u))
    let body = NSBezierPath()
    body.move(to: CGPoint(x: cx - 0.11 * u, y: top - 0.10 * u))
    body.line(to: CGPoint(x: cx + 0.11 * u, y: top - 0.10 * u))
    body.line(to: CGPoint(x: cx + 0.085 * u, y: top - 0.30 * u))
    body.line(to: CGPoint(x: cx - 0.085 * u, y: top - 0.30 * u))
    body.close()
    pin.append(body)
    pin.append(NSBezierPath(roundedRect: CGRect(x: cx - 0.21 * u, y: top - 0.38 * u, width: 0.42 * u, height: 0.085 * u), xRadius: 0.03 * u, yRadius: 0.03 * u))
    let needle = NSBezierPath()
    needle.move(to: CGPoint(x: cx - 0.028 * u, y: top - 0.38 * u))
    needle.line(to: CGPoint(x: cx + 0.028 * u, y: top - 0.38 * u))
    needle.line(to: CGPoint(x: cx, y: top - 0.64 * u))
    needle.close()
    pin.append(needle)
    var tilt = AffineTransform(translationByX: plate.midX, byY: plate.midY)
    tilt.rotate(byDegrees: -32)
    tilt.translate(x: -plate.midX, y: -plate.midY + 0.02 * u)
    pin.transform(using: tilt)

    context.saveGState()
    shape.addClip()
    let shadow = NSShadow()
    shadow.shadowColor = NSColor(white: 0, alpha: 0.35)
    shadow.shadowBlurRadius = s * 0.03
    shadow.shadowOffset = NSSize(width: 0, height: -s * 0.02)
    shadow.set()
    NSColor.white.setFill()
    pin.fill()
    context.restoreGState()
    NSGraphicsContext.restoreGraphicsState()
    return rep
}

let out = URL(fileURLWithPath: CommandLine.arguments[1])
let iconset = out.appendingPathComponent("AppIcon.iconset")
try! FileManager.default.createDirectory(at: iconset, withIntermediateDirectories: true)
for (points, scale) in [(16, 1), (16, 2), (32, 1), (32, 2), (128, 1), (128, 2), (256, 1), (256, 2), (512, 1), (512, 2)] {
    let rep = draw(size: CGFloat(points * scale))
    let name = scale == 1 ? "icon_\(points)x\(points).png" : "icon_\(points)x\(points)@2x.png"
    try! rep.representation(using: .png, properties: [:])!.write(to: iconset.appendingPathComponent(name))
}
try! draw(size: 512).representation(using: .png, properties: [:])!.write(to: out.appendingPathComponent("AppIcon.png"))
print("wrote \(iconset.path)")
