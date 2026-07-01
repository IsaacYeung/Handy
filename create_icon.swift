#!/usr/bin/swift
// Handy icon generator — pure CoreGraphics, no NSApplication needed
import Foundation
import CoreGraphics
import ImageIO

func drawIcon(ctx: CGContext, size s: CGFloat) {
    // ── Background: dark navy rounded rect ───────────────────────────────────
    let r = s * 0.215
    let bg = CGMutablePath()
    bg.addRoundedRect(in: CGRect(x: 0, y: 0, width: s, height: s),
                      cornerWidth: r, cornerHeight: r)
    ctx.addPath(bg)
    ctx.setFillColor(CGColor(red: 0.07, green: 0.07, blue: 0.16, alpha: 1))
    ctx.fillPath()

    // ── Move to center, tilt +15° (counterclockwise = left-end goes down) ────
    ctx.saveGState()
    ctx.translateBy(x: s * 0.5, y: s * 0.5)
    ctx.rotate(by: 15 * .pi / 180)

    let kw = s * 0.60   // knife body width
    let kh = s * 0.19   // knife body height
    let kr = kh / 2     // pill-end radius
    let showTools  = s >= 64
    let showRivets = s >= 64
    let showGlints = s >= 128

    // ── Silver tools (drawn behind body) ─────────────────────────────────────
    if showTools {
        func silverFill(_ c: CGFloat) -> CGColor {
            CGColor(red: c, green: c, blue: c + 0.04, alpha: 1)
        }
        let strokeSilver = CGColor(red: 0.55, green: 0.55, blue: 0.58, alpha: 1)
        let tw = s * 0.003  // stroke width

        // Blade — upper-right, extends from top edge of knife
        let bx: CGFloat = kw * 0.20
        let bLen = kh * 1.45
        let blade = CGMutablePath()
        blade.move(   to: CGPoint(x: bx - kh*0.07, y:  kh*0.50))
        blade.addLine(to: CGPoint(x: bx - kh*0.11, y:  kh*0.50 + bLen))
        blade.addLine(to: CGPoint(x: bx + kh*0.03, y:  kh*0.50 + bLen * 0.91))
        blade.addLine(to: CGPoint(x: bx + kh*0.07, y:  kh*0.50))
        blade.closeSubpath()
        ctx.addPath(blade); ctx.setFillColor(silverFill(0.80)); ctx.fillPath()
        ctx.addPath(blade); ctx.setStrokeColor(strokeSilver); ctx.setLineWidth(tw); ctx.strokePath()

        // Scissors — upper-left
        let sx: CGFloat = -kw * 0.22
        let sLen = kh * 1.25

        let scA = CGMutablePath()   // front blade
        scA.move(   to: CGPoint(x: sx - kh*0.08, y:  kh*0.50))
        scA.addLine(to: CGPoint(x: sx - kh*0.14, y:  kh*0.50 + sLen))
        scA.addLine(to: CGPoint(x: sx + kh*0.01, y:  kh*0.50 + sLen * 0.88))
        scA.addLine(to: CGPoint(x: sx + kh*0.04, y:  kh*0.50))
        scA.closeSubpath()
        ctx.addPath(scA); ctx.setFillColor(silverFill(0.74)); ctx.fillPath()
        ctx.addPath(scA); ctx.setStrokeColor(strokeSilver); ctx.setLineWidth(tw); ctx.strokePath()

        let scB = CGMutablePath()   // back blade
        scB.move(   to: CGPoint(x: sx + kh*0.01, y:  kh*0.50))
        scB.addLine(to: CGPoint(x: sx + kh*0.07, y:  kh*0.50 + sLen))
        scB.addLine(to: CGPoint(x: sx + kh*0.17, y:  kh*0.50 + sLen * 0.88))
        scB.addLine(to: CGPoint(x: sx + kh*0.10, y:  kh*0.50))
        scB.closeSubpath()
        ctx.addPath(scB); ctx.setFillColor(silverFill(0.83)); ctx.fillPath()
        ctx.addPath(scB); ctx.setStrokeColor(strokeSilver); ctx.setLineWidth(tw); ctx.strokePath()
    }

    // ── Knife body ──────────────────────────────────────────────────────────
    let body = CGMutablePath()
    body.addRoundedRect(in: CGRect(x: -kw/2, y: -kh/2, width: kw, height: kh),
                        cornerWidth: kr, cornerHeight: kr)

    ctx.addPath(body)
    ctx.setFillColor(CGColor(red: 0.87, green: 0.17, blue: 0.15, alpha: 1))
    ctx.fillPath()

    // Top gloss stripe (clip to body)
    ctx.saveGState()
    ctx.addPath(body); ctx.clip()
    ctx.addRect(CGRect(x: -kw/2, y: kh*0.28, width: kw, height: kh*0.25))
    ctx.setFillColor(CGColor(red: 1, green: 1, blue: 1, alpha: 0.10))
    ctx.fillPath()
    ctx.restoreGState()

    // Body border
    ctx.addPath(body)
    ctx.setStrokeColor(CGColor(red: 0.48, green: 0.06, blue: 0.06, alpha: 1))
    ctx.setLineWidth(s * 0.006)
    ctx.strokePath()

    // ── Rivets ──────────────────────────────────────────────────────────────
    if showRivets {
        for rx in [kw * 0.36, -kw * 0.36] {
            let rr = kh * 0.17
            let rivet = CGMutablePath()
            rivet.addEllipse(in: CGRect(x: rx - rr, y: -rr, width: rr*2, height: rr*2))
            ctx.addPath(rivet)
            ctx.setFillColor(CGColor(red: 0.55, green: 0.44, blue: 0.12, alpha: 1))
            ctx.fillPath()
            ctx.addPath(rivet)
            ctx.setStrokeColor(CGColor(red: 0.32, green: 0.24, blue: 0.04, alpha: 0.9))
            ctx.setLineWidth(s * 0.003); ctx.strokePath()
        }
    }

    // ── Eyes ────────────────────────────────────────────────────────────────
    let eyeR   = kh * 0.195
    let eyeSep = kw * 0.090
    let eyeY   = kh * 0.08

    for side: CGFloat in [-1, 1] {
        let ex = side * eyeSep

        // White sclera
        let white = CGMutablePath()
        white.addEllipse(in: CGRect(x: ex - eyeR, y: eyeY - eyeR, width: eyeR*2, height: eyeR*2))
        ctx.addPath(white)
        ctx.setFillColor(CGColor(red: 1, green: 0.97, blue: 0.95, alpha: 1))
        ctx.fillPath()

        // Pupil
        let pr = eyeR * 0.58
        let pupil = CGMutablePath()
        pupil.addEllipse(in: CGRect(x: ex - pr, y: eyeY - pr, width: pr*2, height: pr*2))
        ctx.addPath(pupil)
        ctx.setFillColor(CGColor(red: 0.07, green: 0.05, blue: 0.18, alpha: 1))
        ctx.fillPath()

        // Glint
        if showGlints {
            let gr = pr * 0.36
            let glint = CGMutablePath()
            glint.addEllipse(in: CGRect(x: ex + pr*0.16, y: eyeY + pr*0.16, width: gr*2, height: gr*2))
            ctx.addPath(glint)
            ctx.setFillColor(CGColor(red: 1, green: 1, blue: 1, alpha: 0.90))
            ctx.fillPath()
        }
    }

    // ── Smile ────────────────────────────────────────────────────────────────
    ctx.saveGState()
    ctx.setStrokeColor(CGColor(red: 1, green: 0.94, blue: 0.90, alpha: 1))
    ctx.setLineWidth(kh * 0.11)
    ctx.setLineCap(.round)
    let smW = kw * 0.095
    let smY = -kh * 0.12
    let smile = CGMutablePath()
    smile.move(to: CGPoint(x: -smW, y: smY + kh * 0.065))
    smile.addCurve(to:         CGPoint(x:  smW, y: smY + kh * 0.065),
                   control1:   CGPoint(x: -smW * 0.4, y: smY - kh * 0.095),
                   control2:   CGPoint(x:  smW * 0.4, y: smY - kh * 0.095))
    ctx.addPath(smile); ctx.strokePath()
    ctx.restoreGState()

    ctx.restoreGState()  // undo center transform
}

