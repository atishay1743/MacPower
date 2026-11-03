#!/usr/bin/env swift
// Generates Resources/AppIcon.png (1024x1024) and Resources/AppIcon.icns.
//
// A flat, Liquid Glass–style icon: a graphite tile with a single
// frosted-glass bolt. Run from the repo root:  swift scripts/make-icon.swift
import AppKit
import CoreGraphics

let size: CGFloat = 1024
let tile: CGFloat = 824                       // Apple's icon grid: 100pt margin
let origin = (size - tile) / 2
let tileRect = CGRect(x: origin, y: origin, width: tile, height: tile)

let space = CGColorSpace(name: CGColorSpace.displayP3)!

func color(_ hex: UInt32, _ alpha: CGFloat = 1) -> CGColor {
    CGColor(
        colorSpace: space,
        components: [
            CGFloat((hex >> 16) & 0xFF) / 255,
            CGFloat((hex >> 8) & 0xFF) / 255,
            CGFloat(hex & 0xFF) / 255,
            alpha,
        ])!
}

func gradient(_ stops: [(UInt32, CGFloat, CGFloat)]) -> CGGradient {
    CGGradient(
        colorsSpace: space,
        colors: stops.map { color($0.0, $0.1) } as CFArray,
        locations: stops.map { $0.2 })!
}

/// Apple-style continuous-corner tile (a superellipse, not a plain rounded rect).
func squircle(in rect: CGRect, exponent n: CGFloat = 4.2) -> CGPath {
    let path = CGMutablePath()
    let a = rect.width / 2, b = rect.height / 2
    let steps = 720
    for i in 0...steps {
        let t = CGFloat(i) / CGFloat(steps) * 2 * .pi
        let c = cos(t), s = sin(t)
        let x = rect.midX + a * pow(abs(c), 2 / n) * (c < 0 ? -1 : 1)
        let y = rect.midY + b * pow(abs(s), 2 / n) * (s < 0 ? -1 : 1)
        i == 0 ? path.move(to: CGPoint(x: x, y: y)) : path.addLine(to: CGPoint(x: x, y: y))
    }
    path.closeSubpath()
    return path
}

/// Lightning bolt, drawn in a 0...1 unit box (y up) and scaled into `rect`,
/// with every corner rounded so the glass reads soft rather than sharp.
func bolt(in rect: CGRect, radius: CGFloat = 14) -> CGPath {
    let pts: [CGPoint] = [
        (0.60, 1.00), (0.12, 0.40), (0.44, 0.40),
        (0.36, 0.00), (0.88, 0.62), (0.55, 0.62),
    ].map { CGPoint(x: rect.minX + $0.0 * rect.width, y: rect.minY + $0.1 * rect.height) }

    let path = CGMutablePath()
    let n = pts.count
    // Start on the midpoint of the last edge, then round each vertex in turn.
    path.move(to: CGPoint(x: (pts[n - 1].x + pts[0].x) / 2, y: (pts[n - 1].y + pts[0].y) / 2))
    for i in 0..<n {
        let corner = pts[i]
        let next = pts[(i + 1) % n]
        let mid = CGPoint(x: (corner.x + next.x) / 2, y: (corner.y + next.y) / 2)
        path.addArc(tangent1End: corner, tangent2End: mid, radius: radius)
    }
    path.closeSubpath()
    return path
}

