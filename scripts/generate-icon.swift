#!/usr/bin/env swift

import AppKit
import CoreGraphics

/// Generates a macOS app icon with a journal/notebook design.
func renderIcon(size: CGFloat) -> NSImage {
    let image = NSImage(size: NSSize(width: size, height: size))
    image.lockFocus()

    guard let context = NSGraphicsContext.current?.cgContext else {
        image.unlockFocus()
        return image
    }

    let inset = size * 0.05
    let roundedRect = CGRect(x: inset, y: inset, width: size - inset * 2, height: size - inset * 2)
    let cornerRadius = size * 0.22
    let colorSpace = CGColorSpaceCreateDeviceRGB()

    // Background: deep warm teal gradient
    let bgPath = CGPath(roundedRect: roundedRect, cornerWidth: cornerRadius, cornerHeight: cornerRadius, transform: nil)
    context.addPath(bgPath)
    context.clip()

    let bgColors = [
        CGColor(red: 0.08, green: 0.18, blue: 0.22, alpha: 1.0),
        CGColor(red: 0.04, green: 0.10, blue: 0.14, alpha: 1.0),
    ]
    if let gradient = CGGradient(colorsSpace: colorSpace, colors: bgColors as CFArray, locations: [0.0, 1.0]) {
        context.drawLinearGradient(gradient,
                                   start: CGPoint(x: 0, y: size),
                                   end: CGPoint(x: size, y: 0),
                                   options: [])
    }

    let center = CGPoint(x: size / 2, y: size / 2)

    // --- Notebook body ---
    let bookWidth = size * 0.52
    let bookHeight = size * 0.58
    let bookLeft = center.x - bookWidth / 2
    let bookBottom = center.y - bookHeight * 0.45
    let bookCorner = size * 0.03

    let bookRect = CGRect(x: bookLeft, y: bookBottom, width: bookWidth, height: bookHeight)
    let bookPath = CGPath(roundedRect: bookRect, cornerWidth: bookCorner, cornerHeight: bookCorner, transform: nil)

    // Book cover fill with subtle gradient
    context.saveGState()
    context.addPath(bookPath)
    context.clip()
    let bookColors = [
        CGColor(red: 0.92, green: 0.88, blue: 0.80, alpha: 1.0),
        CGColor(red: 0.85, green: 0.80, blue: 0.72, alpha: 1.0),
    ]
    if let bookGradient = CGGradient(colorsSpace: colorSpace, colors: bookColors as CFArray, locations: [0.0, 1.0]) {
        context.drawLinearGradient(bookGradient,
                                   start: CGPoint(x: bookLeft, y: bookBottom + bookHeight),
                                   end: CGPoint(x: bookLeft + bookWidth, y: bookBottom),
                                   options: [])
    }
    context.restoreGState()

    // Book spine — vertical line on left
    let spineX = bookLeft + size * 0.06
    context.setStrokeColor(CGColor(red: 0.65, green: 0.58, blue: 0.48, alpha: 0.6))
    context.setLineWidth(size * 0.008)
    context.move(to: CGPoint(x: spineX, y: bookBottom + bookCorner))
    context.addLine(to: CGPoint(x: spineX, y: bookBottom + bookHeight - bookCorner))
    context.strokePath()

    // Horizontal ruled lines on the page
    let lineStartX = spineX + size * 0.04
    let lineEndX = bookLeft + bookWidth - size * 0.04
    let lineStartY = bookBottom + bookHeight - size * 0.10
    let lineSpacing = size * 0.055
    let lineCount = 7

    context.setStrokeColor(CGColor(red: 0.55, green: 0.50, blue: 0.45, alpha: 0.25))
    context.setLineWidth(size * 0.004)

    for i in 0..<lineCount {
        let y = lineStartY - CGFloat(i) * lineSpacing
        context.move(to: CGPoint(x: lineStartX, y: y))
        context.addLine(to: CGPoint(x: lineEndX, y: y))
    }
    context.strokePath()

    // Simulated handwriting strokes on the lines (wavy marks)
    context.setStrokeColor(CGColor(red: 0.25, green: 0.25, blue: 0.30, alpha: 0.45))
    context.setLineWidth(size * 0.006)
    context.setLineCap(.round)

    let writingWidths: [CGFloat] = [0.70, 0.55, 0.80, 0.45, 0.65, 0.35]
    for i in 0..<min(writingWidths.count, lineCount - 1) {
        let y = lineStartY - CGFloat(i) * lineSpacing - size * 0.008
        let startX = lineStartX + size * 0.01
        let endX = startX + (lineEndX - lineStartX) * writingWidths[i]

        // Slightly wavy line to simulate handwriting
        context.move(to: CGPoint(x: startX, y: y))
        let midX = (startX + endX) / 2
        context.addQuadCurve(to: CGPoint(x: midX, y: y),
                             control: CGPoint(x: startX + (midX - startX) * 0.5, y: y + size * 0.006))
        context.addQuadCurve(to: CGPoint(x: endX, y: y),
                             control: CGPoint(x: midX + (endX - midX) * 0.5, y: y - size * 0.005))
    }
    context.strokePath()

    // Book outline
    context.addPath(bookPath)
    context.setStrokeColor(CGColor(red: 0.55, green: 0.48, blue: 0.38, alpha: 0.5))
    context.setLineWidth(size * 0.010)
    context.strokePath()

    // --- Pen, angled from bottom-right ---
    let penLength = size * 0.42
    let penWidth = size * 0.045
    let penAngle: CGFloat = .pi / 4  // 45 degrees

    // Pen tip sits on the page
    let penTipX = center.x + size * 0.10
    let penTipY = center.y - size * 0.05

    let cosA = cos(penAngle)
    let sinA = sin(penAngle)

    // Pen body (from tip going up-right)
    let penBodyStartX = penTipX + penWidth * 0.8 * cosA
    let penBodyStartY = penTipY + penWidth * 0.8 * sinA
    let penBodyEndX = penTipX + penLength * cosA
    let penBodyEndY = penTipY + penLength * sinA

    // Perpendicular offset for pen width
    let perpX = -sinA * penWidth / 2
    let perpY = cosA * penWidth / 2

    // Pen nib (triangle from tip to body start)
    context.setFillColor(CGColor(red: 0.30, green: 0.30, blue: 0.30, alpha: 1.0))
    context.move(to: CGPoint(x: penTipX, y: penTipY))
    context.addLine(to: CGPoint(x: penBodyStartX + perpX, y: penBodyStartY + perpY))
    context.addLine(to: CGPoint(x: penBodyStartX - perpX, y: penBodyStartY - perpY))
    context.closePath()
    context.fillPath()

    // Pen body
    let penBodyPath = CGMutablePath()
    penBodyPath.move(to: CGPoint(x: penBodyStartX + perpX, y: penBodyStartY + perpY))
    penBodyPath.addLine(to: CGPoint(x: penBodyEndX + perpX, y: penBodyEndY + perpY))
    penBodyPath.addLine(to: CGPoint(x: penBodyEndX - perpX, y: penBodyEndY - perpY))
    penBodyPath.addLine(to: CGPoint(x: penBodyStartX - perpX, y: penBodyStartY - perpY))
    penBodyPath.closeSubpath()

    context.saveGState()
    context.addPath(penBodyPath)
    context.clip()
    let penColors = [
        CGColor(red: 0.22, green: 0.58, blue: 0.62, alpha: 1.0),
        CGColor(red: 0.16, green: 0.45, blue: 0.50, alpha: 1.0),
    ]
    if let penGradient = CGGradient(colorsSpace: colorSpace, colors: penColors as CFArray, locations: [0.0, 1.0]) {
        context.drawLinearGradient(penGradient,
                                   start: CGPoint(x: penBodyStartX + perpX, y: penBodyStartY + perpY),
                                   end: CGPoint(x: penBodyStartX - perpX, y: penBodyStartY - perpY),
                                   options: [])
    }
    context.restoreGState()

    // Pen clip (thin metallic strip along the pen)
    let clipOffset: CGFloat = 0.65
    let clipStartX = penBodyStartX + (penBodyEndX - penBodyStartX) * 0.2
    let clipStartY = penBodyStartY + (penBodyEndY - penBodyStartY) * 0.2
    let clipEndX = penBodyStartX + (penBodyEndX - penBodyStartX) * clipOffset
    let clipEndY = penBodyStartY + (penBodyEndY - penBodyStartY) * clipOffset
    let clipW = penWidth * 0.12

    context.setStrokeColor(CGColor(red: 0.85, green: 0.82, blue: 0.75, alpha: 0.7))
    context.setLineWidth(clipW)
    context.setLineCap(.round)
    context.move(to: CGPoint(x: clipStartX + perpX * 0.5, y: clipStartY + perpY * 0.5))
    context.addLine(to: CGPoint(x: clipEndX + perpX * 0.5, y: clipEndY + perpY * 0.5))
    context.strokePath()

    // Small ink dot at pen tip
    let dotR = size * 0.010
    context.setFillColor(CGColor(red: 0.15, green: 0.15, blue: 0.20, alpha: 0.8))
    context.fillEllipse(in: CGRect(x: penTipX - dotR, y: penTipY - dotR, width: dotR * 2, height: dotR * 2))

    image.unlockFocus()
    return image
}

