import XCTest
@testable import LidEffects
@MainActor final class LidAppearanceTests:XCTestCase {
 func testReducedMotionKeepsBlurAndDarkening() {
 let tuning=IslaLidVisual.appearance(reduceMotion:true)
 XCTAssertEqual(tuning.recession,0)
 XCTAssertEqual(tuning.maxBlurRadius,135)
 XCTAssertEqual(tuning.maxDim,0.08)
 }
 func testNormalAppearanceKeepsFullScreenWithLightDarkening() {
 let tuning=IslaLidVisual.appearance(reduceMotion:false)
 XCTAssertEqual(tuning.maxBlurRadius,135);XCTAssertEqual(tuning.maxDim,0.08)
 XCTAssertEqual(tuning.viewingDistance,6);XCTAssertEqual(tuning.recession,0)
 XCTAssertEqual(tuning.blurEvenness,0);XCTAssertEqual(tuning.dimReach,0.5)
 }
 func testClosingKeepsAllFourScreenCorners() {
 let geometry=DepthGeometry();let size=CGSize(width:1800,height:1169)
 let expected=[CGPoint(x:0,y:0),CGPoint(x:1800,y:0),CGPoint(x:1800,y:1169),CGPoint(x:0,y:1169)]
 for angle in [110.0,70.0,30.0] {
 let corners=geometry.corners(startAngle:110,currentAngle:angle,viewingDistanceRatio:6,recession:IslaLidVisual.appearance(reduceMotion:false).recession,screenSize:size)
 for (actual,wanted) in zip(corners,expected) {
 XCTAssertEqual(actual.x,wanted.x,accuracy:0.001);XCTAssertEqual(actual.y,wanted.y,accuracy:0.001)
 }
 }
 }
}
