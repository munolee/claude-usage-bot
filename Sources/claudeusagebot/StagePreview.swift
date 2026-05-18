import AppKit
import ClaudeUsageCore

/// A small floating window that lays out every `EvolutionStage` side by side so the user
/// can see the whole progression at once. Reusable — `show()` brings the existing window
/// to the front instead of opening a duplicate.
@MainActor
final class StagePreview {
    private var window: NSWindow?

    /// Threshold copy paired with each stage. Keep in sync with EvolutionStage.stage(forFraction:_).
    private static let thresholdLabels: [EvolutionStage: String] = [
        .egg:      "0%",
        .baby:     "0–20%",
        .growth:   "20–50%",
        .mature:   "50–80%",
        .perfect:  "80–100%",
        .ultimate: "≥ 100%"
    ]

    func show() {
        if let window {
            NSApp.activate(ignoringOtherApps: true)
            window.makeKeyAndOrderFront(nil)
            return
        }

        let mascotW: CGFloat = 80
        let mascotH: CGFloat = 60
        let cellW: CGFloat = 110
        let labelArea: CGFloat = 44
        let padding: CGFloat = 24
        let stages = EvolutionStage.allCases

        let contentW = padding * 2 + CGFloat(stages.count) * cellW
        let contentH = padding * 2 + mascotH + labelArea

        let w = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: contentW, height: contentH),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        w.title = "진화 단계 미리보기"
        w.isReleasedWhenClosed = false
        w.center()

        let container = NSView(frame: NSRect(x: 0, y: 0, width: contentW, height: contentH))
        container.wantsLayer = true
        container.layer?.backgroundColor = NSColor.windowBackgroundColor.cgColor
        w.contentView = container

        for (idx, stage) in stages.enumerated() {
            let cellX = padding + CGFloat(idx) * cellW
            let mascotX = cellX + (cellW - mascotW) / 2
            let mascotY = padding + labelArea

            let mascot = MascotView(frame: NSRect(x: mascotX, y: mascotY, width: mascotW, height: mascotH))
            mascot.stage = stage
            container.addSubview(mascot)

            let nameLabel = NSTextField(labelWithString: stage.label)
            nameLabel.alignment = .center
            nameLabel.font = .systemFont(ofSize: 13, weight: .semibold)
            nameLabel.frame = NSRect(x: cellX, y: padding + 22, width: cellW, height: 20)
            container.addSubview(nameLabel)

            let thresholdLabel = NSTextField(labelWithString: Self.thresholdLabels[stage] ?? "")
            thresholdLabel.alignment = .center
            thresholdLabel.font = .systemFont(ofSize: 11)
            thresholdLabel.textColor = .secondaryLabelColor
            thresholdLabel.frame = NSRect(x: cellX, y: padding + 4, width: cellW, height: 18)
            container.addSubview(thresholdLabel)
        }

        NSApp.activate(ignoringOtherApps: true)
        w.makeKeyAndOrderFront(nil)
        window = w
    }
}
