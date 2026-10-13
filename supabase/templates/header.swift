// The artwork at the top of the sign-up and password emails: the Minor logo with a small mind map
// around it, on the app's background, in the soft branch colors the app uses on its maps.
// Run from the repo root, then upload the site:
//   swift supabase/templates/header.swift website/assets/email-header.jpg
// The emails load it from https://minorai.site/assets/email-header.jpg (shown at 560×224).

import AppKit
import CoreGraphics
import ImageIO
import UniformTypeIdentifiers

let width = 1200
let height = 480
let space = CGColorSpace(name: CGColorSpace.sRGB)!

func rgb(_ hex: UInt32, _ alpha: CGFloat = 1) -> CGColor {
    CGColor(colorSpace: space, components: [
        CGFloat((hex >> 16) & 0xff) / 255, CGFloat((hex >> 8) & 0xff) / 255, CGFloat(hex & 0xff) / 255, alpha,
    ])!
}

let background: UInt32 = 0x100e11
// Branch colors as the app draws them on a dark map.
let mint: UInt32 = 0x5fd39c
let violet: UInt32 = 0xb795ef
let pink: UInt32 = 0xe58cbf
let sky: UInt32 = 0x7eb2e6
let sun: UInt32 = 0xe8c76d
let coral: UInt32 = 0xeb9080

let ctx = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0, space: space,
                    bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
// Top-left origin, like the layout numbers below.
ctx.translateBy(x: 0, y: CGFloat(height))
ctx.scaleBy(x: 1, y: -1)

func radial(_ center: CGPoint, _ radius: CGFloat, _ hex: UInt32, _ alpha: CGFloat) {
    let gradient = CGGradient(colorsSpace: space, colors: [rgb(hex, alpha), rgb(hex, 0)] as CFArray, locations: [0, 1])!
    ctx.drawRadialGradient(gradient, startCenter: center, startRadius: 0, endCenter: center, endRadius: radius, options: [])
}

// Background with a little light behind the logo.
ctx.setFillColor(rgb(background))
ctx.fill(CGRect(x: 0, y: 0, width: width, height: height))
let logoCenter = CGPoint(x: 600, y: 236)
radial(logoCenter, 300, 0xffffff, 0.05)

// The mind map: branches from the logo to colored ideas, each with two smaller ones.
struct Branch { let node: CGPoint; let color: UInt32; let leaves: [CGPoint] }
let branches = [
    Branch(node: CGPoint(x: 372, y: 128), color: sun, leaves: [CGPoint(x: 232, y: 82), CGPoint(x: 212, y: 160)]),
    Branch(node: CGPoint(x: 318, y: 262), color: pink, leaves: [CGPoint(x: 172, y: 232), CGPoint(x: 168, y: 306)]),
    Branch(node: CGPoint(x: 396, y: 386), color: coral, leaves: [CGPoint(x: 262, y: 428), CGPoint(x: 236, y: 370)]),
    Branch(node: CGPoint(x: 830, y: 120), color: mint, leaves: [CGPoint(x: 968, y: 76), CGPoint(x: 992, y: 150)]),
    Branch(node: CGPoint(x: 886, y: 256), color: violet, leaves: [CGPoint(x: 1036, y: 222), CGPoint(x: 1030, y: 300)]),
    Branch(node: CGPoint(x: 818, y: 384), color: sky, leaves: [CGPoint(x: 958, y: 426), CGPoint(x: 976, y: 362)]),
]

// A mind-map curve: leaves and arrives horizontally.
func curve(_ from: CGPoint, _ to: CGPoint) -> CGPath {
    let path = CGMutablePath()
    let mid = from.x + (to.x - from.x) * 0.55
    path.move(to: from)
    path.addCurve(to: to, control1: CGPoint(x: mid, y: from.y), control2: CGPoint(x: mid, y: to.y))
    return path
}

// A stroke that fades from one color to another along its length.
func fadingStroke(_ path: CGPath, width lineWidth: CGFloat, from start: CGPoint, _ startColor: CGColor, to end: CGPoint, _ endColor: CGColor) {
    ctx.saveGState()
    ctx.addPath(path)
    ctx.setLineWidth(lineWidth)
    ctx.setLineCap(.round)
    ctx.replacePathWithStrokedPath()
    ctx.clip()
    let gradient = CGGradient(colorsSpace: space, colors: [startColor, endColor] as CFArray, locations: [0, 1])!
    ctx.drawLinearGradient(gradient, start: start, end: end, options: [.drawsBeforeStartLocation, .drawsAfterEndLocation])
    ctx.restoreGState()
}

