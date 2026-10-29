import XCTest
import AppKit
@testable import Isla
@MainActor final class LocalStoreTests: XCTestCase {
 func testFileDroppedDuringLoadIsRetained() async throws {
  let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
  defer { try? FileManager.default.removeItem(at: directory) }
  let store = LocalStore(directory: directory)
  let file = URL(fileURLWithPath:"/tmp/dropped-during-load.txt")
  store.addFiles([file])
  let deadline = Date().addingTimeInterval(2)
  while !store.loaded && Date() < deadline { try await Task.sleep(for:.milliseconds(10)) }
  XCTAssertTrue(store.loaded)
  XCTAssertEqual(store.document.files.map(\.url), [file])
  let saved = await store.flush()
  XCTAssertTrue(saved)
  let restored = try await store.repository.load()
  XCTAssertEqual(restored.files.map(\.url),[file])
 }
 func testDraggedFileProviderIsAccepted() async throws {
  let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
  defer { try? FileManager.default.removeItem(at: directory) }
  try FileManager.default.createDirectory(at:directory,withIntermediateDirectories:true)
  let file = directory.appendingPathComponent("drag.txt")
  try Data("test".utf8).write(to:file)
  let store = LocalStore(directory:directory.appendingPathComponent("data"))
  let provider = try XCTUnwrap(NSItemProvider(contentsOf:file))
  XCTAssertTrue(ShelfService.accept([provider],into:store))
  let deadline = Date().addingTimeInterval(2)
  while store.document.files.isEmpty && Date() < deadline { try await Task.sleep(for:.milliseconds(10)) }
  XCTAssertEqual(store.document.files.map(\.url),[file])
  _ = await store.flush()
 }

 func testImmediateQuitWaitsForLoadAndSavesDrop() async throws {
  let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
  defer { try? FileManager.default.removeItem(at:directory) }
  let store = LocalStore(directory:directory)
  let file = URL(fileURLWithPath:"/tmp/drop-before-quit.txt")
  store.addFiles([file])
  let saved = await store.flush()
  XCTAssertTrue(saved)
  let restored = try await store.repository.load()
  XCTAssertEqual(restored.files.map(\.url),[file])
 }

}
