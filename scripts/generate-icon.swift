#!/usr/bin/env swift

import AppKit
import Foundation

// Generate app icon using SF Symbols
let sizes: [(Int, String)] = [
    (16, "icon_16x16.png"),
    (32, "icon_16x16@2x.png"),
    (32, "icon_32x32.png"),
    (64, "icon_32x32@2x.png"),
    (128, "icon_128x128.png"),
    (256, "icon_128x128@2x.png"),
    (256, "icon_256x256.png"),
    (512, "icon_256x256@2x.png"),
    (512, "icon_512x512.png"),
    (1024, "icon_512x512@2x.png")
]

let outputDir = FileManager.default.currentDirectoryPath + "/Sources/WhisperAI/Resources/AppIcon.iconset"

// Create directory if needed
try? FileManager.default.createDirectory(atPath: outputDir, withIntermediateDirectories: true)

for (size, filename) in sizes {
    let imageSize = NSSize(width: size, height: size)

    let image = NSImage(size: imageSize)
    image.lockFocus()

    // Background - gradient blue circle
    let rect = NSRect(origin: .zero, size: imageSize)
    let path = NSBezierPath(ovalIn: rect.insetBy(dx: CGFloat(size) * 0.05, dy: CGFloat(size) * 0.05))

    // Gradient from light blue to dark blue
    let gradient = NSGradient(colors: [
        NSColor(red: 0.2, green: 0.6, blue: 1.0, alpha: 1.0),
        NSColor(red: 0.1, green: 0.4, blue: 0.9, alpha: 1.0)
    ])
    gradient?.draw(in: path, angle: -90)

    // Draw microphone SF Symbol
    if let micImage = NSImage(systemSymbolName: "mic.fill", accessibilityDescription: nil) {
        let config = NSImage.SymbolConfiguration(pointSize: CGFloat(size) * 0.5, weight: .semibold)
        let configuredMic = micImage.withSymbolConfiguration(config)

        // Calculate centered position
        let micSize = NSSize(width: CGFloat(size) * 0.5, height: CGFloat(size) * 0.5)
        let micRect = NSRect(
            x: (imageSize.width - micSize.width) / 2,
            y: (imageSize.height - micSize.height) / 2,
            width: micSize.width,
            height: micSize.height
        )

        // Draw white microphone
        NSColor.white.setFill()
        configuredMic?.draw(in: micRect, from: .zero, operation: .sourceOver, fraction: 1.0)
    }

    image.unlockFocus()

    // Save as PNG
    if let tiffData = image.tiffRepresentation,
       let bitmap = NSBitmapImageRep(data: tiffData),
       let pngData = bitmap.representation(using: .png, properties: [:]) {
        let filePath = outputDir + "/" + filename
        try? pngData.write(to: URL(fileURLWithPath: filePath))
        print("Created: \(filename)")
    }
}

print("\nNow run: iconutil -c icns \(outputDir) -o Sources/WhisperAI/Resources/AppIcon.icns")
