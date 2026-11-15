// Draws the app icon and writes Assets/AppIcon.icns.
// Run from the package root:  swift scripts/make-icon.swift
//
// The icon is drawn in code, so it has no outside artwork and no SF Symbols in it.

import AppKit
import CoreGraphics
import ImageIO
import UniformTypeIdentifiers

/// Draws the icon on a 1024-point canvas. The rounded square follows the macOS icon grid:
/// 824 points wide, centred, with room left around it for the shadow.
func drawIcon(in context: CGContext) {
    let rgb = CGColorSpaceCreateDeviceRGB()
    func color(_ red: CGFloat, _ green: CGFloat, _ blue: CGFloat, _ alpha: CGFloat = 1) -> CGColor {
        CGColor(colorSpace: rgb, components: [red / 255, green / 255, blue / 255, alpha])!
    }

    let tile = CGPath(
        roundedRect: CGRect(x: 100, y: 100, width: 824, height: 824),
        cornerWidth: 185, cornerHeight: 185, transform: nil
    )

    // Soft shadow under the tile.
    context.saveGState()
    context.setShadow(offset: CGSize(width: 0, height: -12), blur: 28, color: color(0, 0, 0, 0.35))
    context.addPath(tile)
    context.setFillColor(color(18, 71, 196))
    context.fillPath()
    context.restoreGState()

    // Blue background, lighter at the top.
    context.saveGState()
    context.addPath(tile)
    context.clip()
    let gradient = CGGradient(
        colorsSpace: rgb,
        colors: [color(70, 150, 255), color(16, 62, 184)] as CFArray,
        locations: [0, 1]
    )!
    context.drawLinearGradient(gradient, start: CGPoint(x: 512, y: 924), end: CGPoint(x: 512, y: 100), options: [])
    context.restoreGState()

    let white = color(255, 255, 255)
    let keyhole = color(16, 62, 184)

    // Shackle, lifted out of the body on the left side: the padlock is open.
    let shackle = CGMutablePath()
    shackle.move(to: CGPoint(x: 617, y: 500))
    shackle.addLine(to: CGPoint(x: 617, y: 668))
    shackle.addArc(center: CGPoint(x: 512, y: 668), radius: 105, startAngle: 0, endAngle: .pi, clockwise: false)
    shackle.addLine(to: CGPoint(x: 407, y: 612))
    context.addPath(shackle)
    context.setStrokeColor(white)
    context.setLineWidth(64)
    context.setLineCap(.round)
    context.setLineJoin(.round)
    context.strokePath()

    // Body.
    context.addPath(CGPath(
        roundedRect: CGRect(x: 302, y: 226, width: 420, height: 310),
        cornerWidth: 62, cornerHeight: 62, transform: nil
    ))
    context.setFillColor(white)
    context.fillPath()

    // Keyhole: a circle with a tapered slot below it.
    context.setFillColor(keyhole)
    context.fillEllipse(in: CGRect(x: 512 - 42, y: 400 - 42, width: 84, height: 84))
    let slot = CGMutablePath()
    slot.move(to: CGPoint(x: 512 - 20, y: 400))
    slot.addLine(to: CGPoint(x: 512 + 20, y: 400))
    slot.addLine(to: CGPoint(x: 512 + 30, y: 300))
    slot.addLine(to: CGPoint(x: 512 - 30, y: 300))
    slot.closeSubpath()
    context.addPath(slot)
    context.fillPath()
}

func writePNG(pixels: Int, to url: URL) throws {
    guard let context = CGContext(
        data: nil, width: pixels, height: pixels, bitsPerComponent: 8, bytesPerRow: 0,
        space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
    ) else { throw CocoaError(.fileWriteUnknown) }
    context.interpolationQuality = .high
    context.scaleBy(x: CGFloat(pixels) / 1024, y: CGFloat(pixels) / 1024)
    drawIcon(in: context)
    guard let image = context.makeImage(),
          let destination = CGImageDestinationCreateWithURL(url as CFURL, UTType.png.identifier as CFString, 1, nil)
    else { throw CocoaError(.fileWriteUnknown) }
    CGImageDestinationAddImage(destination, image, nil)
    guard CGImageDestinationFinalize(destination) else { throw CocoaError(.fileWriteUnknown) }
}

let fileManager = FileManager.default
let root = URL(fileURLWithPath: fileManager.currentDirectoryPath)
guard fileManager.fileExists(atPath: root.appendingPathComponent("Package.swift").path) else {
    fputs("Run this from the package root.\n", stderr)
    exit(1)
}

let assets = root.appendingPathComponent("Assets", isDirectory: true)
let iconset = fileManager.temporaryDirectory.appendingPathComponent("BitMount-\(UUID().uuidString).iconset", isDirectory: true)
try fileManager.createDirectory(at: assets, withIntermediateDirectories: true)
try fileManager.createDirectory(at: iconset, withIntermediateDirectories: true)
defer { try? fileManager.removeItem(at: iconset) }

for points in [16, 32, 128, 256, 512] {
    try writePNG(pixels: points, to: iconset.appendingPathComponent("icon_\(points)x\(points).png"))
    try writePNG(pixels: points * 2, to: iconset.appendingPathComponent("icon_\(points)x\(points)@2x.png"))
}

let output = assets.appendingPathComponent("AppIcon.icns")
let iconutil = Process()
iconutil.executableURL = URL(fileURLWithPath: "/usr/bin/iconutil")
iconutil.arguments = ["-c", "icns", "-o", output.path, iconset.path]
try iconutil.run()
iconutil.waitUntilExit()
guard iconutil.terminationStatus == 0 else {
    fputs("iconutil failed.\n", stderr)
    exit(1)
}

// A preview for the README or a quick look. Not used by the app.
if CommandLine.arguments.contains("--preview") {
    try writePNG(pixels: 1024, to: assets.appendingPathComponent("AppIcon-preview.png"))
}
print(output.path)
