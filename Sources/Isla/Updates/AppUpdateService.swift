import AppKit
import Combine
import IslandCore

@MainActor final class AppUpdateService:ObservableObject {
 typealias Fetch = @Sendable (URLRequest) async throws -> (Data,HTTPURLResponse)
 static let interval:TimeInterval=7*24*60*60
 static let endpoint=URL(string:"https://api.github.com/repos/joanferreres/Isla/releases/latest")!
 let currentVersion:String
 @Published private(set) var available:AppUpdate?
 @Published private(set) var checking=false
 @Published private(set) var lastChecked:Date?
 @Published private(set) var error:String?
 @Published var automaticChecksEnabled:Bool {
 didSet { defaults.set(automaticChecksEnabled,forKey:"updates.automatic");if automaticChecksEnabled { start() } else { suspend() } }
 }
 var onAvailable:(() -> Void)?
 private let defaults:UserDefaults
 private let fetch:Fetch
 private var timer:Timer?
 private var task:Task<Void,Never>?
 private var paused=true
 private var generation=0
 init(currentVersion:String=Bundle.main.object(forInfoDictionaryKey:"CFBundleShortVersionString") as? String ?? "0.0.0",defaults:UserDefaults = .standard,fetch:@escaping Fetch=AppUpdateService.load) {
 self.currentVersion=currentVersion;self.defaults=defaults;self.fetch=fetch
 automaticChecksEnabled=defaults.object(forKey:"updates.automatic") as? Bool ?? true
 lastChecked=defaults.object(forKey:"updates.lastChecked") as? Date
 if let data=defaults.data(forKey:"updates.cached") {
 if let decoded=try? JSONDecoder().decode(AppUpdate.self,from:data),let update=AppUpdate(tag:decoded.tag,pageURL:decoded.pageURL) {
 if update.isNewer(than:currentVersion) { available=update }
 } else { defaults.removeObject(forKey:"updates.cached");defaults.removeObject(forKey:"updates.etag") }
 }
 }
 nonisolated private static func load(_ request:URLRequest) async throws -> (Data,HTTPURLResponse) {
 let session=URLSession(configuration:.ephemeral)
 defer { session.finishTasksAndInvalidate() }
 let (data,response)=try await session.data(for:request)
 guard let response=response as? HTTPURLResponse else { throw URLError(.badServerResponse) }
 return (data,response)
 }
 func start() {
 suspend();paused=false
 guard automaticChecksEnabled else { return }
 if available != nil { onAvailable?() }
 schedule()
 }
 func suspend() {
 paused=true;generation += 1;timer?.invalidate();timer=nil;task?.cancel();task=nil;checking=false
 }
 private func schedule() {
 timer?.invalidate();timer=nil
 guard !paused,automaticChecksEnabled else { return }
 let attempted=defaults.object(forKey:"updates.lastAttempt") as? Date ?? .distantPast
 let delay=max(5,Self.interval-Date().timeIntervalSince(attempted))
 timer=Timer.scheduledTimer(withTimeInterval:delay,repeats:false) { [weak self] _ in
 Task { @MainActor [weak self] in
 guard let self else { return }
 self.task=Task { [weak self] in await self?.check() }
 }
 }
 timer?.tolerance=min(900,delay*0.1)
 }
 func check(force:Bool=false) async {
 guard !checking else { return }
 if !force {
 guard automaticChecksEnabled,!paused else { return }
 if let last=defaults.object(forKey:"updates.lastAttempt") as? Date,Date().timeIntervalSince(last) < Self.interval { schedule();return }
 }
 checking=true;error=nil;let token=generation
 defaults.set(Date(),forKey:"updates.lastAttempt")
 defer { if token == generation { checking=false;schedule() } }
 var request=URLRequest(url:Self.endpoint,cachePolicy:.reloadIgnoringLocalCacheData,timeoutInterval:15)
 request.setValue("application/vnd.github+json",forHTTPHeaderField:"Accept")
 request.setValue("Isla/\(currentVersion)",forHTTPHeaderField:"User-Agent")
 // A conditional response is useful only while its corresponding payload is cached.
 if defaults.data(forKey:"updates.cached") != nil,let etag=defaults.string(forKey:"updates.etag") { request.setValue(etag,forHTTPHeaderField:"If-None-Match") }
 do {
 let (data,response)=try await fetch(request)
 guard !Task.isCancelled,token == generation else { return }
 switch response.statusCode {
 case 200:
 let update=try AppUpdate.decodeLatest(data)
 if let update {
 defaults.set(try JSONEncoder().encode(update),forKey:"updates.cached")
 if let etag=response.value(forHTTPHeaderField:"ETag") { defaults.set(etag,forKey:"updates.etag") } else { defaults.removeObject(forKey:"updates.etag") }
 available=update.isNewer(than:currentVersion) ? update : nil
 } else {
 available=nil;defaults.removeObject(forKey:"updates.cached");defaults.removeObject(forKey:"updates.etag")
 }
 case 304: break
 case 404:
 available=nil;defaults.removeObject(forKey:"updates.cached");defaults.removeObject(forKey:"updates.etag")
 default: throw URLError(.badServerResponse)
 }
 lastChecked=Date();defaults.set(lastChecked,forKey:"updates.lastChecked")
 if available != nil,!force { onAvailable?() }
 } catch {
 guard !Task.isCancelled,token == generation else { return }
 self.error="No se pudo comprobar GitHub. Inténtalo más tarde."
 }
 }
 func claimAutomaticNotice() -> AppUpdate? {
 guard let available,defaults.string(forKey:"updates.notified") != available.tag else { return nil }
 defaults.set(available.tag,forKey:"updates.notified");return available
 }
 func openDownload() { if let available { NSWorkspace.shared.open(available.pageURL) } }
}
