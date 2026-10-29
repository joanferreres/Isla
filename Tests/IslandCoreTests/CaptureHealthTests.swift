import XCTest
@testable import IslandCore
final class CaptureHealthTests:XCTestCase {
 func testSlowPrewarmAcknowledgesFrameBeforeCheckingDeadline() {
 var health=CaptureHealth();health.begin(at:0)
 health.observePrewarm(hasFrame:true,at:2.5)
 health.observePrewarm(hasFrame:true,at:4)
 XCTAssertNil(health.error);XCTAssertTrue(health.canRender)
 }
 func testPrewarmWithoutFramesStillTimesOut() {
 var health=CaptureHealth();health.begin(at:0)
 health.observePrewarm(hasFrame:false,at:2.5)
 XCTAssertNotNil(health.error);XCTAssertFalse(health.canRender)
 }
 func testFailureCanBeResetForRetry() {
 var health=CaptureHealth();health.begin(at:0);health.fail("failed")
 XCTAssertFalse(health.canStart);health.reset();XCTAssertTrue(health.canStart);XCTAssertNil(health.error)
 }
 func testRepeatedBeginDoesNotExtendTimeout() {
 var health=CaptureHealth();health.begin(at:0);health.begin(at:1.5);health.check(at:2.1)
 XCTAssertNotNil(health.error);XCTAssertFalse(health.canStart)
 }
 func testFailureAfterFrameStopsRendering() {
 var health=CaptureHealth();health.begin(at:0);health.receivedFrame(at:0.1)
 XCTAssertTrue(health.canRender);health.fail("stopped");XCTAssertFalse(health.canRender)
 }
}
