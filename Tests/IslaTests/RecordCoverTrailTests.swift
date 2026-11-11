import XCTest
@testable import Isla
import AppKit

@MainActor final class RecordCoverTrailTests: XCTestCase {
    func testForwardAndBackExposeEagerCovers() {
        var trail = RecordCoverTrail()
        let first = NSImage(size: NSSize(width: 2, height: 2))
        let second = NSImage(size: NSSize(width: 3, height: 3))
        trail.land(keys: ["a"], image: first)
        XCTAssertNil(trail.nextCover)
        XCTAssertNil(trail.previousCover)
        trail.land(keys: ["b"], image: second)
        XCTAssertIdentical(trail.previousCover, first)
        XCTAssertNil(trail.nextCover)
        trail.land(keys: ["a"], image: first)
        XCTAssertIdentical(trail.nextCover, second)
        XCTAssertNil(trail.previousCover)
    }

    func testNeighborPrefetchFillsNextBeforeVisit() {
        var trail = RecordCoverTrail()
        let current = NSImage(size: NSSize(width: 2, height: 2))
        let upcoming = NSImage(size: NSSize(width: 4, height: 4))
        let prior = NSImage(size: NSSize(width: 5, height: 5))
        trail.land(keys: ["now"], image: current)
        trail.applyNeighbors(previousKeys: ["prev"], previousImage: prior,
                             nextKeys: ["next"], nextImage: upcoming)
        XCTAssertIdentical(trail.nextCover, upcoming)
        XCTAssertIdentical(trail.previousCover, prior)
    }

    func testMediaRemoteAndFingerprintKeysAliasTheSameEntry() {
        var trail = RecordCoverTrail()
        let art = NSImage(size: NSSize(width: 2, height: 2))
        let remote = "mediaremote:Song\u{001F}Artist\u{001F}Album"
        trail.land(keys: RecordCoverTrail.keys(trackID: remote, title: "Song", artist: "Artist"), image: art)
        trail.land(keys: RecordCoverTrail.keys(trackID: "ABCD1234", title: "Song", artist: "Artist"), image: art)
        XCTAssertEqual(trail.entries.count, 1)
    }

    func testNavigationHintConsumesPrefetchedNeighborWithForeignID() {
        var trail = RecordCoverTrail()
        let now = NSImage(size: NSSize(width: 2, height: 2))
        let upcoming = NSImage(size: NSSize(width: 4, height: 4))
        trail.land(keys: ["persistent-now"], image: now)
        trail.applyNeighbors(previousKeys: [], previousImage: nil,
                             nextKeys: ["persistent-next"], nextImage: upcoming)
        XCTAssertIdentical(trail.nextCover, upcoming)
        let landed = NSImage(size: NSSize(width: 6, height: 6))
        trail.land(keys: ["mediaremote:Next\u{001F}Artist\u{001F}Album"], image: landed, navigation: .next)
        XCTAssertIdentical(trail.previousCover, now)
        XCTAssertNil(trail.nextCover)
        XCTAssertEqual(trail.entries.count, 2)
    }
}
