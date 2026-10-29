import Foundation
import Combine
import IslandCore
@MainActor final class LocalStore: ObservableObject {
 @Published var document = LocalDocument() { didSet { if loaded && !needsRecovery { scheduleSave(delay: oldValue.tasks != document.tasks || oldValue.files != document.files ? 0 : 300) } } }
 @Published private(set) var loaded = false
 @Published private(set) var needsRecovery = false
 @Published private(set) var message: String?
 let repository: LocalRepository
 private var loadTask: Task<Void, Never>?
 private var queuedFiles: [URL] = []
 private var pending: Task<Void, Never>?
 init(directory: URL? = nil) {
  let root = directory ?? FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].appendingPathComponent("Isla")
  repository = LocalRepository(directory: root)
  loadTask = Task { do { document = try await repository.load(); loaded = true; drainQueuedFiles() } catch { needsRecovery = true; loaded = true; message = "No se pudieron leer los datos. El archivo original se conserva." } }
 }
 func scheduleSave(delay: Int = 0) {
  guard loaded, !needsRecovery else { return }
  pending?.cancel()
  pending = Task { [weak self] in
   try? await Task.sleep(for: .milliseconds(delay))
   guard !Task.isCancelled, let self else { return }
   _ = await self.write()
  }
 }
 @discardableResult private func write() async -> Bool {
  do { try await repository.save(document); message = nil; return true }
  catch { message = "No se pudieron guardar los cambios: \(error.localizedDescription)"; return false }
 }
 func flush() async -> Bool {
 pending?.cancel(); await loadTask?.value; pending?.cancel()
 guard loaded else { return false }
 if needsRecovery { return queuedFiles.isEmpty }
 return await write()
 }
 func recover() {
  Task { do {
   let backup = try await repository.recover()
   document = LocalDocument(); needsRecovery = false; drainQueuedFiles()
   message = "Copia del archivo anterior: \(backup.lastPathComponent)"
  } catch { message = "No se pudo conservar una copia: \(error.localizedDescription)" } }
 }
 func addTask(_ title: String) {
  let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
  guard !trimmed.isEmpty else { return }
  document.tasks.append(TodoItem(title: trimmed)); scheduleSave()
 }
 func addFiles(_ urls: [URL]) {
 guard loaded, !needsRecovery else { queuedFiles.append(contentsOf:urls); return }
 for url in urls { document.addFile(url) }; scheduleSave()
 }
 private func drainQueuedFiles() {
 let files = queuedFiles; queuedFiles.removeAll()
 if !files.isEmpty { addFiles(files) }
 }
 func removeFile(_ id: UUID) { document.files.removeAll { $0.id == id }; scheduleSave() }
 func clearFiles() { document.files.removeAll(); scheduleSave() }
}
