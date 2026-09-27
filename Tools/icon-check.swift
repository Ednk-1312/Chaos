// icon-check.swift — samples key pixels of the rendered icon to verify drawing.
import Foundation
import CoreGraphics
import ImageIO

let url = URL(fileURLWithPath: "build/AppIcon.iconset/icon_512x512.png")
guard let src = CGImageSourceCreateWithURL(url as CFURL, nil),
      let image = CGImageSourceCreateImageAtIndex(src, 0, nil) else { fatalError("no image") }

let w = image.width, h = image.height
let space = CGColorSpace(name: CGColorSpace.sRGB)!
var buf = [UInt8](repeating: 0, count: w * h * 4)
let ctx = CGContext(data: &buf, width: w, height: h, bitsPerComponent: 8, bytesPerRow: w * 4,
                    space: space, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
ctx.draw(image, in: CGRect(x: 0, y: 0, width: w, height: h))

func pixel(_ x: Int, _ y: Int) -> (r: UInt8, g: UInt8, b: UInt8) {
    // flip y: buffer is top-down, design space is bottom-up
    let i = ((h - 1 - y) * w + x) * 4
    return (buf[i], buf[i + 1], buf[i + 2])
}

func describe(_ name: String, _ p: (r: UInt8, g: UInt8, b: UInt8)) {
    print("\(name): rgb(\(p.r), \(p.g), \(p.b))")
}

// 512px image = half of the 1024 design space.
func dpixel(_ dx: Int, _ dy: Int) -> (r: UInt8, g: UInt8, b: UInt8) {
    pixel(dx / 2, dy / 2)
}

describe("corner  (bg, expect dark ~0x15-2A)", dpixel(60, 60))
describe("center  (C face, expect near-white)", dpixel(512, 722))
describe("core    (below C, expect red glow)", dpixel(512, 380))
describe("crack   (expect dark, cutting C)", dpixel(518, 690))
describe("ring mid-left (expect white/gray)", dpixel(310, 512))

// Checks (non-fatal, summarized)
var failures = 0
func check(_ name: String, _ cond: Bool) {
    if !cond { failures += 1; print("FAIL: \(name)") }
}

let corner = dpixel(60, 60)
check("corner should be dark", corner.r < 0x50 && corner.g < 0x50)

// Sample the C stroke slightly inside the band to dodge the crack line.
let center = dpixel(560, 700)
check("C face should be light (got \(center))", center.r > 180 && center.g > 180)

// Glow ring outside the dark disc (radius 238–330 from center): sample at (512, 780).
let core = dpixel(512, 780)
check("glow ring should be red (got \(core))", core.r > 70 && core.r > core.b)

// Dead center of the crack segment (560,760)→(500,690) passes through (530,725).
let crack = dpixel(530, 725)
check("crack should be dark (got \(crack))", crack.r < 0x60)

print(failures == 0 ? "icon-check: PASS" : "icon-check: \(failures) failure(s)")
if failures > 0 { exit(1) }
