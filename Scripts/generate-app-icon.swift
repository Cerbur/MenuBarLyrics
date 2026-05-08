#!/usr/bin/env swift

import AppKit
import CoreGraphics
import Foundation

let scriptURL = URL(fileURLWithPath: CommandLine.arguments[0])
let rootURL = scriptURL
    .deletingLastPathComponent()
    .deletingLastPathComponent()
let resourcesURL = rootURL
    .appendingPathComponent("Packaging")
    .appendingPathComponent("Resources")
let iconsetURL = resourcesURL.appendingPathComponent("MenuBarLyrics.iconset")
let icnsURL = resourcesURL.appendingPathComponent("MenuBarLyrics.icns")

try FileManager.default.createDirectory(
    at: iconsetURL,
    withIntermediateDirectories: true
)

func polygon(_ points: [CGPoint]) -> CGPath {
    let path = CGMutablePath()
    guard let first = points.first else {
        return path
    }

    path.move(to: first)
    points.dropFirst().forEach { path.addLine(to: $0) }
    path.closeSubpath()
    return path
}

func fillRoundedRect(
    _ rect: CGRect,
    radius: CGFloat,
    color: CGColor,
    in context: CGContext
) {
    context.addPath(CGPath(
        roundedRect: rect,
        cornerWidth: radius,
        cornerHeight: radius,
        transform: nil
    ))
    context.setFillColor(color)
    context.fillPath()
}

func drawIcon(size: Int, destination: URL) throws {
    let scale = CGFloat(size) / 1024
    guard let context = CGContext(
        data: nil,
        width: size,
        height: size,
        bitsPerComponent: 8,
        bytesPerRow: 0,
        space: CGColorSpace(name: CGColorSpace.sRGB)!,
        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
    ) else {
        throw CocoaError(.fileWriteUnknown)
    }

    context.scaleBy(x: scale, y: scale)
    context.setAllowsAntialiasing(true)
    context.setShouldAntialias(true)

    fillRoundedRect(
        CGRect(x: 64, y: 64, width: 896, height: 896),
        radius: 196,
        color: CGColor(red: 0.95, green: 0.96, blue: 0.94, alpha: 1),
        in: context
    )

    fillRoundedRect(
        CGRect(x: 176, y: 678, width: 672, height: 132),
        radius: 66,
        color: CGColor(red: 0.13, green: 0.15, blue: 0.16, alpha: 1),
        in: context
    )

    fillRoundedRect(
        CGRect(x: 226, y: 720, width: 96, height: 48),
        radius: 24,
        color: CGColor(red: 0.18, green: 0.74, blue: 0.77, alpha: 1),
        in: context
    )

    [
        CGRect(x: 352, y: 730, width: 240, height: 14),
        CGRect(x: 352, y: 758, width: 172, height: 14),
        CGRect(x: 614, y: 730, width: 104, height: 14)
    ].forEach {
        fillRoundedRect(
            $0,
            radius: 7,
            color: CGColor(red: 0.94, green: 0.95, blue: 0.92, alpha: 1),
            in: context
        )
    }

    context.addPath(polygon([
        CGPoint(x: 334, y: 414),
        CGPoint(x: 640, y: 284),
        CGPoint(x: 640, y: 382),
        CGPoint(x: 334, y: 512)
    ]))
    context.setFillColor(CGColor(red: 0.96, green: 0.62, blue: 0.23, alpha: 1))
    context.fillPath()

    let ink = CGColor(red: 0.10, green: 0.12, blue: 0.13, alpha: 1)
    fillRoundedRect(
        CGRect(x: 404, y: 216, width: 96, height: 292),
        radius: 48,
        color: ink,
        in: context
    )
    fillRoundedRect(
        CGRect(x: 524, y: 156, width: 96, height: 352),
        radius: 48,
        color: ink,
        in: context
    )
    fillRoundedRect(
        CGRect(x: 322, y: 486, width: 182, height: 108),
        radius: 54,
        color: ink,
        in: context
    )
    fillRoundedRect(
        CGRect(x: 442, y: 456, width: 190, height: 112),
        radius: 56,
        color: ink,
        in: context
    )

    context.addPath(polygon([
        CGPoint(x: 490, y: 214),
        CGPoint(x: 638, y: 152),
        CGPoint(x: 638, y: 222),
        CGPoint(x: 490, y: 284)
    ]))
    context.setFillColor(CGColor(red: 0.18, green: 0.74, blue: 0.77, alpha: 1))
    context.fillPath()

    context.setStrokeColor(CGColor(red: 0.18, green: 0.74, blue: 0.77, alpha: 1))
    context.setLineWidth(18)
    context.setLineCap(.round)
    [
        (CGPoint(x: 236, y: 280), CGPoint(x: 300, y: 280)),
        (CGPoint(x: 224, y: 346), CGPoint(x: 322, y: 346)),
        (CGPoint(x: 704, y: 302), CGPoint(x: 794, y: 302)),
        (CGPoint(x: 686, y: 374), CGPoint(x: 760, y: 374))
    ].forEach { start, end in
        context.move(to: start)
        context.addLine(to: end)
    }
    context.strokePath()

    guard let image = context.makeImage() else {
        throw CocoaError(.fileWriteUnknown)
    }

    let bitmap = NSBitmapImageRep(cgImage: image)
    guard let data = bitmap.representation(using: .png, properties: [:]) else {
        throw CocoaError(.fileWriteUnknown)
    }
    try data.write(to: destination)
}

let iconFiles: [(String, Int)] = [
    ("icon_16x16.png", 16),
    ("icon_16x16@2x.png", 32),
    ("icon_32x32.png", 32),
    ("icon_32x32@2x.png", 64),
    ("icon_128x128.png", 128),
    ("icon_128x128@2x.png", 256),
    ("icon_256x256.png", 256),
    ("icon_256x256@2x.png", 512),
    ("icon_512x512.png", 512),
    ("icon_512x512@2x.png", 1024)
]

for (name, size) in iconFiles {
    try drawIcon(size: size, destination: iconsetURL.appendingPathComponent(name))
}

let process = Process()
process.executableURL = URL(fileURLWithPath: "/usr/bin/iconutil")
process.arguments = ["-c", "icns", iconsetURL.path, "-o", icnsURL.path]
try process.run()
process.waitUntilExit()

if process.terminationStatus != 0 {
    throw CocoaError(.fileWriteUnknown)
}

print("Generated \(icnsURL.path)")
