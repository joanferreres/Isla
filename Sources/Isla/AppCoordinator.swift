import AppKit
import SwiftUI
import Combine
import IslandCore
@MainActor final class AppCoordinator: NSObject, NSApplicationDelegate {
 let preferences = PreferencesStore()
 let local = LocalStore()
 let music = AppleMusicService()
 let activity = CodexActivityService()
 let usage = CodexUsageService()
 let statistics = StatisticsStore()
 lazy var screenshots=ScreenshotService(onCapture:{ _ in })
 lazy var calendar = CalendarService(preferences:preferences)
 lazy var lid = LidEffectController(preferences:preferences)
 private var appliedPreferences:Preferences?
 var integrationSubscriptions = Set<AnyCancellable>()
 var displays: DisplayCoordinator?
 var status: NSStatusItem?
 var settings: NSWindow?
 func applicationDidFinishLaunching(_ notification: Notification) {
 if !UserDefaults.standard.bool(forKey:"compactClickLayoutApplied") {
 if preferences.value.expandedWidth == 600 { preferences.value.expandedWidth=640 }
 preferences.value.openOnHover=false
 UserDefaults.standard.set(true,forKey:"compactClickLayoutApplied")
 }
 activity.onCompletion = { [weak self] event in self?.statistics.record(event) }
 usage.onSnapshot = { [weak self] snapshot in self?.statistics.record(snapshot) }
 displays = DisplayCoordinator(preferences: preferences, local: local, music: music, calendar: calendar, activity: activity, usage: usage, statistics: statistics, settings: { [weak self] in self?.showSettings() })
 displays?.reconcile()
 local.$loaded.filter{$0}.first().sink { [weak self] _ in
 guard let self else { return }
 let folder=self.screenshots.folder.resolvingSymlinksInPath()
 let captured=self.local.document.files.filter{$0.url.deletingLastPathComponent().resolvingSymlinksInPath() == folder}
 for item in captured { self.local.removeFile(item.id) }
 }.store(in:&integrationSubscriptions)
 preferences.$value.sink { [weak self] value in
 guard let self else { return };let old=self.appliedPreferences;self.appliedPreferences=value
 AIUsageAccounts.shared.apply(value)
 self.screenshots.copyToClipboard=value.screenshotClipboardEnabled
 if old?.screenshotsEnabled != value.screenshotsEnabled {
 if value.screenshotsEnabled { do { try self.screenshots.start(copyToClipboard:value.screenshotClipboardEnabled) } catch { self.screenshots.error="No se pudo acceder a Escritorio/capturas." } }
 else { self.screenshots.stop() }
 }
 if old?.musicEnabled != value.musicEnabled { if value.musicEnabled { self.music.connect() } else { self.music.disconnect() } }
 if old?.calendarEnabled != value.calendarEnabled { if value.calendarEnabled { self.calendar.connect() } else { self.calendar.disconnect() } }
 else if old?.selectedCalendarIDs != value.selectedCalendarIDs { self.calendar.refresh() }
 self.activity.soundEnabled=value.aiSoundEnabled
 self.activity.completionHighlightEnabled = value.aiVisualEnabled
 self.activity.completionNoticeEnabled = value.aiVisualEnabled
 if !value.aiVisualEnabled { self.activity.latest=nil }
 if old?.codexEnabled != value.codexEnabled { if value.codexEnabled { self.activity.connect();self.usage.connect() } else { self.activity.disconnect();self.usage.disconnect() } }
 if old?.lidEffectEnabled != value.lidEffectEnabled { if value.lidEffectEnabled { Task { await self.lid.enable(requestPermission:old != nil) } } else { self.lid.disable() } }
 }.store(in:&integrationSubscriptions)

 let center=NSWorkspace.shared.notificationCenter
 Publishers.Merge(center.publisher(for:NSWorkspace.willSleepNotification),center.publisher(for:NSWorkspace.screensDidSleepNotification)).sink { [weak self] _ in
 guard let self else { return };self.music.pauseForSleep();self.activity.pauseForSleep();self.usage.disconnect();AIUsageAccounts.shared.suspend();self.lid.suspend()
 }.store(in:&integrationSubscriptions)
 Publishers.Merge(center.publisher(for:NSWorkspace.didWakeNotification),center.publisher(for:NSWorkspace.screensDidWakeNotification)).sink { [weak self] _ in
 guard let self else { return };let value=self.preferences.value
 AIUsageAccounts.shared.apply(value)
 if value.musicEnabled { self.music.connect() };if value.codexEnabled { self.activity.connect();self.usage.connect() };if value.lidEffectEnabled { Task { await self.lid.enable() } }
 }.store(in:&integrationSubscriptions)
 installMainMenu()
 status = NSStatusBar.system.statusItem(withLength: 28)
 status?.button?.image = Self.menuBarIcon()
 status?.button?.setAccessibilityLabel("Isla")
 status?.button?.toolTip="Isla"
 let menu = NSMenu()
 for (title, action) in [("Abrir Isla", #selector(openIsland)), ("Ajustes…", #selector(openSettings)), ("Salir", #selector(quit))] {
 let item = NSMenuItem(title: title, action: action, keyEquivalent: ""); item.target = self; menu.addItem(item)
 }
 status?.menu = menu
 }
 /// Static vector version of the app mark, legible at menu-bar size.
 private static func menuBarIcon() -> NSImage {
 let image=NSImage(size:NSSize(width:24,height:18),flipped:false) { _ in
 let outer=NSBezierPath(roundedRect:NSRect(x:1,y:3,width:22,height:12),xRadius:6,yRadius:6)
 let cyan=NSColor(srgbRed:0.05,green:0.88,blue:0.95,alpha:1)
 let violet=NSColor(srgbRed:0.66,green:0.32,blue:1,alpha:1)
 NSGradient(starting:cyan,ending:violet)?.draw(in:outer,angle:0)
 NSColor(srgbRed:0.04,green:0.05,blue:0.07,alpha:1).setFill()
 NSBezierPath(roundedRect:NSRect(x:2.5,y:4.5,width:19,height:9),xRadius:4.5,yRadius:4.5).fill()
 NSColor.white.setFill()
 NSBezierPath(roundedRect:NSRect(x:8.5,y:8,width:7,height:2),xRadius:1,yRadius:1).fill()
 return true
 }
 image.isTemplate=false
 return image
 }
 func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
 Task { let savedLocal = await local.flush(); let savedStatistics = await statistics.flush(); let saved = savedLocal && savedStatistics; if !saved { displays?.open() }; sender.reply(toApplicationShouldTerminate:saved) }
 return .terminateLater
 }
 func installMainMenu() {
 let root = NSMenu(); let appMenu = NSMenu(); let appItem = NSMenuItem(); appItem.submenu = appMenu; root.addItem(appItem)
 let settingsItem = NSMenuItem(title:"Ajustes…",action:#selector(openSettings),keyEquivalent:","); settingsItem.target=self; appMenu.addItem(settingsItem)
 let quitItem = NSMenuItem(title:"Salir de Isla",action:#selector(quit),keyEquivalent:"q"); quitItem.target = self; appMenu.addItem(quitItem)
 let editMenu = NSMenu(title:"Edición"); let editItem = NSMenuItem(title:"Edición",action:nil,keyEquivalent:""); editItem.submenu = editMenu; root.addItem(editItem)
 for (title, selector, key) in [("Deshacer","undo:","z"),("Cortar","cut:","x"),("Copiar","copy:","c"),("Pegar","paste:","v"),("Seleccionar todo","selectAll:","a")] { editMenu.addItem(NSMenuItem(title:title,action:NSSelectorFromString(selector),keyEquivalent:key)) }
 NSApp.mainMenu = root
 }
 @objc func openIsland() { displays?.open() }
 @objc func openSettings() { showSettings() }
 @objc func quit() { NSApp.terminate(nil) }
 func showSettings() {
 if settings == nil {
 let window = NSWindow(contentRect: NSRect(x: 0,y: 0,width: 640,height: 480), styleMask: [.titled,.closable], backing: .buffered, defer: false)
 window.title = "Ajustes de Isla"; window.isReleasedWhenClosed = false
 window.contentView = NSHostingView(rootView: SettingsView(calendar:calendar,music:music,usage:usage,activity:activity,screenshots:screenshots,lid:lid,store: preferences)); window.center(); settings = window
 }
 NSApp.activate(ignoringOtherApps: true); settings?.makeKeyAndOrderFront(nil)
 }
}
