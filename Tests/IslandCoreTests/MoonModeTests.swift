import XCTest
@testable import IslandCore

final class MoonModeTests:XCTestCase {
 func testThreeModesCycleAndControlSoundAndVisuals() {
 var p=Preferences()
 XCTAssertEqual(p.aiNotificationMode,.sound)
 p.aiNotificationMode=p.aiNotificationMode.next
 XCTAssertEqual(p.aiNotificationMode,.visual)
 XCTAssertFalse(p.aiSoundEnabled);XCTAssertTrue(p.aiVisualEnabled)
 p.aiNotificationMode=p.aiNotificationMode.next
 XCTAssertEqual(p.aiNotificationMode,.none)
 XCTAssertFalse(p.aiSoundEnabled);XCTAssertFalse(p.aiVisualEnabled)
 p.aiNotificationMode=p.aiNotificationMode.next
 XCTAssertTrue(p.aiSoundEnabled);XCTAssertTrue(p.aiVisualEnabled)
 }
 func testAllModesPersist() throws {
 for mode in AINotificationMode.allCases {
 var p=Preferences();p.aiNotificationMode=mode;p.codexEnabled=true
 let restored=try JSONDecoder().decode(Preferences.self,from:JSONEncoder().encode(p))
 XCTAssertEqual(restored.aiNotificationMode,mode);XCTAssertTrue(restored.codexEnabled)
 }
 }
 func testOldSettingsMigrateToEquivalentModes() throws {
 let decode:(String)throws->Preferences={ try JSONDecoder().decode(Preferences.self,from:Data($0.utf8)) }
 XCTAssertEqual(try decode("{\"moonModeEnabled\":true}").aiNotificationMode,.none)
 XCTAssertEqual(try decode("{\"completionSoundEnabled\":false}").aiNotificationMode,.visual)
 XCTAssertEqual(try decode("{}").aiNotificationMode,.sound)
 }

 func testMoonSilencesSoundAndRestoresPreviousChoice() {
 var p=Preferences()
 XCTAssertTrue(p.aiSoundEnabled)
 p.moonModeEnabled=true
 XCTAssertFalse(p.aiSoundEnabled)
 XCTAssertTrue(p.completionSoundEnabled)
 p.moonModeEnabled=false
 XCTAssertTrue(p.aiSoundEnabled)
 p.completionSoundEnabled=false
 p.moonModeEnabled=true;p.moonModeEnabled=false
 XCTAssertFalse(p.aiSoundEnabled)
 }
 func testMoonPersistsWithoutDisconnectingAI() throws {
 var p=Preferences();p.codexEnabled=true;p.moonModeEnabled=true
 let restored=try JSONDecoder().decode(Preferences.self,from:JSONEncoder().encode(p))
 XCTAssertTrue(restored.moonModeEnabled)
 XCTAssertTrue(restored.codexEnabled)
 XCTAssertFalse(restored.aiSoundEnabled)
 }
 func testExistingPreferencesDefaultToMoonOff() throws {
 let p=try JSONDecoder().decode(Preferences.self,from:Data("{\"codexEnabled\":true}".utf8))
 XCTAssertFalse(p.moonModeEnabled)
 XCTAssertTrue(p.aiSoundEnabled)
 }
}
