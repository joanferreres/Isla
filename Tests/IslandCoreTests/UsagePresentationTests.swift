import XCTest
@testable import IslandCore
final class UsagePresentationTests:XCTestCase {
 func testMissingPrimaryDoesNotSubstituteReviewUsage() {
 let snapshot=UsageSnapshot(fetchedAt:Date(),windows:[UsageWindow(id:"review_primary_window",usedPercent:90,resetsAt:nil)],creditRemaining:12,creditUnit:"créditos")
 XCTAssertNil(snapshot.homeUsage)
 }
 func testPrimarySelectedRegardlessOfOrderAndClamped() {
 let snapshot=UsageSnapshot(fetchedAt:Date(),windows:[UsageWindow(id:"secondary_window",usedPercent:85,resetsAt:nil),UsageWindow(id:"primary_window",usedPercent:125,resetsAt:nil)],creditRemaining:nil,creditUnit:nil)
 XCTAssertEqual(snapshot.homeUsage?.usedFraction,1)
 XCTAssertEqual(snapshot.homeUsage?.remainingPercent,0)
 }
 func testOldPreferencesKeepConnectionsAndEnableHomeVisibility() throws {
 let p=try JSONDecoder().decode(Preferences.self,from:Data("{\"codexEnabled\":true,\"musicEnabled\":true,\"expandedWidth\":500}".utf8))
 XCTAssertTrue(p.showCodexOnHome);XCTAssertTrue(p.codexEnabled);XCTAssertTrue(p.musicEnabled);XCTAssertEqual(p.expandedWidth,500)
 var hidden=p;hidden.showCodexOnHome=false
 let restored=try JSONDecoder().decode(Preferences.self,from:JSONEncoder().encode(hidden))
 XCTAssertFalse(restored.showCodexOnHome);XCTAssertTrue(restored.codexEnabled)
 }
}
