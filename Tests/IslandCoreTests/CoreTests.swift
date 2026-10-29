import XCTest
@testable import IslandCore
final class CoreTests: XCTestCase {
 func testExternalGeometry() {
 let screen = CGRect(x: 1800, y: 100, width: 1600, height: 1000)
 let frame = IslandGeometry.frame(screen: screen, notchHeight: 0, expanded: false, width: 300)
 XCTAssertEqual(frame.midX, screen.midX); XCTAssertEqual(frame.maxY, screen.maxY); XCTAssertEqual(frame.height, 32)
 }
 func testExpandedHeight() { XCTAssertEqual(IslandGeometry.frame(screen: CGRect(x: 0, y: 0, width: 1800, height: 1100), notchHeight: 38, expanded: true, width: 640).height, 358) }
 func testPinnedSurvivesLeave() { var state = IslandState(); state.enter(); state.togglePinned(); state.leave(); XCTAssertTrue(state.expanded); state.close(); XCTAssertFalse(state.expanded); XCTAssertFalse(state.pinned) }
 func testInvalidPreferences() { var p = Preferences(); p.expandedWidth = .infinity; XCTAssertEqual(p.normalized().expandedWidth, 640); p.expandedWidth = 200; XCTAssertEqual(p.normalized().expandedWidth, 480) }
}
