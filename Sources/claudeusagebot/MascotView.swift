import AppKit

/// Small pixel-art Claude mascot — a round head with antenna and friendly eyes.
/// Drawn programmatically; no asset files needed.
final class MascotView: NSView {
    enum Mood { case calm, busy, alarmed }

    var mood: Mood = .calm { didSet { if mood != oldValue { needsDisplay = true } } }
    var blinkPhase: CGFloat = 0 { didSet { needsDisplay = true } }

    var onClick: (() -> Void)?

    override var isFlipped: Bool { true }

    override func draw(_ dirtyRect: NSRect) {
        guard let ctx = NSGraphicsContext.current?.cgContext else { return }
        ctx.setShouldAntialias(true)

        let bodyRect = bounds.insetBy(dx: 4, dy: 4)
        let bodyColor: NSColor
        switch mood {
        case .calm:    bodyColor = NSColor(calibratedRed: 0.85, green: 0.55, blue: 0.32, alpha: 1) // Claude orange-ish
        case .busy:    bodyColor = NSColor(calibratedRed: 0.95, green: 0.75, blue: 0.30, alpha: 1)
        case .alarmed: bodyColor = NSColor(calibratedRed: 0.92, green: 0.35, blue: 0.30, alpha: 1)
        }

        // Soft drop shadow
        ctx.saveGState()
        ctx.setShadow(offset: CGSize(width: 0, height: -2), blur: 6, color: NSColor.black.withAlphaComponent(0.25).cgColor)

        // Body (rounded square)
        let path = NSBezierPath(roundedRect: bodyRect, xRadius: bodyRect.width / 2.6, yRadius: bodyRect.height / 2.6)
        bodyColor.setFill()
        path.fill()
        ctx.restoreGState()

        // Antenna
        NSColor.black.withAlphaComponent(0.6).setStroke()
        let antenna = NSBezierPath()
        antenna.lineWidth = 1.5
        antenna.move(to: NSPoint(x: bounds.midX, y: bodyRect.minY))
        antenna.line(to: NSPoint(x: bounds.midX, y: bodyRect.minY - 6))
        antenna.stroke()
        NSColor.white.setFill()
        let bulb = NSBezierPath(ovalIn: NSRect(x: bounds.midX - 2.5, y: bodyRect.minY - 9, width: 5, height: 5))
        bulb.fill()
        NSColor.black.withAlphaComponent(0.5).setStroke()
        bulb.lineWidth = 0.8
        bulb.stroke()

        // Eyes (blink shrinks the vertical radius)
        let eyeOpen: CGFloat = max(0.15, 1.0 - blinkPhase)
        let eyeW: CGFloat = bodyRect.width * 0.14
        let eyeH: CGFloat = bodyRect.height * 0.18 * eyeOpen
        let eyeY = bodyRect.minY + bodyRect.height * 0.42 - eyeH / 2
        let leftX = bodyRect.minX + bodyRect.width * 0.32 - eyeW / 2
        let rightX = bodyRect.minX + bodyRect.width * 0.68 - eyeW / 2
        NSColor.black.withAlphaComponent(0.85).setFill()
        NSBezierPath(ovalIn: NSRect(x: leftX, y: eyeY, width: eyeW, height: eyeH)).fill()
        NSBezierPath(ovalIn: NSRect(x: rightX, y: eyeY, width: eyeW, height: eyeH)).fill()

        // Mouth — small smile, frown when alarmed
        let mouth = NSBezierPath()
        mouth.lineWidth = 1.5
        NSColor.black.withAlphaComponent(0.7).setStroke()
        let mouthY = bodyRect.minY + bodyRect.height * 0.66
        let mouthW: CGFloat = bodyRect.width * 0.22
        if mood == .alarmed {
            mouth.move(to: NSPoint(x: bounds.midX - mouthW / 2, y: mouthY + 2))
            mouth.curve(to: NSPoint(x: bounds.midX + mouthW / 2, y: mouthY + 2),
                        controlPoint1: NSPoint(x: bounds.midX, y: mouthY - 2),
                        controlPoint2: NSPoint(x: bounds.midX, y: mouthY - 2))
        } else {
            mouth.move(to: NSPoint(x: bounds.midX - mouthW / 2, y: mouthY))
            mouth.curve(to: NSPoint(x: bounds.midX + mouthW / 2, y: mouthY),
                        controlPoint1: NSPoint(x: bounds.midX, y: mouthY + 4),
                        controlPoint2: NSPoint(x: bounds.midX, y: mouthY + 4))
        }
        mouth.stroke()
    }

    override func mouseDown(with event: NSEvent) {
        onClick?()
    }
}
