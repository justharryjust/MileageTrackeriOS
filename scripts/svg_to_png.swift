#!/usr/bin/env swift
import Foundation
import AppKit
import CoreGraphics
import ImageIO

// Convert SVG to PNG at 1024x1024
func svgToPNG(svgPath: String, pngPath: String, size: CGFloat = 1024) {
    let svgURL = URL(fileURLWithPath: svgPath)
    guard let image = NSImage(contentsOf: svgURL) else {
        print("✗ Failed to load SVG: \(svgPath)")
        return
    }

    let rect = NSRect(x: 0, y: 0, width: size, height: size)
    let rep = NSBitmapImageRep(
        bitmapDataPlanes: nil,
        pixelsWide: Int(size),
        pixelsHigh: Int(size),
        bitsPerSample: 8,
        samplesPerPixel: 4,
        hasAlpha: true,
        isPlanar: false,
        colorSpaceName: .deviceRGB,
        bytesPerRow: 0,
        bitsPerPixel: 32
    )!

    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    image.draw(in: rect, from: .zero, operation: .copy, fraction: 1.0)
    NSGraphicsContext.restoreGraphicsState()

    guard let pngData = rep.representation(using: .png, properties: [:]) else {
        print("✗ Failed to create PNG data")
        return
    }

    try! pngData.write(to: URL(fileURLWithPath: pngPath))
    let kb = pngData.count / 1024
    print("✓ \(pngPath) (\(kb) KB)")
}

let base = "/Users/harryjust/Development/MileageTracker/MileageTrackeriOS"
let svgFile = "\(base)/output/app_icons_v3/icon_v3.svg"
let outDir = "\(base)/output/app_icons_v3"

// Light variant (already has green bg)
svgToPNG(svgPath: svgFile, pngPath: "\(outDir)/generated_light.png")

print("Done!")
