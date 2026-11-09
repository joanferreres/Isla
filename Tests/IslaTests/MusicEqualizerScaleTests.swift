import XCTest
@testable import Isla

final class MusicEqualizerScaleTests: XCTestCase {
    func testNativeHundredthsAreConvertedToDecibelsWithoutLosingTheFullRange() {
        let scale = MusicEqualizerScale(maximum: 1200)
        XCTAssertEqual(scale.decibels(-1200), -12)
        XCTAssertEqual(scale.nativeValue(1), 100)
        XCTAssertEqual(MusicEqualizerScale(maximum: 12).nativeValue(1), 1)
    }
}
