import XCTest
@testable import ClaudeUsageCore

final class EvolutionStageTests: XCTestCase {
    func testNoSessionIsEgg() {
        XCTAssertEqual(EvolutionStage.stage(forFraction: 0.0, hasActiveSession: false), .egg)
        XCTAssertEqual(EvolutionStage.stage(forFraction: 0.5, hasActiveSession: false), .egg)
        XCTAssertEqual(EvolutionStage.stage(forFraction: 2.0, hasActiveSession: false), .egg)
    }

    func testZeroFractionWithActiveSessionIsEgg() {
        XCTAssertEqual(EvolutionStage.stage(forFraction: 0.0, hasActiveSession: true), .egg)
    }

    func testThresholds() {
        // Just-over-zero → baby
        XCTAssertEqual(EvolutionStage.stage(forFraction: 0.0001, hasActiveSession: true), .baby)
        XCTAssertEqual(EvolutionStage.stage(forFraction: 0.19,    hasActiveSession: true), .baby)
        // 20% → growth (closed-open intervals; 0.20 itself is growth)
        XCTAssertEqual(EvolutionStage.stage(forFraction: 0.20,    hasActiveSession: true), .growth)
        XCTAssertEqual(EvolutionStage.stage(forFraction: 0.49,    hasActiveSession: true), .growth)
        // 50% → mature
        XCTAssertEqual(EvolutionStage.stage(forFraction: 0.50,    hasActiveSession: true), .mature)
        XCTAssertEqual(EvolutionStage.stage(forFraction: 0.79,    hasActiveSession: true), .mature)
        // 80% → perfect
        XCTAssertEqual(EvolutionStage.stage(forFraction: 0.80,    hasActiveSession: true), .perfect)
        XCTAssertEqual(EvolutionStage.stage(forFraction: 0.99,    hasActiveSession: true), .perfect)
        // 100% and over → ultimate
        XCTAssertEqual(EvolutionStage.stage(forFraction: 1.00,    hasActiveSession: true), .ultimate)
        XCTAssertEqual(EvolutionStage.stage(forFraction: 5.00,    hasActiveSession: true), .ultimate)
    }

    func testLabelsArePopulatedForEveryCase() {
        for stage in EvolutionStage.allCases {
            XCTAssertFalse(stage.label.isEmpty, "missing label for \(stage)")
        }
    }
}
