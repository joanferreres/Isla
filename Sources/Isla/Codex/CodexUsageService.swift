import SwiftUI
import IslandCore
struct CodexCredential:Sendable { var token:String;var account:String }
actor CodexCredentialReader {
 func load() throws -> CodexCredential {
 let root=ProcessInfo.processInfo.environment["CODEX_HOME"].map{URL(fileURLWithPath:$0)} ?? FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".codex")
 guard let data=try? Data(contentsOf:root.appendingPathComponent("auth.json")),let row=try? JSONSerialization.jsonObject(with:data) as? [String:Any],let tokens=row["tokens"] as? [String:Any],let access=tokens["access_token"] as? String,!access.isEmpty,let account=tokens["account_id"] as? String,!account.isEmpty else { throw MusicFailure(message:"Inicia sesión en Codex para consultar tu uso.") }
 return CodexCredential(token:access,account:account)
 }
}
@MainActor final class CodexUsageService:ObservableObject {
 @Published var snapshot:UsageSnapshot?
 @Published var error:String?
 @Published var loading=false
 @Published var enabled=false
 @Published var stale=false
 let credentials=CodexCredentialReader()
 var timer:Timer?
 var generation=0
 var failures=0
 var nextRefresh=Date.distantPast
 var onSnapshot:((UsageSnapshot) -> Void)?
 func connect() { guard !enabled else { return };enabled=true;generation += 1;Task { await refresh() } }
 private func scheduleNext() {
 timer?.invalidate()
 let delay=max(5,nextRefresh.timeIntervalSinceNow)
 timer=Timer.scheduledTimer(withTimeInterval:delay,repeats:false) { [weak self] _ in Task { @MainActor in await self?.refresh() } }
 timer?.tolerance=min(30,delay*0.1)
 }
 func disconnect() { enabled=false;generation += 1;timer?.invalidate();timer=nil;loading=false;stale=snapshot != nil }
 func refresh() async {
 guard enabled,!loading else { return };loading=true;defer{loading=false;if enabled { scheduleNext() }};let g=generation
 do {
 let credential=try await credentials.load()
 guard enabled,g == generation else { return }
 var request=URLRequest(url:URL(string:"https://chatgpt.com/backend-api/wham/usage")!);request.timeoutInterval=15
 request.setValue("Bearer \(credential.token)",forHTTPHeaderField:"Authorization");request.setValue(credential.account,forHTTPHeaderField:"ChatGPT-Account-Id");request.setValue("application/json",forHTTPHeaderField:"Accept")
 let (data,response)=try await URLSession.shared.data(for:request)
 guard enabled,g == generation else { return }
 guard let http=response as? HTTPURLResponse,http.statusCode == 200 else { let code=(response as? HTTPURLResponse)?.statusCode ?? 0;throw MusicFailure(message:[401,403].contains(code) ? "Vuelve a iniciar sesión en Codex para consultar el uso." : "Codex no pudo proporcionar el uso (\(code)).") }
 let result=try CodexUsageDecoder.decode(data,fetchedAt:Date())
 snapshot=result;stale=false;error=nil;failures=0;nextRefresh=Date().addingTimeInterval(300);onSnapshot?(result)
 } catch { guard enabled,g == generation else { return };self.error=error.localizedDescription;stale=snapshot != nil;failures += 1;nextRefresh=Date().addingTimeInterval(failures == 1 ? 60 : failures == 2 ? 300 : 900) }
 }
}
