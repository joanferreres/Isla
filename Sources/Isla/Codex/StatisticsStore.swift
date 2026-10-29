import SwiftUI
import IslandCore
actor StatisticsRepository {
 let url:URL
 init() { url=FileManager.default.urls(for:.applicationSupportDirectory,in:.userDomainMask)[0].appendingPathComponent("Isla/codex-statistics.json") }
 func load() throws -> UsageHistory {
 guard FileManager.default.fileExists(atPath:url.path) else { return UsageHistory() }
 let data=try Data(contentsOf:url)
 do { return try JSONDecoder().decode(UsageHistory.self,from:data) } catch {
 let backup=url.deletingLastPathComponent().appendingPathComponent("codex-statistics-corrupt-\(UUID().uuidString).json")
 try FileManager.default.copyItem(at:url,to:backup);return UsageHistory()
 }
 }
 func save(_ history:UsageHistory) throws { try FileManager.default.createDirectory(at:url.deletingLastPathComponent(),withIntermediateDirectories:true);try JSONEncoder().encode(history).write(to:url,options:.atomic) }
}
@MainActor final class StatisticsStore:ObservableObject {
 @Published var history=UsageHistory()
 @Published var error:String?
 let repository=StatisticsRepository()
 var loaded=false
 var queuedReadings:[UsageSnapshot]=[]
 var queuedCompletions:[TurnCompletion]=[]
 var loadTask:Task<Void,Never>?
 var saveTask:Task<Void,Never>?
 init() {
 loadTask=Task { do { history=try await repository.load() } catch { self.error="No se pudo leer el historial de Codex." };loaded=true;for item in queuedReadings { history.record(item) };for item in queuedCompletions { history.record(item) };queuedReadings=[];queuedCompletions=[] }
 }
 func record(_ snapshot:UsageSnapshot) { if !loaded { queuedReadings.append(snapshot);return };history.record(snapshot);scheduleSave() }
 func record(_ completion:TurnCompletion) { if !loaded { queuedCompletions.append(completion);return };history.record(completion);scheduleSave() }
 func scheduleSave() { history.prune(before:Date().addingTimeInterval(-90*86400));saveTask?.cancel();saveTask=Task { try? await Task.sleep(for:.milliseconds(200));guard !Task.isCancelled else { return };_ = await flush() } }
 func flush() async -> Bool { await loadTask?.value;do { try await repository.save(history);return true } catch { self.error="No se pudo guardar el historial de Codex.";return false } }
}
