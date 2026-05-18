import AppKit
import ClaudeUsageCore

/// Owns the borderless panel that floats the mascot + speech bubble above other windows.
/// Anchors itself to the bottom-right of the active screen.
@MainActor
final class OverlayController {
    private let mascotSize: CGFloat = 56
    private let maxBubbleWidth: CGFloat = 240
    private let margin: CGFloat = 24
    private let mascotBubbleGap: CGFloat = 6

    private let panel: NSPanel
    private let mascot: MascotView
    private let bubble: SpeechBubbleView
    private var bubbleHideWorkItem: DispatchWorkItem?
    private var blinkTimer: Timer?

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

        mascot = MascotView(frame: NSRect(x: 0, y: 0, width: mascotSize, height: mascotSize))
        container.addSubview(mascot)

        mascot.onClick = { [weak self] in self?.onMascotClick?() }

        startBlinking()
        layoutAtBottomRight()
        panel.orderFrontRegardless()
    }

    func updateMood(_ mood: MascotView.Mood) {
        mascot.mood = mood
    }

    /// Show the bubble for `seconds`; pass nil to keep it visible.
    func showBubble(_ text: String, autoHideAfter seconds: TimeInterval? = 6) {
        bubble.text = text
        bubble.isHidden = false
        layoutAtBottomRight()
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
        layoutAtBottomRight()
    }

    // MARK: - Layout

    private func layoutAtBottomRight() {
        guard let screen = NSScreen.main ?? NSScreen.screens.first else { return }
        let visible = screen.visibleFrame

        let bubbleSize: NSSize
        if bubble.isHidden || bubble.text.isEmpty {
            bubbleSize = .zero
        } else {
            bubbleSize = SpeechBubbleView.preferredSize(for: bubble.text, maxWidth: maxBubbleWidth)
        }

        let contentWidth = max(mascotSize, bubbleSize.width)
        let contentHeight = mascotSize + (bubbleSize.height > 0 ? bubbleSize.height + mascotBubbleGap : 0)

        let originX = visible.maxX - contentWidth - margin
        let originY = visible.minY + margin
        panel.setFrame(NSRect(x: originX, y: originY, width: contentWidth, height: contentHeight), display: true)

        guard let container = panel.contentView else { return }
        // Container coords are non-flipped here. Stack bubble above mascot.
        let mascotX = container.bounds.maxX - mascotSize
        let mascotY = container.bounds.minY
        mascot.frame = NSRect(x: mascotX, y: mascotY, width: mascotSize, height: mascotSize)

        if bubbleSize.width > 0 {
            // Anchor the tail to the mascot's top edge.
            let bubbleX = container.bounds.maxX - bubbleSize.width
            let bubbleY = mascot.frame.maxY + mascotBubbleGap
            bubble.frame = NSRect(x: bubbleX, y: bubbleY, width: bubbleSize.width, height: bubbleSize.height)
            bubble.tailSide = .right
        }
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

    func setHidden(_ hidden: Bool) {
        if hidden { panel.orderOut(nil) } else { panel.orderFrontRegardless() }
    }
}
