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

final class ClaudeTurnEventTests: XCTestCase {
    func line(_ type: String, stop: String, side: Bool = false) -> Data {
        Data(#"{"type":"\#(type)","isSidechain":\#(side),"sessionId":"s1","uuid":"u1","timestamp":"2026-11-24T10:00:00.123Z","message":{"stop_reason":"\#(stop)"}}"#.utf8)
    }
    func testEndTurnIsClaudeCompletion() {
        let event = ClaudeTurnEvent.completion(line: line("assistant", stop: "end_turn"))
        XCTAssertEqual(event?.source, .claude)
        XCTAssertEqual(event?.turnID, "u1")
    }
    func testToolUseSubagentAndUserLinesAreIgnored() {
        XCTAssertNil(ClaudeTurnEvent.completion(line: line("assistant", stop: "tool_use")))
        XCTAssertNil(ClaudeTurnEvent.completion(line: line("assistant", stop: "end_turn", side: true)))
        XCTAssertNil(ClaudeTurnEvent.completion(line: line("user", stop: "end_turn")))
    }
    func testEachAppHasItsOwnColour() {
        let colours = AlertSource.allCases.map { "\($0.rgb.r),\($0.rgb.g),\($0.rgb.b)" }
        XCTAssertEqual(Set(colours).count, AlertSource.allCases.count)
    }
}
