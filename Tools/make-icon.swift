// make-icon.swift — renders the Chaos app icon with CoreGraphics (no external deps).
// Run: swift Tools/make-icon.swift
// Produces the full iconset, builds Chaos.icns via iconutil, and updates the asset catalog.

import Foundation
import CoreGraphics
import ImageIO
import UniformTypeIdentifiers

let canvas: CGFloat = 1024

// MARK: - Color helpers

func rgba(_ hex: UInt32, _ alpha: CGFloat = 1) -> CGColor {
    CGColor(
        srgbRed: CGFloat((hex >> 16) & 0xFF) / 255.0,
        green: CGFloat((hex >> 8) & 0xFF) / 255.0,
        blue: CGFloat(hex & 0xFF) / 255.0,
        alpha: alpha
    )
}

// MARK: - Path helpers

func roundedRectPath(in rect: CGRect, radius: CGFloat) -> CGPath {
    CGPath(roundedRect: rect, cornerWidth: radius, cornerHeight: radius, transform: nil)
}

func circlePath(center: CGPoint, radius: CGFloat) -> CGPath {
    CGPath(ellipseIn: CGRect(x: center.x - radius, y: center.y - radius,
                             width: radius * 2, height: radius * 2), transform: nil)
}

/// The "C": an open ring drawn as a stroked arc.
func cRingPath(center: CGPoint, radius: CGFloat) -> CGPath {
    let path = CGMutablePath()
    // Start at upper-right opening, sweep counter-clockwise to lower-right opening.
    let start: CGFloat = 35 * .pi / 180
    let end: CGFloat = 325 * .pi / 180
    path.addArc(center: center, radius: radius, startAngle: start, endAngle: end, clockwise: false, transform: .identity)
    return path
}

// MARK: - Drawing

