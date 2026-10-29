import XCTest
import IslandCore
@testable import Isla

@MainActor final class CompletionNotificationTests:XCTestCase {
 func testCompletionSignalsSoundAndRailWhileKeepingVisualNotice() {
 var sounds=0;var records=0
 let service=CodexActivityService(playSound:{sounds += 1})
 service.onCompletion={_ in records += 1}
 let event=TurnCompletion(sessionID:"test",turnID:"one",timestamp:Date())
 service.announce(event)
 XCTAssertEqual(sounds,1);XCTAssertEqual(records,1)
 XCTAssertNotNil(service.completionPulse);XCTAssertEqual(service.latest,event)
 }
 func testMoonKeepsNoticeButSuppressesSoundAndRail() {
 var sounds=0
 let service=CodexActivityService(playSound:{sounds += 1})
 service.soundEnabled=false;service.completionHighlightEnabled=false
 let event=TurnCompletion(sessionID:"test",turnID:"one",timestamp:Date())
 service.announce(event)
 XCTAssertEqual(sounds,0);XCTAssertNil(service.completionPulse)
 XCTAssertEqual(service.latest,event)
 }
 func testNoAlertsStillRecordsCompletionWithoutNoticeSoundOrRail() {
 var records=0
 let service=CodexActivityService(playSound:{XCTFail("Silent mode")})
 service.soundEnabled=false;service.completionHighlightEnabled=false;service.completionNoticeEnabled=false
 service.onCompletion={_ in records += 1}
 service.announce(TurnCompletion(sessionID:"test",turnID:"silent",timestamp:Date()))
 XCTAssertEqual(records,1);XCTAssertNil(service.latest);XCTAssertNil(service.completionPulse)
 }
 func testPreviewCreatesFreshPulseWithoutAddingHistoryOrCompletion() {
 let service=CodexActivityService(playSound:{})
 service.onCompletion={_ in XCTFail("Preview must not add history")}
 service.previewNotification();let first=service.completionPulse
 service.previewNotification()
 XCTAssertNotNil(first);XCTAssertNotEqual(first,service.completionPulse)
 XCTAssertNil(service.latest)
 }
}
