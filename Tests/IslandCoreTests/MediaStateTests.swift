import XCTest
@testable import IslandCore
final class MediaStateTests:XCTestCase {
 func testOldArtworkCannotReplaceCurrentTrack() {
 var state=MediaState()
 state.update(MediaSnapshot(trackID:"A",title:"A",artist:"",playing:true,position:0,duration:60))
 state.update(MediaSnapshot(trackID:"B",title:"B",artist:"",playing:true,position:0,duration:60))
 XCTAssertFalse(state.acceptArtwork(Data([1]),for:"A")); XCTAssertNil(state.artworkData)
 XCTAssertTrue(state.acceptArtwork(Data([2]),for:"B"))
 state.update(nil); XCTAssertNil(state.artworkData)
 }
}
