import AppKit
import SwiftUI
import Combine
import IslandCore
@MainActor final class IslandModel: ObservableObject {
 @Published var state = IslandState()
 @Published var section="Inicio"
 @Published private(set) var fileDropTarget:ShelfDropTarget?
 var airDropFrame:CGRect = .null
 @Published var headerHeight: CGFloat = 32
 @Published var notchWidth: CGFloat = 196
 @Published var hasPhysicalNotch=false
 @Published var expandedSize=CGSize(width:640,height:205)
 @Published var sideWidth:CGFloat=0
 @Published var compactSize=CGSize(width:268,height:32)
 func apply(_ layout:IslandLayout) { expandedSize=layout.openSize;compactSize=layout.compactSize(sideWidth:sideWidth) }
 var pointerInside = false
 private var interactionHolds = 0
 private var pending: Task<Void, Never>?
 func updatePointerPresence(_ inside:Bool) {
 pointerInside=inside
 if inside { pending?.cancel() } else { leave() }
 }
 func enter() { pending?.cancel(); state.enter() }
 func leave() { guard interactionHolds == 0 else { return }; pending?.cancel(); pending=Task { try? await Task.sleep(for:.milliseconds(250)); guard !Task.isCancelled,interactionHolds == 0 else { return }; state.leave() } }
 func beginInteraction() { interactionHolds += 1; pending?.cancel() }
 func endInteraction() { interactionHolds=max(0,interactionHolds-1); if interactionHolds == 0 && !pointerInside { leave() } }
 func toggle() { pending?.cancel(); state.togglePinned() }
 func close() { pending?.cancel(); state.close() }
 func trackFileDrop(at point:CGPoint) {
 if fileDropTarget == nil {
 airDropFrame = section == "Archivos" && state.expanded ? airDropFrame : .null
 beginInteraction()
 section="Archivos"
 enter()
 }
 let target:ShelfDropTarget = airDropFrame.contains(point) ? .airDrop : .shelf
 if fileDropTarget != target { fileDropTarget=target }
 }
 func finishFileDrop() {
 guard fileDropTarget != nil else { return }
 fileDropTarget=nil
 endInteraction()
 }
}
enum ShelfDropTarget { case shelf, airDrop }
final class IslandPanel: NSPanel {
 var onEscape:(() -> Void)?
 override var canBecomeKey:Bool { true }
 override var canBecomeMain:Bool { false }
 override func constrainFrameRect(_ frameRect:NSRect,to screen:NSScreen?) -> NSRect { frameRect }
 override func keyDown(with event:NSEvent) { if event.keyCode == 53 { onEscape?() } else { super.keyDown(with:event) } }
}
// A nonactivating panel must accept the first click while another app is active.
final class IslandHostingView<Content:View>:NSHostingView<Content> {
 override func acceptsFirstMouse(for event:NSEvent?) -> Bool { true }
}
@MainActor final class IslandMenuAction:NSMenuItem {
 private let handler:() -> Void
 init(_ title:String,handler:@escaping () -> Void) {
 self.handler=handler;super.init(title:title,action:nil,keyEquivalent:"")
 target=self;action=#selector(invoke)
 }
 required init(coder:NSCoder) { fatalError("init(coder:) has not been implemented") }
 @objc private func invoke() { handler() }
}
@MainActor enum IslandContextMenu {
 static func make(mode:AINotificationMode,pinned:Bool,setMode:@escaping (AINotificationMode) -> Void,togglePin:@escaping () -> Void,settings:@escaping () -> Void,quit:@escaping () -> Void) -> NSMenu {
 let menu=NSMenu(),modes=NSMenu(title:"Modo luna")
 for value in AINotificationMode.allCases {
 let item=IslandMenuAction(value.title) { setMode(value) };item.state=value == mode ? .on : .off;modes.addItem(item)
 }
 let moon=NSMenuItem(title:"Modo luna",action:nil,keyEquivalent:"");moon.submenu=modes;menu.addItem(moon)
 menu.addItem(IslandMenuAction(pinned ? "Desfijar isla" : "Fijar isla",handler:togglePin))
 menu.addItem(.separator());menu.addItem(IslandMenuAction("Ajustes…",handler:settings))
 menu.addItem(.separator());menu.addItem(IslandMenuAction("Salir de Isla",handler:quit))
 return menu
 }
}
@MainActor final class NotchWindowController: NSObject, NSWindowDelegate, NSDraggingDestination {
 let model=IslandModel()
 let panel:IslandPanel
 let preferences:PreferencesStore
 let displayID:UInt32
 var layout:IslandLayout?
 var monitors:[Any]=[]
 private var menuTrackingDepth=0
 private var pendingResize:DispatchWorkItem?
 private var mediaPlaying=false
 private let openSettings:() -> Void
 private let local:LocalStore
 private let airDrop=AirDropService()
 var subscriptions=Set<AnyCancellable>()
 init(screen:NSScreen,preferences:PreferencesStore,local:LocalStore,music:AppleMusicService,calendar:CalendarService,activity:CodexActivityService,usage:CodexUsageService,statistics:StatisticsStore,showRecordPlayer:@escaping () -> Void,settings:@escaping () -> Void) {
 self.preferences=preferences;self.openSettings=settings;self.local=local; displayID=(screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)?.uint32Value ?? 0
 panel=IslandPanel(contentRect:.zero,styleMask:[.borderless,.nonactivatingPanel],backing:.buffered,defer:false)
 super.init()
 panel.delegate=self
 panel.registerForDraggedTypes([.fileURL])
 panel.onEscape={ [weak model] in model?.close() }; panel.isOpaque=false; panel.backgroundColor = .clear; panel.hasShadow=false;panel.acceptsMouseMovedEvents=true
 // Keep the system menu bar and Control Center above the island.
 panel.level = NSWindow.Level(rawValue:NSWindow.Level.mainMenu.rawValue-1); panel.hidesOnDeactivate=false; panel.collectionBehavior=[.canJoinAllSpaces,.canJoinAllApplications,.fullScreenAuxiliary,.stationary]; panel.isMovable=false
 panel.contentView=IslandHostingView(rootView:IslandView(model:model,preferences:preferences,local:local,music:music,calendar:calendar,activity:activity,usage:usage,statistics:statistics,airDrop:airDrop,showRecordPlayer:showRecordPlayer,settings:settings))
 preferences.$value.map{$0.normalized().expandedWidth}.removeDuplicates().dropFirst().sink { [weak self] _ in DispatchQueue.main.async { self?.refreshGeometry() } }.store(in:&subscriptions)
 if let monitor=NSEvent.addGlobalMonitorForEvents(matching:[.mouseMoved,.leftMouseDragged,.rightMouseDragged,.leftMouseDown,.rightMouseDown]) { [weak self] event in
 guard let self else { return };self.updatePointer(fileDrag:event.type == .leftMouseDragged)
 // Global monitors only receive events delivered to other apps. Recover a click
 // inside the camera housing if the system menu bar took the click.
 if (event.type == .leftMouseDown && !self.model.state.expanded) || event.type == .rightMouseDown,let layout=self.layout {
 let point=NSEvent.mouseLocation
 if layout.containsGlobalActivation(point,physicalNotch:self.model.hasPhysicalNotch) {
 if event.type == .rightMouseDown { self.scheduleContextMenu(at:point) } else { self.model.enter() }
 }
 }
 } { monitors.append(monitor) }
 if let monitor=NSEvent.addLocalMonitorForEvents(matching:[.mouseMoved,.leftMouseDragged,.rightMouseDragged,.leftMouseDown,.rightMouseDown]) { [weak self] event in
 guard let self else { return event };self.updatePointer(fileDrag:event.type == .leftMouseDragged)
 if event.type == .rightMouseDown,event.window === self.panel,!self.model.state.expanded,
 let layout=self.layout {
 let point=self.panel.convertPoint(toScreen:event.locationInWindow)
 if layout.containsCompactClick(point) { self.scheduleContextMenu(at:point);return nil }
 }
 // Handle the first primary click before SwiftUI's context-menu recognizer or first-mouse filtering.
 if event.type == .leftMouseDown,event.window === self.panel,!self.model.state.expanded,
 let layout=self.layout,layout.containsCompactClick(self.panel.convertPoint(toScreen:event.locationInWindow)) {
 self.model.enter();return nil
 }
 return event
 } { monitors.append(monitor) }
 model.$section.map { $0 == "Archivos" }.removeDuplicates().dropFirst().sink { [weak self] _ in DispatchQueue.main.async { self?.refreshGeometry() } }.store(in:&subscriptions)
 model.$state.map{ $0.expanded }.removeDuplicates().dropFirst().sink { [weak self] expanded in
 // Resize after @Published assigns; let the closing animation finish before shrinking the window.
 DispatchQueue.main.async {
 guard let self else { return };self.pendingResize?.cancel();self.updatePointer()
 if expanded { self.refreshGeometry() } else {
 let resize=DispatchWorkItem { [weak self] in guard let self,!self.model.state.expanded else { return };self.refreshGeometry() }
 self.pendingResize=resize;DispatchQueue.main.asyncAfter(deadline:.now()+0.38,execute:resize)
 }
 }
 }.store(in:&subscriptions)
 Publishers.CombineLatest(music.$state.map{$0.snapshot?.playing == true}.removeDuplicates(),calendar.$reminder.map{$0 != nil}.removeDuplicates()).sink { [weak self] playing,reminder in
 guard let self else { return }
 self.mediaPlaying=playing
 self.model.sideWidth=reminder ? 104 : playing ? 36 : 0
 if let layout=self.layout { self.model.apply(layout) }
 DispatchQueue.main.async { self.refreshGeometry() }
 }.store(in:&subscriptions)
 NotificationCenter.default.publisher(for:NSMenu.didBeginTrackingNotification).sink { [weak self] _ in
 guard let self else { return };self.menuTrackingDepth += 1;self.model.beginInteraction()
 }.store(in:&subscriptions)
 NotificationCenter.default.publisher(for:NSMenu.didEndTrackingNotification).sink { [weak self] _ in
 guard let self,self.menuTrackingDepth>0 else { return };self.menuTrackingDepth -= 1
 if self.menuTrackingDepth == 0 { self.updatePointer() };self.model.endInteraction()
 }.store(in:&subscriptions)
 refreshGeometry()
 }
 private func scheduleContextMenu(at point:CGPoint) {
 guard menuTrackingDepth == 0 else { return }
 // Leave the event-monitor callback before starting AppKit's menu tracking loop.
 DispatchQueue.main.async { [weak self] in
 guard let self,self.menuTrackingDepth == 0,self.panel.isVisible else { return }
 let menu=IslandContextMenu.make(mode:self.preferences.value.aiNotificationMode,pinned:self.model.state.pinned,setMode:{ [weak self] in self?.preferences.value.aiNotificationMode=$0 },togglePin:{ [weak self] in self?.model.toggle() },settings:self.openSettings,quit:{ NSApp.terminate(nil) })
 let anchor=CGPoint(x:point.x,y:min(point.y,self.layout.map { $0.metrics.frame.maxY-$0.metrics.headerHeight-4 } ?? point.y))
 menu.popUp(positioning:nil,at:anchor,in:nil)
 }
 }
 func show() {
 model.pointerInside=false;refreshGeometry();panel.orderFrontRegardless();updatePointer()
 // App activation can finish ordering its windows after the workspace notification.
 // Reassert the island once on the next main-loop turn without changing its level.
 DispatchQueue.main.async { [weak panel] in panel?.orderFrontRegardless() }
 }
 func stop() { pendingResize?.cancel();model.finishFileDrop();panel.unregisterDraggedTypes();monitors.forEach { NSEvent.removeMonitor($0) }; monitors=[]; subscriptions=[]; panel.close() }
 func refreshGeometry() {
 guard let screen=NSScreen.screens.first(where:{ ($0.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)?.uint32Value == displayID }) else { return }
 let height=screen.safeAreaInsets.top > 0 ? screen.safeAreaInsets.top : max(24,min(38,screen.frame.maxY-screen.visibleFrame.maxY))
 let width:CGFloat
 if let left=screen.auxiliaryTopLeftArea,let right=screen.auxiliaryTopRightArea { width=max(0,right.minX-left.maxX) } else { width=156 }
 model.headerHeight=height; model.notchWidth=width; model.hasPhysicalNotch=screen.safeAreaInsets.top > 0
 layout=IslandLayout(metrics:DisplayMetrics(id:displayID,frame:screen.frame,notchWidth:width,headerHeight:height,builtIn:CGDisplayIsBuiltin(displayID) != 0),expandedWidth:preferences.value.normalized().expandedWidth,expandedHeight:model.section == "Archivos" ? 190 : mediaPlaying ? 235 : 205)
 if let layout { model.apply(layout);let frame=layout.windowFrame(expanded:model.state.expanded,sideWidth:model.sideWidth);if panel.frame != frame { panel.setFrame(frame,display:true) } }
 updatePointer()
 }
 func updatePointer(fileDrag:Bool=false) {
 guard menuTrackingDepth == 0 else { return }
 guard let layout else { return }
 let frame=layout.visibleFrame(expanded:model.state.expanded,sideWidth:model.sideWidth)
 let p=NSEvent.mouseLocation
 // Rounded bottom corners must pass clicks through as well as transparent margins.
 let radius:CGFloat=model.state.expanded ? 24 : 12
 var inside=frame.contains(p)
 if inside,p.y < frame.minY+radius {
 let cx=p.x < frame.midX ? frame.minX+radius : frame.maxX-radius
 if p.x < frame.minX+radius || p.x > frame.maxX-radius { inside=hypot(p.x-cx,p.y-(frame.minY+radius)) <= radius }
 }
 let ignoresMouse = model.fileDropTarget == nil && (model.state.expanded || fileDrag ? !inside : !layout.containsCompactClick(p))
 if panel.ignoresMouseEvents != ignoresMouse { panel.ignoresMouseEvents = ignoresMouse }
 let hoverInside=layout.containsHover(p,expanded:model.state.expanded,sideWidth:model.sideWidth)
 if hoverInside != model.pointerInside { model.updatePointerPresence(hoverInside) }
 }

