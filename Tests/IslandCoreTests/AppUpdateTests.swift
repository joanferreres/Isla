import XCTest
@testable import IslandCore
final class AppUpdateTests:XCTestCase {
 func testVersionsCompareNumericallyAndNormalizeShortVersions() {
 XCTAssertGreaterThan(AppVersion("v1.10.0")!,AppVersion("1.9.99")!)
 XCTAssertEqual(AppVersion("v1.2"),AppVersion("1.2.0"))
 XCTAssertLessThan(AppVersion("0.8.7")!,AppVersion("0.8.8")!)
 for invalid in ["", "v", "1..2", "1.2.3.4", "-1.2.3", "1.2-beta", "1.2.3+meta", "1.２.3", "99999999999999999999999"] { XCTAssertNil(AppVersion(invalid),invalid) }
 }
 func testOnlyStableReleaseWithPackagedAppCanBeOffered() throws {
 func payload(tag:String="v0.8.9",url:String="https://github.com/joanferreres/Isla/releases/tag/v0.8.9",draft:Bool=false,prerelease:Bool=false,asset:String="Isla.zip") throws -> Data {
 try JSONSerialization.data(withJSONObject:["tag_name":tag,"html_url":url,"draft":draft,"prerelease":prerelease,"assets":[["name":asset]]])
 }
 let valid=try XCTUnwrap(AppUpdate.decodeLatest(payload()))
 XCTAssertTrue(valid.isNewer(than:"0.8.8"));XCTAssertFalse(valid.isNewer(than:"0.8.9"));XCTAssertFalse(valid.isNewer(than:"1.0.0"))
 XCTAssertNil(try AppUpdate.decodeLatest(payload(draft:true)))
 XCTAssertNil(try AppUpdate.decodeLatest(payload(prerelease:true)))
 XCTAssertNil(try AppUpdate.decodeLatest(payload(asset:"Source code.zip")))
 XCTAssertNil(try AppUpdate.decodeLatest(payload(url:"https://example.com/joanferreres/Isla/releases/tag/v0.8.9")))
 XCTAssertNil(try AppUpdate.decodeLatest(payload(url:"http://github.com/joanferreres/Isla/releases/tag/v0.8.9")))
 XCTAssertNil(try AppUpdate.decodeLatest(payload(url:"https://github.com/other/project/releases/tag/v0.8.9")))
 XCTAssertNil(try AppUpdate.decodeLatest(payload(url:"https://github.com/joanferreres/Isla/releases/tag/v0.8.9?redirect=1")))
 }
}