// Generate all required icon sizes
let sizes: [(CGFloat, String)] = [
    (16, "icon_16x16"),
    (32, "icon_16x16@2x"),
    (32, "icon_32x32"),
    (64, "icon_32x32@2x"),
    (128, "icon_128x128"),
    (256, "icon_128x128@2x"),
    (256, "icon_256x256"),
    (512, "icon_256x256@2x"),
    (512, "icon_512x512"),
    (1024, "icon_512x512@2x"),
]

// Create iconset directory
let iconsetPath = "AppIcon.iconset"
let fm = FileManager.default
try? fm.createDirectory(atPath: iconsetPath, withIntermediateDirectories: true)

for (size, name) in sizes {
    let image = renderIcon(size: size)
    guard let tiffData = image.tiffRepresentation,
          let bitmap = NSBitmapImageRep(data: tiffData),
          let pngData = bitmap.representation(using: .png, properties: [:]) else {
        print("Failed to generate \(name)")
        continue
    }
    let path = "\(iconsetPath)/\(name).png"
    try! pngData.write(to: URL(fileURLWithPath: path))
    print("Generated \(path) (\(Int(size))x\(Int(size)))")
}

print("\nConverting to .icns...")
let process = Process()
process.executableURL = URL(fileURLWithPath: "/usr/bin/iconutil")
process.arguments = ["-c", "icns", iconsetPath]
try! process.run()
process.waitUntilExit()

if process.terminationStatus == 0 {
    print("Created AppIcon.icns")
} else {
    print("iconutil failed")
}

// Clean up iconset
try? fm.removeItem(atPath: iconsetPath)
