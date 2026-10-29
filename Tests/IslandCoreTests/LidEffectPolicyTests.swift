import XCTest
@testable import IslandCore
final class LidEffectPolicyTests:XCTestCase {
 func testPartiallyClosedAtLaunchDoesNotActivate() {
 var policy=LidEffectPolicy()
 XCTAssertEqual(policy.update(angle:70,timestamp:0),.inactive)
 XCTAssertEqual(policy.update(angle:70,timestamp:1),.inactive)
 }
 func testClosingActivatesAndOpeningReleases() {
 var p=LidEffectPolicy();_ = p.update(angle:125,timestamp:0)
 XCTAssertEqual(p.update(angle:120,timestamp:0.2),.prewarming)
 if case .active = p.update(angle:110,timestamp:0.4) {} else { XCTFail("Closing should activate") }
 XCTAssertEqual(p.update(angle:113,timestamp:0.6),.active(progress:4.0/60))
 XCTAssertEqual(p.update(angle:117,timestamp:0.8),.inactive)
 }
 func testCaptureNeverStartsWhileStationaryOrOpening() {
 var p=LidEffectPolicy()
 for i in 0..<40 { XCTAssertEqual(p.update(angle:120,timestamp:Double(i)/4),.inactive) }
 XCTAssertEqual(p.update(angle:122,timestamp:10),.inactive)
 }
 func testClosingFromNinetyDegreesIsDetected() {
 var p=LidEffectPolicy();_ = p.update(angle:90,timestamp:0)
 XCTAssertEqual(p.update(angle:86,timestamp:0.2),.prewarming)
 guard case let .active(progress)=p.update(angle:75,timestamp:0.4) else { return XCTFail("Closing from normal angle must activate") }
 XCTAssertGreaterThan(progress,0)
 }
 func testSlowCumulativeClosingTriggersAndStationaryStopsCapture() {
 var p=LidEffectPolicy();_ = p.update(angle:120,timestamp:0)
 var state=LidEffectState.inactive
 for i in 1...45 { state=p.update(angle:120-Double(i)*0.2,timestamp:Double(i)*0.1) }
 guard case .active=state else { return XCTFail("Slow closing must activate") }
 XCTAssertEqual(p.update(angle:111,timestamp:7.5),.inactive)
 }
 func testSlowOpeningReversesActiveEffect() {
 var p=LidEffectPolicy();_ = p.update(angle:120,timestamp:0);_ = p.update(angle:100,timestamp:0.1)
 var state=LidEffectState.inactive
 for i in 1...16 { state=p.update(angle:100+Double(i)*0.1,timestamp:0.1+Double(i)*0.03) }
 XCTAssertEqual(state,.active(progress:(112-101.6)/60))
 }
 func testReverseThenCloseAgainUsesSameOpenPosition() {
 var p=LidEffectPolicy();_ = p.update(angle:120,timestamp:0)
 XCTAssertEqual(p.update(angle:90,timestamp:0.1),.active(progress:22.0/60))
 XCTAssertEqual(p.update(angle:100,timestamp:0.2),.active(progress:12.0/60))
 XCTAssertEqual(p.update(angle:95,timestamp:0.3),.active(progress:17.0/60))
 XCTAssertEqual(p.update(angle:112,timestamp:0.4),.inactive)
 }
 func testSlowReopeningKeepsEffectBeyondClosingTimeout() {
 var p=LidEffectPolicy();_ = p.update(angle:120,timestamp:0);_ = p.update(angle:90,timestamp:0.1)
 for i in 1...20 {
 guard case .active = p.update(angle:90+Double(i)*0.1,timestamp:0.1+Double(i)*0.1) else { return XCTFail("Opening motion must keep reversing the effect") }
 }
 XCTAssertEqual(p.update(angle:92,timestamp:5.2),.inactive)
 }
 func testHalfOpenWaitsThreeSecondsThenClearsAndStaysClear() {
 var p=LidEffectPolicy();_ = p.update(angle:120,timestamp:0)
 let effect=p.update(angle:90,timestamp:1)
 XCTAssertEqual(effect,.active(progress:22.0/60))
 XCTAssertEqual(p.update(angle:90,timestamp:2.5),effect)
 XCTAssertEqual(p.update(angle:90,timestamp:3.99),effect)
 XCTAssertEqual(p.update(angle:90,timestamp:4),.inactive)
 XCTAssertEqual(p.update(angle:90,timestamp:30),.inactive)
 }
 func testMovementRestartsThreeSecondWait() {
 var p=LidEffectPolicy();_ = p.update(angle:120,timestamp:0);_ = p.update(angle:90,timestamp:1)
 let reversed=p.update(angle:95,timestamp:3)
 XCTAssertEqual(p.update(angle:95,timestamp:5.99),reversed)
 XCTAssertEqual(p.update(angle:95,timestamp:6),.inactive)
 }
 func testStationarySensorJitterDoesNotKeepEffectAlive() {
 var p=LidEffectPolicy();_ = p.update(angle:120,timestamp:0)
 _ = p.update(angle:90.0,timestamp:1)
 for i in 1...29 {
 let angle=90.0+(i.isMultiple(of:2) ? 0.08 : -0.08)
 guard case .active = p.update(angle:angle,timestamp:1+Double(i)*0.1) else { return XCTFail("Keep effect until three seconds") }
 }
 XCTAssertEqual(p.update(angle:90.08,timestamp:4),.inactive)
 XCTAssertEqual(p.update(angle:89.92,timestamp:5),.inactive)
 }
 func testSmallStepsAccumulateIntoRealOpeningMotion() {
 var p=LidEffectPolicy();_ = p.update(angle:120,timestamp:0);_ = p.update(angle:90,timestamp:1)
 for i in 1...50 {
 guard case .active = p.update(angle:90+Double(i)*0.1,timestamp:1+Double(i)*0.1) else { return XCTFail("Slow cumulative movement must remain active") }
 }
 XCTAssertEqual(p.update(angle:95,timestamp:9.1),.inactive)
 }
 func testNoiseDoesNotStartCapture() {
 var p=LidEffectPolicy()
 for i in 0..<100 { XCTAssertEqual(p.update(angle:120+(i.isMultiple(of:2) ? 0.1 : -0.1),timestamp:Double(i)*0.1),.inactive) }
 }
 func testMalformedReportsRejected() {
 XCTAssertNil(LidReportDecoder.decode([7,0]))
 XCTAssertEqual(LidReportDecoder.decode([1,100,0]),100)
 XCTAssertEqual(LidReportDecoder.decode([7,0x10,0x27,0,0]),100)
 XCTAssertNil(LidReportDecoder.decode([1,255,255]))
 }
}
