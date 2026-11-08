import XCTest
@testable import IslandCore

final class RecordCueTests: XCTestCase {
    func testMovingTheNeedleBetweenGroovesCanSeekInEitherDirection() throws {
        for fraction in [0.0, 0.25, 0.75, 1.0] {
            let needle = RecordCue.tip(at: RecordCue.angle(at: fraction))
            XCTAssertEqual(try XCTUnwrap(RecordCue.progress(at: needle)), fraction, accuracy: 0.0001)
        }
    }

    func testDroppingOnTheSupportOrOutsideTheRecordDoesNotSeek() {
        XCTAssertNil(RecordCue.progress(at: RecordCue.tip(at: 0)))
        XCTAssertNil(RecordCue.progress(at: CGPoint(x: 0, y: 0)))
    }
}
