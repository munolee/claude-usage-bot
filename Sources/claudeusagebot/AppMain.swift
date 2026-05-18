import AppKit
import ClaudeUsageCore

@MainActor
private final class AppDelegate: NSObject, NSApplicationDelegate {
    private var overlay: OverlayController!
    private var poller: UsagePoller!
    private var statusItem: NSStatusItem?
    private var isPaused = false

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)

        overlay = OverlayController()
        overlay.onMascotClick = { [weak self] in self?.handleMascotClick() }

        poller = UsagePoller(interval: 30)
        poller.onUpdate = { [weak self] summary in self?.handleSummary(summary) }
        poller.start()

        createStatusItem()
    }

    private func handleSummary(_ summary: UsageSummary) {
        let total = summary.today.totalTokens
        let mood: MascotView.Mood
        switch total {
        case ..<200_000:     mood = .calm
        case ..<1_000_000:   mood = .busy
        default:             mood = .alarmed
        }
        overlay.updateMood(mood)
        rebuildStatusMenu()
    }

    private func handleMascotClick() {
        guard let summary = poller.lastSummary else {
            overlay.showBubble("아직 사용량을 읽고 있어요…")
            return
        }
        overlay.showBubble(bubbleText(for: summary))
    }

    private func bubbleText(for summary: UsageSummary) -> String {
        let today = summary.today
        let total = UsageFormatter.compact(today.totalTokens)
        let cost = UsageFormatter.usd(today.estimatedCostUSD)
        let header = "오늘 \(total) tokens · \(cost)"

        let topModels = summary.perModelToday
            .sorted { $0.value.totalTokens > $1.value.totalTokens }
            .prefix(2)
            .map { (model, totals) in "· \(shortModelName(model)): \(UsageFormatter.compact(totals.totalTokens))" }

        if topModels.isEmpty {
            return "\(header)\n오늘 아직 사용 기록이 없어요."
        }
        return ([header] + topModels).joined(separator: "\n")
    }

    /// "claude-sonnet-4-6" → "Sonnet 4.6"
    private func shortModelName(_ model: String) -> String {
        let lower = model.lowercased()
        let family: String
        if lower.contains("opus") { family = "Opus" }
        else if lower.contains("sonnet") { family = "Sonnet" }
        else if lower.contains("haiku") { family = "Haiku" }
        else { return model }
        // Extract first version-looking chunk (e.g., "4-6" or "4-5")
        let pattern = #/(\d+)-(\d+)/#
        if let match = model.firstMatch(of: pattern) {
            return "\(family) \(match.1).\(match.2)"
        }
        return family
    }

    // MARK: - Status menu

    private func createStatusItem() {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        item.button?.image = Self.makeStatusIcon()
        item.button?.toolTip = "Claude Usage Bot"
        statusItem = item
        rebuildStatusMenu()
    }

    private static func makeStatusIcon() -> NSImage {
        let size = NSSize(width: 18, height: 18)
        let image = NSImage(size: size, flipped: true) { _ in
            NSColor.black.setFill()
            NSBezierPath(ovalIn: NSRect(x: 2, y: 4, width: 14, height: 12)).fill()
            NSColor.white.setFill()
            NSBezierPath(ovalIn: NSRect(x: 6, y: 8, width: 2.5, height: 2.5)).fill()
            NSBezierPath(ovalIn: NSRect(x: 10, y: 8, width: 2.5, height: 2.5)).fill()
            return true
        }
        image.isTemplate = true
        return image
    }

    private func rebuildStatusMenu() {
        guard let statusItem else { return }
        let menu = NSMenu()

        if let summary = poller.lastSummary {
            let header = NSMenuItem(
                title: "오늘 \(UsageFormatter.compact(summary.today.totalTokens)) tokens · \(UsageFormatter.usd(summary.today.estimatedCostUSD))",
                action: nil,
                keyEquivalent: ""
            )
            header.isEnabled = false
            menu.addItem(header)

            let week = NSMenuItem(
                title: "최근 7일 \(UsageFormatter.compact(summary.last7Days.totalTokens)) · \(UsageFormatter.usd(summary.last7Days.estimatedCostUSD))",
                action: nil,
                keyEquivalent: ""
            )
            week.isEnabled = false
            menu.addItem(week)
            menu.addItem(.separator())
        }

        let show = NSMenuItem(title: "지금 보여줘", action: #selector(showNow), keyEquivalent: "s")
        show.target = self
        menu.addItem(show)

        let refresh = NSMenuItem(title: "새로고침", action: #selector(refresh), keyEquivalent: "r")
        refresh.target = self
        menu.addItem(refresh)

        let pause = NSMenuItem(
            title: isPaused ? "보이기" : "숨기기",
            action: #selector(togglePause),
            keyEquivalent: "p"
        )
        pause.target = self
        menu.addItem(pause)

        menu.addItem(.separator())
        let quit = NSMenuItem(title: "Quit", action: #selector(quit), keyEquivalent: "q")
        quit.target = self
        menu.addItem(quit)

        statusItem.menu = menu
    }

    @objc private func showNow() {
        handleMascotClick()
    }

    @objc private func refresh() {
        poller.refreshNow()
    }

    @objc private func togglePause() {
        isPaused.toggle()
        overlay.setHidden(isPaused)
        rebuildStatusMenu()
    }

    @objc private func quit() {
        NSApp.terminate(nil)
    }
}

@main
private enum ClaudeUsageBotMain {
    @MainActor
    static func main() {
        let app = NSApplication.shared
        let delegate = AppDelegate()
        app.delegate = delegate
        app.run()
    }
}
