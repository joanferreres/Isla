import XCTest
@testable import IslandCore
final class UsageHistoryTests:XCTestCase {
 func testCompletionCountedOnceAndRetainedByDate() {
 var history=UsageHistory()
 let event=TurnCompletion(sessionID:"root",turnID:"one",timestamp:Date(timeIntervalSince1970:10))
 history.record(event);history.record(event)
 XCTAssertEqual(history.completions.count,1)
 history.prune(before:Date(timeIntervalSince1970:11));XCTAssertTrue(history.completions.isEmpty)
 }
 func testUnknownTokensDoNotBecomeZero() { let event=TurnCompletion(sessionID:"s",turnID:"t",timestamp:Date());XCTAssertNil(event.reportedTokens) }
}
