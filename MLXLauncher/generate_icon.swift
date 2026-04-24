#!/usr/bin/env swift

import Cocoa

func generateKittyIcon(size: Int) -> NSImage {
    let img = NSImage(size: NSSize(width: size, height: size))
    img.lockFocus()

    let ctx = NSGraphicsContext.current!.cgContext
    let s = CGFloat(size)

    // Background: rounded rectangle with gradient
    let bgRect = CGRect(x: 0, y: 0, width: s, height: s)
    let bgPath = CGPath(roundedRect: bgRect, cornerWidth: s * 0.22, cornerHeight: s * 0.22, transform: nil)
    ctx.addPath(bgPath)
    ctx.clip()

    // Gradient background - deep purple to warm pink
    let colorSpace = CGColorSpace(name: CGColorSpace.sRGB)!
    let gradient = CGGradient(
        colorsSpace: colorSpace,
        colors: [
            CGColor(srgbRed: 0.18, green: 0.05, blue: 0.32, alpha: 1.0),
            CGColor(srgbRed: 0.45, green: 0.10, blue: 0.40, alpha: 1.0),
            CGColor(srgbRed: 0.25, green: 0.08, blue: 0.35, alpha: 1.0),
        ] as CFArray,
        locations: [0.0, 0.5, 1.0]
    )!
    ctx.drawLinearGradient(gradient, start: CGPoint(x: 0, y: s), end: CGPoint(x: s, y: 0), options: [])

    // Subtle grid pattern (terminal vibes)
    ctx.setStrokeColor(CGColor(srgbRed: 1, green: 1, blue: 1, alpha: 0.03))
    ctx.setLineWidth(s * 0.002)
    let gridStep = s / 32
    for i in 0..<33 {
        let pos = CGFloat(i) * gridStep
        ctx.move(to: CGPoint(x: pos, y: 0))
        ctx.addLine(to: CGPoint(x: pos, y: s))
        ctx.move(to: CGPoint(x: 0, y: pos))
        ctx.addLine(to: CGPoint(x: s, y: pos))
    }
    ctx.strokePath()

    // Draw the kitty using "pixels" (ASCII-art style blocks)
    let ascii: [(row: Int, cols: [Int], color: (CGFloat, CGFloat, CGFloat, CGFloat))] = [
        // Ears (top)
        (3,  [9, 10, 21, 22],                                    (1.0, 0.85, 0.5, 1.0)),  // ear tips
        (4,  [8, 9, 10, 11, 20, 21, 22, 23],                     (1.0, 0.85, 0.5, 1.0)),  // ears
        (5,  [7, 8, 9, 10, 11, 12, 19, 20, 21, 22, 23, 24],     (1.0, 0.85, 0.5, 1.0)),  // ears
        (6,  [7, 8, 11, 12, 19, 20, 23, 24],                     (1.0, 0.85, 0.5, 1.0)),  // outer ears
        (6,  [9, 10, 21, 22],                                    (1.0, 0.6, 0.7, 1.0)),   // inner ears (pink)
        // Head
        (7,  [7, 8, 9, 10, 11, 12, 13, 14, 15, 16, 17, 18, 19, 20, 21, 22, 23, 24], (1.0, 0.85, 0.5, 1.0)),
        (8,  [7, 8, 9, 10, 11, 12, 13, 14, 15, 16, 17, 18, 19, 20, 21, 22, 23, 24], (1.0, 0.85, 0.5, 1.0)),
        // Eyes row
        (9,  [7, 8, 13, 14, 17, 18, 23, 24],                     (1.0, 0.85, 0.5, 1.0)),  // face
        (9,  [9, 10, 11, 12],                                    (0.3, 0.9, 0.7, 1.0)),   // left eye (green/teal)
        (9,  [19, 20, 21, 22],                                   (0.3, 0.9, 0.7, 1.0)),   // right eye
        (10, [7, 8, 13, 14, 17, 18, 23, 24],                     (1.0, 0.85, 0.5, 1.0)),
        (10, [9, 10],                                            (0.3, 0.9, 0.7, 1.0)),   // left eye bottom
        (10, [11, 12],                                           (0.1, 0.1, 0.15, 1.0)),  // left pupil
        (10, [19, 20],                                           (0.1, 0.1, 0.15, 1.0)),  // right pupil
        (10, [21, 22],                                           (0.3, 0.9, 0.7, 1.0)),   // right eye bottom
        // Nose / mouth
        (11, [7, 8, 9, 10, 11, 12, 13, 14, 17, 18, 19, 20, 21, 22, 23, 24], (1.0, 0.85, 0.5, 1.0)),
        (11, [15, 16],                                           (1.0, 0.5, 0.6, 1.0)),   // nose (pink)
        (12, [7, 8, 9, 10, 11, 12, 13, 19, 20, 21, 22, 23, 24], (1.0, 0.85, 0.5, 1.0)),
        (12, [14, 15, 16, 17, 18],                               (1.0, 0.85, 0.5, 1.0)),  // mouth area
        // Whiskers encoded as face
        (13, [8, 9, 10, 11, 12, 13, 14, 15, 16, 17, 18, 19, 20, 21, 22, 23], (1.0, 0.85, 0.5, 1.0)),
        // Body
        (14, [9, 10, 11, 12, 13, 14, 15, 16, 17, 18, 19, 20, 21, 22], (1.0, 0.85, 0.5, 1.0)),
        (15, [9, 10, 11, 12, 13, 14, 15, 16, 17, 18, 19, 20, 21, 22], (1.0, 0.85, 0.5, 1.0)),
        (16, [8, 9, 10, 11, 12, 13, 14, 15, 16, 17, 18, 19, 20, 21, 22, 23], (1.0, 0.85, 0.5, 1.0)),
        (17, [8, 9, 10, 11, 12, 13, 14, 15, 16, 17, 18, 19, 20, 21, 22, 23], (1.0, 0.85, 0.5, 1.0)),
        // Belly
        (18, [8, 9, 10, 11, 20, 21, 22, 23],                     (1.0, 0.85, 0.5, 1.0)),
        (18, [12, 13, 14, 15, 16, 17, 18, 19],                   (1.0, 0.95, 0.8, 1.0)),  // white belly
        (19, [8, 9, 10, 11, 20, 21, 22, 23],                     (1.0, 0.85, 0.5, 1.0)),
        (19, [12, 13, 14, 15, 16, 17, 18, 19],                   (1.0, 0.95, 0.8, 1.0)),
        // Paws
        (20, [8, 9, 10, 11, 12, 13, 14, 15, 16, 17, 18, 19, 20, 21, 22, 23], (1.0, 0.85, 0.5, 1.0)),
        (21, [8, 9, 10, 22, 23, 24],                             (1.0, 0.85, 0.5, 1.0)),  // outer paws
        (21, [11, 12, 13, 14, 17, 18, 19, 20],                   (1.0, 0.95, 0.8, 1.0)),  // inner paws
        // Tail
        (19, [24, 25],                                           (1.0, 0.85, 0.5, 1.0)),
        (18, [25, 26],                                           (1.0, 0.85, 0.5, 1.0)),
        (17, [26, 27],                                           (1.0, 0.85, 0.5, 1.0)),
        (16, [25, 26, 27],                                       (1.0, 0.85, 0.5, 1.0)),
    ]

    // "MLX" text pixels at bottom
    let mlxText: [(row: Int, cols: [Int])] = [
        // M
        (24, [5, 6, 11, 12]),
        (25, [5, 6, 7, 10, 11, 12]),
        (26, [5, 6, 8, 9, 11, 12]),
        (27, [5, 6, 11, 12]),
        // L
        (24, [14, 15]),
        (25, [14, 15]),
        (26, [14, 15]),
        (27, [14, 15, 16, 17, 18]),
        // X
        (24, [20, 21, 25, 26]),
        (25, [22, 23, 24]),
        (26, [22, 23, 24]),
        (27, [20, 21, 25, 26]),
    ]

    let cellSize = s / 32.0

    // Draw kitty pixels
    for entry in ascii {
        let r = entry.row
        let cols = entry.cols
        let (cr, cg, cb, ca) = entry.color
        ctx.setFillColor(CGColor(srgbRed: cr, green: cg, blue: cb, alpha: ca))
        for c in cols {
            let rect = CGRect(
                x: CGFloat(c) * cellSize,
                y: s - CGFloat(r + 1) * cellSize,
                width: cellSize + 0.5,
                height: cellSize + 0.5
            )
            ctx.fill(rect)
        }
    }

    // Draw MLX text
    ctx.setFillColor(CGColor(srgbRed: 0.5, green: 1.0, blue: 0.85, alpha: 0.9))
    for entry in mlxText {
        let r = entry.row
        for c in entry.cols {
            let rect = CGRect(
                x: CGFloat(c) * cellSize,
                y: s - CGFloat(r + 1) * cellSize,
                width: cellSize + 0.5,
                height: cellSize + 0.5
            )
            ctx.fill(rect)
        }
    }

    // Subtle glow around the kitty's eyes
    ctx.setFillColor(CGColor(srgbRed: 0.3, green: 0.9, blue: 0.7, alpha: 0.08))
    for r in 8...11 {
        for c in 7...25 {
            let rect = CGRect(
                x: CGFloat(c) * cellSize,
                y: s - CGFloat(r + 1) * cellSize,
                width: cellSize,
                height: cellSize
            )
            ctx.fill(rect)
        }
    }

    img.unlockFocus()
    return img
}

