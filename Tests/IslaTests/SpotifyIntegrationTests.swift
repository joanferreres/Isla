import XCTest
import IslandCore
@testable import Isla

actor StubMusicReader:AppleMusicReading {
 let source:MediaSource
 var snapshot:MediaSnapshot?
 var commands:[MediaCommand]=[]
 init(source:MediaSource,snapshot:MediaSnapshot?) { self.source=source;self.snapshot=snapshot }
 func isRunning() async -> Bool { true }
 func read() async throws -> MediaSnapshot? { snapshot }
 func cachedArtwork(trackID:String) async -> Data? { nil }
 func rememberCachedArtwork(_ data:Data,for trackID:String) async {}
 func adoptSystemArtwork(for trackID:String) async {}
 func artwork(trackID:String) async throws -> Data? { nil }
 func neighbors() async throws -> MusicNeighbors? { nil }
 func send(_ command:MediaCommand) async throws { commands.append(command) }
 func volume(_ value:Int?) async throws -> Int { value ?? 50 }
 func shuffle(_ value:Bool?) async throws -> Bool { value ?? false }
 func activeSource() async -> MediaSource? { source }
 func commandCount() -> Int { commands.count }
}

final class SpotifyIntegrationTests:XCTestCase {
 func testAutomaticSourcePrefersTheProviderThatIsPlaying() async throws {
  let apple=StubMusicReader(source:.appleMusic,snapshot:MediaSnapshot(trackID:"A",title:"Apple",artist:"Artist",playing:false,position:0,duration:100))
  let spotify=StubMusicReader(source:.spotify,snapshot:MediaSnapshot(trackID:"spotify:S",title:"Spotify",artist:"Artist",playing:true,position:4,duration:120,source:.spotify))
  let bridge=MusicSourceBridge(apple:apple,spotify:spotify)
  let snapshot=try await bridge.read()
  XCTAssertEqual(snapshot?.source,.spotify)
  try await bridge.send(.next)
  let spotifyCommands=await spotify.commandCount()
  let appleCommands=await apple.commandCount()
  XCTAssertEqual(spotifyCommands,1)
  XCTAssertEqual(appleCommands,0)
 }

 func testExplicitAppleMusicSourceDoesNotReadSpotify() async throws {
  let apple=StubMusicReader(source:.appleMusic,snapshot:MediaSnapshot(trackID:"A",title:"Apple",artist:"Artist",playing:false,position:0,duration:100))
  let spotify=StubMusicReader(source:.spotify,snapshot:MediaSnapshot(trackID:"spotify:S",title:"Spotify",artist:"Artist",playing:true,position:4,duration:120,source:.spotify))
  let bridge=MusicSourceBridge(preference:.appleMusic,apple:apple,spotify:spotify)
  let snapshot=try await bridge.read()
  XCTAssertEqual(snapshot?.source,.appleMusic)
 }

 func testSpotifyArtworkOnlyAllowsSpotifyCDNOverHTTPS() {
  XCTAssertNotNil(SpotifyBridge.artworkURL("https://i.scdn.co/image/example"))
  XCTAssertNil(SpotifyBridge.artworkURL("http://i.scdn.co/image/example"))
  XCTAssertNil(SpotifyBridge.artworkURL("https://example.com/image"))
 }
}
