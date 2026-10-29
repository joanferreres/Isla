import XCTest
@testable import IslandCore
final class CodexTurnTrackerTests:XCTestCase {
 func testSeedingAndRepeatedCompletionDoNotNotify() {
 var tracker=CodexTurnTracker()
 tracker.seed([.completed(session:"root",turn:"old")])
 XCTAssertNil(tracker.consume(.completed(session:"root",turn:"old")))
 XCTAssertNil(tracker.consume(.started(session:"root",turn:"new")))
 XCTAssertNotNil(tracker.consume(.completed(session:"root",turn:"new")))
 XCTAssertNil(tracker.consume(.completed(session:"root",turn:"new")))
 }
 func testAbortAndToolCompletionDoNotNotify() throws {
 var tracker=CodexTurnTracker();_ = tracker.consume(.started(session:"s",turn:"t"));_ = tracker.consume(.aborted(session:"s",turn:"t"))
 XCTAssertNil(tracker.consume(.completed(session:"s",turn:"t")))
 XCTAssertNil(try CodexEvent.decode(line:Data(#"{"type":"event_msg","payload":{"type":"item_completed"}}"#.utf8),session:"s"))
 }
 func testPartialLineIsRetained() {
 var stream=JSONLineBuffer()
 XCTAssertEqual(stream.append(Data("{\"a\":".utf8)).count,0)
 XCTAssertEqual(stream.append(Data("1}\n".utf8)),[Data("{\"a\":1}".utf8)])
 }
}
