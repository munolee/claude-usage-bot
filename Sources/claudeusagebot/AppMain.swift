import AppKit
import ClaudeUsageCore

@MainActor
private final class AppDelegate: NSObject, NSApplicationDelegate {
    private static let sessionBudgetKey = "sessionBudgetUSD"
    private static let resetExpiresOverrideKey = "resetExpiresOverride"
    private static let defaultBudgetUSD: Double = 100
    private static let budgetChoices: [Double] = [20, 50, 100, 200, 500, 1000]

    private var overlay: OverlayController!
    private var poller: UsagePoller!
    private var stagePreview = StagePreview()
    private var statusItem: NSStatusItem?
    private var isPaused = false
    private var budgetUSD: Double = defaultBudgetUSD
    /// Absolute Date when the user said the session resets. Overrides the auto-detected
    /// session.expiresAt for display. Auto-cleared once the time passes.
    private var resetExpiresOverride: Date?

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)

        let defaults = UserDefaults.standard
        let saved = defaults.double(forKey: Self.sessionBudgetKey)
        if saved > 0 { budgetUSD = saved }
        if let overrideTS = defaults.object(forKey: Self.resetExpiresOverrideKey) as? TimeInterval {
            let date = Date(timeIntervalSince1970: overrideTS)
            if date > Date() {
                resetExpiresOverride = date
            } else {
                defaults.removeObject(forKey: Self.resetExpiresOverrideKey)
            }
        }

        overlay = OverlayController()
        overlay.onMascotClick = { [weak self] in self?.poller.refreshFromClick() }
        overlay.menuProvider = { [weak self] in self?.buildMenu() }
        // Placeholder until the first snapshot lands.
        overlay.showBubble("…", autoHideAfter: nil)

        poller = UsagePoller(interval: 30)
        poller.onUpdate = { [weak self] snapshot in self?.handleSnapshot(snapshot) }
        poller.start()

        createStatusItem()
    }

    private func handleSnapshot(_ snapshot: UsageSnapshot) {
        let view = effectiveView(for: snapshot)
        let stage = EvolutionStage.stage(
            forFraction: view.fraction,
            hasActiveSession: view.hasActiveUsage
        )
        overlay.updateStage(stage)
        // Bubble is always visible — every refresh just updates its text in place.
        overlay.showBubble(bubbleText(for: view), autoHideAfter: nil)
        rebuildStatusMenu()
    }

    /// Resolved view-model for a snapshot. Prefers the Anthropic API response when
    /// available so the bubble matches Claude Code's `/usage` exactly; falls back to
    /// JSONL-derived cost ÷ budget math.
    private struct DisplayView {
        let fraction: Double
        let percentInt: Int
        let remaining: TimeInterval?
        let hasActiveUsage: Bool
        let source: Source

        enum Source { case api, jsonl, none }
    }

    private func effectiveView(for snapshot: UsageSnapshot) -> DisplayView {
        if let api = snapshot.apiUsage {
            let pct = api.fiveHour.utilization
            let remaining = api.fiveHour.remaining()
            return DisplayView(
                fraction: pct / 100,
                percentInt: Int(pct.rounded()),
                remaining: remaining,
                hasActiveUsage: pct > 0 || (remaining ?? 0) > 0,
                source: .api
            )
        }
        if let session = snapshot.session {
            let fraction = session.usageFraction(budgetUSD: budgetUSD)
            return DisplayView(
                fraction: fraction,
                percentInt: Int((fraction * 100).rounded()),
                remaining: displayedRemaining(for: session),
                hasActiveUsage: true,
                source: .jsonl
            )
        }
        return DisplayView(fraction: 0, percentInt: 0, remaining: nil, hasActiveUsage: false, source: .none)
    }

    private func bubbleText(for view: DisplayView) -> String {
        switch view.source {
        case .none:
            return "활성 세션 없음"
        case .api, .jsonl:
            guard let remaining = view.remaining else {
                return "\(view.percentInt)%"
            }
            return "\(view.percentInt)%  ·  \(formatRemaining(remaining))"
        }
    }

    /// Returns the remaining time we should display. Honors a manual override if it's
    /// still in the future, otherwise falls back to the session's auto-detected expiry.
    /// Auto-clears stale overrides.
    private func displayedRemaining(for session: SessionWindow) -> TimeInterval {
        let now = Date()
        if let override = resetExpiresOverride {
            if override > now { return override.timeIntervalSince(now) }
            resetExpiresOverride = nil
            UserDefaults.standard.removeObject(forKey: Self.resetExpiresOverrideKey)
        }
        return session.remaining(from: now)
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

        let snapshot = poller.lastSnapshot
        let view = snapshot.map(effectiveView(for:))

        if let view, view.hasActiveUsage {
            let stage = EvolutionStage.stage(forFraction: view.fraction, hasActiveSession: true)
            let remainingStr = view.remaining.map { " · \(formatRemaining($0))" } ?? ""
            let header = NSMenuItem(
                title: "\(stage.label) · \(view.percentInt)%\(remainingStr)",
                action: nil,
                keyEquivalent: ""
            )
            header.isEnabled = false
            menu.addItem(header)
        } else {
            let none = NSMenuItem(title: "\(EvolutionStage.egg.label) · 활성 세션 없음", action: nil, keyEquivalent: "")
            none.isEnabled = false
            menu.addItem(none)
        }

        if let snapshot {
            let line = NSMenuItem(title: apiStatusLine(snapshot: snapshot, source: view?.source), action: nil, keyEquivalent: "")
            line.isEnabled = false
            menu.addItem(line)
        }
        menu.addItem(.separator())

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
        // Calibration only makes sense for the JSONL fallback — when we have the API
        // response, the numbers are already authoritative.
        let usingApi = view?.source == .api
        calibrate.isEnabled = !usingApi && (poller.lastSnapshot?.session?.usageUSD ?? 0) > 0
        if usingApi {
            calibrate.title = "Claude Code 값에 맞춰 보정 (API 사용 중, 불필요)"
        }
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

    /// Human-readable summary of the API fetch state. Tells the user at a glance whether
    /// the numbers above are from Anthropic's API (accurate) or our JSONL estimate (approx).
    private func apiStatusLine(snapshot: UsageSnapshot, source: DisplayView.Source?) -> String {
        if source == .api, let api = snapshot.apiUsage {
            let ago = Int(Date().timeIntervalSince(api.fetchedAt))
            let agoStr = ago < 60 ? "\(max(0, ago))s 전" : "\(ago / 60)m 전"
            return "데이터: Anthropic API (\(agoStr))"
        }
        switch snapshot.apiStatus {
        case .idle:
            return "데이터: JSONL 추정 (API 응답 대기)"
        case .ok:
            return "데이터: JSONL 추정"
        case .rateLimited(let until):
            let wait = max(0, Int(until.timeIntervalSinceNow))
            return "데이터: JSONL 추정 (API 재시도 \(wait / 60)m \(wait % 60)s 후)"
        case .unauthenticated:
            return "데이터: JSONL 추정 (Claude Code 로그인 필요)"
        case .error(let msg):
            return "데이터: JSONL 추정 (API 오류: \(msg))"
        }
    }

    @objc private func refresh() {
        poller.refreshFromClick()
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
        alert.informativeText = "지금 Claude Code의 /usage 에 보이는 사용률과 남은 시간을 입력하세요. 둘 다 선택사항이며, 입력한 항목만 보정됩니다."

        // Stacked accessory view: percent field on top, remaining-time field below.
        let container = NSView(frame: NSRect(x: 0, y: 0, width: 260, height: 70))
        let pctLabel = NSTextField(labelWithString: "사용률 (%)")
        pctLabel.frame = NSRect(x: 0, y: 44, width: 80, height: 18)
        pctLabel.font = .systemFont(ofSize: 11)
        container.addSubview(pctLabel)
        let pctInput = NSTextField(frame: NSRect(x: 90, y: 42, width: 160, height: 22))
        pctInput.placeholderString = "예: 30"
        container.addSubview(pctInput)

        let timeLabel = NSTextField(labelWithString: "남은 시간")
        timeLabel.frame = NSRect(x: 0, y: 8, width: 80, height: 18)
        timeLabel.font = .systemFont(ofSize: 11)
        container.addSubview(timeLabel)
        let timeInput = NSTextField(frame: NSRect(x: 90, y: 6, width: 160, height: 22))
        timeInput.placeholderString = "예: 2h 30m, 또는 2:30"
        container.addSubview(timeInput)

        alert.accessoryView = container
        alert.addButton(withTitle: "보정")
        alert.addButton(withTitle: "취소")
        NSApp.activate(ignoringOtherApps: true)
        pctInput.becomeFirstResponder()

        guard alert.runModal() == .alertFirstButtonReturn else { return }

        // Percent (optional)
        let rawPct = pctInput.stringValue.trimmingCharacters(in: .whitespaces).replacingOccurrences(of: "%", with: "")
        if let pct = Double(rawPct), pct > 0 {
            let newBudget = session.usageUSD / (pct / 100)
            budgetUSD = newBudget
            UserDefaults.standard.set(newBudget, forKey: Self.sessionBudgetKey)
        }

        // Remaining time (optional)
        let rawTime = timeInput.stringValue.trimmingCharacters(in: .whitespaces)
        if let seconds = parseDuration(rawTime), seconds > 0 {
            let expires = Date().addingTimeInterval(seconds)
            resetExpiresOverride = expires
            UserDefaults.standard.set(expires.timeIntervalSince1970, forKey: Self.resetExpiresOverrideKey)
        }

        if let snapshot = poller.lastSnapshot { handleSnapshot(snapshot) }
    }

    /// Parses "2h 30m", "2:30", "1h", "45m", "150" (minutes) into seconds. Returns nil on failure.
    private func parseDuration(_ raw: String) -> TimeInterval? {
        guard !raw.isEmpty else { return nil }
        // "2:30" form
        if raw.contains(":") {
            let parts = raw.split(separator: ":")
            guard parts.count == 2,
                  let h = Int(parts[0].trimmingCharacters(in: .whitespaces)),
                  let m = Int(parts[1].trimmingCharacters(in: .whitespaces)) else { return nil }
            return TimeInterval(h * 3600 + m * 60)
        }
        // "2h 30m" / "2h" / "30m" form
        var total: TimeInterval = 0
        var matched = false
        let scanner = Scanner(string: raw.lowercased())
        scanner.charactersToBeSkipped = .whitespaces
        while !scanner.isAtEnd {
            guard let n = scanner.scanInt() else { break }
            if scanner.scanString("h") != nil {
                total += TimeInterval(n * 3600)
                matched = true
            } else if scanner.scanString("m") != nil {
                total += TimeInterval(n * 60)
                matched = true
            } else if scanner.isAtEnd {
                // Bare number → assume minutes
                total += TimeInterval(n * 60)
                matched = true
            } else {
                return nil
            }
        }
        return matched ? total : nil
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
