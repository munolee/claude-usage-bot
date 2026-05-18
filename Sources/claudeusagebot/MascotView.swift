import AppKit
import ClaudeUsageCore

/// Pixel-art mascot that swaps sprites based on `stage`. All sprites share a 16×12 cell
/// canvas (smaller forms simply use less of it). Rendered with anti-aliasing off so the
/// pixel grid stays crisp.
final class MascotView: NSView {
    var stage: EvolutionStage = .egg { didSet { if stage != oldValue { needsDisplay = true } } }
    var blinkPhase: CGFloat = 0 { didSet { needsDisplay = true } }

    var onClick: (() -> Void)?
    var onDrag: ((NSPoint) -> Void)?
    var onDragEnd: (() -> Void)?
    /// Returns the menu to show on right-click / control-click. AppKit calls this
    /// automatically for every "show context menu" gesture, so we don't need to
    /// implement rightMouseDown ourselves.
    var menuProvider: (() -> NSMenu?)?

    override func menu(for event: NSEvent) -> NSMenu? {
        menuProvider?()
    }

    private var dragLastScreenLocation: NSPoint?
    private var dragAccumulated: CGFloat = 0
    private static let clickVsDragThreshold: CGFloat = 4

    override var isFlipped: Bool { true }

    static let canvasCols = 16
    static let canvasRows = 12

    // Cell legend:
    //   .  transparent
    //   X  body orange
    //   o  eye cream (also doubles as speckle on orange forms)
    //   W  eggshell cream-white (egg only)
    //   s  orange speckle on the egg (same color as body X)
    // Each row is exactly 16 chars, and every sprite has exactly 12 rows so layout cells
    // line up across stages.
    private static let sprites: [EvolutionStage: [String]] = [
        .egg: [
            "................",
            "......WWWW......",
            ".....WWWWWW.....",
            "....WWWWWssW....", // 2-cell speckle, upper right
            "....WWssWWsW....", // 2x2 blob (left, row 1) + L tail (right)
            "....WWssWWWW....", // 2x2 blob (left, row 2)
            "....WWWWWWWW....",
            "....ssWWWWWW....", // 2x2 blob anchored to the left edge, row 1
            "....ssWWWssW....", // 2x2 blob row 2 + 2x2 blob (right, row 1)
            "....WWWWWssW....", // 2x2 blob (right, row 2)
            ".....WWWWWW.....",
            "......WWWW......"
        ],
        .baby: [
            "................",
            "................",
            "................",
            "................",
            ".....XXXXXX.....",
            "....XXXXXXXX....",
            "....XooXXooX....",
            "....XooXXooX....",
            "....XXXXXXXX....",
            ".....XXXXXX.....",
            "......X..X......",
            "......X..X......"
        ],
        .growth: [
            "................",
            "................",
            "................",
            "....XXXXXXXX....",
            "..XXXXXXXXXXXX..",
            ".XXXXXXXXXXXXXX.",
            ".XXXooXXXXooXXX.",
            ".XXXooXXXXooXXX.",
            ".XXXXXXXXXXXXXX.",
            ".XXXXXXXXXXXXXX.",
            "...X.X....X.X...",
            "...X.X....X.X..."
        ],
        .mature: [
            "................",
            ".X............X.",
            ".X............X.",
            "....XXXXXXXX....",
            "..XXXXXXXXXXXX..",
            ".XXXXXXXXXXXXXX.",
            ".XXXooXXXXooXXX.",
            ".XXXooXXXXooXXX.",
            ".XXXXXXXXXXXXXX.",
            ".XXXXXXXXXXXXXX.",
            "...X.X....X.X...",
            "...X.X....X.X..."
        ],
        .perfect: [
            "................",
            "................",
            "..XXXXXXXXXXXX..",
            "..XXoXXXXXXoXX..",
            "..XXoXXXXXXoXX..",
            "..XXXXXXXXXXXX..",
            "XXXXXXXXXXXXXXXX",
            "XXXXXXXXXXXXXXXX",
            "..XXXXXXXXXXXX..",
            "..X.X......X.X..",
            "..X.X......X.X..",
            "................"
        ],
        .ultimate: [
            ".X.X........X.X.",
            ".X.X........X.X.",
            "XXXXX......XXXXX",
            "XXXXXX....XXXXXX",
            "XXXXXXX..XXXXXXX",
            "XXXXXXXXXXXXXXXX",
            "XXXXooXXXXooXXXX",
            "XXXXooXXXXooXXXX",
            "XXXXXXXXXXXXXXXX",
            "XXXXXXXXXXXXXXXX",
            ".X.X.X....X.X.X.",
            ".X.X.X....X.X.X."
        ]
    ]

    override func draw(_ dirtyRect: NSRect) {
        guard let ctx = NSGraphicsContext.current?.cgContext else { return }
        ctx.setShouldAntialias(false)
        ctx.interpolationQuality = .none

        let bodyColor = NSColor(calibratedRed: 0.85, green: 0.48, blue: 0.36, alpha: 1) // salmon-orange
        let eyeColor = NSColor(calibratedRed: 0.97, green: 0.87, blue: 0.78, alpha: 1) // cream
        let eggshell = NSColor(calibratedRed: 0.97, green: 0.94, blue: 0.88, alpha: 1) // warm off-white

        // Blink only when the sprite actually has eyes (eggs don't).
        let eyesOpen = blinkPhase < 0.5
        let activeEyeColor = eyesOpen ? eyeColor : bodyColor

        let cell = floor(min(
            bounds.width / CGFloat(Self.canvasCols),
            bounds.height / CGFloat(Self.canvasRows)
        ))
        guard cell > 0 else { return }
        let drawW = cell * CGFloat(Self.canvasCols)
        let drawH = cell * CGFloat(Self.canvasRows)
        let originX = floor((bounds.width - drawW) / 2)
        let originY = floor(bounds.height - drawH)

        let sprite = Self.sprites[stage] ?? Self.sprites[.egg]!
        for (rowIdx, row) in sprite.enumerated() {
            for (colIdx, ch) in row.enumerated() {
                let color: NSColor?
                switch ch {
                case "X": color = bodyColor
                case "o": color = activeEyeColor
                case "W": color = eggshell
                case "s": color = bodyColor
                default:  color = nil
                }
                guard let color else { continue }
                color.setFill()
                NSRect(
                    x: originX + CGFloat(colIdx) * cell,
                    y: originY + CGFloat(rowIdx) * cell,
                    width: cell,
                    height: cell
                ).fill()
            }
        }
    }

    // MARK: - Mouse handling

    override func mouseDown(with event: NSEvent) {
        dragLastScreenLocation = NSEvent.mouseLocation
        dragAccumulated = 0
    }

    override func mouseDragged(with event: NSEvent) {
        guard let last = dragLastScreenLocation else { return }
        let current = NSEvent.mouseLocation
        let delta = NSPoint(x: current.x - last.x, y: current.y - last.y)
        dragLastScreenLocation = current
        dragAccumulated += hypot(delta.x, delta.y)
        if dragAccumulated >= Self.clickVsDragThreshold {
            onDrag?(delta)
        }
    }

    override func mouseUp(with event: NSEvent) {
        let wasDrag = dragAccumulated >= Self.clickVsDragThreshold
        dragLastScreenLocation = nil
        dragAccumulated = 0
        if wasDrag {
            onDragEnd?()
        } else {
            onClick?()
        }
    }
}
