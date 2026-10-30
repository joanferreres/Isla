import XCTest
import IslandCore
@testable import Isla

private actor ReleaseServer {
 var requests:[URLRequest]=[]
 var status:Int
 let data:Data
 let delay:Duration
 init(status:Int=200,tag:String="v0.8.9",delay:Duration = .zero) {
 self.status=status;self.delay=delay
 data=try! JSONSerialization.data(withJSONObject:["tag_name":tag,"html_url":"https://github.com/joanferreres/Isla/releases/tag/\(tag)","draft":false,"prerelease":false,"assets":[["name":"Isla.zip"]]])
 }
 func load(_ request:URLRequest) async throws -> (Data,HTTPURLResponse) {
 requests.append(request)
 if delay != .zero { try await Task.sleep(for:delay) }
 return (data,HTTPURLResponse(url:request.url!,statusCode:status,httpVersion:"HTTP/1.1",headerFields:["ETag":"test-release"])!)
 }
 func setStatus(_ status:Int) { self.status=status }
 func recorded() -> [URLRequest] { requests }
}
@MainActor final class AppUpdateServiceTests:XCTestCase {
 private func isolatedDefaults() -> UserDefaults {
 let name="IslaUpdateTests.\(UUID().uuidString)"
 let defaults=UserDefaults(suiteName:name)!
 addTeardownBlock { defaults.removePersistentDomain(forName:name) }
 return defaults
 }
 func testAvailableReleasePersistsAndAutomaticNoticeIsOnlyOncePerVersion() async throws {
 let defaults=isolatedDefaults(),server=ReleaseServer()
 let service=AppUpdateService(currentVersion:"0.8.8",defaults:defaults,fetch:{try await server.load($0)})
 var alerts=0;service.onAvailable={alerts+=1};service.start()
 await service.check()
 XCTAssertEqual(service.available?.version,"0.8.9");XCTAssertEqual(alerts,1)
 XCTAssertNotNil(service.claimAutomaticNotice());XCTAssertNil(service.claimAutomaticNotice())
 await service.check()
 let requests=await server.recorded();XCTAssertEqual(requests.count,1)
 service.suspend()
 let restored=AppUpdateService(currentVersion:"0.8.8",defaults:defaults,fetch:{try await server.load($0)})
 XCTAssertEqual(restored.available?.version,"0.8.9");XCTAssertNil(restored.claimAutomaticNotice())
 let upgraded=AppUpdateService(currentVersion:"0.8.9",defaults:defaults,fetch:{try await server.load($0)})
 XCTAssertNil(upgraded.available)
 }
 func testManualCheckWorksWhenDisabledAndNeverTriggersAutomaticPrompt() async {
 let defaults=isolatedDefaults(),server=ReleaseServer();defaults.set(false,forKey:"updates.automatic")
 let service=AppUpdateService(currentVersion:"0.8.8",defaults:defaults,fetch:{try await server.load($0)})
 var alerts=0;service.onAvailable={alerts+=1};service.start();await service.check()
 var requests=await server.recorded();XCTAssertTrue(requests.isEmpty)
 await service.check(force:true)
 requests=await server.recorded();XCTAssertEqual(requests.count,1);XCTAssertEqual(alerts,0)
 XCTAssertNotNil(service.available);XCTAssertFalse(service.automaticChecksEnabled)
 }
 func testConditionalCheckUsesCachedReleaseWithoutCredentials() async {
 let defaults=isolatedDefaults(),server=ReleaseServer()
 let service=AppUpdateService(currentVersion:"0.8.8",defaults:defaults,fetch:{try await server.load($0)})
 await service.check(force:true);await server.setStatus(304);await service.check(force:true)
 let requests=await server.recorded()
 XCTAssertEqual(requests.count,2);XCTAssertEqual(requests[1].value(forHTTPHeaderField:"If-None-Match"),"test-release")
 XCTAssertNil(requests[1].value(forHTTPHeaderField:"Authorization"));XCTAssertNotNil(service.available)
 XCTAssertNotNil(service.lastChecked);XCTAssertNil(service.error)
 }
 func testOfflineAndRateLimitKeepKnownUpdateAndDoNotRepeatRequests() async {
 let defaults=isolatedDefaults(),server=ReleaseServer()
 let service=AppUpdateService(currentVersion:"0.8.8",defaults:defaults,fetch:{try await server.load($0)})
 await service.check(force:true);await server.setStatus(403);await service.check(force:true)
 XCTAssertNotNil(service.error);XCTAssertNotNil(service.available)
 service.start();await service.check()
 let requests=await server.recorded();XCTAssertEqual(requests.count,2)
 service.suspend()
 }
 func testCorruptedCacheCannotHideAnUpdateWithConditionalResponse() async {
 let defaults=isolatedDefaults(),server=ReleaseServer()
 defaults.set(Data("invalid".utf8),forKey:"updates.cached");defaults.set("stale",forKey:"updates.etag")
 let service=AppUpdateService(currentVersion:"0.8.8",defaults:defaults,fetch:{try await server.load($0)})
 await service.check(force:true)
 let requests=await server.recorded()
 XCTAssertNil(requests[0].value(forHTTPHeaderField:"If-None-Match"));XCTAssertNotNil(service.available)
 }
 func testSleepDiscardsResultOfAnInFlightCheck() async throws {
 let defaults=isolatedDefaults(),server=ReleaseServer(delay:.milliseconds(100))
 let service=AppUpdateService(currentVersion:"0.8.8",defaults:defaults,fetch:{try await server.load($0)})
 let pending=Task { await service.check(force:true) }
 for _ in 0..<20 { if service.checking { break };try await Task.sleep(for:.milliseconds(5)) }
 XCTAssertTrue(service.checking);service.suspend();await pending.value
 XCTAssertNil(service.available);XCTAssertFalse(service.checking)
 }
}
