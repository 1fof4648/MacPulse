import AppKit

// Crops the raw window captures down to the panel/pill geometry (detected from
// the alpha capture of the same window) and composes the README hero.
// Usage: swift compose.swift

let dir = FileManager.default.currentDirectoryPath + "/assets"

func cgImage(_ path: String) -> CGImage? {
    guard let img = NSImage(contentsOfFile: path) else { return nil }
    var r = NSRect(origin: .zero, size: img.size)
    return img.cgImage(forProposedRect: &r, context: nil, hints: nil)
}

/// Bounding box of pixels at/above an alpha threshold (top-left origin).
func alphaBBox(_ path: String, _ threshold: CGFloat = 0.9) -> CGRect? {
    guard let cg = cgImage(path) else { return nil }
    let w = cg.width, h = cg.height
    var buf = [UInt8](repeating: 0, count: w * h * 4)
    guard let ctx = CGContext(data: &buf, width: w, height: h, bitsPerComponent: 8,
                              bytesPerRow: w * 4, space: CGColorSpaceCreateDeviceRGB(),
                              bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
    ctx.draw(cg, in: CGRect(x: 0, y: 0, width: w, height: h))
    let cut = UInt8(threshold * 255)
    var minX = w, minY = h, maxX = 0, maxY = 0
    for y in 0..<h {
        for x in 0..<w where buf[(y * w + x) * 4 + 3] >= cut {
            if x < minX { minX = x }; if x > maxX { maxX = x }
            if y < minY { minY = y }; if y > maxY { maxY = y }
        }
    }
    guard maxX > minX else { return nil }
    // CGBitmapContext rows are stored top-first, matching cropping(to:)'s origin
    return CGRect(x: minX, y: minY, width: maxX - minX + 1, height: maxY - minY + 1)
}

func writePNG(_ rep: NSBitmapImageRep, _ out: String) {
    try! rep.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: out))
}

func newRep(_ w: Int, _ h: Int) -> NSBitmapImageRep {
    NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: w, pixelsHigh: h,
                     bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                     colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
}

/// Crop `src` to `rect` and round its corners.
func cropRounded(_ src: String, _ rect: CGRect, radius: CGFloat, out: String) {
    guard let cg = cgImage(src), let cut = cg.cropping(to: rect) else { return }
    let rep = newRep(cut.width, cut.height)
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    let box = NSRect(x: 0, y: 0, width: cut.width, height: cut.height)
    NSBezierPath(roundedRect: box, xRadius: radius, yRadius: radius).addClip()
    NSGraphicsContext.current!.cgContext.draw(cut, in: box)
    NSGraphicsContext.restoreGraphicsState()
    writePNG(rep, out)
}

// ---- 1. crop the panel and the pill -------------------------------------

if let r = alphaBBox("\(dir)/island-expanded.png") {
    cropRounded("\(dir)/panel-raw.png", r, radius: 68, out: "\(dir)/panel.png")
    print("panel \(Int(r.width))x\(Int(r.height))")
}
if let r = alphaBBox("\(dir)/pill-alpha.png") {
    cropRounded("\(dir)/pill-raw.png", r, radius: 48, out: "\(dir)/pill.png")
    print("pill \(Int(r.width))x\(Int(r.height))")
}

// ---- 2. compose the hero -------------------------------------------------

let W = 2400, H = 1040
let rep = newRep(W, H)
NSGraphicsContext.saveGraphicsState()
NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
let ctx = NSGraphicsContext.current!.cgContext
let space = CGColorSpaceCreateDeviceRGB()

// deep navy base
let base = CGGradient(colorsSpace: space, colors: [
    CGColor(red: 0.09, green: 0.16, blue: 0.29, alpha: 1),
    CGColor(red: 0.02, green: 0.05, blue: 0.11, alpha: 1)
] as CFArray, locations: [0, 1])!
ctx.drawLinearGradient(base, start: CGPoint(x: 0, y: CGFloat(H)),
                       end: CGPoint(x: CGFloat(W) * 0.4, y: 0),
                       options: [.drawsBeforeStartLocation, .drawsAfterEndLocation])

// colour blooms, macOS-wallpaper style
func bloom(_ x: CGFloat, _ y: CGFloat, _ r: CGFloat, _ c: CGColor) {
    let g = CGGradient(colorsSpace: space, colors: [c, c.copy(alpha: 0)!] as CFArray, locations: [0, 1])!
    ctx.drawRadialGradient(g, startCenter: CGPoint(x: x, y: y), startRadius: 0,
                           endCenter: CGPoint(x: x, y: y), endRadius: r, options: [])
}
bloom(300, 880, 900, CGColor(red: 0.25, green: 0.55, blue: 1.0, alpha: 0.22))
bloom(2050, 220, 1000, CGColor(red: 0.35, green: 0.75, blue: 1.0, alpha: 0.15))
bloom(1500, 1000, 800, CGColor(red: 0.55, green: 0.35, blue: 0.95, alpha: 0.12))

// icon
if let icon = cgImage(FileManager.default.currentDirectoryPath + "/AppIcon-1024.png") {
    ctx.draw(icon, in: CGRect(x: 150, y: CGFloat(H) - 170 - 260, width: 260, height: 260))
}

// type
func text(_ s: String, _ x: CGFloat, _ y: CGFloat, _ size: CGFloat, _ weight: NSFont.Weight, _ alpha: CGFloat) {
    let attrs: [NSAttributedString.Key: Any] = [
        .font: NSFont.systemFont(ofSize: size, weight: weight),
        .foregroundColor: NSColor(white: 1, alpha: alpha)
    ]
    NSAttributedString(string: s, attributes: attrs).draw(at: NSPoint(x: x, y: y))
}
text("MacPulse", 150, CGFloat(H) - 560, 132, .bold, 1.0)
text("Liquid Glass battery & memory governor for macOS", 156, CGFloat(H) - 640, 44, .medium, 0.72)
text("Kalman-forecast Low Power Mode  ·  password-free  ·  no Xcode project",
     156, CGFloat(H) - 706, 30, .regular, 0.45)

// the real panel screenshot, with a soft drop shadow
if let panel = cgImage("\(dir)/panel.png") {
    let pw: CGFloat = 900
    let ph = pw * CGFloat(panel.height) / CGFloat(panel.width)
    let box = CGRect(x: CGFloat(W) - pw - 170, y: (CGFloat(H) - ph) / 2, width: pw, height: ph)
    ctx.setShadow(offset: CGSize(width: 0, height: -26), blur: 70,
                  color: CGColor(red: 0, green: 0, blue: 0, alpha: 0.55))
    ctx.draw(panel, in: box)
    ctx.setShadow(offset: .zero, blur: 0, color: nil)
}

NSGraphicsContext.restoreGraphicsState()
writePNG(rep, "\(dir)/hero.png")
print("hero \(W)x\(H)")
