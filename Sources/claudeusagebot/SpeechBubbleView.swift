import AppKit

/// Rounded speech bubble with a downward tail, drawn left of / above the mascot.
/// Multi-line text is supported. Sizes itself via `preferredSize(for:maxWidth:)`.
final class SpeechBubbleView: NSView {
    enum TailSide { case right, left }

    var text: String = "" { didSet { needsDisplay = true } }
    var tailSide: TailSide = .right { didSet { needsDisplay = true } }

    static let cornerRadius: CGFloat = 10
    static let padding = NSEdgeInsets(top: 8, left: 12, bottom: 10, right: 12)
    static let tailHeight: CGFloat = 8
    static let tailWidth: CGFloat = 10

    override var isFlipped: Bool { true }

    static func preferredSize(for text: String, maxWidth: CGFloat) -> NSSize {
        let attr = NSAttributedString(string: text, attributes: Self.textAttributes)
        let bounding = attr.boundingRect(
            with: NSSize(width: maxWidth - padding.left - padding.right, height: .greatestFiniteMagnitude),
            options: [.usesLineFragmentOrigin, .usesFontLeading]
        )
        let width = ceil(bounding.width) + padding.left + padding.right
        let height = ceil(bounding.height) + padding.top + padding.bottom + tailHeight
        return NSSize(width: width, height: height)
    }

    private static let textAttributes: [NSAttributedString.Key: Any] = {
        let paragraph = NSMutableParagraphStyle()
        paragraph.lineSpacing = 2
        return [
            .font: NSFont.systemFont(ofSize: 12, weight: .semibold),
            .foregroundColor: NSColor.white,
            .paragraphStyle: paragraph
        ]
    }()

    override func draw(_ dirtyRect: NSRect) {
        guard let ctx = NSGraphicsContext.current?.cgContext else { return }
        ctx.setShouldAntialias(true)

        let bubbleRect = NSRect(
            x: 0,
            y: 0,
            width: bounds.width,
            height: bounds.height - Self.tailHeight
        )
        let path = NSBezierPath(roundedRect: bubbleRect, xRadius: Self.cornerRadius, yRadius: Self.cornerRadius)

        // Tail
        let tailY = bubbleRect.maxY
        let tailCenterX: CGFloat
        switch tailSide {
        case .right: tailCenterX = bubbleRect.maxX - Self.cornerRadius - Self.tailWidth
        case .left:  tailCenterX = bubbleRect.minX + Self.cornerRadius + Self.tailWidth
        }
        path.move(to: NSPoint(x: tailCenterX - Self.tailWidth / 2, y: tailY))
        path.line(to: NSPoint(x: tailCenterX, y: tailY + Self.tailHeight))
        path.line(to: NSPoint(x: tailCenterX + Self.tailWidth / 2, y: tailY))
        path.close()

        // Fill + soft drop shadow
        ctx.saveGState()
        ctx.setShadow(offset: CGSize(width: 0, height: -1), blur: 4, color: NSColor.black.withAlphaComponent(0.35).cgColor)
        NSColor(calibratedWhite: 0.08, alpha: 0.95).setFill()
        path.fill()
        ctx.restoreGState()

        // Hairline border for definition against dark backgrounds
        NSColor.white.withAlphaComponent(0.08).setStroke()
        path.lineWidth = 0.5
        path.stroke()

        // Text
        let textRect = NSRect(
            x: Self.padding.left,
            y: Self.padding.top,
            width: bubbleRect.width - Self.padding.left - Self.padding.right,
            height: bubbleRect.height - Self.padding.top - Self.padding.bottom
        )
        let attr = NSAttributedString(string: text, attributes: Self.textAttributes)
        attr.draw(with: textRect, options: [.usesLineFragmentOrigin, .usesFontLeading])
    }

    /// Pass-through clicks (we want the mascot beneath to handle them).
    override func hitTest(_ point: NSPoint) -> NSView? { nil }
}
