import XCTest
@testable import Beacons

/// `batteryAdvice(percent:charging:previous:)` and its numbers and sentences
/// (DeviceStatus.swift): the staged suggestion to charge the beacon. Every value is a literal
/// here, so a constant changed in the source fails instead of following itself.
/// TWIN: android BatteryAdviceTest, the same numbers, sentences and table.
final class BatteryAdviceTests: XCTestCase {

    /// The three levels and the re-arm margin. Wrong input: any of them changed on this
    /// phone alone (the drift check holds the pair; this holds the value).
    func testTheLevelsAreTwentyTenAndFiveWithASevenPointMargin() {
        XCTAssertEqual(batteryAdviceLowPercent, 20)
        XCTAssertEqual(batteryAdviceSoonPercent, 10)
        XCTAssertEqual(batteryAdviceNowPercent, 5)
        XCTAssertEqual(batteryAdviceRearmMargin, 7)
        XCTAssertEqual(BatteryAdvice.allCases.map(\.threshold), [20, 10, 5])
    }

    /// Each stage says its own sentence, lowercase-first, with no percent in it. Wrong input:
    /// two stages sharing a sentence, or a reworded one.
    func testEachStageSaysItsSentence() {
        XCTAssertEqual(BatteryAdvice.low.message,
                       "beacon battery is getting low. charge it when you get the chance.")
        XCTAssertEqual(BatteryAdvice.chargeSoon.message,
                       "beacon battery is low. charge it soon, or detection will stop.")
        XCTAssertEqual(BatteryAdvice.chargeNow.message,
                       "beacon battery is almost empty. plug it in now to keep detecting.")
    }

    /// With nothing showing, a reading maps straight to its stage, at or under each level, and
    /// the first frame after a connect can already be in any stage. Wrong inputs: `<` for `<=`
    /// (20 and 10 and 5 fall a stage short); the mildest match taken instead of the most
    /// severe (8 reads as getting low).
    func testAReadingMapsToTheMostSevereStageItIsAtOrUnder() {
        let cases: [(Int?, BatteryAdvice?)] = [
            (nil, nil), (82, nil), (21, nil), (20, .low), (11, .low), (10, .chargeSoon),
            (6, .chargeSoon), (5, .chargeNow), (0, .chargeNow),
        ]
        for (percent, expected) in cases {
            XCTAssertEqual(batteryAdvice(percent: percent, charging: false, previous: nil), expected,
                           "\(String(describing: percent))")
        }
    }

    /// Charging hides the suggestion at any level: the owner is already doing what it asks.
    /// Wrong input: the charging test dropped (a beacon on its charger at 5% still says to
    /// plug it in).
    func testChargingHidesEveryStage() {
        XCTAssertNil(batteryAdvice(percent: 5, charging: true, previous: .chargeNow))
        XCTAssertNil(batteryAdvice(percent: 20, charging: true, previous: nil))
    }

    /// A stage that is showing eases only once the reading is the margin above its level, and
    /// worsens at once: the board's percent climbs a few points when the radios ease off, and
    /// a bare threshold would put the notice up and down. Wrong inputs: the latch dropped (22
    /// after getting-low reads as nothing); a narrower margin (26 after getting-low reads as
    /// nothing); the margin taken from the milder stage (17 after charge-soon still reads
    /// charge-soon); worsening held back by the latch (8 after getting-low stays getting-low).
    func testAShowingStageEasesOnlyPastItsMarginAndWorsensAtOnce() {
        let cases: [(Int, BatteryAdvice, BatteryAdvice?)] = [
            (22, .low, .low), (26, .low, .low), (27, .low, nil), (18, .low, .low),
            (12, .chargeSoon, .chargeSoon), (16, .chargeSoon, .chargeSoon), (17, .chargeSoon, .low),
            (7, .chargeNow, .chargeNow), (11, .chargeNow, .chargeNow), (12, .chargeNow, .low),
            (30, .chargeNow, nil), (8, .low, .chargeSoon), (3, .chargeSoon, .chargeNow),
        ]
        for (percent, previous, expected) in cases {
            XCTAssertEqual(batteryAdvice(percent: percent, charging: false, previous: previous),
                           expected, "\(percent) after \(previous)")
        }
    }

    /// The status frame's "bat" and "chg" are what feed the rule: "chg" is sent only while
    /// true. Wrong input: a renamed key (battery nil, so no stage ever shows).
    func testTheStatusFrameCarriesTheBatteryAndTheChargingFlag() throws {
        let draining = try JSONDecoder().decode(DeviceStatus.self, from: Data(#"{"bat":18}"#.utf8))
        XCTAssertEqual(draining.battery, 18)
        XCTAssertFalse(draining.charging)
        let charging = try JSONDecoder().decode(DeviceStatus.self,
                                                from: Data(#"{"bat":18,"chg":true}"#.utf8))
        XCTAssertEqual(charging.battery, 18)
        XCTAssertTrue(charging.charging)
        XCTAssertEqual(batteryAdvice(percent: draining.battery, charging: draining.charging,
                                     previous: nil), .low)
        XCTAssertNil(batteryAdvice(percent: charging.battery, charging: charging.charging,
                                   previous: .low))
    }
}