let logoRadius: CGFloat = 96
for branch in branches {
    let side: CGFloat = branch.node.x < logoCenter.x ? -1 : 1
    let start = CGPoint(x: logoCenter.x + side * logoRadius * 0.92, y: logoCenter.y + (branch.node.y - logoCenter.y) * 0.32)
    fadingStroke(curve(start, branch.node), width: 3, from: start, rgb(0xffffff, 0.35), to: branch.node, rgb(branch.color, 0.9))
    for leaf in branch.leaves {
        fadingStroke(curve(branch.node, leaf), width: 2.5, from: branch.node, rgb(branch.color, 0.7), to: leaf, rgb(branch.color, 0.35))
    }
}
for branch in branches {
    for leaf in branch.leaves {
        ctx.setFillColor(rgb(branch.color, 0.7))
        ctx.fillEllipse(in: CGRect(x: leaf.x - 5, y: leaf.y - 5, width: 10, height: 10))
    }
    // An idea: a filled dot with a dark rim, the way map dots sit on the canvas.
    ctx.setFillColor(rgb(background))
    ctx.fillEllipse(in: CGRect(x: branch.node.x - 15, y: branch.node.y - 15, width: 30, height: 30))
    ctx.setFillColor(rgb(branch.color))
    ctx.fillEllipse(in: CGRect(x: branch.node.x - 11, y: branch.node.y - 11, width: 22, height: 22))
}

// The logo: three rounded heptagon rings and a filled core (same geometry as the launch splash).
func heptagon(_ center: CGPoint, _ radius: CGFloat, corner: CGFloat) -> CGPath {
    let vertices = (0..<7).map { i -> CGPoint in
        let angle = -CGFloat.pi / 2 + CGFloat(i) * 2 * .pi / 7
        return CGPoint(x: center.x + radius * cos(angle), y: center.y + radius * sin(angle))
    }
    let path = CGMutablePath()
    let first = vertices[0], last = vertices[6]
    path.move(to: CGPoint(x: (first.x + last.x) / 2, y: (first.y + last.y) / 2))
    for i in 0..<7 {
        path.addArc(tangent1End: vertices[i], tangent2End: vertices[(i + 1) % 7], radius: corner)
    }
    path.closeSubpath()
    return path
}

let rings: [(radius: CGFloat, width: CGFloat, corner: CGFloat)] = [(1, 0.1185, 0.22), (0.7997, 0.096, 0.34), (0.5822, 0.096, 0.18)]
// A soft light from the logo's outline only; the gaps between the rings stay dark, as on the icon.
let outline = logoRadius * (1 + 0.1185 / 2)
ctx.saveGState()
ctx.setShadow(offset: .zero, blur: 30, color: rgb(0xffffff, 0.28))
ctx.addPath(heptagon(logoCenter, outline, corner: outline * 0.22))
ctx.setFillColor(rgb(0xffffff))
ctx.fillPath()
ctx.restoreGState()
ctx.addPath(heptagon(logoCenter, outline, corner: outline * 0.22))
ctx.setFillColor(rgb(0x141215))
ctx.fillPath()
ctx.setStrokeColor(rgb(0xffffff))
ctx.setLineJoin(.round)
for ring in rings {
    let r = logoRadius * ring.radius
    ctx.addPath(heptagon(logoCenter, r, corner: r * ring.corner))
    ctx.setLineWidth(logoRadius * ring.width)
    ctx.strokePath()
}
let core = logoRadius * 0.3707
ctx.addPath(heptagon(logoCenter, core, corner: core * 0.31))
ctx.setFillColor(rgb(0xffffff))
ctx.fillPath()

// Fade every edge into the page color, so the picture has no visible border in the email.
func edgeFade(from start: CGPoint, to end: CGPoint) {
    let gradient = CGGradient(colorsSpace: space, colors: [rgb(background), rgb(background, 0)] as CFArray, locations: [0, 1])!
    ctx.drawLinearGradient(gradient, start: start, end: end, options: [])
}
edgeFade(from: CGPoint(x: 0, y: 0), to: CGPoint(x: 0, y: 56))
edgeFade(from: CGPoint(x: 0, y: CGFloat(height)), to: CGPoint(x: 0, y: CGFloat(height) - 70))
edgeFade(from: CGPoint(x: 0, y: 0), to: CGPoint(x: 110, y: 0))
edgeFade(from: CGPoint(x: CGFloat(width), y: 0), to: CGPoint(x: CGFloat(width) - 110, y: 0))

let output = URL(fileURLWithPath: CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "email-header.jpg")
let destination = CGImageDestinationCreateWithURL(output as CFURL, UTType.jpeg.identifier as CFString, 1, nil)!
CGImageDestinationAddImage(destination, ctx.makeImage()!, [kCGImageDestinationLossyCompressionQuality: 0.9] as CFDictionary)
CGImageDestinationFinalize(destination)
print("\(output.path): \((try? output.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0) bytes")