func createICNS(outputPath: String) {
    let iconsetPath = "/tmp/AppIcon.iconset"

    // Clean up
    try? FileManager.default.removeItem(atPath: iconsetPath)
    try? FileManager.default.createDirectory(atPath: iconsetPath, withIntermediateDirectories: true)

    let sizes: [(name: String, size: Int)] = [
        ("icon_16x16", 16),
        ("icon_16x16@2x", 32),
        ("icon_32x32", 32),
        ("icon_32x32@2x", 64),
        ("icon_128x128", 128),
        ("icon_128x128@2x", 256),
        ("icon_256x256", 256),
        ("icon_256x256@2x", 512),
        ("icon_512x512", 512),
        ("icon_512x512@2x", 1024),
    ]

    for (name, size) in sizes {
        let image = generateKittyIcon(size: size)
        guard let tiffData = image.tiffRepresentation,
              let bitmapRep = NSBitmapImageRep(data: tiffData),
              let pngData = bitmapRep.representation(using: .png, properties: [:]) else {
            print("Failed to generate \(name)")
            continue
        }

        let filePath = "\(iconsetPath)/\(name).png"
        try! pngData.write(to: URL(fileURLWithPath: filePath))
    }

    // Convert iconset to icns
    let task = Process()
    task.launchPath = "/usr/bin/iconutil"
    task.arguments = ["-c", "icns", iconsetPath, "-o", outputPath]
    task.launch()
    task.waitUntilExit()

    if task.terminationStatus == 0 {
        print("Icon created at \(outputPath)")
    } else {
        print("iconutil failed with status \(task.terminationStatus)")
    }

    // Clean up iconset
    try? FileManager.default.removeItem(atPath: iconsetPath)
}

// Main
let outputPath = CommandLine.arguments.count > 1
    ? CommandLine.arguments[1]
    : "/tmp/AppIcon.icns"

createICNS(outputPath: outputPath)
