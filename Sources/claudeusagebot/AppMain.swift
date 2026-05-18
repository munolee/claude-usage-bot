import AppKit
import ClaudeUsageCore

@MainActor
private final class AppDelegate: NSObject, NSApplicationDelegate {
    private static let sessionBudgetKey = "sessionBudgetUSD"
    private static let defaultBudgetUSD: Double = 100
    private static let budgetChoices: [Double] = [20, 50, 100, 200, 500, 1000]

    private var overlay: OverlayController!
    private var poller: UsagePoller!
    private var stagePreview = StagePreview()
    private var statusItem: NSStatusItem?
    private var isPaused = false
    private var budgetUSD: Double = defaultBudgetUSD

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)

        let saved = UserDefaults.standard.double(forKey: Self.sessionBudgetKey)
        if saved > 0 { budgetUSD = saved }

        overlay = OverlayController()
        overlay.onMascotClick = { [weak self] in self?.poller.refreshNow() }
        overlay.menuProvider = { [weak self] in self?.buildMenu() }
        // Placeholder until the first snapshot lands.
        overlay.showBubble("…", autoHideAfter: nil)

        poller = UsagePoller(interval: 30)
        poller.onUpdate = { [weak self] snapshot in self?.handleSnapshot(snapshot) }
        poller.start()

        createStatusItem()
    }

    private func handleSnapshot(_ snapshot: UsageSnapshot) {
        let fraction = snapshot.session?.usageFraction(budgetUSD: budgetUSD) ?? 0
        let stage = EvolutionStage.stage(
            forFraction: fraction,
            hasActiveSession: snapshot.session != nil
        )
        overlay.updateStage(stage)
        // Bubble is always visible — every refresh just updates its text in place.
        overlay.showBubble(bubbleText(for: snapshot), autoHideAfter: nil)
        rebuildStatusMenu()
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
        statusItem?.menu = buildMenu()
    }

    /// The single source of truth for the app's menu. Shared by the status item and
    /// the right-click / control-click context menu on the mascot.
    fileprivate func buildMenu() -> NSMenu {
        let menu = NSMenu()

        if let session = poller.lastSnapshot?.session {
            let fraction = session.usageFraction(budgetUSD: budgetUSD)
            let pct = Int((fraction * 100).rounded())
            let stage = EvolutionStage.stage(forFraction: fraction, hasActiveSession: true)
            let header = NSMenuItem(
                title: "\(stage.label) · \(pct)% · \(formatRemaining(session.remaining(from: Date())))",
                action: nil,
                keyEquivalent: ""
            )
            header.isEnabled = false
            menu.addItem(header)
            menu.addItem(.separator())
        } else {
            let none = NSMenuItem(title: "\(EvolutionStage.egg.label) · 활성 세션 없음", action: nil, keyEquivalent: "")
            none.isEnabled = false
            menu.addItem(none)
            menu.addItem(.separator())
        }

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

        let previewStages = NSMenuItem(title: "전체 모습 보기", action: #selector(showAllStages), keyEquivalent: "")
        previewStages.target = self
        menu.addItem(previewStages)

        let calibrate = NSMenuItem(
            title: "Claude Code 값에 맞춰 보정…",
            action: #selector(calibrateBudget),
            keyEquivalent: ""
        )
        calibrate.target = self
        calibrate.isEnabled = (poller.lastSnapshot?.session?.usageUSD ?? 0) > 0
        menu.addItem(calibrate)

        // Budget submenu
        let budgetItem = NSMenuItem(title: "세션 한도: \(formatBudget())", action: nil, keyEquivalent: "")
        let budgetMenu = NSMenu()
        for choice in Self.budgetChoices {
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

        return menu
    }

    private func formatBudget() -> String {
        budgetUSD == floor(budgetUSD) ? "$\(Int(budgetUSD))" : String(format: "$%.2f", budgetUSD)
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

    @objc private func showAllStages() {
        stagePreview.show()
    }

    /// One-shot calibration: user enters the % they see in Claude Code's /usage and we
    /// back-solve the budget so future displays match. budget = currentCost / (pct/100).
    @objc private func calibrateBudget() {
        guard let session = poller.lastSnapshot?.session, session.usageUSD > 0 else {
            let alert = NSAlert()
            alert.messageText = "보정할 사용량이 없어요"
            alert.informativeText = "활성 세션에 가격 정보가 있는 모델 메시지가 한 건 이상 있어야 보정이 가능합니다."
            alert.runModal()
            return
        }

        let alert = NSAlert()
        alert.messageText = "Claude Code 값에 맞춰 보정"
        alert.informativeText = "지금 Claude Code의 /usage 가 보여주는 사용률(%)을 입력하세요. 이 값에 맞도록 세션 한도가 자동 계산됩니다."
        let input = NSTextField(frame: NSRect(x: 0, y: 0, width: 220, height: 24))
        input.placeholderString = "예: 30"
        alert.accessoryView = input
        alert.addButton(withTitle: "보정")
        alert.addButton(withTitle: "취소")
        NSApp.activate(ignoringOtherApps: true)
        input.becomeFirstResponder()

        guard alert.runModal() == .alertFirstButtonReturn else { return }
        let raw = input.stringValue.trimmingCharacters(in: .whitespaces).replacingOccurrences(of: "%", with: "")
        guard let pct = Double(raw), pct > 0 else { return }

        let newBudget = session.usageUSD / (pct / 100)
        budgetUSD = newBudget
        UserDefaults.standard.set(newBudget, forKey: Self.sessionBudgetKey)
        if let snapshot = poller.lastSnapshot { handleSnapshot(snapshot) }
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
