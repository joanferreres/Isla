import XCTest
import UniformTypeIdentifiers
import SwiftUI
import IslandCore
@testable import Isla
@MainActor final class IslandInteractionTests:XCTestCase {
 func testNativeNotchMenuKeepsModesPinSettingsAndQuitActions() {
 var selected=AINotificationMode.sound,pins=0,settings=0,quits=0
 let menu=IslandContextMenu.make(mode:.visual,pinned:false,setMode:{selected=$0},togglePin:{pins+=1},settings:{settings+=1},quit:{quits+=1})
 XCTAssertEqual(menu.items.filter{!$0.isSeparatorItem}.map(\.title),["Modo luna","Fijar isla","Ajustes…","Salir de Isla"])
 let modes=menu.items[0].submenu!
 XCTAssertEqual(modes.items.map(\.state),[.off,.on,.off])
 modes.performActionForItem(at:2);XCTAssertEqual(selected,.none)
 menu.performActionForItem(at:1);menu.performActionForItem(at:3);menu.performActionForItem(at:5)
 XCTAssertEqual(pins,1);XCTAssertEqual(settings,1);XCTAssertEqual(quits,1)
 }
 func testInactiveIslandAcceptsFirstClickBelowNotch() {
 let view=IslandHostingView(rootView:Color.black.opacity(0.01).frame(width:292,height:70))
 let panel=IslandPanel(contentRect:NSRect(x:0,y:0,width:292,height:70),styleMask:[.borderless,.nonactivatingPanel],backing:.buffered,defer:false)
 panel.contentView=view;view.layoutSubtreeIfNeeded()
 XCTAssertTrue(view.acceptsFirstMouse(for:nil))
 XCTAssertNotNil(view.hitTest(NSPoint(x:146,y:6)))
 }
 func testPointerPresenceDoesNotOpenAndClickOpensUnpinned() {
 let model=IslandModel()
 model.updatePointerPresence(true)
 XCTAssertFalse(model.state.expanded)
 model.enter()
 XCTAssertTrue(model.state.expanded);XCTAssertFalse(model.state.pinned)
 }
 func testReturningPointerCancelsPendingClose() async throws {
 let model=IslandModel();model.enter();model.updatePointerPresence(false)
 model.updatePointerPresence(true)
 try await Task.sleep(for:.milliseconds(320))
 XCTAssertTrue(model.state.expanded)
 }
 func testLeavingClosesUnlessPinned() async throws {
 let model=IslandModel();model.enter();model.updatePointerPresence(false)
 try await Task.sleep(for:.milliseconds(320));XCTAssertFalse(model.state.expanded)
 model.toggle();model.updatePointerPresence(false)
 try await Task.sleep(for:.milliseconds(320));XCTAssertTrue(model.state.expanded)
 }
 func testDropsResolveMultipleFilesOnceInOrderAndWithoutDuplicates() async throws {
 let directory=FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
 try FileManager.default.createDirectory(at:directory,withIntermediateDirectories:true)
 defer { try? FileManager.default.removeItem(at:directory) }
 let first=directory.appendingPathComponent("one.txt"),second=directory.appendingPathComponent("two.txt")
 try Data("one".utf8).write(to:first);try Data("two".utf8).write(to:second)
 let result:[URL]=await withCheckedContinuation { continuation in
 let accepted=ShelfService.loadURLs([first,second,first].map{NSItemProvider(object:$0 as NSURL)}) { continuation.resume(returning:$0) }
 XCTAssertTrue(accepted)
 }
 XCTAssertEqual(result,[first,second])
 }
 func testUnsupportedDropsDoNotOpenAirDrop() {
 XCTAssertFalse(ShelfService.loadURLs([NSItemProvider(object:"plain text" as NSString)]) { _ in XCTFail("Text is not a file") })
 }
}
