import XCTest
@testable import IslandCore
@MainActor final class LocalDocumentTests: XCTestCase {
 func testShelfDeduplicates() {
  var document = LocalDocument()
  document.addFile(URL(fileURLWithPath: "/tmp/a.txt"))
  document.addFile(URL(fileURLWithPath: "/tmp/./a.txt"))
  XCTAssertEqual(document.files.count, 1)
 }
 func testDocumentRoundTrip() throws {
  var document = LocalDocument()
  document.note = "Nota personal\nSegunda línea"
  document.tasks = [TodoItem(title: "Revisar archivo")]
  let restored = try JSONDecoder().decode(LocalDocument.self, from: JSONEncoder().encode(document))
  XCTAssertEqual(restored.note, document.note)
  XCTAssertEqual(restored.tasks.first?.title, "Revisar archivo")
 }
 func testCorruptionPreservedAndRecoveryBackedUp() async throws {
  let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
  defer { try? FileManager.default.removeItem(at: directory) }
  try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
  let file = directory.appendingPathComponent("local.json")
  let original = Data("{truncated".utf8)
  try original.write(to: file)
  let repository = LocalRepository(directory: directory)
  do { _ = try await repository.load(); XCTFail("Corruption must throw") } catch { }
  XCTAssertEqual(try Data(contentsOf: file), original)
  let backup = try await repository.recover()
  XCTAssertEqual(try Data(contentsOf: backup), original)
  let restored = try await repository.load()
  XCTAssertEqual(restored.note, "")
 }
 func testRepositoryPersistsAllLocalContent() async throws {
  let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
  defer { try? FileManager.default.removeItem(at: directory) }
  let repository = LocalRepository(directory: directory)
  var document = LocalDocument(); document.note = "Guardada"; document.tasks = [TodoItem(title: "Hecha")]
  document.tasks[0].completed = true; document.addFile(URL(fileURLWithPath: "/tmp/ref.txt"))
  try await repository.save(document)
  let restored = try await repository.load()
  XCTAssertEqual(restored.note, document.note)
  XCTAssertTrue(restored.tasks[0].completed)
  XCTAssertEqual(restored.files[0].url.path, "/tmp/ref.txt")
 }
}
