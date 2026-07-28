import AppKit

// Renders a 1024x1024 app icon: a purple squircle with a white pawprint.
let size: CGFloat = 1024
let image = NSImage(size: NSSize(width: size, height: size))
image.lockFocus()

let rect = NSRect(x: 0, y: 0, width: size, height: size)
let squircle = NSBezierPath(roundedRect: rect, xRadius: size * 0.225, yRadius: size * 0.225)

let gradient = NSGradient(colors: [
    NSColor(srgbRed: 0.52, green: 0.42, blue: 0.99, alpha: 1),
    NSColor(srgbRed: 0.36, green: 0.27, blue: 0.86, alpha: 1),
])
gradient?.draw(in: squircle, angle: -90)

// White pawprint, tinted from the SF Symbol.
if let symbol = NSImage(systemSymbolName: "pawprint.fill", accessibilityDescription: nil) {
    let config = NSImage.SymbolConfiguration(pointSize: size * 0.52, weight: .semibold)
    if let glyph = symbol.withSymbolConfiguration(config) {
        let tinted = NSImage(size: glyph.size)
        tinted.lockFocus()
        NSColor.white.set()
        let gRect = NSRect(origin: .zero, size: glyph.size)
        glyph.draw(in: gRect)
        gRect.fill(using: .sourceAtop)
        tinted.unlockFocus()

        let w = glyph.size.width
        let h = glyph.size.height
        let target = NSRect(x: (size - w) / 2, y: (size - h) / 2, width: w, height: h)
        tinted.draw(in: target, from: .zero, operation: .sourceOver, fraction: 1)
    }
}

image.unlockFocus()

guard let tiff = image.tiffRepresentation,
      let rep = NSBitmapImageRep(data: tiff),
      let png = rep.representation(using: .png, properties: [:]) else {
    FileHandle.standardError.write(Data("failed to render icon\n".utf8))
    exit(1)
}
let out = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "/tmp/desktoppet-icon-1024.png"
try png.write(to: URL(fileURLWithPath: out))
print("wrote \(out)")
