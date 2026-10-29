import XCTest
@testable import IslandCore
final class CodexUsageDecoderTests:XCTestCase {
 func testLimitsDoNotInventCredits() throws {
 let data=Data(#"{"rate_limit":{"primary_window":{"used_percent":105,"reset_at":1791295200}}}"#.utf8)
 let snapshot=try CodexUsageDecoder.decode(data,fetchedAt:Date(timeIntervalSince1970:0))
 XCTAssertNil(snapshot.creditRemaining);XCTAssertEqual(snapshot.windows.first?.remainingPercent,0)
 }
 func testUnknownSchemaAndEmptyFail() { XCTAssertThrowsError(try CodexUsageDecoder.decode(Data("{}".utf8),fetchedAt:Date())) }
 func testCreditBalanceRemainsSeparate() throws {
 let data=Data(#"{"credits":{"balance":"25.5","has_credits":true}}"#.utf8)
 let snapshot=try CodexUsageDecoder.decode(data,fetchedAt:Date())
 XCTAssertEqual(snapshot.creditRemaining,25.5);XCTAssertTrue(snapshot.windows.isEmpty)
 }
}
