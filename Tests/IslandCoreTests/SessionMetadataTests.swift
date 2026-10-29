import XCTest
@testable import IslandCore
final class SessionMetadataTests:XCTestCase {
 func testDesktopRootAcceptedAndHelperExcluded() {
 let root=Data(#"{"type":"session_meta","payload":{"id":"main","source":"vscode","originator":"codex_work_desktop"}}"#.utf8)
 XCTAssertEqual(CodexSessionMetadata.rootID(line:root),"main")
 let child=Data(#"{"type":"session_meta","payload":{"id":"helper","source":{"subagent":{"thread_spawn":{"parent_thread_id":"main"}}},"parent_thread_id":"main"}}"#.utf8)
 XCTAssertNil(CodexSessionMetadata.rootID(line:child))
 }
 func testUnknownSourceIsNotGuessedAsMain() {
 XCTAssertNil(CodexSessionMetadata.rootID(line:Data(#"{"type":"session_meta","payload":{"id":"s","source":"unknown"}}"#.utf8)))
 }
}
