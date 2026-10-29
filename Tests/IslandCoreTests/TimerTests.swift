import XCTest
@testable import IslandCore
final class TimerTests: XCTestCase {
 let start = Date(timeIntervalSince1970: 1000)
 func testSuspensionUsesDeadline() { var timer = Countdown(seconds: 60); timer.start(at: start); XCTAssertEqual(timer.remaining(at: start.addingTimeInterval(75)), 0) }
 func testPausedTimeDoesNotAdvance() { var timer = Countdown(seconds: 60); timer.start(at: start); timer.pause(at: start.addingTimeInterval(10)); XCTAssertEqual(timer.remaining(at: start.addingTimeInterval(100)), 50) }
 func testStartDoesNotResetRunningTimer() { var timer = Countdown(seconds: 60); timer.start(at: start); timer.start(at: start.addingTimeInterval(20)); XCTAssertEqual(timer.remaining(at: start.addingTimeInterval(30)), 30) }
 func testResumeAndReset() { var timer = Countdown(seconds: 60); timer.start(at: start); timer.pause(at: start.addingTimeInterval(10)); timer.start(at: start.addingTimeInterval(100)); XCTAssertEqual(timer.remaining(at: start.addingTimeInterval(120)), 30); timer.reset(); XCTAssertEqual(timer.remaining(at: start.addingTimeInterval(200)), 60) }
 func testStopwatchPauseAndResume() { var watch = Stopwatch(); watch.start(at: start); watch.pause(at: start.addingTimeInterval(5)); XCTAssertEqual(watch.elapsed(at: start.addingTimeInterval(20)), 5); watch.start(at: start.addingTimeInterval(20)); XCTAssertEqual(watch.elapsed(at: start.addingTimeInterval(23)), 8); watch.reset(); XCTAssertEqual(watch.elapsed(at: start.addingTimeInterval(25)), 0) }
}
