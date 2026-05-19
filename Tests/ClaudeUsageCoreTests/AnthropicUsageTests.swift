import XCTest
@testable import ClaudeUsageCore

final class AnthropicUsageTests: XCTestCase {
    func testDecodesFullResponse() throws {
        // Captured verbatim from a real `/api/oauth/usage` 200 response, with the
        // user's identifying fields removed.
        let json = """
        {
          "five_hour": {"utilization": 41.0, "resets_at": "2026-05-18T11:50:00.232793+00:00"},
          "seven_day": {"utilization": 15.0, "resets_at": "2026-05-24T00:00:00.000000+00:00"},
          "seven_day_sonnet": {"utilization": 0.0, "resets_at": "2026-05-24T00:00:00.000000+00:00"},
          "seven_day_opus": null,
          "extra_usage": {"is_enabled": false, "max_extra_usage": 0, "current_extra_usage": 0}
        }
        """
        let usage = try AnthropicUsage.decode(Data(json.utf8))

        XCTAssertEqual(usage.fiveHour.utilization, 41.0, accuracy: 0.0001)
        XCTAssertNotNil(usage.fiveHour.resetsAt)
        XCTAssertEqual(usage.sevenDay?.utilization, 15.0)
        XCTAssertEqual(usage.sevenDaySonnet?.utilization, 0.0)
        XCTAssertNil(usage.sevenDayOpus)
    }

    func testHandlesNullableSevenDayWindows() throws {
        let json = """
        {
          "five_hour": {"utilization": 7.5, "resets_at": "2026-05-18T11:50:00Z"},
          "seven_day": null,
          "seven_day_sonnet": null,
          "seven_day_opus": null
        }
        """
        let usage = try AnthropicUsage.decode(Data(json.utf8))
        XCTAssertEqual(usage.fiveHour.utilization, 7.5, accuracy: 0.0001)
        XCTAssertNil(usage.sevenDay)
        XCTAssertNil(usage.sevenDayOpus)
        XCTAssertNil(usage.sevenDaySonnet)
    }

    func testRemainingClampsToZeroForPastResets() {
        let past = Date().addingTimeInterval(-60)
        let win = AnthropicUsageWindow(utilization: 50, resetsAt: past)
        XCTAssertEqual(win.remaining(from: Date())!, 0, accuracy: 0.5)
    }

    func testRemainingComputesPositiveInterval() {
        let future = Date().addingTimeInterval(900)
        let win = AnthropicUsageWindow(utilization: 50, resetsAt: future)
        let remaining = win.remaining(from: Date())!
        XCTAssertGreaterThan(remaining, 800)
        XCTAssertLessThan(remaining, 1000)
    }

    func testFetchedAtIsStamped() throws {
        let json = """
        {"five_hour": {"utilization": 1.0, "resets_at": "2026-05-18T11:50:00Z"}}
        """
        let stamp = Date(timeIntervalSince1970: 1_700_000_000)
        let usage = try AnthropicUsage.decode(Data(json.utf8), fetchedAt: stamp)
        XCTAssertEqual(usage.fetchedAt, stamp)
    }
}
