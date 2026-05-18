import AppKit

/// Pixel-art mascot. Drawn from a string grid with anti-aliasing off so cells stay crisp.
/// Click vs. drag is disambiguated by total mouse travel; the parent controller moves the panel.
final class MascotView: NSView {
    enum Mood { case calm, busy, alarmed }

    var mood: Mood = .calm { didSet { if mood != oldValue { needsDisplay = true } } }
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

    // X = body, o = eye, . = transparent.
    // 14 columns × 9 rows. Flat-topped body with side bumps mid-row, two cream eyes,
    // four short leg stubs hanging from the bottom.
    private static let sprite: [String] = [
        "...XXXXXXXX...",
        ".XXXXXXXXXXXX.",
        "XXXXXXXXXXXXXX",
        "XXXooXXXXooXXX",
        "XXXooXXXXooXXX",
        "XXXXXXXXXXXXXX",
        "XXXXXXXXXXXXXX",
        "..X.X....X.X..",
        "..X.X....X.X.."
    ]
    private static var cols: Int { sprite[0].count }
    private static var rows: Int { sprite.count }

    override func draw(_ dirtyRect: NSRect) {
        guard let ctx = NSGraphicsContext.current?.cgContext else { return }
        ctx.setShouldAntialias(false)
        ctx.interpolationQuality = .none

        let bodyColor: NSColor
        switch mood {
        case .calm:    bodyColor = NSColor(calibratedRed: 0.85, green: 0.48, blue: 0.36, alpha: 1) // salmon-orange
        case .busy:    bodyColor = NSColor(calibratedRed: 0.91, green: 0.60, blue: 0.27, alpha: 1) // warm amber
        case .alarmed: bodyColor = NSColor(calibratedRed: 0.79, green: 0.32, blue: 0.29, alpha: 1) // muted red
        }
        let eyeColor = NSColor(calibratedRed: 0.97, green: 0.87, blue: 0.78, alpha: 1)

        // Eyes close on blink — fall back to body color so the cells "fill in".
        let eyesOpen = blinkPhase < 0.5
        let activeEyeColor = eyesOpen ? eyeColor : bodyColor

        let cell = floor(min(bounds.width / CGFloat(Self.cols), bounds.height / CGFloat(Self.rows)))
        guard cell > 0 else { return }
        let drawW = cell * CGFloat(Self.cols)
        let drawH = cell * CGFloat(Self.rows)
        // Center horizontally; pin to bottom so the legs sit on the panel's bottom edge.
        let originX = floor((bounds.width - drawW) / 2)
        let originY = floor(bounds.height - drawH)

        for (rowIdx, row) in Self.sprite.enumerated() {
            for (colIdx, ch) in row.enumerated() {
                let color: NSColor?
                switch ch {
                case "X": color = bodyColor
                case "o": color = activeEyeColor
                default:  color = nil
                }
                guard let color else { continue }
                color.setFill()
                let rect = NSRect(
                    x: originX + CGFloat(colIdx) * cell,
                    y: originY + CGFloat(rowIdx) * cell,
                    width: cell,
                    height: cell
                )
                rect.fill()
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