func drawIcon(size: CGFloat) -> CGImage? {
    let space = CGColorSpace(name: CGColorSpace.sRGB)!
    let ctx = CGContext(data: nil, width: Int(size), height: Int(size),
                        bitsPerComponent: 8, bytesPerRow: 0, space: space,
                        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!

    let s = size / canvas // scale factor from design space

    ctx.scaleBy(x: s, y: s)

    // macOS 26 character: full-bleed rounded square.
    let bgRect = CGRect(x: 0, y: 0, width: canvas, height: canvas)
    let bgPath = roundedRectPath(in: bgRect, radius: 232)

    // Background: vertical gradient dark slate.
    ctx.saveGState()
    ctx.addPath(bgPath)
    ctx.clip()
    let bgColors = [rgba(0x2A2D35), rgba(0x15171C)] as CFArray
    let bgGrad = CGGradient(colorsSpace: space, colors: bgColors, locations: [0, 1])!
    ctx.drawLinearGradient(bgGrad, start: CGPoint(x: 512, y: canvas), end: CGPoint(x: 512, y: 0), options: [])

    // Faint system grid (distorted by the fault zone later).
    ctx.setStrokeColor(rgba(0xFFFFFF, 0.05))
    ctx.setLineWidth(2)
    for i in stride(from: CGFloat(128), through: 896, by: 96) {
        ctx.move(to: CGPoint(x: i, y: 0)); ctx.addLine(to: CGPoint(x: i, y: canvas))
        ctx.move(to: CGPoint(x: 0, y: i)); ctx.addLine(to: CGPoint(x: canvas, y: i))
    }
    ctx.strokePath()

    // Contained energy core: red radial glow.
    let coreCenter = CGPoint(x: 512, y: 512)
    let coreColors = [
        rgba(0xFF8A50, 0.95),
        rgba(0xF5475F, 0.65),
        rgba(0xD92850, 0.35),
        rgba(0x5A0C24, 0.0),
    ] as CFArray
    let coreGrad = CGGradient(colorsSpace: space, colors: coreColors, locations: [0, 0.45, 0.8, 1])!
    ctx.drawRadialGradient(coreGrad,
                           startCenter: coreCenter, startRadius: 0,
                           endCenter: coreCenter, endRadius: 330, options: [])

    // Cracks radiating from the core across the grid.
    ctx.setStrokeColor(rgba(0xFF6E5E, 0.85))
    ctx.setLineWidth(7)
    ctx.setLineCap(.round)
    let cracks: [(CGPoint, CGPoint)] = [
        (CGPoint(x: 690, y: 690), CGPoint(x: 810, y: 804)),
        (CGPoint(x: 722, y: 562), CGPoint(x: 862, y: 562)),
        (CGPoint(x: 686, y: 394), CGPoint(x: 800, y: 308)),
        (CGPoint(x: 470, y: 232), CGPoint(x: 470, y: 116)),
        (CGPoint(x: 334, y: 280), CGPoint(x: 252, y: 182)),
        (CGPoint(x: 300, y: 554), CGPoint(x: 168, y: 554)),
        (CGPoint(x: 330, y: 722), CGPoint(x: 220, y: 798)),
    ]
    for (from, to) in cracks {
        ctx.move(to: from); ctx.addLine(to: to)
    }
    ctx.strokePath()

    // Inner disc behind the C for contrast.
    ctx.setFillColor(rgba(0x1C1E24, 0.88))
    ctx.fillEllipse(in: CGRect(x: 274, y: 274, width: 476, height: 476))

    // The C: thick white arc with subtle vertical shading.
    ctx.saveGState()
    let ring = cRingPath(center: coreCenter, radius: 210)
    ctx.addPath(ring)
    ctx.setLineWidth(84)
    ctx.setLineCap(.butt)
    ctx.setStrokeColor(rgba(0xF2F5FB))
    ctx.replacePathWithStrokedPath()
    ctx.clip()
    let faceColors = [rgba(0xFFFFFF), rgba(0xC9D2E4)] as CFArray
    let faceGrad = CGGradient(colorsSpace: space, colors: faceColors, locations: [0, 1])!
    ctx.drawLinearGradient(faceGrad, start: CGPoint(x: 512, y: 722), end: CGPoint(x: 512, y: 302), options: [])
    ctx.restoreGState()

    // Fracture: a jagged fault line slicing through the C's upper arc.
    let fault = CGMutablePath()
    fault.move(to: CGPoint(x: 560, y: 760))
    fault.addLine(to: CGPoint(x: 500, y: 690))
    fault.addLine(to: CGPoint(x: 545, y: 648))
    fault.addLine(to: CGPoint(x: 470, y: 560))
    ctx.saveGState()
    ctx.addPath(fault)
    ctx.setLineWidth(14)
    ctx.setLineCap(.round)
    ctx.setStrokeColor(rgba(0x15171C))
    ctx.strokePath()
    ctx.restoreGState()

    // Small energy bead at the fault entry point.
    ctx.setFillColor(rgba(0xFF5C7A))
    ctx.fillEllipse(in: CGRect(x: 548, y: 748, width: 26, height: 26))

    // Bottom terminals of the C get slight glow to suggest the broken circuit.
    ctx.setStrokeColor(rgba(0xFFB4A8, 0.9))
    ctx.setLineWidth(10)
    ctx.move(to: CGPoint(x: 682, y: 596)); ctx.addLine(to: CGPoint(x: 722, y: 626))
    ctx.move(to: CGPoint(x: 682, y: 428)); ctx.addLine(to: CGPoint(x: 722, y: 398))
    ctx.strokePath()

    ctx.restoreGState() // end clip

    return ctx.makeImage()
}

// MARK: - Output

func writePNG(_ image: CGImage, to url: URL) throws {
    let dest = CGImageDestinationCreateWithURL(url as CFURL, UTType.png.identifier as CFString, 1, nil)!
    CGImageDestinationAddImage(dest, image, nil)
    CGImageDestinationFinalize(dest)
}

let iconsetURL = URL(fileURLWithPath: "build/AppIcon.iconset")
try? FileManager.default.removeItem(at: iconsetURL)
try FileManager.default.createDirectory(at: iconsetURL, withIntermediateDirectories: true)

let sizes: [(Int, Bool)] = [(16, false), (16, true), (32, false), (32, true),
                            (128, false), (128, true), (256, false), (256, true),
                            (512, false), (512, true)]

guard let master = drawIcon(size: canvas) else {
    fatalError("icon rendering failed")
}

for (size, retina) in sizes {
    let px = retina ? size * 2 : size
    let name = retina ? "icon_\(size)x\(size)@2x.png" : "icon_\(size)x\(size).png"
    let url = iconsetURL.appendingPathComponent(name)
    let ctx = CGContext(data: nil, width: px, height: px, bitsPerComponent: 8, bytesPerRow: 0,
                        space: CGColorSpace(name: CGColorSpace.sRGB)!,
                        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
    ctx.interpolationQuality = .high
    ctx.draw(master, in: CGRect(x: 0, y: 0, width: px, height: px))
    let scaled = ctx.makeImage()!
    try writePNG(scaled, to: url)
}

// Sync into the asset catalog.
let catalog = URL(fileURLWithPath: "Chaos/Assets.xcassets/AppIcon.appiconset")
for (size, retina) in sizes {
    let name = retina ? "icon_\(size)x\(size)@2x.png" : "icon_\(size)x\(size).png"
    let src = iconsetURL.appendingPathComponent(name)
    let dst = catalog.appendingPathComponent(name)
    try? FileManager.default.removeItem(at: dst)
    try FileManager.default.copyItem(at: src, to: dst)
}

print("Icon PNGs written to \(iconsetURL.path) and \(catalog.path)")
