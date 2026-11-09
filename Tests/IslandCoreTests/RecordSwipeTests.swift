import XCTest
@testable import IslandCore

final class RecordSwipeTests: XCTestCase {
    func testHorizontalSwipeSelectsTheTrackInItsDirection() {
        XCTAssertEqual(RecordSwipe(translation: CGSize(width: -82, height: 14), diameter: 500), .next)
        XCTAssertEqual(RecordSwipe(translation: CGSize(width: 82, height: -14), diameter: 500), .previous)
    }

    func testShortVerticalAndDiagonalDragsDoNotSkip() {
        XCTAssertNil(RecordSwipe(translation: CGSize(width: 30, height: 0), diameter: 200))
        XCTAssertNil(RecordSwipe(translation: CGSize(width: 50, height: 0), diameter: 500))
        XCTAssertNil(RecordSwipe(translation: CGSize(width: 65, height: 100), diameter: 200))
        XCTAssertNil(RecordSwipe(translation: CGSize(width: 70, height: 55), diameter: 200))
    }
}
