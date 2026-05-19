import AppKit
import ClaudeUsageCore

// Standalone renderer that exports each evolution-stage sprite as a PNG. The same
// MascotSprite data the live app uses is consumed here — only the drawing layer differs.
//
// Usage:
//   swift run spriterender                 → writes to ./docs/stages/
//   swift run spriterender path/to/output  → writes to the supplied directory

// `spriterender icons <out.iconset> [stage]`  → write the 10-file Apple iconset
// `spriterender [<outdir>]`                   → existing stage PNG export (default ./docs/stages)
let args = CommandLine.arguments
let iconsMode = args.count >= 2 && args[1] == "icons"

let outputPath: String = {
    if iconsMode {
        return args.count >= 3 ? args[2] : FileManager.default.currentDirectoryPath + "/AppIcon.iconset"
    }
    if args.count > 1 {
        return args[1]
    }
    return FileManager.default.currentDirectoryPath + "/docs/stages"
}()
let outputDir = URL(fileURLWithPath: outputPath)
try? FileManager.default.createDirectory(at: outputDir, withIntermediateDirectories: true)

// Each cell rendered at 16×16 device pixels — gives a 256×192 PNG per stage that scales
// crisply when GitHub renders it inline.
let cellPx: CGFloat = 16
let cols = CGFloat(MascotSprite.canvasCols)
let rows = CGFloat(MascotSprite.canvasRows)
let imageSize = NSSize(width: cols * cellPx, height: rows * cellPx)

// Same palette as MascotView. Kept inline (rather than reaching into the AppKit module)
// so this stays a single self-contained executable.
let bodyColor = NSColor(calibratedRed: 0.85, green: 0.48, blue: 0.36, alpha: 1)
let eyeColor = NSColor(calibratedRed: 0.97, green: 0.87, blue: 0.78, alpha: 1)
let eggshell = NSColor(calibratedRed: 0.97, green: 0.94, blue: 0.88, alpha: 1)
let wandShaft = NSColor(calibratedWhite: 0.30, alpha: 1)

func color(for ch: Character) -> NSColor? {
    switch ch {
    case "X": return bodyColor
    case "o", "c": return eyeColor
    case "W": return eggshell
    case "s": return bodyColor
    case "g": return wandShaft
    default:  return nil
    }
}

func renderSprite(_ sprite: [String]) -> Data {
    let bitmap = NSBitmapImageRep(
        bitmapDataPlanes: nil,
        pixelsWide: Int(imageSize.width),
        pixelsHigh: Int(imageSize.height),
        bitsPerSample: 8,
        samplesPerPixel: 4,
        hasAlpha: true,
        isPlanar: false,
        colorSpaceName: .deviceRGB,
        bytesPerRow: 0,
        bitsPerPixel: 0
    )!
    let gctx = NSGraphicsContext(bitmapImageRep: bitmap)!
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = gctx

    gctx.cgContext.setShouldAntialias(false)
    gctx.cgContext.interpolationQuality = .none

    // Top-down: row 0 is drawn at the top, just like the live view (which is isFlipped).
    for (rowIdx, row) in sprite.enumerated() {
        for (colIdx, ch) in row.enumerated() {
            guard let c = color(for: ch) else { continue }
            c.setFill()
            // Bitmap origin is bottom-left, so flip Y.
            let y = (rows - 1 - CGFloat(rowIdx)) * cellPx
            NSRect(x: CGFloat(colIdx) * cellPx, y: y, width: cellPx, height: cellPx).fill()
        }
    }

    NSGraphicsContext.restoreGraphicsState()
    guard let data = bitmap.representation(using: .png, properties: [:]) else {
        fatalError("PNG encoding failed")
    }
    return data
}

func renderCombined(_ stages: [EvolutionStage]) -> Data {
    // One row, left-to-right, with a thin transparent gutter between stages.
    let gutter: CGFloat = cellPx
    let cellW = cols * cellPx
    let totalW = CGFloat(stages.count) * cellW + CGFloat(stages.count - 1) * gutter
    let bitmap = NSBitmapImageRep(
        bitmapDataPlanes: nil,
        pixelsWide: Int(totalW),
        pixelsHigh: Int(imageSize.height),
        bitsPerSample: 8,
        samplesPerPixel: 4,
        hasAlpha: true,
        isPlanar: false,
        colorSpaceName: .deviceRGB,
        bytesPerRow: 0,
        bitsPerPixel: 0
    )!
    let gctx = NSGraphicsContext(bitmapImageRep: bitmap)!
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = gctx
    gctx.cgContext.setShouldAntialias(false)
    gctx.cgContext.interpolationQuality = .none

    for (idx, stage) in stages.enumerated() {
        let sprite = MascotSprite.sprite(for: stage)
        let xOffset = CGFloat(idx) * (cellW + gutter)
        for (rowIdx, row) in sprite.enumerated() {
            for (colIdx, ch) in row.enumerated() {
                guard let c = color(for: ch) else { continue }
                c.setFill()
                let y = (rows - 1 - CGFloat(rowIdx)) * cellPx
                NSRect(
                    x: xOffset + CGFloat(colIdx) * cellPx,
                    y: y,
                    width: cellPx,
                    height: cellPx
                ).fill()
            }
        }
    }

    NSGraphicsContext.restoreGraphicsState()
    return bitmap.representation(using: .png, properties: [:])!
}

