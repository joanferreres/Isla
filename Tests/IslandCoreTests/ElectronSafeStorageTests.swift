import XCTest
@testable import IslandCore
final class ElectronSafeStorageTests:XCTestCase {
 func testUnwrapsCursorSafeStorageV1() throws {
  let sealed="cursor-safe-storage:v1:djEww03mXiOogQVLP8swh7hQqtqlBH7lTtLbkPi9LvYgD+T/p309ZcP2xQuH6COtTRyO"
  let plain=try ElectronSafeStorage.unwrap(sealed,password:"isla-fixture-password")
  XCTAssertEqual(plain,"fixture.eyJzdWIiOiJmaXh0dXJlLWFjY291bnQifQ.sig")
 }
 func testPlaintextPassesThrough() throws {
  XCTAssertEqual(try ElectronSafeStorage.unwrap("plain-token",password:"unused"),"plain-token")
 }
 func testRejectsBadPassword() {
  let sealed="cursor-safe-storage:v1:djEww03mXiOogQVLP8swh7hQqtqlBH7lTtLbkPi9LvYgD+T/p309ZcP2xQuH6COtTRyO"
  XCTAssertThrowsError(try ElectronSafeStorage.unwrap(sealed,password:"wrong"))
 }
}
