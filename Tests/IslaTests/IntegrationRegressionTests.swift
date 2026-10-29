import XCTest
@testable import Isla
import IslandCore
@MainActor final class IntegrationRegressionTests:XCTestCase {
 func testNewRootFinishedAfterStartupIsNotHistorical() async throws {
 let root=FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
 defer { try? FileManager.default.removeItem(at:root) }
 let sessions=root.appendingPathComponent("sessions")
 try FileManager.default.createDirectory(at:sessions,withIntermediateDirectories:true)
 let reader=CodexSessionReader(roots:[root],discoveryInterval:0)
 let first=await reader.scan();XCTAssertTrue(first.events.isEmpty)
 let payload="""
 {"type":"session_meta","payload":{"id":"root","source":"vscode"}}
 {"type":"event_msg","payload":{"type":"task_started","turn_id":"one"}}
 {"type":"event_msg","payload":{"type":"task_complete","turn_id":"one"}}
 
 """
 try Data(payload.utf8).write(to:sessions.appendingPathComponent("root.jsonl"))
 let second=await reader.scan()
 var tracker=CodexTurnTracker();tracker.seed(second.seed)
 XCTAssertEqual(second.events.compactMap{tracker.consume($0)}.count,1)
 let third=await reader.scan();XCTAssertTrue(third.events.isEmpty)
 }
 func testArtworkIdentityMustBelongToItsOwnReply() {
 let reply=MusicReply(artwork:Data([2]),artworkTrackID:"B")
 XCTAssertNil(reply.artwork(for:"A"))
 XCTAssertEqual(reply.artwork(for:"B"),Data([2]))
 }
 func testDisplayedSizeUsesTheClampedLayout() {
 let model=IslandModel()
 let metrics=DisplayMetrics(id:1,frame:CGRect(x:0,y:0,width:400,height:300),notchWidth:150,headerHeight:28,builtIn:false)
 let layout=IslandLayout(metrics:metrics,expandedWidth:800,expandedHeight:340)
 model.apply(layout)
 XCTAssertEqual(model.expandedSize,layout.openSize)
 XCTAssertEqual(model.expandedSize,CGSize(width:400,height:300))
 }
}
actor DeniedMusicReader:AppleMusicReading {
 var calls=0
 func isRunning() async -> Bool { true }
 func read() async throws -> MediaSnapshot? { calls += 1;throw MusicFailure(message:"denied",code:-1743) }
 func artwork(trackID:String) async throws -> Data? { nil }
 func send(_ command:MediaCommand) async throws {}
 func count() -> Int { calls }
}
extension IntegrationRegressionTests {
 func testDeniedAutomationRequiresExplicitReconnect() async {
 let reader=DeniedMusicReader();let music=AppleMusicService(reader:reader)
 music.enabled=true
 await music.refresh();await music.refresh();await music.refresh()
 let count=await reader.count();XCTAssertEqual(count,1)
 music.disconnect();music.connect()
 // connect schedules an initial refresh; let it finish before inspecting.
 try? await Task.sleep(for:.milliseconds(30))
 let retryCount=await reader.count();XCTAssertEqual(retryCount,2)
 music.disconnect()
 }
}
extension IntegrationRegressionTests {
 func testSystemMediaArtworkIsBoundToAppleMusicTrack() throws {
 let data=Data(#"{"payload":{"bundleIdentifier":"com.apple.Music","title":"One","artist":"Artist","album":"Album","durationMicros":120000000,"elapsedTimeMicros":2000000,"isPlaying":false,"artworkDataBase64":"AQID"}}"#.utf8)
 let reply=try SystemMediaReply.decode(data)
 XCTAssertEqual(reply.snapshot?.title,"One");XCTAssertEqual(reply.snapshot?.duration,120)
 XCTAssertEqual(reply.snapshot?.position,2)
 XCTAssertEqual(reply.artwork(for:reply.snapshot!.trackID),Data([1,2,3]))
 XCTAssertNil(reply.artwork(for:"another-track"))
 }
 func testSystemMediaDoesNotUseAnotherAppsArtwork() throws {
 let data=Data(#"{"payload":{"bundleIdentifier":"com.apple.Safari","title":"One","artist":"Artist","artworkDataBase64":"AQID"}}"#.utf8)
 XCTAssertNil(try SystemMediaReply.decode(data).snapshot)
 XCTAssertNil(try SystemMediaReply.decode(data).artwork)
 }
 func testAlbumChangeChangesArtworkIdentity() throws {
 func reply(_ album:String) throws -> MusicReply {
 try SystemMediaReply.decode(Data("{\"payload\":{\"bundleIdentifier\":\"com.apple.Music\",\"title\":\"One\",\"artist\":\"Artist\",\"album\":\"\(album)\"}}".utf8))
 }
 XCTAssertNotEqual(try reply("Original").snapshot?.trackID,try reply("Live").snapshot?.trackID)
 }
}
extension IntegrationRegressionTests {
 func testOldDatedChatResumesAfterStartup() async throws {
 let root=FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
 defer { try? FileManager.default.removeItem(at:root) }
 let folder=root.appendingPathComponent("sessions/2020/01/01")
 try FileManager.default.createDirectory(at:folder,withIntermediateDirectories:true)
 let file=folder.appendingPathComponent("old.jsonl")
 try Data("{\"type\":\"session_meta\",\"payload\":{\"id\":\"old\",\"source\":\"vscode\"}}\n".utf8).write(to:file)
 let reader=CodexSessionReader(roots:[root],discoveryInterval:0)
 let initial=await reader.scan();XCTAssertEqual(initial.found,1)
 let handle=try FileHandle(forWritingTo:file);try handle.seekToEnd()
 try handle.write(contentsOf:Data("{\"type\":\"event_msg\",\"payload\":{\"type\":\"task_started\",\"turn_id\":\"one\"}}\n{\"type\":\"event_msg\",\"payload\":{\"type\":\"task_complete\",\"turn_id\":\"one\"}}\n".utf8));try handle.close()
 let next=await reader.scan();var tracker=CodexTurnTracker();tracker.seed(initial.seed)
 XCTAssertEqual(next.events.compactMap{tracker.consume($0)}.count,1)
 }
 func testSleepRemovesMusicNotificationObserver() {
 let music=AppleMusicService(reader:DeniedMusicReader())
 music.connect();XCTAssertNotNil(music.observer)
 music.pauseForSleep();XCTAssertNil(music.observer)
 music.connect();XCTAssertNotNil(music.observer)
 music.disconnect();XCTAssertNil(music.observer)
 }
}

extension IntegrationRegressionTests {
 func testLidAccessIsValidatedWithCaptureAPI() async {
 var checks=0
 let lid=LidEffectController(preferences:PreferencesStore(),captureCheck:{ checks += 1;return true },angleRead:{ 100 })
 await lid.enable()
 XCTAssertEqual(checks,1,"Do not block ScreenCaptureKit solely on the legacy preflight result")
 XCTAssertTrue(lid.enabled)
 lid.disable()
 }
 func testDeniedCaptureDoesNotEnableLidEffect() async {
 var checks=0
 let lid=LidEffectController(preferences:PreferencesStore(),captureCheck:{ checks += 1;return false },angleRead:{ 100 })
 await lid.enable()
 XCTAssertEqual(checks,1);XCTAssertFalse(lid.enabled);XCTAssertNotNil(lid.error)
 lid.disable()
 }
}
