import Foundation

/// Parses Claude Code's `~/.claude/projects/**/*.jsonl` transcript files into UsageRecords.
///
/// Only assistant messages with a `message.usage` block are extracted. Lines without
/// usage data (user messages, meta lines, snapshots, etc.) are skipped.
public enum UsageReader {
    /// Default location Claude Code writes session transcripts to.
    public static var defaultRoot: URL {
        let home = FileManager.default.homeDirectoryForCurrentUser
        return home.appendingPathComponent(".claude/projects", isDirectory: true)
    }

    /// Returns every `*.jsonl` file under the projects root, depth-first.
    public static func transcriptFiles(in root: URL = defaultRoot) -> [URL] {
        let fm = FileManager.default
        guard let enumerator = fm.enumerator(
            at: root,
            includingPropertiesForKeys: [.isRegularFileKey],
            options: [.skipsHiddenFiles]
        ) else {
            return []
        }
        var results: [URL] = []
        for case let url as URL in enumerator where url.pathExtension == "jsonl" {
            results.append(url)
        }
        return results
    }

    /// Streams a single JSONL file and returns every UsageRecord it contains.
    public static func records(in file: URL) throws -> [UsageRecord] {
        let data = try Data(contentsOf: file)
        guard let text = String(data: data, encoding: .utf8) else { return [] }
        return parse(text: text)
    }

    /// Parses raw JSONL text into UsageRecords. Public for testability.
    public static func parse(text: String) -> [UsageRecord] {
        var records: [UsageRecord] = []
        text.enumerateLines { line, _ in
            guard !line.isEmpty,
                  let data = line.data(using: .utf8),
                  let record = parseLine(data) else { return }
            records.append(record)
        }
        return records
    }

    private static func parseLine(_ data: Data) -> UsageRecord? {
        guard let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return nil
        }
        guard (root["type"] as? String) == "assistant",
              let message = root["message"] as? [String: Any],
              let usage = message["usage"] as? [String: Any],
              let messageId = message["id"] as? String,
              let model = message["model"] as? String else {
            return nil
        }
        let timestamp = (root["timestamp"] as? String).flatMap(parseTimestamp) ?? Date()
        return UsageRecord(
            messageId: messageId,
            requestId: root["requestId"] as? String,
            sessionId: root["sessionId"] as? String,
            model: model,
            timestamp: timestamp,
            inputTokens: usage["input_tokens"] as? Int ?? 0,
            outputTokens: usage["output_tokens"] as? Int ?? 0,
            cacheCreationInputTokens: usage["cache_creation_input_tokens"] as? Int ?? 0,
            cacheReadInputTokens: usage["cache_read_input_tokens"] as? Int ?? 0
        )
    }

    private static func parseTimestamp(_ s: String) -> Date? {
        // ISO8601DateFormatter is not Sendable under Swift 6 strict concurrency,
        // so we construct fresh instances here. Parsing happens at most a few thousand
        // times per refresh — cheap enough to skip caching.
        let withFraction = ISO8601DateFormatter()
        withFraction.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let d = withFraction.date(from: s) { return d }
        let plain = ISO8601DateFormatter()
        plain.formatOptions = [.withInternetDateTime]
        return plain.date(from: s)
    }
}
