import AppKit
import ClaudeUsageCore

// Standalone renderer that exports each evolution-stage sprite as a PNG. The same
// MascotSprite data the live app uses is consumed here — only the drawing layer differs.
//
// Usage:
//   swift run spriterender                 → writes to ./docs/stages/
//   swift run spriterender path/to/output  → writes to the supplied directory

let outputPath: String = {
    if CommandLine.arguments.count > 1 {
        return CommandLine.arguments[1]
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
