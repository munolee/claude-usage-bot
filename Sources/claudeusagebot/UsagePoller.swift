import Foundation
import ClaudeUsageCore

/// Periodically re-scans `~/.claude/projects/**/*.jsonl` and emits a fresh summary.
///
/// Scanning is done on a background queue so the main run loop stays responsive even when
/// transcripts have grown large. The completion is hopped back to the main actor.
struct UsageSnapshot: Sendable {
    let summary: UsageSummary
    let session: SessionWindow?
}

@MainActor
final class UsagePoller {
    private let interval: TimeInterval
    private let root: URL
    private var timer: Timer?
    private let queue = DispatchQueue(label: "ClaudeUsageBot.UsagePoller", qos: .utility)
    private(set) var lastSnapshot: UsageSnapshot?

    var onUpdate: ((UsageSnapshot) -> Void)?

    init(interval: TimeInterval = 30, root: URL = UsageReader.defaultRoot) {
        self.interval = interval
        self.root = root
    }

    func start() {
        refreshNow()
        let t = Timer(timeInterval: interval, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.refreshNow() }
        }
        RunLoop.main.add(t, forMode: .common)
        self.timer = t
    }

    func stop() {
        timer?.invalidate()
        timer = nil
    }

    func refreshNow() {
        let root = self.root
        queue.async { [weak self] in
            let files = UsageReader.transcriptFiles(in: root)
            var allRecords: [UsageRecord] = []
            allRecords.reserveCapacity(files.count * 32)
            for file in files {
                if let recs = try? UsageReader.records(in: file) {
                    allRecords.append(contentsOf: recs)
                }
            }
            let summary = UsageAggregator.summarize(records: allRecords)
            let session = SessionDetector.currentSession(records: allRecords)
            let snapshot = UsageSnapshot(summary: summary, session: session)
            Task { @MainActor in
                self?.lastSnapshot = snapshot
                self?.onUpdate?(snapshot)
            }
        }
    }
}
