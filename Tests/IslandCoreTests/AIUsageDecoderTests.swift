import XCTest
@testable import IslandCore
final class AIUsageDecoderTests:XCTestCase {
 func testClaudeSharedWindowsAndReset() throws {
 let data=Data(#"{"five_hour":{"utilization":37,"resets_at":"2026-10-10T15:00:00Z"},"seven_day":{"utilization":26},"seven_day_sonnet":{"utilization":0}}"#.utf8)
 let snapshot=try AIUsageDecoder.decode(data,provider:.claude,fetchedAt:Date())
 XCTAssertEqual(snapshot.windows.map(\.usedPercent),[37,26,0])
 XCTAssertNotNil(snapshot.windows[0].resetsAt)
 }
 func testCursorIndependentBucketsIncludingZero() throws {
 let data=Data(#"{"billingCycleEnd":"2026-11-01T00:00:00.000Z","individualUsage":{"plan":{"autoPercentUsed":0,"apiPercentUsed":19,"totalPercentUsed":9.5}}}"#.utf8)
 let snapshot=try AIUsageDecoder.decode(data,provider:.cursor,fetchedAt:Date())
 XCTAssertEqual(snapshot.windows.map(\.usedPercent),[0,19])
 XCTAssertEqual(snapshot.windows.map(\.id),["auto","api"])
 XCTAssertNotNil(snapshot.windows.first?.resetsAt)
 }
 func testCursorEnterpriseAndMissingLimit() throws {
 let data=Data(#"{"individualUsage":{"overall":{"enabled":true,"used":25,"limit":100}}}"#.utf8)
 XCTAssertEqual(try AIUsageDecoder.decode(data,provider:.cursor,fetchedAt:Date()).windows.first?.usedPercent,25)
 XCTAssertThrowsError(try AIUsageDecoder.decode(Data(#"{"individualUsage":{"plan":{"used":0,"limit":0}}}"#.utf8),provider:.cursor,fetchedAt:Date()))
 }
 func testLegacyPreferencesIncludeNewProviders() throws {
 let p=try JSONDecoder().decode(Preferences.self,from:Data("{}".utf8))
 XCTAssertTrue(p.cursorEnabled);XCTAssertTrue(p.claudeEnabled)
 var changed=p;changed.showCursorOnHome=false;changed.claudeEnabled=false
 XCTAssertEqual(try JSONDecoder().decode(Preferences.self,from:JSONEncoder().encode(changed)),changed)
 }
}
