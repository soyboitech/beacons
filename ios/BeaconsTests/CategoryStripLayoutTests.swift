import XCTest
@testable import Beacons

/// Pins the CategoryStripLayout wrap rule. Widths are points: a 350pt strip with 6pt gaps has
/// a six-across share of about 53.3pt, and the Status tiles' NETCAM (JetBrains Mono 11pt with
/// 0.8 tracking, R16) is about 44.4pt at the default text size, under that share. The fixture
/// widths below are the rule's inputs, not measurements of a face. The rule is Android's
/// categoryTilesPerRow with iOS geometry;
/// Android twin: CategoryTilesPerRowTest.
final class CategoryStripLayoutTests: XCTestCase {
    private func cols(_ widest: CGFloat, width: CGFloat = 350, preferred: Int = 6,
                      count: Int = 6, spacing: CGFloat = 6) -> Int {
        CategoryStripLayout.columns(widestTile: widest, rowWidth: width, preferred: preferred,
                                    count: count, spacing: spacing)
    }

    func testSixAcrossWhileTheWidestLabelFits() {
        XCTAssertEqual(cols(41), 6)
    }

    func testWrapsToThreeWhenALabelWouldNotFitItsShare() {
        XCTAssertEqual(cols(54), 3, "a label wider than a ~53.3pt share wraps instead of truncating")
    }

    func testASmallerPreferredCountIsKeptWhenItFits() {
        XCTAssertEqual(cols(41, preferred: 4, count: 7, spacing: 8), 4)
        XCTAssertEqual(cols(90, preferred: 4, count: 7, spacing: 8), 3)
    }

    /// A label wider than a three-across share (~112.7pt on a 350pt strip) drops to two. At the
    /// two largest accessibility sizes the old 10pt NETCAM label was that wide, which truncated
    /// it on Status and broke it mid-word on the Log before the two-across step existed.
    func testALabelTooWideForThreeDropsToTwoAndNoFurther() {
        XCTAssertEqual(cols(120), 2)
        XCTAssertEqual(cols(120, preferred: 3, count: 3, spacing: 8), 2, "a three-tile strip too")
        XCTAssertEqual(cols(500), 2, "two is the floor")
        XCTAssertEqual(cols(100, preferred: 3, count: 3, spacing: 8), 3)
    }

    func testOneOrTwoTilesAreNeverRearranged() {
        XCTAssertEqual(cols(500, preferred: 1, count: 1, spacing: 8), 1)
        XCTAssertEqual(cols(500, preferred: 2, count: 2, spacing: 8), 2)
    }
}

/// Pins FoldColumns, the two columns iPhone Duo's inner display splits at the fold (Status and
/// Beacon). The split is in the row's own space; nil means "no fold", the middle.
final class FoldColumnsTests: XCTestCase {
    func testNoFoldSplitsTheRowEvenly() {
        let w = FoldColumns.widths(total: 350, split: nil, gap: 14)
        XCTAssertEqual(w.leading, 168)
        XCTAssertEqual(w.trailing, 168)
    }

    /// The Duo inner display's Status row: 835pt of content, the fold 459.5pt in, a 16pt gutter
    /// on each side of it. The gap straddles the fold, so neither column crosses it.
    func testTheGapIsCentredOnTheFold() {
        let w = FoldColumns.widths(total: 835, split: 459.5, gap: 32)
        XCTAssertEqual(w.leading, 443.5)
        XCTAssertEqual(w.trailing, 359.5)
        XCTAssertEqual(w.leading + 32 + w.trailing, 835)
    }

    func testASplitOutsideTheRowIsClamped() {
        XCTAssertEqual(FoldColumns.widths(total: 300, split: 400, gap: 20).trailing, 0)
        XCTAssertEqual(FoldColumns.widths(total: 300, split: -10, gap: 20).leading, 0)
    }
}

/// Pins `hingeMoved` (Components.swift), the step rule behind `onHingeMove`: the Map takes its
/// camera back when iPhone Duo's hinge starts to move, and must not when a half-open phone
/// merely trembles (a camera set cancels a map gesture in flight).
final class HingeMoveTests: XCTestCase {
    /// Wrong inputs: the threshold dropped (a 1 degree tremor reports a move); the absolute
    /// value dropped (a closing hinge, whose angle falls, never reports); the closed test
    /// dropped (a hinge that closes inside one step goes unreported).
    func testAMoveIsClosingOrLeavingClosedOrAStepOfFiveDegreesEitherWay() {
        XCTAssertEqual(hingeMoveDegrees, 5)
        XCTAssertFalse(hingeMoved(from: 130, to: 131, closedChanged: false))
        XCTAssertFalse(hingeMoved(from: 130, to: 125.5, closedChanged: false))
        XCTAssertTrue(hingeMoved(from: 0, to: 5.9, closedChanged: false))
        XCTAssertTrue(hingeMoved(from: 180, to: 174, closedChanged: false))
        XCTAssertTrue(hingeMoved(from: 3, to: 0, closedChanged: true))
    }

    /// The first reading and a hinge that stops reporting both count; no hinge at all, twice,
    /// does not. Wrong input: nil treated as zero (a phone with no hinge reports a move to 0).
    func testTheFirstReadingAndALostHingeCountAndNoHingeDoesNot() {
        XCTAssertTrue(hingeMoved(from: nil, to: 0, closedChanged: false))
        XCTAssertTrue(hingeMoved(from: 42, to: nil, closedChanged: false))
        XCTAssertFalse(hingeMoved(from: nil, to: nil, closedChanged: false))
    }
}
