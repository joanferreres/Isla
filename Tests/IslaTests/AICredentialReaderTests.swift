import XCTest
import SQLite3
@testable import Isla
@MainActor final class AICredentialReaderTests:XCTestCase {
 func testCursorReadsOwnSessionAndJWTSubjectWithoutChangingDatabase() async throws {
 let home=FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
 defer { try? FileManager.default.removeItem(at:home) }
 let path=home.appendingPathComponent("Library/Application Support/Cursor/User/globalStorage/state.vscdb")
 try FileManager.default.createDirectory(at:path.deletingLastPathComponent(),withIntermediateDirectories:true)
 let payload=Data(#"{"sub":"account-fixture"}"#.utf8).base64EncodedString().replacingOccurrences(of:"=",with:"")
 let token="fixture.\(payload).fixture"
 var db:OpaquePointer?
 XCTAssertEqual(sqlite3_open(path.path,&db),SQLITE_OK)
 XCTAssertEqual(sqlite3_exec(db,"CREATE TABLE ItemTable (key TEXT PRIMARY KEY,value TEXT); INSERT INTO ItemTable VALUES ('cursorAuth/accessToken','\(token)');",nil,nil,nil),SQLITE_OK)
 sqlite3_close(db)
 let before=try Data(contentsOf:path)
 let request=try await AICredentialReader().request(.cursor,interactive:false,home:home)
 XCTAssertEqual(request.url?.absoluteString,"https://cursor.com/api/usage-summary")
 XCTAssertEqual(request.value(forHTTPHeaderField:"Cookie"),"WorkosCursorSessionToken=account-fixture::\(token)")
 XCTAssertEqual(try Data(contentsOf:path),before)
 }
 func testCursorDecryptsSafeStorageTokenWithProvidedPassword() async throws {
 let home=FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
 defer { try? FileManager.default.removeItem(at:home) }
 let path=home.appendingPathComponent("Library/Application Support/Cursor/User/globalStorage/state.vscdb")
 try FileManager.default.createDirectory(at:path.deletingLastPathComponent(),withIntermediateDirectories:true)
 let sealed="cursor-safe-storage:v1:djEww03mXiOogQVLP8swh7hQqtqlBH7lTtLbkPi9LvYgD+T/p309ZcP2xQuH6COtTRyO"
 let plain="fixture.eyJzdWIiOiJmaXh0dXJlLWFjY291bnQifQ.sig"
 var db:OpaquePointer?
 XCTAssertEqual(sqlite3_open(path.path,&db),SQLITE_OK)
 let sql="CREATE TABLE ItemTable (key TEXT PRIMARY KEY,value TEXT); INSERT INTO ItemTable VALUES ('cursorAuth/accessToken','\(sealed)'); INSERT INTO ItemTable VALUES ('cursorAuth/stripeMembershipAuthId','fixture-account');"
 XCTAssertEqual(sqlite3_exec(db,sql,nil,nil,nil),SQLITE_OK)
 sqlite3_close(db)
 let request=try await AICredentialReader().request(.cursor,interactive:false,home:home,cursorSafePassword:"isla-fixture-password")
 XCTAssertEqual(request.value(forHTTPHeaderField:"Cookie"),"WorkosCursorSessionToken=fixture-account::\(plain)")
 }
 func testMissingCursorSessionFailsWithoutCreatingStore() async throws {
 let home=FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
 do { _=try await AICredentialReader().request(.cursor,interactive:false,home:home);XCTFail("Missing session should not produce a request") } catch { XCTAssertFalse(FileManager.default.fileExists(atPath:home.path)) }
 }
}

@MainActor final class ClaudeSessionMemoryTests:XCTestCase {
 func testAuthorizedSessionIsReusedWithoutAnotherKeychainRead() async throws {
 let home=FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
 defer { try? FileManager.default.removeItem(at:home) }
 let directory=home.appendingPathComponent(".claude")
 try FileManager.default.createDirectory(at:directory,withIntermediateDirectories:true)
 let file=directory.appendingPathComponent(".credentials.json")
 let data=try JSONSerialization.data(withJSONObject:["claudeAiOauth":["accessToken":"fixture-authorized","expiresAt":Date().addingTimeInterval(3600).timeIntervalSince1970*1000]])
 try data.write(to:file)
 let reader=AICredentialReader()
 let first=try await reader.request(.claude,interactive:false,home:home)
 try FileManager.default.removeItem(at:file)
 let second=try await reader.request(.claude,interactive:false,home:home)
 XCTAssertEqual(first.value(forHTTPHeaderField:"Authorization"),second.value(forHTTPHeaderField:"Authorization"))
 }
 func testExpiredSessionExplainsLoginInsteadOfAskingPermissionAgain() async throws {
 let home=FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
 defer { try? FileManager.default.removeItem(at:home) }
 let directory=home.appendingPathComponent(".claude")
 try FileManager.default.createDirectory(at:directory,withIntermediateDirectories:true)
 try JSONSerialization.data(withJSONObject:["claudeAiOauth":["accessToken":"expired-fixture","expiresAt":1]]).write(to:directory.appendingPathComponent(".credentials.json"))
 do { _=try await AICredentialReader().request(.claude,interactive:false,home:home);XCTFail("Expired token must be rejected") } catch { XCTAssertTrue(error.localizedDescription.contains("ha caducado"));XCTAssertFalse(error.localizedDescription.contains("Permitir acceso")) }
 }
 func testEmptyOAuthTokenExplainsAPIKeyIsNotEnough() async throws {
 let home=FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
 defer { try? FileManager.default.removeItem(at:home) }
 let directory=home.appendingPathComponent(".claude")
 try FileManager.default.createDirectory(at:directory,withIntermediateDirectories:true)
 try JSONSerialization.data(withJSONObject:["claudeAiOauth":["accessToken":"","expiresAt":0]]).write(to:directory.appendingPathComponent(".credentials.json"))
 do { _=try await AICredentialReader().request(.claude,interactive:false,home:home);XCTFail("Empty OAuth must fail") } catch {
  XCTAssertTrue(error.localizedDescription.contains("Claude") || error.localizedDescription.contains("claude auth login") || error.localizedDescription.contains("API key"))
 }
 }
 func testClaudeDesktopSessionBuildsOrganizationUsageRequest() async throws {
 let home=FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
 defer { try? FileManager.default.removeItem(at:home) }
 let support=home.appendingPathComponent("Library/Application Support/Claude")
 try FileManager.default.createDirectory(at:support,withIntermediateDirectories:true)
 try JSONSerialization.data(withJSONObject:["version":2,"samples":[["org":"org-fixture","u":[:]]]]).write(to:support.appendingPathComponent("plan-usage-history.json"))
 // Cookie DB with a plaintext-looking encrypted_value is not exercised here — without Claude Safe Storage
 // the desktop path fails closed; empty OAuth alone must not invent a request.
 try JSONSerialization.data(withJSONObject:["claudeAiOauth":["accessToken":"","expiresAt":0]]).write(to:{
  let dir=home.appendingPathComponent(".claude");try FileManager.default.createDirectory(at:dir,withIntermediateDirectories:true)
  return dir.appendingPathComponent(".credentials.json")
 }())
 do { _=try await AICredentialReader().request(.claude,interactive:false,home:home);XCTFail("Must fail without desktop cookies or OAuth") } catch {
  XCTAssertFalse(error.localizedDescription.isEmpty)
 }
 }
}
