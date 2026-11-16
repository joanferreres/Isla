import XCTest
import AppKit
@testable import Isla
@MainActor final class LocalStoreTests: XCTestCase {
 func testShelfExportsAnActualFileForFinderAndSharing() async throws {
  let file=FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString+".txt")
  try Data("tray export".utf8).write(to:file)
  defer { try? FileManager.default.removeItem(at:file) }
  let provider=ShelfService.dragProvider(for:file)
  XCTAssertEqual(provider.suggestedName,file.lastPathComponent)
  let exported:URL=try await withCheckedThrowingContinuation { continuation in
   provider.loadInPlaceFileRepresentation(forTypeIdentifier:"public.item") { url,_,error in
    if let error { continuation.resume(throwing:error) }
    else if let url { continuation.resume(returning:url) }
    else { continuation.resume(throwing:CocoaError(.fileReadUnknown)) }
   }
  }
  XCTAssertEqual(try Data(contentsOf:exported),Data("tray export".utf8))
  XCTAssertTrue(FileManager.default.fileExists(atPath:file.path))
 }
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
 func testDraggedFilePasteboardIsAccepted() async throws {
  let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
  defer { try? FileManager.default.removeItem(at: directory) }
  try FileManager.default.createDirectory(at:directory,withIntermediateDirectories:true)
  let file = directory.appendingPathComponent("drag.txt")
  try Data("test".utf8).write(to:file)
  let store = LocalStore(directory:directory.appendingPathComponent("data"))
  let pasteboard=NSPasteboard.withUniqueName()
  defer { pasteboard.releaseGlobally() }
  XCTAssertTrue(pasteboard.writeObjects([file as NSURL]))
  store.addFiles(ShelfService.fileURLs(from:pasteboard))
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
