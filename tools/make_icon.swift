// Génère Resources/AppIcon.icns : tracé ECG sur papier millimétré
// Usage : swift tools/make_icon.swift <dossier de sortie>
import AppKit

func render(size px: Int) -> NSBitmapImageRep {
    let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: px, pixelsHigh: px, bitsPerSample: 8,
                               samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                               colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    let ctx = NSGraphicsContext.current!.cgContext
    let s = CGFloat(px) / 1024
    ctx.scaleBy(x: s, y: s)

    // Carré arrondi (gabarit macOS : 824 pt centré)
    let card = CGRect(x: 100, y: 100, width: 824, height: 824)
    let shape = CGPath(roundedRect: card, cornerWidth: 185, cornerHeight: 185, transform: nil)
    ctx.saveGState()
    ctx.setShadow(offset: CGSize(width: 0, height: -12), blur: 28, color: NSColor.black.withAlphaComponent(0.35).cgColor)
    ctx.addPath(shape); ctx.setFillColor(NSColor(red: 1, green: 0.965, blue: 0.95, alpha: 1).cgColor); ctx.fillPath()
    ctx.restoreGState()

    ctx.saveGState()
    ctx.addPath(shape); ctx.clip()
    // Quadrillage : petits carreaux 20 pt, grands carreaux 100 pt
    for i in stride(from: 0, through: 1024, by: 20) {
        let big = i % 100 == 0
        ctx.setStrokeColor(NSColor(red: 0.93, green: 0.45, blue: 0.45, alpha: big ? 0.55 : 0.22).cgColor)
        ctx.setLineWidth(big ? 3 : 1.5)
        ctx.move(to: CGPoint(x: CGFloat(i), y: 0)); ctx.addLine(to: CGPoint(x: CGFloat(i), y: 1024))
        ctx.move(to: CGPoint(x: 0, y: CGFloat(i))); ctx.addLine(to: CGPoint(x: 1024, y: CGFloat(i)))
        ctx.strokePath()
    }

    // Tracé P-QRS-T
    let base: CGFloat = 470
    let path = CGMutablePath()
    path.move(to: CGPoint(x: 60, y: base))
    func beat(_ x: CGFloat) {
        path.addLine(to: CGPoint(x: x, y: base))
        path.addCurve(to: CGPoint(x: x + 90, y: base), control1: CGPoint(x: x + 20, y: base + 70), control2: CGPoint(x: x + 70, y: base + 70))
        path.addLine(to: CGPoint(x: x + 120, y: base))
        path.addLine(to: CGPoint(x: x + 140, y: base - 40))   // Q
        path.addLine(to: CGPoint(x: x + 180, y: base + 340))  // R
        path.addLine(to: CGPoint(x: x + 220, y: base - 130))  // S
        path.addLine(to: CGPoint(x: x + 245, y: base))
        path.addLine(to: CGPoint(x: x + 290, y: base))
        path.addCurve(to: CGPoint(x: x + 430, y: base), control1: CGPoint(x: x + 330, y: base + 120), control2: CGPoint(x: x + 400, y: base + 120))
    }
    beat(150)
    path.addLine(to: CGPoint(x: 680, y: base))
    path.addCurve(to: CGPoint(x: 770, y: base), control1: CGPoint(x: 700, y: base + 70), control2: CGPoint(x: 750, y: base + 70))
    path.addLine(to: CGPoint(x: 800, y: base))
    path.addLine(to: CGPoint(x: 820, y: base - 40))
    path.addLine(to: CGPoint(x: 860, y: base + 340))
    path.addLine(to: CGPoint(x: 900, y: base - 130))
    path.addLine(to: CGPoint(x: 925, y: base))
    path.addLine(to: CGPoint(x: 1000, y: base))
    ctx.addPath(path)
    ctx.setLineJoin(.round); ctx.setLineCap(.round)
    ctx.setLineWidth(30)
    ctx.setStrokeColor(NSColor(red: 0.78, green: 0.08, blue: 0.12, alpha: 1).cgColor)
    ctx.strokePath()
    ctx.restoreGState()

    NSGraphicsContext.restoreGraphicsState()
    return rep
}

let out = URL(fileURLWithPath: CommandLine.arguments[1])
let iconset = out.appendingPathComponent("AppIcon.iconset")
try? FileManager.default.removeItem(at: iconset)
try! FileManager.default.createDirectory(at: iconset, withIntermediateDirectories: true)
for base in [16, 32, 128, 256, 512] {
    for scale in [1, 2] {
        let name = scale == 1 ? "icon_\(base)x\(base).png" : "icon_\(base)x\(base)@2x.png"
        let data = render(size: base * scale).representation(using: .png, properties: [:])!
        try! data.write(to: iconset.appendingPathComponent(name))
    }
}
try! render(size: 1024).representation(using: .png, properties: [:])!.write(to: out.appendingPathComponent("AppIcon-preview.png"))
