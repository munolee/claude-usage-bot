import AppKit
import ClaudeUsageCore

/// Owns the borderless panel that floats the mascot + speech bubble above other windows.
/// The mascot has a fixed screen anchor (its bottom-left); the user drags to move it,
/// and the position persists across launches. The bubble grows above the mascot when
/// shown without nudging the mascot.
@MainActor
final class OverlayController {
    private static let anchorXKey = "mascotAnchorX"
    private static let anchorYKey = "mascotAnchorY"

    // Mascot sprite is 14 cols × 9 rows. Cell size 5pt → 70×45pt frame.
    private let mascotWidth: CGFloat = 70
    private let mascotHeight: CGFloat = 45
    private let maxBubbleWidth: CGFloat = 240
    private let defaultMargin: CGFloat = 24
    private let mascotBubbleGap: CGFloat = 6
    private let screenEdgePadding: CGFloat = 4

    private let panel: NSPanel
    private let mascot: MascotView
    private let bubble: SpeechBubbleView
    private var bubbleHideWorkItem: DispatchWorkItem?
    private var blinkTimer: Timer?

    /// Mascot's bottom-left in screen coordinates. Source of truth for layout.
    private var mascotAnchor: NSPoint

    var onMascotClick: (() -> Void)?

    init() {
        let initialRect = NSRect(x: 0, y: 0, width: 280, height: 200)
        panel = NSPanel(
            contentRect: initialRect,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.backgroundColor = .clear
        panel.isOpaque = false
        panel.hasShadow = false
        panel.hidesOnDeactivate = false
        panel.ignoresMouseEvents = false
        panel.level = NSWindow.Level(rawValue: Int(CGWindowLevelForKey(.screenSaverWindow)))
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .ignoresCycle, .stationary]
        panel.titleVisibility = .hidden
        panel.animationBehavior = .none

        let container = NSView(frame: initialRect)
        container.wantsLayer = true
        panel.contentView = container

        bubble = SpeechBubbleView(frame: .zero)
        bubble.isHidden = true
        container.addSubview(bubble)

        mascot = MascotView(frame: NSRect(x: 0, y: 0, width: mascotWidth, height: mascotHeight))
        container.addSubview(mascot)

        mascotAnchor = Self.loadAnchor() ?? Self.defaultAnchor(mascotWidth: mascotWidth, margin: defaultMargin)

        mascot.onClick = { [weak self] in self?.onMascotClick?() }
        mascot.onDrag = { [weak self] delta in self?.moveAnchor(by: delta) }
        mascot.onDragEnd = { [weak self] in self?.persistAnchor() }

        startBlinking()
        relayout()
        panel.orderFrontRegardless()
    }

    func updateMood(_ mood: MascotView.Mood) {
        mascot.mood = mood
    }

    /// Show the bubble for `seconds`; pass nil to keep it visible.
    func showBubble(_ text: String, autoHideAfter seconds: TimeInterval? = 6) {
        bubble.text = text
        bubble.isHidden = false
        relayout()
        bubbleHideWorkItem?.cancel()
        guard let seconds else { return }
        let work = DispatchWorkItem { [weak self] in self?.hideBubble() }
        bubbleHideWorkItem = work
        DispatchQueue.main.asyncAfter(deadline: .now() + seconds, execute: work)
    }

    func hideBubble() {
        bubble.isHidden = true
        bubbleHideWorkItem?.cancel()
        bubbleHideWorkItem = nil
        relayout()
    }

    func setHidden(_ hidden: Bool) {
        if hidden { panel.orderOut(nil) } else { panel.orderFrontRegardless() }
    }

    /// Move the mascot back to the bottom-right default and forget the saved position.
    func resetPosition() {
        mascotAnchor = Self.defaultAnchor(mascotWidth: mascotWidth, margin: defaultMargin)
        UserDefaults.standard.removeObject(forKey: Self.anchorXKey)
        UserDefaults.standard.removeObject(forKey: Self.anchorYKey)
        relayout()
    }

    // MARK: - Drag

    private func moveAnchor(by delta: NSPoint) {
        mascotAnchor = NSPoint(x: mascotAnchor.x + delta.x, y: mascotAnchor.y + delta.y)
        clampAnchorToVisibleScreens()
        relayout()
    }

    private func persistAnchor() {
        let defaults = UserDefaults.standard
        defaults.set(Double(mascotAnchor.x), forKey: Self.anchorXKey)
        defaults.set(Double(mascotAnchor.y), forKey: Self.anchorYKey)
    }

    private func clampAnchorToVisibleScreens() {
        // Allow the mascot anywhere across the union of visible frames, but keep it
        // fully on-screen on whatever display it intersects.
        guard let screen = screenContaining(mascotCenter()) ?? NSScreen.main else { return }
        let v = screen.visibleFrame
        let minX = v.minX + screenEdgePadding
        let maxX = v.maxX - mascotWidth - screenEdgePadding
        let minY = v.minY + screenEdgePadding
        let maxY = v.maxY - mascotHeight - screenEdgePadding
        mascotAnchor.x = min(max(mascotAnchor.x, minX), maxX)
        mascotAnchor.y = min(max(mascotAnchor.y, minY), maxY)
    }

    private func mascotCenter() -> NSPoint {
        NSPoint(x: mascotAnchor.x + mascotWidth / 2, y: mascotAnchor.y + mascotHeight / 2)
    }

