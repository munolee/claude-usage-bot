import Foundation
import ClaudeUsageCore

/// Periodically re-scans `~/.claude/projects/**/*.jsonl` and emits a fresh summary.
///
/// Scanning is done on a background queue so the main run loop stays responsive even when
/// transcripts have grown large. The completion is hopped back to the main actor.
///
/// In parallel, the poller fetches `/api/oauth/usage` on a slower cadence (default 5 min)
/// and stamps the result onto every snapshot until it expires or is replaced. The API call
/// runs through `AnthropicUsageClient` which reads the keychain on each request, so token
/// rotation happens transparently. Failures are silent — the snapshot's `apiUsage` simply
/// stays `nil` (or stale, for transient errors) and consumers fall back to JSONL-based math.
struct UsageSnapshot: Sendable {
    let summary: UsageSummary
    let session: SessionWindow?
    /// Most recent successful API response, if any. May be older than this snapshot's
    /// JSONL scan — the API runs on a much slower cadence than the local refresh.
    let apiUsage: AnthropicUsage?
    /// Status of the last API attempt. Used to show a one-line indicator in the menu.
    let apiStatus: ApiStatus
}

enum ApiStatus: Sendable, Equatable {
    /// Haven't attempted a fetch yet this run.
    case idle
    /// Last fetch succeeded.
    case ok
    /// Backed off after a 429. `until` is when we'll try again.
    case rateLimited(until: Date)
    /// Keychain missing / 401. Stays this way until restart or a manual refresh.
    case unauthenticated
    /// Generic error — network, decoding, etc.
    case error(String)
}

@MainActor
final class UsagePoller {
    private let interval: TimeInterval
    private let apiInterval: TimeInterval
    private let root: URL
    private var timer: Timer?
    private let queue = DispatchQueue(label: "ClaudeUsageBot.UsagePoller", qos: .utility)
    private(set) var lastSnapshot: UsageSnapshot?

    /// Backoff state for the API fetch loop. Lives on the main actor — all mutation
    /// happens from `maybeFetchApiUsage` which is `@MainActor`.
    private var apiClient = AnthropicUsageClient()
    private var lastApiUsage: AnthropicUsage?
    private var apiStatus: ApiStatus = .idle
    private var nextApiAttempt: Date = .distantPast
    /// 5m → 10m → 20m → 40m, capped at 60m, on consecutive 429s.
    private var apiBackoff: TimeInterval

    /// Click-triggered fetches bypass the 5-minute cadence but enforce their own
    /// short debounce so a chatty user can't hammer the endpoint. 20s lines up with
    /// the typical floor we've seen before the server starts replying 429.
    private let clickDebounceInterval: TimeInterval = 20
    private var lastClickFetch: Date = .distantPast

    var onUpdate: ((UsageSnapshot) -> Void)?

    /// API cadence is short enough to keep the displayed utilization close to what
    /// `/usage` reports on demand — the five-hour rolling window can drift by several
    /// percentage points across a couple of minutes of heavy use — but long enough
    /// that we don't pound the endpoint. 429 backoff kicks in if we still get throttled.
    init(interval: TimeInterval = 30, apiInterval: TimeInterval = 90, root: URL = UsageReader.defaultRoot) {
        self.interval = interval
        self.apiInterval = apiInterval
        self.apiBackoff = apiInterval
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

    /// Explicit user action that should *bypass* every gate (debounce, 429 backoff,
    /// stale "unauthenticated" status). Used by the "Claude Code 로그인…" menu entry
    /// where the user just proved we have a working token — we must hit the API
    /// immediately rather than wait for the next scheduled poll.
    func forceApiRefresh() {
        nextApiAttempt = .distantPast
        lastClickFetch = .distantPast
        apiStatus = .idle
        apiBackoff = apiInterval
        refreshNow()
    }

    /// Mascot/menu click entry point. Always rescans JSONL (cheap, local). For the API,
    /// opens the gate so the next refresh cycle hits the endpoint — unless we're inside
    /// a 429 backoff window, or another click already fetched within `clickDebounceInterval`.
    func refreshFromClick() {
        let now = Date()
        let inBackoff: Bool = {
            if case .rateLimited = apiStatus { return true }
            return false
        }()
        if !inBackoff && now.timeIntervalSince(lastClickFetch) >= clickDebounceInterval {
            lastClickFetch = now
            nextApiAttempt = .distantPast
        }
        refreshNow()
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
            Task { @MainActor in
                guard let self else { return }
                await self.maybeFetchApiUsage()
                let snapshot = UsageSnapshot(
                    summary: summary,
                    session: session,
                    apiUsage: self.lastApiUsage,
                    apiStatus: self.apiStatus
                )
                self.lastSnapshot = snapshot
                self.onUpdate?(snapshot)
            }
        }
    }

    /// Fires an API fetch if enough time has passed since the last attempt. The classifier
    /// here is intentionally simple — one in-flight request at a time, status updates after
    /// it returns. We don't try to refresh more aggressively than `apiInterval` even on
    /// success: the endpoint is rate-limited and the values only meaningfully change every
    /// few minutes anyway.
    private func maybeFetchApiUsage() async {
        let now = Date()
        guard now >= nextApiAttempt else { return }
        nextApiAttempt = now.addingTimeInterval(apiInterval)

        do {
            let usage = try await apiClient.fetch()
            lastApiUsage = usage
            apiStatus = .ok
            apiBackoff = apiInterval  // reset on success
        } catch let AnthropicUsageError.rateLimited(retryAfter) {
            apiBackoff = min(apiBackoff * 2, 3600)
            let wait = retryAfter ?? apiBackoff
            let until = Date().addingTimeInterval(wait)
            nextApiAttempt = until
            apiStatus = .rateLimited(until: until)
        } catch AnthropicUsageError.authenticationFailed,
                AnthropicUsageError.tokenUnavailable {
            apiStatus = .unauthenticated
            // Try again on the normal cadence — a Claude Code re-login may fix this.
        } catch let AnthropicUsageError.server(code) {
            apiStatus = .error("HTTP \(code)")
        } catch let AnthropicUsageError.network(msg) {
            apiStatus = .error("네트워크: \(msg)")
        } catch let AnthropicUsageError.decoding(msg) {
            apiStatus = .error("응답 파싱: \(msg)")
        } catch {
            apiStatus = .error(String(describing: error))
        }
    }
}
