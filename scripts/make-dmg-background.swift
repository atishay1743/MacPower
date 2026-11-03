#!/usr/bin/env swift
// Generates Resources/DMGBackground.png: a quiet gradient with one arrow
// pointing from the app icon to the Applications shortcut.
//
// The gradient stays mid-tone on purpose. Finder draws icon labels in black
// (light mode) or white (dark mode) and we can't control that, so a mid-tone
// background keeps both readable.
//
// Run from the repo root:  swift scripts/make-dmg-background.swift
import AppKit
import CoreGraphics

let points = CGSize(width: 660, height: 420)   // matches the Finder window in create-dmg.sh
let scale: CGFloat = 2
let space = CGColorSpace(name: CGColorSpace.sRGB)!

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

let pixelWidth = Int(points.width * scale), pixelHeight = Int(points.height * scale)
let ctx = CGContext(
    data: nil, width: pixelWidth, height: pixelHeight, bitsPerComponent: 8,
    bytesPerRow: 0, space: space,
    bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
ctx.scaleBy(x: scale, y: scale)

// Base gradient: orange (bottom-left) to amber (top-right), like the icon.
ctx.drawLinearGradient(
    gradient([(0xD4491A, 1, 0), (0xDB6A1C, 1, 0.5), (0xE08F24, 1, 1)]),
    start: .zero, end: CGPoint(x: points.width, y: points.height), options: [])

// A faint glow in the middle so the arrow has some air around it.
let centre = CGPoint(x: points.width / 2, y: points.height - 208)
ctx.drawRadialGradient(
    gradient([(0xFFFFFF, 0.14, 0), (0xFFFFFF, 0, 1)]),
    startCenter: centre, startRadius: 0, endCenter: centre, endRadius: 260, options: [])

// Arrow: shaft plus open chevron head, round caps, soft glow.
let shaftStart = CGPoint(x: centre.x - 46, y: centre.y)
let tip = CGPoint(x: centre.x + 46, y: centre.y)
let arrow = CGMutablePath()
arrow.move(to: shaftStart)
arrow.addLine(to: tip)
arrow.move(to: CGPoint(x: tip.x - 20, y: tip.y + 20))
arrow.addLine(to: tip)
arrow.addLine(to: CGPoint(x: tip.x - 20, y: tip.y - 20))

ctx.saveGState()
ctx.setLineCap(.round)
ctx.setLineJoin(.round)
ctx.setLineWidth(6)
ctx.setStrokeColor(color(0xFFFFFF, 0.9))
ctx.setShadow(offset: .zero, blur: 14, color: color(0xFFE2B8, 0.6))
ctx.addPath(arrow)
ctx.strokePath()
ctx.restoreGState()

let rep = NSBitmapImageRep(cgImage: ctx.makeImage()!)
rep.size = NSSize(width: points.width, height: points.height)   // 144 dpi, 660x420 pt
let url = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
    .appendingPathComponent("Resources/DMGBackground.png")
try! rep.representation(using: .png, properties: [:])!.write(to: url)
print("Wrote Resources/DMGBackground.png")
