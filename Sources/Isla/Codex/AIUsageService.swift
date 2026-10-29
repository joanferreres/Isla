import SwiftUI
import IslandCore
import SQLite3
import Security
import LocalAuthentication

actor AICredentialReader {
 private var cachedClaude:Data?
 private var cachedUntil=Date.distantPast
 private let savedService="local.personal.isla.claude-session"
 private func silentKeychain(_ query:[CFString:Any]) -> (OSStatus,CFTypeRef?) {
 var allowed:DarwinBoolean=true;SecKeychainGetUserInteractionAllowed(&allowed);SecKeychainSetUserInteractionAllowed(false)
 defer { SecKeychainSetUserInteractionAllowed(allowed.boolValue) }
 var result:CFTypeRef?;let status=SecItemCopyMatching(query as CFDictionary,&result);return (status,result)
 }
 private func savedSession() -> Data? {
 let (_,result)=silentKeychain([kSecClass:kSecClassGenericPassword,kSecAttrService:savedService,kSecAttrAccount:"session",kSecReturnData:true,kSecMatchLimit:kSecMatchLimitOne])
 guard let data=result as? Data,let row=try? JSONSerialization.jsonObject(with:data) as? [String:Any],let oauth=row["claudeAiOauth"] as? [String:Any],let expiry=oauth["expiresAt"] as? NSNumber,expiry.doubleValue/1000>Date().timeIntervalSince1970 else { return nil };return data
 }
 private func saveSession(token:String,expiry:Date) {
 guard let data=try? JSONSerialization.data(withJSONObject:["claudeAiOauth":["accessToken":token,"expiresAt":expiry.timeIntervalSince1970*1000]]) else { return }
 let query:[CFString:Any]=[kSecClass:kSecClassGenericPassword,kSecAttrService:savedService,kSecAttrAccount:"session"]
 var allowed:DarwinBoolean=true;SecKeychainGetUserInteractionAllowed(&allowed);SecKeychainSetUserInteractionAllowed(false)
 defer { SecKeychainSetUserInteractionAllowed(allowed.boolValue) }
 if SecItemUpdate(query as CFDictionary,[kSecValueData:data] as CFDictionary) == errSecItemNotFound {
 var add=query;add[kSecValueData]=data;SecItemAdd(add as CFDictionary,nil)
 }
 }
 func forgetClaude() {
 cachedClaude=nil;cachedUntil = .distantPast
 var allowed:DarwinBoolean=true;SecKeychainGetUserInteractionAllowed(&allowed);SecKeychainSetUserInteractionAllowed(false)
 defer { SecKeychainSetUserInteractionAllowed(allowed.boolValue) }
 SecItemDelete([kSecClass:kSecClassGenericPassword,kSecAttrService:savedService,kSecAttrAccount:"session"] as CFDictionary)
 }
 func request(_ provider:AIProvider,interactive:Bool,home:URL=FileManager.default.homeDirectoryForCurrentUser) throws -> URLRequest {
 if provider == .cursor {
 let url=home.appendingPathComponent("Library/Application Support/Cursor/User/globalStorage/state.vscdb")
 var db:OpaquePointer?
 guard sqlite3_open_v2(url.path,&db,SQLITE_OPEN_READONLY | SQLITE_OPEN_NOMUTEX,nil) == SQLITE_OK else { if db != nil { sqlite3_close(db) };throw MusicFailure(message:"Inicia sesión en la app de Cursor.") }
 defer { sqlite3_close(db) }
 sqlite3_busy_timeout(db,1000)
 func value(_ key:String) -> String? {
 var statement:OpaquePointer?
 guard sqlite3_prepare_v2(db,"SELECT value FROM ItemTable WHERE key=?",-1,&statement,nil) == SQLITE_OK else { return nil }
 defer { sqlite3_finalize(statement) }
 sqlite3_bind_text(statement,1,key,-1,unsafeBitCast(-1,to:sqlite3_destructor_type.self))
 guard sqlite3_step(statement) == SQLITE_ROW,let text=sqlite3_column_text(statement,0) else { return nil }
 return String(cString:text)
 }
 guard let token=value("cursorAuth/accessToken"),!token.isEmpty else { throw MusicFailure(message:"Inicia sesión en la app de Cursor.") }
 var account=value("cursorAuth/stripeMembershipAuthId")
 if account?.isEmpty != false {
 let parts=token.split(separator:".")
 if parts.count>1 {
 var payload=String(parts[1]).replacingOccurrences(of:"-",with:"+").replacingOccurrences(of:"_",with:"/")
 payload += String(repeating:"=",count:(4-payload.count%4)%4)
 if let data=Data(base64Encoded:payload),let row=try? JSONSerialization.jsonObject(with:data) as? [String:Any] { account=row["sub"] as? String }
 }
 }
 guard let account,!account.isEmpty else { throw MusicFailure(message:"Vuelve a iniciar sesión en Cursor.") }
 var request=URLRequest(url:URL(string:"https://cursor.com/api/usage-summary")!)
 request.setValue("WorkosCursorSessionToken=\(account)::\(token)",forHTTPHeaderField:"Cookie")
 return request
 }
 let directory=ProcessInfo.processInfo.environment["CLAUDE_CONFIG_DIR"].map{URL(fileURLWithPath:$0)} ?? home.appendingPathComponent(".claude")
 var data=try? Data(contentsOf:directory.appendingPathComponent(".credentials.json"))
 if data == nil,Date()<cachedUntil { data=cachedClaude }
 if data == nil,home == FileManager.default.homeDirectoryForCurrentUser { data=savedSession() }
 if data == nil {
 // Legacy login-keychain items ignore LAContext. Disable interaction at the process level too.
 var wasAllowed:DarwinBoolean=true
 SecKeychainGetUserInteractionAllowed(&wasAllowed)
 SecKeychainSetUserInteractionAllowed(interactive)
 defer { SecKeychainSetUserInteractionAllowed(wasAllowed.boolValue) }
 // Enumerate metadata first, then read the newest item. Background refresh never opens a permission dialog.
 let context=LAContext();context.interactionNotAllowed=true
 let query:[CFString:Any]=[kSecClass:kSecClassGenericPassword,kSecAttrService:"Claude Code-credentials",kSecReturnAttributes:true,kSecReturnPersistentRef:true,kSecMatchLimit:kSecMatchLimitAll,kSecUseAuthenticationContext:context]
 var result:CFTypeRef?
 if SecItemCopyMatching(query as CFDictionary,&result) == errSecSuccess,let rows=result as? [[String:Any]],let newest=rows.sorted(by:{($0[kSecAttrModificationDate as String] as? Date ?? .distantPast)>($1[kSecAttrModificationDate as String] as? Date ?? .distantPast)}).first,let ref=newest[kSecValuePersistentRef as String] {
 context.interactionNotAllowed = !interactive
 let read:[CFString:Any]=[kSecClass:kSecClassGenericPassword,kSecValuePersistentRef:ref,kSecReturnData:true,kSecMatchLimit:kSecMatchLimitOne,kSecUseAuthenticationContext:context]
 var secret:CFTypeRef?
 if SecItemCopyMatching(read as CFDictionary,&secret) == errSecSuccess { data=secret as? Data }
 }
 }
 guard let data,let row=try? JSONSerialization.jsonObject(with:data) as? [String:Any],let oauth=row["claudeAiOauth"] as? [String:Any],let token=oauth["accessToken"] as? String,!token.isEmpty else { throw MusicFailure(message:"No se pudo leer la sesión de Claude Code. Conecta tu cuenta en Claude Code; Isla no repetirá peticiones de acceso.") }
 let expiry=(oauth["expiresAt"] as? NSNumber).map{Date(timeIntervalSince1970:$0.doubleValue/1000)} ?? Date().addingTimeInterval(300)
 guard expiry>Date() else { throw MusicFailure(message:"La sesión de Claude Code ha caducado. Inicia sesión de nuevo en Claude Code; conceder acceso al llavero no renueva la sesión.") }
 cachedClaude=data;cachedUntil=expiry
 if home == FileManager.default.homeDirectoryForCurrentUser { saveSession(token:token,expiry:expiry) }
 var request=URLRequest(url:URL(string:"https://api.anthropic.com/api/oauth/usage")!)
 request.setValue("Bearer \(token)",forHTTPHeaderField:"Authorization")
 request.setValue("oauth-2025-04-20",forHTTPHeaderField:"anthropic-beta")
 return request
 }
}
@MainActor final class AIUsageService:ObservableObject {
 let provider:AIProvider
 @Published var snapshot:UsageSnapshot?
 @Published var error:String?
 @Published var loading=false
 @Published var enabled=false
 @Published var stale=false
 @Published private(set) var accessRequested=false
 private let reader=AICredentialReader()
 private var timer:Timer?
 private var generation=0
 private var task:Task<Void,Never>?
 private var retryAfter=Date.distantPast
 init(_ provider:AIProvider) { self.provider=provider;accessRequested=provider == .claude && UserDefaults.standard.bool(forKey:"claudeAccessRequested") }
 func connect() { guard !enabled else { return };enabled=true;generation += 1;task=Task { await refresh() } }
 func disconnect() { enabled=false;generation += 1;task?.cancel();task=nil;timer?.invalidate();timer=nil;loading=false;stale=snapshot != nil }
 func refresh(interactive:Bool=false) async {
 guard enabled,!loading else { return }
 guard Date()>=retryAfter else { schedule();return }
 let g=generation;loading=true
 defer { if g == generation { loading=false;if enabled { schedule() } } }
 do {
 let mayAsk=interactive && provider == .claude && !accessRequested
 if mayAsk { accessRequested=true;UserDefaults.standard.set(true,forKey:"claudeAccessRequested") }
 var request=try await reader.request(provider,interactive:mayAsk)
 guard enabled,g == generation,!Task.isCancelled else { return }
 request.timeoutInterval=15;request.setValue("application/json",forHTTPHeaderField:"Accept")
 let (data,response)=try await URLSession.shared.data(for:request)
 guard enabled,g == generation,!Task.isCancelled else { return }
 let http=response as? HTTPURLResponse,code=http?.statusCode ?? 0
 if code == 429 { retryAfter=Date().addingTimeInterval(max(900,Double(http?.value(forHTTPHeaderField:"Retry-After") ?? "") ?? 0));throw MusicFailure(message:"\(provider.title) limita las consultas. Se actualizará más tarde.") }
 if provider == .claude,[401,403].contains(code) { await reader.forgetClaude() }
 guard code == 200 else { throw MusicFailure(message:[401,403].contains(code) ? "Abre \(provider.title == "Claude" ? "Claude Code" : provider.title) y renueva tu sesión." : "No se pudo consultar \(provider.title) (\(code)).") }
 snapshot=try AIUsageDecoder.decode(data,provider:provider,fetchedAt:Date());error=nil;stale=false
 } catch { guard enabled,g == generation,!Task.isCancelled else { return };self.error=error is MusicFailure || error is AIUsageDecoder.Failure ? error.localizedDescription : "No se pudo conectar con \(provider.title).";stale=snapshot != nil }
 }
 private func schedule() {
 timer?.invalidate()
 let delay=max(900,retryAfter.timeIntervalSinceNow)
 timer=Timer.scheduledTimer(withTimeInterval:delay,repeats:false) { [weak self] _ in Task { @MainActor in await self?.refresh() } };timer?.tolerance=60
 }
}
@MainActor final class AIUsageAccounts {
 static let shared=AIUsageAccounts()
 let cursor=AIUsageService(.cursor)
 let claude=AIUsageService(.claude)
 func apply(_ value:Preferences) { if value.cursorEnabled { cursor.connect() } else { cursor.disconnect() };if value.claudeEnabled { claude.connect() } else { claude.disconnect() } }
 func suspend() { cursor.disconnect();claude.disconnect() }
}