let ctx = CGContext(
    data: nil, width: Int(size), height: Int(size), bitsPerComponent: 8,
    bytesPerRow: 0, space: space,
    bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!

// MARK: Tile shadow (soft, close — keeps the icon from looking pasted on)
let tilePath = squircle(in: tileRect)
ctx.saveGState()
ctx.setShadow(offset: CGSize(width: 0, height: -14), blur: 34, color: color(0x000000, 0.35))
ctx.addPath(tilePath)
ctx.setFillColor(color(0x000000))
ctx.fillPath()
ctx.restoreGState()

// MARK: Tile body
ctx.saveGState()
ctx.addPath(tilePath)
ctx.clip()

// Base: near-black graphite with a soft directional highlight.
ctx.drawLinearGradient(
    gradient([(0x08090A, 1, 0), (0x131416, 1, 0.5), (0x252629, 1, 1)]),
    start: CGPoint(x: tileRect.minX, y: tileRect.minY),
    end: CGPoint(x: tileRect.maxX, y: tileRect.maxY),
    options: [])

// Top sheen
ctx.drawLinearGradient(
    gradient([(0xFFFFFF, 0.08, 0), (0xFFFFFF, 0, 1)]),
    start: CGPoint(x: size / 2, y: tileRect.maxY),
    end: CGPoint(x: size / 2, y: tileRect.midY),
    options: [])
ctx.restoreGState()

// MARK: Glass bolt
let boltRect = CGRect(x: 0, y: 0, width: 470, height: 650)
    .offsetBy(dx: size / 2 - 235, dy: size / 2 - 325)
let boltPath = bolt(in: boltRect)

// Drop shadow under the glass (clipped away from inside the bolt so the
// translucent body keeps showing the tile behind it).
ctx.saveGState()
let everything = CGMutablePath()
everything.addRect(CGRect(x: 0, y: 0, width: size, height: size))
everything.addPath(boltPath)
ctx.addPath(everything)
ctx.clip(using: .evenOdd)
ctx.setShadow(offset: CGSize(width: 0, height: -26), blur: 36, color: color(0x512F20, 0.7))
ctx.addPath(boltPath)
ctx.setFillColor(color(0xFFFFFF))
ctx.fillPath()
ctx.restoreGState()

// Glass body: translucent, brighter at the top, clearer toward the base.
ctx.saveGState()
ctx.addPath(boltPath)
ctx.clip()
ctx.drawLinearGradient(
    gradient([(0xFFFFFF, 0.92, 0), (0xFFFFFF, 0.82, 0.5), (0xFFFFFF, 0.66, 1)]),
    start: CGPoint(x: boltRect.midX, y: boltRect.maxY),
    end: CGPoint(x: boltRect.midX, y: boltRect.minY),
    options: [])

// Inner shadow hugging the lower edge: sells the thickness of the glass.
ctx.saveGState()
ctx.setShadow(offset: CGSize(width: -6, height: 14), blur: 22, color: color(0x5E4135, 0.5))
ctx.setFillColor(color(0x000000))
ctx.addPath(everything)
ctx.fillPath(using: .evenOdd)
ctx.restoreGState()

// Specular glint on the upper-left face.
ctx.drawRadialGradient(
    gradient([(0xFFFFFF, 0.5, 0), (0xFFFFFF, 0, 1)]),
    startCenter: CGPoint(x: boltRect.minX + 120, y: boltRect.maxY - 70), startRadius: 0,
    endCenter: CGPoint(x: boltRect.minX + 120, y: boltRect.maxY - 70), endRadius: 190,
    options: [])
ctx.restoreGState()

// Specular rim: crisp white on the top-left edge, fading around the sides.
ctx.saveGState()
ctx.addPath(boltPath)
ctx.setLineWidth(9)
ctx.replacePathWithStrokedPath()
ctx.clip()
ctx.drawLinearGradient(
    gradient([(0xFFFFFF, 1, 0), (0xFFFFFF, 0.3, 0.55), (0xFFFFFF, 0.6, 1)]),
    start: CGPoint(x: boltRect.minX, y: boltRect.maxY),
    end: CGPoint(x: boltRect.maxX, y: boltRect.minY),
    options: [])
ctx.restoreGState()

// MARK: Tile rim light
ctx.saveGState()
ctx.addPath(tilePath)
ctx.setLineWidth(3)
ctx.replacePathWithStrokedPath()
ctx.clip()
ctx.drawLinearGradient(
    gradient([(0xFFFFFF, 0.75, 0), (0xFFFFFF, 0.05, 0.5), (0xFFFFFF, 0.35, 1)]),
    start: CGPoint(x: tileRect.minX, y: tileRect.maxY),
    end: CGPoint(x: tileRect.maxX, y: tileRect.minY),
    options: [])
ctx.restoreGState()

// MARK: Write PNG + iconset + icns
let fm = FileManager.default
let root = URL(fileURLWithPath: fm.currentDirectoryPath)
let resources = root.appendingPathComponent("Resources")
let master = ctx.makeImage()!

func writePNG(_ image: CGImage, pixels: Int, to url: URL) {
    let out = CGContext(
        data: nil, width: pixels, height: pixels, bitsPerComponent: 8,
        bytesPerRow: 0, space: space,
        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
    out.interpolationQuality = .high
    out.draw(image, in: CGRect(x: 0, y: 0, width: pixels, height: pixels))
    let rep = NSBitmapImageRep(cgImage: out.makeImage()!)
    try! rep.representation(using: .png, properties: [:])!.write(to: url)
}

writePNG(master, pixels: 1024, to: resources.appendingPathComponent("AppIcon.png"))

let iconset = fm.temporaryDirectory.appendingPathComponent("AppIcon.iconset")
try? fm.removeItem(at: iconset)
try! fm.createDirectory(at: iconset, withIntermediateDirectories: true)
for base in [16, 32, 128, 256, 512] {
    writePNG(master, pixels: base, to: iconset.appendingPathComponent("icon_\(base)x\(base).png"))
    writePNG(master, pixels: base * 2, to: iconset.appendingPathComponent("icon_\(base)x\(base)@2x.png"))
}

let task = Process()
task.executableURL = URL(fileURLWithPath: "/usr/bin/iconutil")
task.arguments = ["-c", "icns", iconset.path, "-o", resources.appendingPathComponent("AppIcon.icns").path]
try! task.run()
task.waitUntilExit()
precondition(task.terminationStatus == 0, "iconutil failed")
try? fm.removeItem(at: iconset)
print("Wrote Resources/AppIcon.png and Resources/AppIcon.icns")
