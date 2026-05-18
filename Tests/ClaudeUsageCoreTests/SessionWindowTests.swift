import XCTest
@testable import ClaudeUsageCore

final class SessionWindowTests: XCTestCase {
    private let model = "claude-sonnet-4-6" // priced model

    func testNoRecordsReturnsNil() {
        XCTAssertNil(SessionDetector.currentSession(records: [], now: parse("2026-05-18T12:00:00Z")))
    }

    func testFirstMessageStartsSessionAndDefinesExpiry() {
        let start = parse("2026-05-18T09:00:00Z")
        let records = [record(at: start, input: 100)]
        let session = SessionDetector.currentSession(
            records: records,
            now: parse("2026-05-18T10:00:00Z")
        )
        XCTAssertEqual(session?.startedAt, start)
        XCTAssertEqual(session?.expiresAt, start.addingTimeInterval(5 * 3600))
        XCTAssertEqual(session?.messageCount, 1)
    }

    func testMessagesWithinFiveHoursStayInSameSession() {
        let start = parse("2026-05-18T09:00:00Z")
        let records = [
            record(at: start, input: 100),
            record(at: parse("2026-05-18T10:30:00Z"), input: 200),
            record(at: parse("2026-05-18T13:30:00Z"), input: 300)
        ]
        let session = SessionDetector.currentSession(
            records: records,
            now: parse("2026-05-18T13:45:00Z")
        )
        XCTAssertEqual(session?.startedAt, start)
        XCTAssertEqual(session?.messageCount, 3)
        XCTAssertEqual(session?.tokens, 600)
    }

    func testMessageAfterExpiryStartsNewSession() {
        let first = parse("2026-05-18T09:00:00Z")
        let afterExpiry = parse("2026-05-18T15:00:00Z") // 6h later → expired
        let records = [
            record(at: first, input: 100),
            record(at: afterExpiry, input: 50)
        ]
        let session = SessionDetector.currentSession(
            records: records,
            now: parse("2026-05-18T15:30:00Z")
        )
        XCTAssertEqual(session?.startedAt, afterExpiry)
        XCTAssertEqual(session?.messageCount, 1)
    }

    func testExpiredSessionReturnsNil() {
        let start = parse("2026-05-18T09:00:00Z")
        let records = [record(at: start, input: 100)]
        // now is past expiry
        XCTAssertNil(SessionDetector.currentSession(
            records: records,
            now: parse("2026-05-18T15:00:00Z")
        ))
    }

    func testRemainingTimeAndFractionMath() throws {
        let start = parse("2026-05-18T09:00:00Z")
        let now = parse("2026-05-18T11:30:00Z")
        // 1M input tokens at sonnet ($3/Mtok input) = $3 cost.
        let records = [record(at: start, input: 1_000_000)]
        let session = try XCTUnwrap(
            SessionDetector.currentSession(records: records, now: now)
        )
        XCTAssertEqual(session.remaining(from: now), 2.5 * 3600, accuracy: 0.001)
        XCTAssertEqual(session.usageFraction(budgetUSD: 20), 0.15, accuracy: 0.001)
    }

    func testDedupesByMessageId() {
        let start = parse("2026-05-18T09:00:00Z")
        let r = record(at: start, input: 100, messageId: "dup")
        let session = SessionDetector.currentSession(
            records: [r, r, r],
            now: parse("2026-05-18T10:00:00Z")
        )
        XCTAssertEqual(session?.messageCount, 1)
        XCTAssertEqual(session?.tokens, 100)
    }

    // MARK: - helpers

    private func record(at date: Date, input: Int, messageId: String = UUID().uuidString) -> UsageRecord {
        UsageRecord(
            messageId: messageId,
            requestId: nil,
            sessionId: nil,
            model: model,
            timestamp: date,
            inputTokens: input,
            outputTokens: 0,
            cacheCreationInputTokens: 0,
            cacheReadInputTokens: 0
        )
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
