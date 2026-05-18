import AppKit
import ClaudeUsageCore

@MainActor
private final class AppDelegate: NSObject, NSApplicationDelegate {
    private static let sessionBudgetKey = "sessionBudgetUSD"
    private static let defaultBudgetUSD: Double = 20

    private var overlay: OverlayController!
    private var poller: UsagePoller!
    private var statusItem: NSStatusItem?
    private var isPaused = false
    private var budgetUSD: Double = defaultBudgetUSD

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)

        let saved = UserDefaults.standard.double(forKey: Self.sessionBudgetKey)
        if saved > 0 { budgetUSD = saved }

        overlay = OverlayController()
        overlay.onMascotClick = { [weak self] in self?.handleMascotClick() }

        poller = UsagePoller(interval: 30)
        poller.onUpdate = { [weak self] snapshot in self?.handleSnapshot(snapshot) }
        poller.start()

        createStatusItem()
    }

    private func handleSnapshot(_ snapshot: UsageSnapshot) {
        let mood: MascotView.Mood
        if let session = snapshot.session {
            switch session.usageFraction(budgetUSD: budgetUSD) {
            case ..<0.5:  mood = .calm
            case ..<0.85: mood = .busy
            default:      mood = .alarmed
            }
        } else {
            mood = .calm
        }
        overlay.updateMood(mood)
        rebuildStatusMenu()
    }

    private func handleMascotClick() {
        guard let snapshot = poller.lastSnapshot else {
            overlay.showBubble("…")
            return
        }
        overlay.showBubble(bubbleText(for: snapshot))
    }

    private func bubbleText(for snapshot: UsageSnapshot) -> String {
        guard let session = snapshot.session else {
            return "활성 세션 없음"
        }
        let pct = Int((session.usageFraction(budgetUSD: budgetUSD) * 100).rounded())
        let remainder = session.remaining(from: Date())
        return "\(pct)%  ·  \(formatRemaining(remainder))"
    }

    /// 7320 → "2h 2m", 2700 → "45m", 0 → "0m".
    private func formatRemaining(_ seconds: TimeInterval) -> String {
        let total = max(0, Int(seconds.rounded(.up)))
        let hours = total / 3600
        let minutes = (total % 3600) / 60
        if hours > 0 && minutes > 0 { return "\(hours)h \(minutes)m" }
        if hours > 0 { return "\(hours)h" }
        return "\(minutes)m"
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

        if let session = poller.lastSnapshot?.session {
            let pct = Int((session.usageFraction(budgetUSD: budgetUSD) * 100).rounded())
            let header = NSMenuItem(
                title: "\(pct)% · \(formatRemaining(session.remaining(from: Date())))",
                action: nil,
                keyEquivalent: ""
            )
            header.isEnabled = false
            menu.addItem(header)
            menu.addItem(.separator())
        } else {
            let none = NSMenuItem(title: "활성 세션 없음", action: nil, keyEquivalent: "")
            none.isEnabled = false
            menu.addItem(none)
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

        let resetPos = NSMenuItem(title: "위치 초기화", action: #selector(resetPosition), keyEquivalent: "")
        resetPos.target = self
        menu.addItem(resetPos)

        // Budget submenu
        let budgetItem = NSMenuItem(title: "세션 한도: \(formatBudget())", action: nil, keyEquivalent: "")
        let budgetMenu = NSMenu()
        for choice in [5.0, 10.0, 20.0, 40.0, 100.0] {
            let entry = NSMenuItem(title: "$\(Int(choice))", action: #selector(setBudget(_:)), keyEquivalent: "")
            entry.target = self
            entry.representedObject = choice
            entry.state = abs(choice - budgetUSD) < 0.001 ? .on : .off
            budgetMenu.addItem(entry)
        }
        budgetItem.submenu = budgetMenu
        menu.addItem(budgetItem)

        menu.addItem(.separator())
        let quit = NSMenuItem(title: "Quit", action: #selector(quit), keyEquivalent: "q")
        quit.target = self
        menu.addItem(quit)

        statusItem.menu = menu
    }

    private func formatBudget() -> String {
        budgetUSD == floor(budgetUSD) ? "$\(Int(budgetUSD))" : String(format: "$%.2f", budgetUSD)
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

    @objc private func resetPosition() {
        overlay.resetPosition()
    }

    @objc private func setBudget(_ sender: NSMenuItem) {
        guard let value = sender.representedObject as? Double else { return }
        budgetUSD = value
        UserDefaults.standard.set(value, forKey: Self.sessionBudgetKey)
        if let snapshot = poller.lastSnapshot { handleSnapshot(snapshot) }
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
