#!/usr/bin/env swift
// Generates the Autohand Voice app icon (1024×1024) programmatically.
//
// The icon is a plain white rounded-square background with a hairline
// light-gray edge, and one continuous smooth sine-wave stroke in the
// same near-black (#1A1A1A) used by the existing brand SVGs.
//
// Usage:
//   swift scripts/generate-app-icon.swift
//
// Output: assets/icon-1024.png

import AppKit
import CoreGraphics

let size: CGFloat = 1024

let repoRoot = URL(
    fileURLWithPath: FileManager.default.currentDirectoryPath
)
let outputURL = repoRoot
    .appendingPathComponent("assets")
    .appendingPathComponent("icon-1024.png")

// Ensure the output directory exists.
try? FileManager.default.createDirectory(
    at: outputURL.deletingLastPathComponent(),
    withIntermediateDirectories: true
)

// --- Background: white rounded rect with a hairline light-gray edge ---
//
// Rendered into an explicitly sized NSBitmapImageRep rather than via
// NSImage.lockFocus(), which silently scales output by the current
// display's backing scale factor (2x on a Retina screen, 1x elsewhere).
// That would make the exported pixel size depend on the machine running
// this script instead of always being exactly `size`.
guard
    let bitmap = NSBitmapImageRep(
        bitmapDataPlanes: nil,
        pixelsWide: Int(size),
        pixelsHigh: Int(size),
        bitsPerSample: 8,
        samplesPerPixel: 4,
        hasAlpha: true,
        isPlanar: false,
        colorSpaceName: .deviceRGB,
        bytesPerRow: 0,
        bitsPerPixel: 0
    ),
    let context = NSGraphicsContext(bitmapImageRep: bitmap)
else {
    fputs("Failed to create bitmap context.\n", stderr)
    exit(1)
}

NSGraphicsContext.saveGraphicsState()
NSGraphicsContext.current = context

let bgRect = NSRect(x: 0, y: 0, width: size, height: size)
let cornerRadius: CGFloat = size * 0.18  // ~18% corner radius

NSColor.white.setFill()
let bgPath = NSBezierPath(
    roundedRect: bgRect.insetBy(dx: 0.5, dy: 0.5),
    xRadius: cornerRadius,
    yRadius: cornerRadius
)
bgPath.fill()

// Hairline light-gray edge
NSColor(calibratedWhite: 0.88, alpha: 1.0).setStroke()
bgPath.lineWidth = 1.0
bgPath.stroke()

// --- Sine wave stroke ---
let waveColor = NSColor(calibratedRed: 26 / 255.0, green: 26 / 255.0, blue: 26 / 255.0, alpha: 1.0)
waveColor.setStroke()

let wavePath = NSBezierPath()
wavePath.lineCapStyle = .round
wavePath.lineJoinStyle = .round

let amplitude: CGFloat = size * 0.18
let centerY = size / 2.0
let cycles: CGFloat = 2.5
let horizontalPadding: CGFloat = size * 0.08
let waveWidth = size - 2 * horizontalPadding

wavePath.move(to: NSPoint(x: horizontalPadding, y: centerY))

let steps = 400
for i in 0...steps {
    let t = CGFloat(i) / CGFloat(steps)
    let x = horizontalPadding + t * waveWidth
    let y = centerY + amplitude * sin(t * cycles * 2.0 * .pi)
    wavePath.line(to: NSPoint(x: x, y: y))
}

wavePath.lineWidth = size * 0.045  // ~4.5% of canvas width
wavePath.stroke()

NSGraphicsContext.restoreGraphicsState()

// --- Export as PNG ---
guard let pngData = bitmap.representation(using: .png, properties: [:]) else {
    fputs("Failed to generate PNG.\n", stderr)
    exit(1)
}

do {
    try pngData.write(to: outputURL)
    print("Wrote \(outputURL.path)")
} catch {
    fputs("Failed to write PNG: \(error)\n", stderr)
    exit(1)
}
