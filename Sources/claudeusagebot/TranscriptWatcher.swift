import Foundation
import CoreServices

/// Watches `~/.claude/projects` recursively for file-system changes. Coalesces bursts
/// into a single `onActivity` callback so a streaming assistant turn doesn't fire dozens
/// of times — one fire per quiet period.
@MainActor
final class TranscriptWatcher {
    private let root: URL
    private let debounce: TimeInterval
    private var stream: FSEventStreamRef?
    private var debounceTask: DispatchWorkItem?

    var onActivity: (() -> Void)?

    init(root: URL, debounce: TimeInterval = 0.6) {
        self.root = root
        self.debounce = debounce
    }

    func start() {
        guard stream == nil else { return }
        guard FileManager.default.fileExists(atPath: root.path) else { return }

        var context = FSEventStreamContext(
            version: 0,
            info: Unmanaged.passUnretained(self).toOpaque(),
            retain: nil,
            release: nil,
            copyDescription: nil
        )

        let callback: FSEventStreamCallback = { _, info, _, _, _, _ in
            guard let info else { return }
            let watcher = Unmanaged<TranscriptWatcher>.fromOpaque(info).takeUnretainedValue()
            Task { @MainActor in watcher.scheduleFire() }
        }

        let paths = [root.path] as CFArray
        let flags = UInt32(kFSEventStreamCreateFlagFileEvents | kFSEventStreamCreateFlagNoDefer)
        guard let s = FSEventStreamCreate(
            kCFAllocatorDefault,
            callback,
            &context,
            paths,
            FSEventStreamEventId(kFSEventStreamEventIdSinceNow),
            0.3, // coalesce latency at the FSEvents layer
            flags
        ) else { return }

        FSEventStreamSetDispatchQueue(s, DispatchQueue.main)
        FSEventStreamStart(s)
        stream = s
    }

    func stop() {
        debounceTask?.cancel()
        debounceTask = nil
        if let s = stream {
            FSEventStreamStop(s)
            FSEventStreamInvalidate(s)
            FSEventStreamRelease(s)
            stream = nil
        }
    }

    // No deinit cleanup — stream lifetime matches the app, and Swift 6's nonisolated
    // deinit can't touch the MainActor-isolated `stream` property anyway. Callers call
    // `stop()` explicitly on app termination if needed.

    private func scheduleFire() {
        debounceTask?.cancel()
        let task = DispatchWorkItem { [weak self] in
            self?.debounceTask = nil
            self?.onActivity?()
        }
        debounceTask = task
        DispatchQueue.main.asyncAfter(deadline: .now() + debounce, execute: task)
    }
}
