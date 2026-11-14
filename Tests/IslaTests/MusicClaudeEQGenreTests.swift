import XCTest
@testable import Isla

final class MusicClaudeEQGenreTests: XCTestCase {
    func testNormalizeGenreTrimsAndLowercases() {
        XCTAssertEqual(MusicClaudeEQService.normalizeGenre("  Rock "), "rock")
        XCTAssertEqual(MusicClaudeEQService.normalizeGenre("Hip  Hop"), "hip hop")
        XCTAssertEqual(MusicClaudeEQService.normalizeGenre(""), "")
    }

    func testSameGenreKeysMatchForCacheGate() {
        let a = MusicClaudeEQService.normalizeGenre("Electronic")
        let b = MusicClaudeEQService.normalizeGenre("electronic")
        XCTAssertEqual(a, b)
        XCTAssertNotEqual(a, MusicClaudeEQService.normalizeGenre("Jazz"))
    }
}
