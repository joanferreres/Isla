import XCTest
import EventKit
@testable import Isla

final class CalendarPermissionTests:XCTestCase {
 func testGrantedCalendarDoesNotRequestAgain() async throws {
 let reader=CalendarReader(authorization:{.fullAccess},requestAccess:{ XCTFail("Existing permission must be reused");return false })
 let granted=try await reader.request()
 XCTAssertTrue(granted)
 }
 func testDeniedCalendarDoesNotOpenAnotherPermissionPrompt() async throws {
 for status in [EKAuthorizationStatus.denied,.restricted,.writeOnly] {
 let reader=CalendarReader(authorization:{status},requestAccess:{ XCTFail("A decided permission must not prompt again");return true })
 let granted=try await reader.request()
 XCTAssertFalse(granted)
 }
 }
 func testFirstConnectionRequestsAccess() async throws {
 let reader=CalendarReader(authorization:{.notDetermined},requestAccess:{true})
 let granted=try await reader.request()
 XCTAssertTrue(granted)
 }
}
