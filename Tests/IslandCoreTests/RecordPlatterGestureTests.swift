import XCTest
@testable import IslandCore

final class RecordPlatterGestureTests: XCTestCase {
    func testHorizontalPanLocksToSwipe() {
        var classifier = RecordPlatterClassifier()
        classifier.addScroll(dx: -20, dy: 2, fromCenter: CGPoint(x: 40, y: 10), radius: 200)
        XCTAssertEqual(classifier.mode, .swipe)
        classifier.reset()
        classifier.addScroll(dx: 28, dy: -4, fromCenter: CGPoint(x: -60, y: 30), radius: 220)
        XCTAssertEqual(classifier.mode, .swipe)
    }

    func testTangentialRubLocksToSpin() {
        var classifier = RecordPlatterClassifier()
        // Vertical motion on the right side of the disc produces torque with little horizontal pan.
        classifier.addScroll(dx: 1, dy: -24, fromCenter: CGPoint(x: 90, y: 0), radius: 200)
        XCTAssertEqual(classifier.mode, .spin)
        XCTAssertNotEqual(classifier.spinDegrees, 0, accuracy: 0.0001)
    }

    func testNativeRotationLocksToSpin() {
        var classifier = RecordPlatterClassifier()
        classifier.addRotation(4)
        XCTAssertEqual(classifier.mode, .spin)
    }
}