    private func screenContaining(_ point: NSPoint) -> NSScreen? {
        NSScreen.screens.first(where: { $0.frame.contains(point) })
    }

    // MARK: - Layout

    /// Recomputes panel frame and subview positions from `mascotAnchor` + bubble visibility.
    /// The mascot stays anchored — the panel grows upward (and possibly sideways) to fit the bubble.
    private func relayout() {
        let bubbleSize: NSSize
        if bubble.isHidden || bubble.text.isEmpty {
            bubbleSize = .zero
        } else {
            bubbleSize = SpeechBubbleView.preferredSize(for: bubble.text, maxWidth: maxBubbleWidth)
        }

        // Decide tail side: if mascot sits on the right half of its screen, bubble extends left
        // with its tail on the right (and vice versa). Keeps the bubble on-screen near edges.
        let screen = screenContaining(mascotCenter()) ?? NSScreen.main
        let visible = screen?.visibleFrame ?? .zero
        let mascotMidX = mascotAnchor.x + mascotWidth / 2
        let preferLeftExtension = mascotMidX > visible.midX
        let tailSide: SpeechBubbleView.TailSide = preferLeftExtension ? .right : .left

        // Panel horizontal extent must cover both the mascot and the bubble.
        let panelMinX: CGFloat
        let panelWidth: CGFloat
        if bubbleSize.width > 0 {
            if preferLeftExtension {
                // Bubble's right edge aligned with mascot's right edge.
                let bubbleMinX = mascotAnchor.x + mascotWidth - bubbleSize.width
                panelMinX = min(mascotAnchor.x, bubbleMinX)
                panelWidth = (mascotAnchor.x + mascotWidth) - panelMinX
            } else {
                // Bubble's left edge aligned with mascot's left edge.
                let bubbleMaxX = mascotAnchor.x + bubbleSize.width
                panelMinX = mascotAnchor.x
                panelWidth = max(mascotWidth, bubbleMaxX - panelMinX)
            }
        } else {
            panelMinX = mascotAnchor.x
            panelWidth = mascotWidth
        }

        let panelMinY = mascotAnchor.y
        let panelHeight = mascotHeight + (bubbleSize.height > 0 ? bubbleSize.height + mascotBubbleGap : 0)

        panel.setFrame(NSRect(x: panelMinX, y: panelMinY, width: panelWidth, height: panelHeight), display: true)

        // Place mascot at its anchor (converted to panel-local coords).
        let mascotLocalX = mascotAnchor.x - panelMinX
        mascot.frame = NSRect(x: mascotLocalX, y: 0, width: mascotWidth, height: mascotHeight)

        if bubbleSize.width > 0 {
            let bubbleLocalX: CGFloat
            if preferLeftExtension {
                bubbleLocalX = (mascotAnchor.x + mascotWidth - bubbleSize.width) - panelMinX
            } else {
                bubbleLocalX = mascotAnchor.x - panelMinX
            }
            let bubbleLocalY = mascot.frame.maxY + mascotBubbleGap
            bubble.frame = NSRect(x: bubbleLocalX, y: bubbleLocalY, width: bubbleSize.width, height: bubbleSize.height)
            bubble.tailSide = tailSide
        }
    }

    // MARK: - Anchor defaults / persistence

    private static func defaultAnchor(mascotWidth: CGFloat, margin: CGFloat) -> NSPoint {
        guard let screen = NSScreen.main ?? NSScreen.screens.first else {
            return NSPoint(x: margin, y: margin)
        }
        let v = screen.visibleFrame
        return NSPoint(x: v.maxX - mascotWidth - margin, y: v.minY + margin)
    }

    private static func loadAnchor() -> NSPoint? {
        let d = UserDefaults.standard
        guard d.object(forKey: anchorXKey) != nil, d.object(forKey: anchorYKey) != nil else {
            return nil
        }
        let point = NSPoint(x: d.double(forKey: anchorXKey), y: d.double(forKey: anchorYKey))
        // Sanity check: must intersect *some* visible screen, otherwise fall back to default.
        let rect = NSRect(x: point.x, y: point.y, width: 1, height: 1)
        guard NSScreen.screens.contains(where: { $0.visibleFrame.intersects(rect) }) else {
            return nil
        }
        return point
    }

    // MARK: - Blink

    private func startBlinking() {
        let t = Timer(timeInterval: 0.05, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.advanceBlink() }
        }
        RunLoop.main.add(t, forMode: .common)
        self.blinkTimer = t
    }

    private var blinkCountdown: TimeInterval = Double.random(in: 2...5)
    private var blinkProgress: TimeInterval = 0

    private func advanceBlink() {
        let dt = 0.05
        if blinkProgress > 0 {
            blinkProgress += dt
            if blinkProgress >= 0.18 {
                blinkProgress = 0
                mascot.blinkPhase = 0
            } else {
                let half = 0.09
                let phase = blinkProgress < half ? blinkProgress / half : (0.18 - blinkProgress) / half
                mascot.blinkPhase = CGFloat(phase)
            }
        } else {
            blinkCountdown -= dt
            if blinkCountdown <= 0 {
                blinkCountdown = Double.random(in: 3...6)
                blinkProgress = 0.001
            }
        }
    }
}
