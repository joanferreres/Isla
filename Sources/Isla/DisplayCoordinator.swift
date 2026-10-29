import AppKit
import Combine
@MainActor final class DisplayCoordinator {
 var controllers:[UInt32:NotchWindowController]=[:]
 let preferences:PreferencesStore
 let local:LocalStore
 let music:AppleMusicService
 let calendar:CalendarService
 let activity:CodexActivityService
 let usage:CodexUsageService
 let statistics:StatisticsStore
 let settings:() -> Void
 var subscriptions=Set<AnyCancellable>()
 init(preferences:PreferencesStore,local:LocalStore,music:AppleMusicService,calendar:CalendarService,activity:CodexActivityService,usage:CodexUsageService,statistics:StatisticsStore,settings:@escaping () -> Void) {
 self.preferences=preferences; self.local=local; self.music=music;self.calendar=calendar;self.activity=activity;self.usage=usage;self.statistics=statistics; self.settings=settings
 NotificationCenter.default.publisher(for:NSApplication.didChangeScreenParametersNotification).sink { [weak self] _ in Task { @MainActor in self?.reconcile() } }.store(in:&subscriptions)
 Publishers.Merge(NSWorkspace.shared.notificationCenter.publisher(for:NSWorkspace.activeSpaceDidChangeNotification),NSWorkspace.shared.notificationCenter.publisher(for:NSWorkspace.didActivateApplicationNotification)).sink { [weak self] _ in Task { @MainActor in self?.reconcile() } }.store(in:&subscriptions)
 NSWorkspace.shared.notificationCenter.publisher(for:NSWorkspace.didWakeNotification).sink { [weak self] _ in Task { @MainActor in self?.reconcile() } }.store(in:&subscriptions)
 preferences.$value.map{($0.showOnAllDisplays,$0.normalized().expandedWidth)}.removeDuplicates(by: ==).dropFirst().sink { [weak self] _ in Task { @MainActor in self?.reconcile() } }.store(in:&subscriptions)
 }
 func reconcile() {
 let all=NSScreen.screens
 // NSScreen.screens begins with the primary display, regardless of keyboard focus.
 let screens=preferences.value.showOnAllDisplays ? all : Array(all.prefix(1))
 let ids=Set(screens.compactMap{($0.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)?.uint32Value})
 for id in Array(controllers.keys) where !ids.contains(id) { controllers.removeValue(forKey:id)?.stop() }
 for screen in screens {
 guard let id=(screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)?.uint32Value else { continue }
 if let controller=controllers[id] { controller.show() } else { let c=NotchWindowController(screen:screen,preferences:preferences,local:local,music:music,calendar:calendar,activity:activity,usage:usage,statistics:statistics,settings:settings); controllers[id]=c; c.show() }
 }
 }
 func open() { (controllers.values.first(where:{$0.layout?.metrics.frame.contains(NSEvent.mouseLocation) == true}) ?? controllers.values.first)?.model.enter() }
}
