import Foundation
public struct TodoItem: Codable, Identifiable, Equatable, Sendable {
 public var id: UUID
 public var title: String
 public var completed: Bool
 public init(title: String) { id = UUID(); self.title = title; completed = false }
}
public struct ShelfItem: Codable, Identifiable, Equatable, Sendable {
 public var id: UUID
 public var url: URL
 public init(url: URL) { id = UUID(); self.url = url.standardizedFileURL }
}
public struct LocalDocument: Codable, Equatable, Sendable {
 public var note = ""
 public var tasks: [TodoItem] = []
 public var files: [ShelfItem] = []
 public init() {}
 public mutating func addFile(_ url: URL) {
  guard url.isFileURL else { return }
  let normalized = url.standardizedFileURL
  if !files.contains(where: { $0.url.standardizedFileURL == normalized }) { files.append(ShelfItem(url: normalized)) }
 }
}
public actor LocalRepository {
 private let directory: URL
 private var file: URL { directory.appendingPathComponent("local.json") }
 public init(directory: URL) { self.directory = directory }
 public func load() throws -> LocalDocument {
  guard FileManager.default.fileExists(atPath: file.path) else { return LocalDocument() }
  return try JSONDecoder().decode(LocalDocument.self, from: Data(contentsOf: file))
 }
 public func save(_ document: LocalDocument) throws {
  try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
  let data = try JSONEncoder().encode(document)
  try data.write(to: file, options: .atomic)
 }
 @discardableResult public func recover() throws -> URL {
  let backup = directory.appendingPathComponent("local-backup-\(Int(Date().timeIntervalSince1970))-\(UUID().uuidString.prefix(8)).json")
  try FileManager.default.copyItem(at: file, to: backup)
  try save(LocalDocument())
  return backup
 }
}
