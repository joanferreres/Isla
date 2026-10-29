import SwiftUI
import IslandCore
@MainActor struct CalendarView:View {
 @ObservedObject var calendar:CalendarService
 @ObservedObject var model:IslandModel
 private var visibleEvents:[CalendarEvent] { Calendar.current.isDateInToday(calendar.selectedDate) ? calendar.events.filter{$0.allDay || $0.end>Date()} : calendar.events }
 @State private var choosingDate=false
 @State private var holdingPicker=false
 var body:some View {
 VStack(alignment:.leading,spacing:8) {
 HStack(alignment:.center,spacing:8) {
 Button { choosingDate.toggle() } label: {
 Text(calendar.selectedDate,format:.dateTime.month(.abbreviated)).font(.system(size:24,weight:.bold)).fixedSize()
 }.buttonStyle(.plain).accessibilityLabel("Elegir fecha")
 .contextMenu { Button("Ir a hoy") { calendar.select(day:Date()) };Button("Abrir Calendario") { NSWorkspace.shared.open(URL(fileURLWithPath:"/System/Applications/Calendar.app")) } }
 .onChange(of:choosingDate) { _,shown in setPickerHold(shown) }
 .popover(isPresented:$choosingDate) { DatePicker("Fecha",selection:Binding(get:{calendar.selectedDate},set:{calendar.select(day:$0);choosingDate=false}),displayedComponents:.date).datePickerStyle(.graphical).padding() }
 ScrollViewReader { proxy in
 ScrollView(.horizontal,showsIndicators:false) {
 HStack(spacing:6) {
 ForEach(calendar.days,id:\.self) { date in
 let selected=Calendar.current.isDate(date,inSameDayAs:calendar.selectedDate)
 let today=Calendar.current.isDateInToday(date)
 let events=calendar.events(on:date)
 Button { calendar.select(day:date) } label: {
 VStack(spacing:3) {
 Text(date,format:.dateTime.weekday(.narrow)).font(.system(size:9,weight:selected ? .bold : .medium)).foregroundStyle(selected ? .white : .gray)
 Text(date,format:.dateTime.day()).font(.system(size:selected ? 20 : 13,weight:selected ? .bold : .semibold)).foregroundStyle(selected || today ? .blue : .gray)
 Circle().fill(events.isEmpty ? Color.clear : selected ? .blue : color(events[0])).frame(width:3,height:3)
 }.frame(width:23,height:42)
 }.buttonStyle(.plain).id(date).accessibilityLabel(date.formatted(date:.complete,time:.omitted))
 }
 }
 }
 .onAppear { proxy.scrollTo(Calendar.current.startOfDay(for:calendar.selectedDate),anchor:.center) }
 .onChange(of:calendar.selectedDate) { _,date in proxy.scrollTo(Calendar.current.startOfDay(for:date),anchor:.center) }
 }
 }
 if !calendar.enabled { empty("Conecta Calendario en Ajustes") }
 else if let error=calendar.error { Text(error).foregroundStyle(.orange).font(.caption2).frame(maxWidth:.infinity,maxHeight:.infinity) }
 else if visibleEvents.isEmpty { empty(Calendar.current.isDateInToday(calendar.selectedDate) ? "Sin eventos para hoy" : "Sin eventos este día") }
 else {
 ScrollView { VStack(spacing:8) { ForEach(visibleEvents) { event in
 HStack(alignment:.top,spacing:8) {
 Text(event.title).font(.system(size:11,weight:.medium)).multilineTextAlignment(.trailing).lineLimit(2).frame(maxWidth:.infinity,alignment:.trailing)
 VStack(spacing:0) { Circle().fill(color(event)).frame(width:5,height:5);Rectangle().fill(color(event).opacity(0.25)).frame(width:1) }.frame(width:6)
 Text(event.allDay ? "Todo el día" : "\(event.start.formatted(date:.omitted,time:.shortened)) – \(event.end.formatted(date:.omitted,time:.shortened))").font(.system(size:10,weight:.medium)).foregroundStyle(.secondary).lineLimit(1).frame(width:80,alignment:.leading)
 }.fixedSize(horizontal:false,vertical:true).accessibilityElement(children:.combine)
 } }.padding(.top,2).frame(maxWidth:.infinity) }
 }
 }.onDisappear { setPickerHold(false) }
 }
 func setPickerHold(_ hold:Bool) { guard hold != holdingPicker else { return };holdingPicker=hold;if hold { model.beginInteraction() } else { model.endInteraction() } }
 func color(_ event:IslandCore.CalendarEvent) -> Color { let c=event.colorRGB;return c.count>=3 ? Color(red:c[0],green:c[1],blue:c[2]) : .mint }
 func empty(_ text:String) -> some View { Text(text).font(.caption2).foregroundStyle(.secondary).frame(maxWidth:.infinity,maxHeight:.infinity) }
}
@MainActor struct HomeView:View {
 @ObservedObject var model:IslandModel
 @ObservedObject var music:AppleMusicService
 @ObservedObject var calendar:CalendarService
 @ObservedObject var preferences:PreferencesStore
 @ObservedObject var usage:CodexUsageService
 @ObservedObject var activity:CodexActivityService
 let openCodex:(String) -> Void
 var body:some View {
 let playing=music.state.snapshot?.playing == true
 let showAI=preferences.value.showCodexOnHome || (preferences.value.cursorEnabled && preferences.value.showCursorOnHome) || (preferences.value.claudeEnabled && preferences.value.showClaudeOnHome)
 VStack(spacing:8) {
 GeometryReader { space in
 HStack(alignment:.top,spacing:16) {
 CalendarView(calendar:calendar,model:model).frame(width:max(0,(space.size.width-17)*0.56))
 if playing {
 Divider().overlay(.white.opacity(0.10))
 MediaView(music:music).frame(maxWidth:.infinity)
 } else if showAI {
 Divider().overlay(.white.opacity(0.10))
 AIHomeRow(usage:usage,activity:activity,preferences:preferences,open:openCodex,vertical:true).frame(maxWidth:.infinity,maxHeight:.infinity,alignment:.center)
 } else { Spacer(minLength:0) }
 }.frame(width:space.size.width,height:space.size.height,alignment:.top).clipped()
 }
 if playing && showAI {
 Divider().overlay(.white.opacity(0.12))
 AIHomeRow(usage:usage,activity:activity,preferences:preferences,open:openCodex)
 }
 }
 }
}
