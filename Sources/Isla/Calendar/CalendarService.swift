import SwiftUI
import EventKit
import CoreImage
import IslandCore
struct CalendarChoice:Identifiable,Sendable { var id:String;var title:String }
actor CalendarReader {
 let store=EKEventStore()
 private let authorization:@Sendable () -> EKAuthorizationStatus
 private let requestAccess:(@Sendable () async throws -> Bool)?
 init(authorization:@escaping @Sendable () -> EKAuthorizationStatus={EKEventStore.authorizationStatus(for:.event)},requestAccess:(@Sendable () async throws -> Bool)?=nil) {
 self.authorization=authorization;self.requestAccess=requestAccess
 }
 func request() async throws -> Bool {
 switch authorization() {
 case .fullAccess:return true
 case .notDetermined:break
 default:return false
 }
 if let requestAccess { return try await requestAccess() }
 return try await store.requestFullAccessToEvents()
 }
 func read(day:Date,ids:[String]) -> ([CalendarChoice],[CalendarEvent],[CalendarEvent])? {
 guard EKEventStore.authorizationStatus(for:.event) == .fullAccess else { return nil }
 let all=store.calendars(for:.event)
 let selected=ids.isEmpty ? all : all.filter{ids.contains($0.calendarIdentifier)}
 let days=CalendarDay.strip(containing:day,calendar:.current)
 let interval=DateInterval(start:days.first!,end:CalendarDay.interval(containing:days.last!,calendar:.current).end)
 let matches=selected.isEmpty ? [] : store.events(matching:store.predicateForEvents(withStart:interval.start,end:interval.end,calendars:selected))
 let tomorrow=Calendar.current.date(byAdding:.day,value:1,to:Calendar.current.startOfDay(for:Date()))!
 let upcomingMatches=selected.isEmpty ? [] : store.events(matching:store.predicateForEvents(withStart:Date(),end:tomorrow.addingTimeInterval(10*60),calendars:selected))
 func convert(_ matches:[EKEvent]) -> [CalendarEvent] { matches.map { event in
 let color=CIColor(cgColor:event.calendar.cgColor)
 return CalendarEvent(id:(event.eventIdentifier ?? UUID().uuidString)+"-\(event.startDate.timeIntervalSince1970)",title:event.title ?? "Sin título",start:event.startDate,end:event.endDate,allDay:event.isAllDay,calendarID:event.calendar.calendarIdentifier,colorRGB:[Double(color.red),Double(color.green),Double(color.blue)])
 }.sorted { a,b in if a.allDay != b.allDay { return a.allDay };return a.start < b.start } }
 return (all.map{CalendarChoice(id:$0.calendarIdentifier,title:$0.title)},convert(matches),convert(upcomingMatches))
 }
}
@MainActor final class CalendarService:ObservableObject {
 @Published var events:[CalendarEvent]=[]
 @Published var surroundingEvents:[CalendarEvent]=[]
 var days:[Date] { CalendarDay.strip(containing:selectedDate,calendar:.current) }
 var nextEvent:CalendarEvent? { surroundingEvents.filter{!$0.allDay && $0.start >= Date()}.min{$0.start < $1.start} }
 func events(on day:Date) -> [CalendarEvent] { CalendarDay.events(on:day,from:surroundingEvents,calendar:.current) }
 @Published var calendars:[CalendarChoice]=[]
 @Published var selectedDate=Date()
 @Published var error:String?
 @Published var enabled=false
 @Published var reminder:CalendarEvent?
 @Published var reminderMinutes=0
 private var upcomingEvents:[CalendarEvent]=[]
 private var reminderTask:Task<Void,Never>?
 let reader=CalendarReader()
 let preferences:PreferencesStore
 var observers:[NSObjectProtocol]=[]
 var generation=0
 init(preferences:PreferencesStore) { self.preferences=preferences }
 func connect() {
 guard !enabled else { refresh();return }; enabled=true;generation += 1
 observers.append(NotificationCenter.default.addObserver(forName:.EKEventStoreChanged,object:nil,queue:.main) { [weak self] _ in Task { @MainActor in self?.refresh() } })
 observers.append(NotificationCenter.default.addObserver(forName:NSApplication.didBecomeActiveNotification,object:nil,queue:.main) { [weak self] _ in Task { @MainActor in self?.refresh() } })
 observers.append(NSWorkspace.shared.notificationCenter.addObserver(forName:NSWorkspace.didWakeNotification,object:nil,queue:.main) { [weak self] _ in Task { @MainActor in self?.refresh() } })
 let g=generation
 Task { do { let granted=try await reader.request(); guard enabled,g == generation else { return };if granted { refresh() } else { error="Permite el acceso al Calendario en Privacidad." } } catch { self.error="No se pudo acceder al Calendario." } }
 }
 func disconnect() { enabled=false;reminderTask?.cancel();reminderTask=nil;reminder=nil;reminderMinutes=0;upcomingEvents=[];generation += 1; events=[];surroundingEvents=[];calendars=[];for o in observers { NotificationCenter.default.removeObserver(o);NSWorkspace.shared.notificationCenter.removeObserver(o) };observers=[] }
 func select(day:Date) { selectedDate=day;refresh() }
 func refresh() {
 guard enabled else { return };let date=selectedDate;let ids=preferences.value.selectedCalendarIDs;generation += 1;let g=generation
 Task { let result=await reader.read(day:date,ids:ids);guard enabled,g == generation else { return };if let result { calendars=result.0;surroundingEvents=result.1;events=CalendarDay.events(on:date,from:result.1,calendar:.current);upcomingEvents=result.2;updateReminder();error=nil } else { events=[];surroundingEvents=[];upcomingEvents=[];updateReminder();error="Calendario sin acceso. Revisa el permiso en Privacidad." } }
 }
 func previewReminder() {
 guard enabled else { return }
 reminderTask?.cancel()
 let start=Date().addingTimeInterval(9*60)
 reminder=CalendarEvent(id:"preview",title:"Prueba de recordatorio",start:start,end:start.addingTimeInterval(3600),allDay:false,calendarID:"preview")
 reminderMinutes=9
 reminderTask=Task { [weak self] in
 do { try await Task.sleep(for:.seconds(8)) } catch { return }
 guard let self,!Task.isCancelled else { return };self.updateReminder()
 }
 }
 private func updateReminder() {
 reminderTask?.cancel();reminderTask=nil
 let now=Date();let next=enabled ? CalendarReminderPolicy.reminder(in:upcomingEvents,at:now) : nil
 if reminder != next { reminder=next }
 let minutes=next.map{Int(ceil($0.start.timeIntervalSince(now)/60))} ?? 0
 if reminderMinutes != minutes { reminderMinutes=minutes }
 guard enabled else { return }
 let midnight=Calendar.current.date(byAdding:.day,value:1,to:Calendar.current.startOfDay(for:now))!
 let deadline=min(CalendarReminderPolicy.nextUpdate(in:upcomingEvents,at:now) ?? midnight,midnight)
 reminderTask=Task { [weak self] in
 do { try await Task.sleep(for:.seconds(max(0.05,deadline.timeIntervalSinceNow))) } catch { return }
 guard let self,!Task.isCancelled,self.enabled else { return }
 if Date()>=midnight { self.refresh() } else { self.updateReminder() }
 }
 }

}
