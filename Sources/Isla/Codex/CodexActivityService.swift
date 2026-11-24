import SwiftUI
import IslandCore
@MainActor final class CodexActivityService:ObservableObject {
 @Published var activeCount=0
 @Published var latest:TurnCompletion?
 @Published var completionPulse:UUID?
 /// Whose turn triggered the current pulse (drives the alert colour).
 @Published var completionSource:AlertSource = .codex
 @Published var enabled=false
 @Published var foundSessions=0
 var tracker=CodexTurnTracker()
 let reader=CodexSessionReader()
 let claudeReader=ClaudeSessionReader()
 var watchesCodex=true
 var watchesClaude=false
 var timer:Timer?
 var refreshing=false
 var generation=0
 var onCompletion:((TurnCompletion) -> Void)?
 var soundEnabled=true
 var completionHighlightEnabled=true
 var completionNoticeEnabled=true
 private let playSound:() -> Void
 init(playSound:@escaping () -> Void={NSSound(named:"Glass")?.play()}) { self.playSound=playSound }
 func previewNotification(source:AlertSource = .codex) {
 completionSource=source
 if completionHighlightEnabled { completionPulse=UUID() }
 if soundEnabled { playSound() }
 }
 func announce(_ completion:TurnCompletion) {
 if completionNoticeEnabled { latest=completion };onCompletion?(completion);previewNotification(source:completion.source ?? .codex)
 Task { try? await Task.sleep(for:.seconds(5));if latest == completion { latest=nil } }
 }
 func connect() { guard !enabled else { return };enabled=true;generation += 1;timer=Timer.scheduledTimer(withTimeInterval:2,repeats:true) { [weak self] _ in Task { @MainActor in await self?.refresh() } };timer?.tolerance=0.4;Task { await refresh() } }
 func pauseForSleep() { enabled=false;generation += 1;timer?.invalidate();timer=nil }
 func disconnect() { enabled=false;generation += 1;timer?.invalidate();timer=nil;tracker=CodexTurnTracker();activeCount=0;latest=nil;Task { await reader.reset();await claudeReader.reset() } }
 func refresh() async {
 guard enabled,!refreshing else { return };refreshing=true;defer { refreshing=false };let g=generation
 if watchesClaude {
 let finished=await claudeReader.scan();guard enabled,g == generation else { return }
 for completion in finished { announce(completion) }
 }
 guard watchesCodex else { return }
 let result=await reader.scan();guard enabled,g == generation else { return }
 tracker.seed(result.seed);if foundSessions != result.found { foundSessions=result.found }
 for event in result.events { if let completion=tracker.consume(event) { announce(completion) } }
 if activeCount != tracker.active.count { activeCount=tracker.active.count }
 }
 func open(_ source:AlertSource) {
 let bundle:String
 switch source { case .codex:bundle="com.openai.codex";case .claude:bundle="com.anthropic.claudefordesktop";case .cursor:bundle="com.todesktop.230313mzl4w4u92" }
 if let url=NSWorkspace.shared.urlForApplication(withBundleIdentifier:bundle) { NSWorkspace.shared.open(url) }
 }
 func openCodex() { if let url=NSWorkspace.shared.urlForApplication(withBundleIdentifier:"com.openai.codex") { NSWorkspace.shared.open(url) } }
}