/// Draws one sprite into the current graphics context, fitted to the given inner box.
/// Caller is responsible for the background. Pixel-art-friendly (no antialiasing).
func drawSprite(_ sprite: [String], in box: NSRect) {
    let cellSize = box.width / CGFloat(MascotSprite.canvasCols)
    let totalH = cellSize * CGFloat(MascotSprite.canvasRows)
    let yBase = box.minY + (box.height - totalH) / 2
    for (rowIdx, row) in sprite.enumerated() {
        for (colIdx, ch) in row.enumerated() {
            guard let c = color(for: ch) else { continue }
            c.setFill()
            // Bitmap origin is bottom-left; flip Y so row 0 sits at the top.
            let y = yBase + (CGFloat(MascotSprite.canvasRows) - 1 - CGFloat(rowIdx)) * cellSize
            NSRect(
                x: box.minX + CGFloat(colIdx) * cellSize,
                y: y,
                width: cellSize,
                height: cellSize
            ).fill()
        }
    }
}

/// Renders one icon: warm orange squircle background + Ultimate drawn in cream
/// (color-inverted palette). No accessory — Ultimate stands alone, centered.
func renderIcon(size: Int) -> Data {
    let bitmap = NSBitmapImageRep(
        bitmapDataPlanes: nil,
        pixelsWide: size,
        pixelsHigh: size,
        bitsPerSample: 8,
        samplesPerPixel: 4,
        hasAlpha: true,
        isPlanar: false,
        colorSpaceName: .deviceRGB,
        bytesPerRow: 0,
        bitsPerPixel: 0
    )!
    let gctx = NSGraphicsContext(bitmapImageRep: bitmap)!
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = gctx

    let S = CGFloat(size)

    // macOS HIG: the squircle should sit inside the icon canvas with ~10% padding
    // so it matches the visual size of every other app icon in the Dock.
    let canvasPadding = S * 0.10
    let squircleSide = S - canvasPadding * 2
    // Apple's continuous-curvature "squircle" — corner radius ≈ 22.5% of the squircle side.
    let cornerRadius = squircleSide * 0.225
    let squircleRect = NSRect(
        x: canvasPadding,
        y: canvasPadding,
        width: squircleSide,
        height: squircleSide
    )
    NSColor(calibratedRed: 0.89, green: 0.52, blue: 0.38, alpha: 1).setFill()
    NSBezierPath(roundedRect: squircleRect, xRadius: cornerRadius, yRadius: cornerRadius).fill()

    gctx.cgContext.setShouldAntialias(false)
    gctx.cgContext.interpolationQuality = .none

    // Mascot fits inside the squircle with its own breathing room.
    let mascotInset = squircleSide * 0.125
    let box = NSRect(
        x: squircleRect.minX + mascotInset,
        y: squircleRect.minY + mascotInset,
        width: squircleSide - mascotInset * 2,
        height: squircleSide - mascotInset * 2
    )

    // Inverted palette: body in near-white (with a hint of warmth so it doesn't
    // look sterile), accents in the original mascot body color so they read as
    // "cut-outs" against the silhouette.
    let cream = NSColor(calibratedRed: 1.00, green: 0.99, blue: 0.97, alpha: 1)
    let accent = NSColor(calibratedRed: 0.85, green: 0.48, blue: 0.36, alpha: 1)
    let wandDark = NSColor(calibratedRed: 0.28, green: 0.20, blue: 0.15, alpha: 1)
    func iconPalette(_ ch: Character) -> NSColor? {
        switch ch {
        case "X": return cream
        case "o", "c": return accent
        case "g": return wandDark
        default:  return nil
        }
    }

    let sprite = MascotSprite.sprite(for: .ultimate)
    let cellSize = box.width / CGFloat(MascotSprite.canvasCols)
    let totalH = cellSize * CGFloat(MascotSprite.canvasRows)
    let yBase = box.minY + (box.height - totalH) / 2
    for (rowIdx, row) in sprite.enumerated() {
        for (colIdx, ch) in row.enumerated() {
            guard let c = iconPalette(ch) else { continue }
            c.setFill()
            let y = yBase + (CGFloat(MascotSprite.canvasRows) - 1 - CGFloat(rowIdx)) * cellSize
            NSRect(
                x: box.minX + CGFloat(colIdx) * cellSize,
                y: y,
                width: cellSize,
                height: cellSize
            ).fill()
        }
    }

    NSGraphicsContext.restoreGraphicsState()
    return bitmap.representation(using: .png, properties: [:])!
}

if iconsMode {
    // Apple's required iconset layout: (filename, pixel size).
    let entries: [(String, Int)] = [
        ("icon_16x16.png",       16),
        ("icon_16x16@2x.png",    32),
        ("icon_32x32.png",       32),
        ("icon_32x32@2x.png",    64),
        ("icon_128x128.png",    128),
        ("icon_128x128@2x.png", 256),
        ("icon_256x256.png",    256),
        ("icon_256x256@2x.png", 512),
        ("icon_512x512.png",    512),
        ("icon_512x512@2x.png", 1024),
    ]
    for (filename, size) in entries {
        let data = renderIcon(size: size)
        let url = outputDir.appendingPathComponent(filename)
        try data.write(to: url)
        print("wrote \(url.path) (\(size)px)")
    }
    exit(0)
}

let stages = EvolutionStage.allCases
for stage in stages {
    let sprite = MascotSprite.sprite(for: stage)
    let data = renderSprite(sprite)
    let url = outputDir.appendingPathComponent("\(stage.rawValue).png")
    try data.write(to: url)
    print("wrote \(url.path)")
}

let combined = renderCombined(stages)
let combinedURL = outputDir.appendingPathComponent("evolution.png")
try combined.write(to: combinedURL)
print("wrote \(combinedURL.path)")