func savePNG(ctx: CGContext, path: String) {
    guard let img = ctx.makeImage() else { return }
    let url = URL(fileURLWithPath: path) as CFURL
    guard let dst = CGImageDestinationCreateWithURL(url, "public.png" as CFString, 1, nil) else { return }
    CGImageDestinationAddImage(dst, img, nil)
    CGImageDestinationFinalize(dst)
}

let dir = "Handy.iconset"
try? FileManager.default.removeItem(atPath: dir)
try? FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)

let specs: [(name: String, px: Int)] = [
    ("icon_16x16",      16), ("icon_16x16@2x",   32),
    ("icon_32x32",      32), ("icon_32x32@2x",   64),
    ("icon_128x128",   128), ("icon_128x128@2x", 256),
    ("icon_256x256",   256), ("icon_256x256@2x", 512),
    ("icon_512x512",   512), ("icon_512x512@2x",1024),
]

for s in specs {
    let n = s.px
    guard let ctx = CGContext(data: nil, width: n, height: n, bitsPerComponent: 8,
                              bytesPerRow: n * 4,
                              space: CGColorSpaceCreateDeviceRGB(),
                              bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
    else { print("Failed ctx \(n)"); continue }
    drawIcon(ctx: ctx, size: CGFloat(n))
    savePNG(ctx: ctx, path: "\(dir)/\(s.name).png")
    print("  \(s.name).png")
}
print("Iconset ready → \(dir)")
