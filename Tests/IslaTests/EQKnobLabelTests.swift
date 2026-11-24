import XCTest
@testable import Isla

final class EQKnobLabelTests: XCTestCase {
    func testLabelShowsSignedWholeDecibels() {
        XCTAssertEqual(EQKnob.label(3), "+3 dB")
        XCTAssertEqual(EQKnob.label(-4.4), "-4 dB")
        XCTAssertEqual(EQKnob.label(0), "0 dB")
        XCTAssertEqual(EQKnob.label(nil), "—")
    }
}
