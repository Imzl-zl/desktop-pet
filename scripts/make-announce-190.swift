import AppKit

// 1.9.0 announcement card built around the split-pet screenshot, 1200x690 @2x.
let scale: CGFloat = 2
let W: CGFloat = 1200, H: CGFloat = 690
let px = NSSize(width: W * scale, height: H * scale)
let ROOT = "/Users/datnt/Project/datnt/desktoppet"

let image = NSImage(size: px)
image.lockFocus()
let ctx = NSGraphicsContext.current!.cgContext
ctx.scaleBy(x: scale, y: scale)

func color(_ r: Double, _ g: Double, _ b: Double, _ a: Double = 1) -> NSColor {
    NSColor(srgbRed: r, green: g, blue: b, alpha: a)
}

NSGradient(colors: [color(0.04, 0.05, 0.13), color(0.09, 0.07, 0.22), color(0.05, 0.06, 0.16)])?
    .draw(in: NSRect(x: 0, y: 0, width: W, height: H), angle: -55)
NSGradient(colors: [color(0.49, 0.36, 1.0, 0.30), .clear])?
    .draw(in: NSRect(x: W - 560, y: H - 420, width: 760, height: 760), relativeCenterPosition: .zero)
NSGradient(colors: [color(0.18, 0.83, 0.75, 0.18), .clear])?
    .draw(in: NSRect(x: -240, y: -260, width: 720, height: 720), relativeCenterPosition: .zero)

func text(_ s: String, x: CGFloat, top: CGFloat, font: NSFont, color c: NSColor,
          width: CGFloat = 1040, kern: CGFloat = 0, center: Bool = false) {
    let p = NSMutableParagraphStyle(); p.alignment = center ? .center : .left
    let a: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: c, .paragraphStyle: p, .kern: kern]
    let attr = NSAttributedString(string: s, attributes: a)
    let h = attr.boundingRect(with: NSSize(width: width, height: 400), options: [.usesLineFragmentOrigin]).height
    attr.draw(with: NSRect(x: x, y: H - top - h, width: width, height: h), options: [.usesLineFragmentOrigin])
}
func rounded(_ s: CGFloat) -> NSFont { NSFont(name: "Arial Rounded MT Bold", size: s) ?? .systemFont(ofSize: s, weight: .bold) }
func sys(_ s: CGFloat, _ w: NSFont.Weight = .regular) -> NSFont { .systemFont(ofSize: s, weight: w) }
func mono(_ s: CGFloat) -> NSFont { .monospacedSystemFont(ofSize: s, weight: .semibold) }

// Header.
if let logo = NSImage(contentsOfFile: "\(ROOT)/web/public/logo.png") {
    let r = NSRect(x: 80, y: H - 108, width: 54, height: 54)
    NSBezierPath(roundedRect: r, xRadius: 14, yRadius: 14).addClip()
    logo.draw(in: r)
    NSGraphicsContext.current!.cgContext.resetClip()
}
text("DesktopPet", x: 146, top: 56, font: rounded(28), color: .white)
text("A desktop pet that watches your AI coding agents", x: 146, top: 90, font: sys(14), color: color(0.55, 0.62, 0.8))
// v1.9.0 pill
let pill = NSRect(x: 1036, y: H - 102, width: 100, height: 36)
color(0.49, 0.40, 1.0, 0.18).setFill(); NSBezierPath(roundedRect: pill, xRadius: 18, yRadius: 18).fill()
text("v1.9.0", x: 1036, top: 64, font: sys(17, .bold), color: color(0.72, 0.66, 1.0), width: 100, center: true)

// Headline.
text("A pet for every project", x: 78, top: 150, font: rounded(52), color: .white)
text("Split your companions across projects, plus a lot more in 1.9.0.", x: 80, top: 214,
     font: sys(20), color: color(0.66, 0.72, 0.86))

// Hero: the split-pet screenshot in a rounded frame.
if let shot = NSImage(contentsOfFile: "/tmp/pets-strip.png") {
    let fw: CGFloat = 1040
    let fh = fw * (shot.size.height / shot.size.width)
    let x: CGFloat = (W - fw) / 2, y = H - 268 - fh
    let frame = NSRect(x: x, y: y, width: fw, height: fh)
    let shadow = NSShadow(); shadow.shadowColor = NSColor(white: 0, alpha: 0.45)
    shadow.shadowBlurRadius = 34; shadow.shadowOffset = NSSize(width: 0, height: -12); shadow.set()
    let clip = NSBezierPath(roundedRect: frame, xRadius: 18, yRadius: 18); clip.addClip()
    shot.draw(in: frame)
    NSGraphicsContext.current!.cgContext.resetClip()
    NSShadow().set()
    color(1, 1, 1, 0.10).setStroke()
    let b = NSBezierPath(roundedRect: frame, xRadius: 18, yRadius: 18); b.lineWidth = 1.5; b.stroke()
}

// Feature pills.
let feats = ["Per-project pets", "Codex earns XP", "Rename pets", "Break reminder"]
let f = sys(16, .semibold)
var widths = feats.map { ($0 as NSString).size(withAttributes: [.font: f]).width + 40 }
let gap: CGFloat = 14
let totalW = widths.reduce(0, +) + gap * CGFloat(feats.count - 1)
var fx = (W - totalW) / 2
for (i, label) in feats.enumerated() {
    let w = widths[i]
    let r = NSRect(x: fx, y: H - 560 - 40, width: w, height: 40)
    color(0.18, 0.83, 0.75, 0.12).setFill(); NSBezierPath(roundedRect: r, xRadius: 20, yRadius: 20).fill()
    color(0.30, 0.85, 0.78, 0.4).setStroke()
    let rb = NSBezierPath(roundedRect: r, xRadius: 20, yRadius: 20); rb.lineWidth = 1; rb.stroke()
    text(label, x: fx, top: 560 + 11, font: f, color: color(0.78, 0.93, 0.9), width: w, center: true)
    fx += w + gap
}

text("github.com/Imzl-zl/desktop-pet", x: 0, top: 642, font: sys(16, .semibold),
     color: color(0.37, 0.89, 0.81), width: W, center: true)

image.unlockFocus()
guard let tiff = image.tiffRepresentation, let rep = NSBitmapImageRep(data: tiff),
      let png = rep.representation(using: .png, properties: [:]) else { exit(1) }
try! png.write(to: URL(fileURLWithPath: "/tmp/desktoppet-190.png"))
print("done")
