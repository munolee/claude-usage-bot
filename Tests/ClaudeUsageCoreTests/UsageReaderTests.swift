import XCTest
@testable import ClaudeUsageCore

final class UsageReaderTests: XCTestCase {
    func testSkipsNonAssistantLines() {
        let lines = [
            #"{"type":"permission-mode","permissionMode":"auto","sessionId":"s1"}"#,
            #"{"type":"file-history-snapshot","messageId":"m1"}"#,
            #"{"type":"user","message":{"role":"user","content":"hi"}}"#
        ].joined(separator: "\n")
        XCTAssertEqual(UsageReader.parse(text: lines).count, 0)
    }

    func testParsesAssistantUsage() {
        let line = """
        {"type":"assistant","timestamp":"2026-01-29T09:18:09.141Z","sessionId":"s1","requestId":"req_1","message":{"id":"msg_1","model":"claude-haiku-4-5-20251001","usage":{"input_tokens":3,"cache_creation_input_tokens":3020,"cache_read_input_tokens":10117,"output_tokens":2}}}
        """
        let records = UsageReader.parse(text: line)
        XCTAssertEqual(records.count, 1)
        let r = records[0]
        XCTAssertEqual(r.messageId, "msg_1")
        XCTAssertEqual(r.requestId, "req_1")
        XCTAssertEqual(r.sessionId, "s1")
        XCTAssertEqual(r.model, "claude-haiku-4-5-20251001")
        XCTAssertEqual(r.inputTokens, 3)
        XCTAssertEqual(r.outputTokens, 2)
        XCTAssertEqual(r.cacheCreationInputTokens, 3020)
        XCTAssertEqual(r.cacheReadInputTokens, 10117)
        XCTAssertEqual(r.totalTokens, 13142)
    }

    func testDedupesByMessageId() {
        let line = """
        {"type":"assistant","timestamp":"2026-05-18T00:00:00.000Z","message":{"id":"dup","model":"claude-sonnet-4-6","usage":{"input_tokens":10,"output_tokens":20,"cache_creation_input_tokens":0,"cache_read_input_tokens":0}}}
        """
        let records = UsageReader.parse(text: [line, line, line].joined(separator: "\n"))
        XCTAssertEqual(records.count, 3, "parser returns each line; dedup happens in aggregator")
        let summary = UsageAggregator.summarize(records: records, now: parse("2026-05-18T12:00:00Z"))
        XCTAssertEqual(summary.today.messageCount, 1)
        XCTAssertEqual(summary.today.inputTokens, 10)
        XCTAssertEqual(summary.today.outputTokens, 20)
    }

    func testPricingAppliedForKnownModels() throws {
        // sonnet: $3/M input, $15/M output → 1M input + 1M output = $18
        let r = UsageRecord(
            messageId: "x", requestId: nil, sessionId: nil,
            model: "claude-sonnet-4-6",
            timestamp: parse("2026-05-18T10:00:00Z"),
            inputTokens: 1_000_000, outputTokens: 1_000_000,
            cacheCreationInputTokens: 0, cacheReadInputTokens: 0
        )
        let cost = try XCTUnwrap(Pricing.cost(of: r))
        XCTAssertEqual(cost, 18, accuracy: 0.001)
        XCTAssertNil(Pricing.cost(of: UsageRecord(
            messageId: "y", requestId: nil, sessionId: nil,
            model: "unknown-model",
            timestamp: parse("2026-05-18T10:00:00Z"),
            inputTokens: 1, outputTokens: 1,
            cacheCreationInputTokens: 0, cacheReadInputTokens: 0
        )))
    }

    func testTodayBoundaryRespectsCalendar() {
        let yesterday = parse("2026-05-17T23:00:00Z")
        let today = parse("2026-05-18T01:00:00Z")
        let records = [
            UsageRecord(messageId: "a", requestId: nil, sessionId: nil,
                        model: "claude-sonnet-4-6", timestamp: yesterday,
                        inputTokens: 100, outputTokens: 0,
                        cacheCreationInputTokens: 0, cacheReadInputTokens: 0),
            UsageRecord(messageId: "b", requestId: nil, sessionId: nil,
                        model: "claude-sonnet-4-6", timestamp: today,
                        inputTokens: 50, outputTokens: 0,
                        cacheCreationInputTokens: 0, cacheReadInputTokens: 0)
        ]
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: "UTC")!
        let s = UsageAggregator.summarize(records: records, now: parse("2026-05-18T12:00:00Z"), calendar: cal)
        XCTAssertEqual(s.today.inputTokens, 50)
        XCTAssertEqual(s.last7Days.inputTokens, 150)
        XCTAssertEqual(s.allTime.inputTokens, 150)
    }

    func testCompactFormatting() {
        XCTAssertEqual(UsageFormatter.compact(0), "0")
        XCTAssertEqual(UsageFormatter.compact(999), "999")
        XCTAssertEqual(UsageFormatter.compact(1500), "1.5K")
        XCTAssertEqual(UsageFormatter.compact(1_234_567), "1.2M")
    }

    private func parse(_ s: String) -> Date {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f.date(from: s) ?? {
            let g = ISO8601DateFormatter()
            g.formatOptions = [.withInternetDateTime]
            return g.date(from: s)!
        }()
    }
}
