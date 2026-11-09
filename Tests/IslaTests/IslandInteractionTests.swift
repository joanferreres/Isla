import XCTest
import AppKit
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
 func testDropsResolveMultipleFilesOnceInOrderAndWithoutDuplicates() throws {
 let directory=FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
 try FileManager.default.createDirectory(at:directory,withIntermediateDirectories:true)
 defer { try? FileManager.default.removeItem(at:directory) }
 let first=directory.appendingPathComponent("one.txt"),second=directory.appendingPathComponent("two.txt")
 try Data("one".utf8).write(to:first);try Data("two".utf8).write(to:second)
 let pasteboard=NSPasteboard.withUniqueName()
 defer { pasteboard.releaseGlobally() }
 XCTAssertTrue(pasteboard.writeObjects([first,second,first].map { $0 as NSURL }))
 XCTAssertEqual(ShelfService.fileURLs(from:pasteboard),[first,second])
 }
 func testUnsupportedDropsDoNotOpenAirDrop() {
 let pasteboard=NSPasteboard.withUniqueName()
 defer { pasteboard.releaseGlobally() }
 XCTAssertTrue(pasteboard.writeObjects(["plain text" as NSString]))
 XCTAssertTrue(ShelfService.fileURLs(from:pasteboard).isEmpty)
 }
 func testFileDragOpensCompactShelfAndKeepsItOpenUntilDragEnds() async throws {
 let model=IslandModel()
 let point=CGPoint(x:25,y:20)
 model.trackFileDrop(at:point)
 XCTAssertTrue(model.state.expanded)
 XCTAssertEqual(model.section,"Archivos")
 XCTAssertEqual(model.fileDropTarget,.shelf)
 model.updatePointerPresence(false)
 try await Task.sleep(for:.milliseconds(320))
 XCTAssertTrue(model.state.expanded)
 model.airDropFrame=CGRect(x:250,y:70,width:100,height:80)
 model.trackFileDrop(at:CGPoint(x:300,y:100))
 XCTAssertEqual(model.fileDropTarget,.airDrop)
 model.trackFileDrop(at:point)
 XCTAssertEqual(model.fileDropTarget,.shelf)
 model.finishFileDrop()
 XCTAssertNil(model.fileDropTarget)
 try await Task.sleep(for:.milliseconds(320))
 XCTAssertFalse(model.state.expanded)
 }
}