 func draggingEntered(_ sender:any NSDraggingInfo) -> NSDragOperation { draggingUpdated(sender) }
 func draggingUpdated(_ sender:any NSDraggingInfo) -> NSDragOperation {
 guard preferences.value.filesEnabled,
       sender.draggingSourceOperationMask.contains(.copy),
       sender.draggingPasteboard.availableType(from:[.fileURL]) != nil,
       let point=fileDropPoint(sender) else { return [] }
 model.trackFileDrop(at:point)
 return .copy
 }
 func draggingExited(_ sender:(any NSDraggingInfo)?) { endFileDrop() }
 func draggingEnded(_ sender:any NSDraggingInfo) { endFileDrop() }
 func prepareForDragOperation(_ sender:any NSDraggingInfo) -> Bool { model.fileDropTarget != nil }
 func performDragOperation(_ sender:any NSDraggingInfo) -> Bool {
 defer { endFileDrop() }
 guard let point=fileDropPoint(sender), model.fileDropTarget != nil else { return false }
 let urls=ShelfService.fileURLs(from:sender.draggingPasteboard)
 guard !urls.isEmpty else { return false }
 model.trackFileDrop(at:point)
 if model.fileDropTarget == .airDrop { return airDrop.send(urls,model:model) }
 local.addFiles(urls)
 return true
 }
 private func fileDropPoint(_ sender:any NSDraggingInfo) -> CGPoint? {
 guard let layout, let content=panel.contentView,
       layout.containsHover(panel.convertPoint(toScreen:sender.draggingLocation),expanded:model.state.expanded,sideWidth:model.sideWidth) else { return nil }
 let point=content.convert(sender.draggingLocation,from:nil)
 return CGPoint(x:point.x,y:content.isFlipped ? point.y : content.bounds.maxY-point.y)
 }
 private func endFileDrop() {
 model.finishFileDrop()
 updatePointer()
 }
}
