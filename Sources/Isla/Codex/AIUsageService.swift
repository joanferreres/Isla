import SwiftUI
import IslandCore
import SQLite3
import Security
import LocalAuthentication

/// Auth for Anthropic Messages / usage: Claude Code OAuth, or an Isla-stored / env API key.
enum ClaudeAPIAuth:Sendable {
 case oauth(token:String)
 case apiKey(String)
}

actor AICredentialReader {
 private var cachedClaude:Data?
 private var cachedUntil=Date.distantPast
 private var cachedCursorToken:String?
 private var cachedCursorSealed:String?
 private let savedService="local.personal.isla.claude-session"
 private let apiKeyService="local.personal.isla.anthropic-api-key"
 private let openAIKeyService="local.personal.isla.openai-api-key"
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
 private func keychainPassword(service:String,account:String,interactive:Bool) throws -> String {
  let base:[CFString:Any]=[kSecClass:kSecClassGenericPassword,kSecAttrService:service,kSecAttrAccount:account,kSecReturnData:true,kSecMatchLimit:kSecMatchLimitOne]
  let (silentStatus,silentResult)=silentKeychain(base)
  if silentStatus == errSecSuccess,let data=silentResult as? Data,let password=String(data:data,encoding:.utf8),!password.isEmpty { return password }
  guard interactive else {
   throw MusicFailure(message:service.hasPrefix("Cursor") ? "Permite a Isla usar «Cursor Safe Storage» del llavero (Ajustes → IA → Actualizar Cursor)." : "Permite el acceso al llavero para leer la sesión.")
  }
  var wasAllowed:DarwinBoolean=true
  SecKeychainGetUserInteractionAllowed(&wasAllowed)
  SecKeychainSetUserInteractionAllowed(true)
  defer { SecKeychainSetUserInteractionAllowed(wasAllowed.boolValue) }
  var result:CFTypeRef?
  let status=SecItemCopyMatching(base as CFDictionary,&result)
  guard status == errSecSuccess,let data=result as? Data,let password=String(data:data,encoding:.utf8),!password.isEmpty else {
   throw MusicFailure(message:status == errSecUserCanceled ? "Se canceló el acceso al llavero." : "No se pudo leer «\(service)» del llavero.")
  }
  return password
 }
 private func unwrapCursorToken(_ sealed:String,interactive:Bool,password:String?) throws -> String {
  guard sealed.hasPrefix(ElectronSafeStorage.cursorPrefix) else { return sealed }
  if sealed == cachedCursorSealed,let cachedCursorToken { return cachedCursorToken }
  let secret=try password ?? keychainPassword(service:"Cursor Safe Storage",account:"Cursor Key",interactive:interactive)
  let token=try ElectronSafeStorage.unwrap(sealed,password:secret)
  cachedCursorSealed=sealed
  cachedCursorToken=token
  return token
 }
 private func jwtSubject(_ token:String) -> String? {
  let parts=token.split(separator:".")
  guard parts.count>1 else { return nil }
  var payload=String(parts[1]).replacingOccurrences(of:"-",with:"+").replacingOccurrences(of:"_",with:"/")
  payload += String(repeating:"=",count:(4-payload.count%4)%4)
  guard let data=Data(base64Encoded:payload),let row=try? JSONSerialization.jsonObject(with:data) as? [String:Any] else { return nil }
  return row["sub"] as? String
 }
 private func claudeOAuthPayload(_ data:Data) -> (token:String,expiry:Date,empty:Bool)? {
  guard let row=try? JSONSerialization.jsonObject(with:data) as? [String:Any],let oauth=row["claudeAiOauth"] as? [String:Any] else { return nil }
  let token=oauth["accessToken"] as? String ?? ""
  let expiry=(oauth["expiresAt"] as? NSNumber).map{Date(timeIntervalSince1970:$0.doubleValue/1000)} ?? Date().addingTimeInterval(300)
  return (token,expiry,token.isEmpty)
 }
 func request(_ provider:AIProvider,interactive:Bool,home:URL=FileManager.default.homeDirectoryForCurrentUser,cursorSafePassword:String?=nil) throws -> URLRequest {
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
   guard let sealed=value("cursorAuth/accessToken"),!sealed.isEmpty else { throw MusicFailure(message:"Inicia sesión en la app de Cursor.") }
   let token:String
   do { token=try unwrapCursorToken(sealed,interactive:interactive,password:cursorSafePassword) }
   catch let failure as MusicFailure { throw failure }
   catch { throw MusicFailure(message:"Cursor cifró la sesión y no se pudo leer. Abre Cursor, confirma el inicio de sesión y pulsa Actualizar en Isla.") }
   var account=value("cursorAuth/stripeMembershipAuthId")
   if account?.isEmpty != false { account=jwtSubject(token) }
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
  if let data,let oauth=claudeOAuthPayload(data),!oauth.empty,oauth.expiry>Date() {
   cachedClaude=data;cachedUntil=oauth.expiry
   if home == FileManager.default.homeDirectoryForCurrentUser { saveSession(token:oauth.token,expiry:oauth.expiry) }
   var request=URLRequest(url:URL(string:"https://api.anthropic.com/api/oauth/usage")!)
   request.setValue("Bearer \(oauth.token)",forHTTPHeaderField:"Authorization")
   request.setValue("oauth-2025-04-20",forHTTPHeaderField:"anthropic-beta")
   return request
  }
  // Empty/expired Claude Code-credentials (common when Claude Code uses ANTHROPIC_API_KEY only).
  if data != nil { forgetClaude() }
  if anthropicAPIKey() != nil {
   throw MusicFailure(message:"Claude Code está con API key (sin OAuth). El EQ funciona; para ver límites en Isla ejecuta «claude auth login».")
  }
  throw MusicFailure(message:interactive
   ? "No hay sesión OAuth de Claude Code ni API key. Ejecuta «claude auth login» o pega una key sk-ant- en Ajustes → Música."
   : "No hay sesión OAuth de Claude Code. Pulsa «Permitir acceso a Claude», ejecuta «claude auth login», o pega una API key en Ajustes → Música.")
 }

 /// Credential for calling Anthropic Messages (auto-EQ, etc.).
 /// Order: Claude Code OAuth → Isla keychain → process env → login-shell `ANTHROPIC_API_KEY`.
 func claudeAPIAuth(interactive:Bool=false,home:URL=FileManager.default.homeDirectoryForCurrentUser) throws -> ClaudeAPIAuth {
  if let oauth=try? claudeOAuthToken(interactive:interactive,home:home) {
   return .oauth(token:oauth)
  }
  if let key=anthropicAPIKey() { return .apiKey(key) }
  throw MusicFailure(message:"""
  Auto-EQ con Claude necesita autenticación.
  1) Preferido: «claude auth login» (Claude Code) y permitir el llavero en Isla → IA → Claude.
  2) O pega una API key de Anthropic (sk-ant-…) en Ajustes → Música → EQ con IA.
  3) O define ANTHROPIC_API_KEY en tu shell de login (~/.zshrc); Isla la importa al llavero.
  """)
 }

 /// Any Anthropic API key Isla can use (keychain, env, or login shell).
 func anthropicAPIKey() -> String? {
  if let key=storedSecret(service:apiKeyService),!key.isEmpty { return key }
  if let key=ProcessInfo.processInfo.environment["ANTHROPIC_API_KEY"]?
   .trimmingCharacters(in:.whitespacesAndNewlines),!key.isEmpty {
   try? storeSecret(key,service:apiKeyService)
   return key
  }
  if let key=loginShellAnthropicAPIKey() {
   try? storeSecret(key,service:apiKeyService)
   return key
  }
  return nil
 }

 /// GUI apps don't inherit ~/.zshrc — read ANTHROPIC_API_KEY from a login shell once.
 private func loginShellAnthropicAPIKey() -> String? {
  let shell=ProcessInfo.processInfo.environment["SHELL"].flatMap{ $0.isEmpty ? nil : $0 } ?? "/bin/zsh"
  let process=Process()
  process.executableURL=URL(fileURLWithPath:shell)
  process.arguments=["-l","-c","printenv ANTHROPIC_API_KEY"]
  let pipe=Pipe();process.standardOutput=pipe;process.standardError=FileHandle.nullDevice
  do { try process.run() } catch { return nil }
  let data=pipe.fileHandleForReading.readDataToEndOfFile()
  process.waitUntilExit()
  guard process.terminationStatus == 0,
        let key=String(data:data,encoding:.utf8)?
   .trimmingCharacters(in:.whitespacesAndNewlines),
        key.hasPrefix("sk-ant-"),key.count>20 else { return nil }
  return key
 }

 /// OpenAI / ChatGPT API key for music AI EQ fallback.
 func openAIAPIKey() throws -> String {
  if let key=storedSecret(service:openAIKeyService),!key.isEmpty { return key }
  if let key=ProcessInfo.processInfo.environment["OPENAI_API_KEY"]?
   .trimmingCharacters(in:.whitespacesAndNewlines),!key.isEmpty {
   return key
  }
  throw MusicFailure(message:"Falta la API key de ChatGPT. Pégala en Ajustes → Música → EQ con IA, o exporta OPENAI_API_KEY.")
 }

 func hasStoredAnthropicAPIKey() -> Bool { storedSecret(service:apiKeyService)?.isEmpty == false }
 func hasStoredOpenAIAPIKey() -> Bool { storedSecret(service:openAIKeyService)?.isEmpty == false }

 func saveAnthropicAPIKey(_ key:String) throws {
  let trimmed=key.trimmingCharacters(in:.whitespacesAndNewlines)
  guard trimmed.hasPrefix("sk-ant-"),trimmed.count>20 else {
   throw MusicFailure(message:"La API key de Anthropic debe empezar por sk-ant-.")
  }
  try storeSecret(trimmed,service:apiKeyService)
 }

 func saveOpenAIAPIKey(_ key:String) throws {
  let trimmed=key.trimmingCharacters(in:.whitespacesAndNewlines)
  guard trimmed.hasPrefix("sk-"),!trimmed.hasPrefix("sk-ant-"),trimmed.count>20 else {
   throw MusicFailure(message:"La API key de OpenAI/ChatGPT debe empezar por sk- (no sk-ant-).")
  }
  try storeSecret(trimmed,service:openAIKeyService)
 }

 func clearAnthropicAPIKey() { clearSecret(service:apiKeyService) }
 func clearOpenAIAPIKey() { clearSecret(service:openAIKeyService) }

 private func storeSecret(_ value:String,service:String) throws {
  let query:[CFString:Any]=[kSecClass:kSecClassGenericPassword,kSecAttrService:service,kSecAttrAccount:"api-key"]
  var allowed:DarwinBoolean=true;SecKeychainGetUserInteractionAllowed(&allowed);SecKeychainSetUserInteractionAllowed(false)
  defer { SecKeychainSetUserInteractionAllowed(allowed.boolValue) }
  let data=Data(value.utf8)
  if SecItemUpdate(query as CFDictionary,[kSecValueData:data] as CFDictionary) == errSecItemNotFound {
   var add=query;add[kSecValueData]=data;add[kSecAttrAccessible]=kSecAttrAccessibleAfterFirstUnlock
   let status=SecItemAdd(add as CFDictionary,nil)
   guard status == errSecSuccess || status == errSecDuplicateItem else {
    throw MusicFailure(message:"No se pudo guardar la API key en el llavero.")
   }
  }
 }

 private func clearSecret(service:String) {
  var allowed:DarwinBoolean=true;SecKeychainGetUserInteractionAllowed(&allowed);SecKeychainSetUserInteractionAllowed(false)
  defer { SecKeychainSetUserInteractionAllowed(allowed.boolValue) }
  SecItemDelete([kSecClass:kSecClassGenericPassword,kSecAttrService:service,kSecAttrAccount:"api-key"] as CFDictionary)
 }

 private func storedSecret(service:String) -> String? {
  let (status,result)=silentKeychain([kSecClass:kSecClassGenericPassword,kSecAttrService:service,kSecAttrAccount:"api-key",kSecReturnData:true,kSecMatchLimit:kSecMatchLimitOne])
  guard status == errSecSuccess,let data=result as? Data,let key=String(data:data,encoding:.utf8) else { return nil }
  let trimmed=key.trimmingCharacters(in:.whitespacesAndNewlines)
  return trimmed.isEmpty ? nil : trimmed
 }

 private func claudeOAuthToken(interactive:Bool,home:URL) throws -> String {
  // Only return a live OAuth bearer — never the API-key fallback path from request(.claude).
  let directory=ProcessInfo.processInfo.environment["CLAUDE_CONFIG_DIR"].map{URL(fileURLWithPath:$0)} ?? home.appendingPathComponent(".claude")
  var data=try? Data(contentsOf:directory.appendingPathComponent(".credentials.json"))
  if data == nil,Date()<cachedUntil { data=cachedClaude }
  if data == nil,home == FileManager.default.homeDirectoryForCurrentUser { data=savedSession() }
  if data == nil {
   var wasAllowed:DarwinBoolean=true
   SecKeychainGetUserInteractionAllowed(&wasAllowed)
   SecKeychainSetUserInteractionAllowed(interactive)
   defer { SecKeychainSetUserInteractionAllowed(wasAllowed.boolValue) }
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
  guard let data,let oauth=claudeOAuthPayload(data),!oauth.empty,oauth.expiry>Date() else {
   throw MusicFailure(message:"Sin sesión OAuth válida de Claude Code.")
  }
  cachedClaude=data;cachedUntil=oauth.expiry
  return oauth.token
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
   // Cursor may need one keychain prompt for «Cursor Safe Storage»; Claude may need «Claude Code-credentials».
   let mayAsk=interactive
   if mayAsk,provider == .claude { accessRequested=true;UserDefaults.standard.set(true,forKey:"claudeAccessRequested") }
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
  } catch { guard enabled,g == generation,!Task.isCancelled else { return };self.error=error is MusicFailure || error is AIUsageDecoder.Failure || error is ElectronSafeStorage.Failure ? error.localizedDescription : "No se pudo conectar con \(provider.title).";stale=snapshot != nil }
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
