import SwiftUI
import UniformTypeIdentifiers
import IslandCore
@MainActor struct IslandView: View {
 @ObservedObject var model:IslandModel
 @ObservedObject var preferences:PreferencesStore
 @ObservedObject var local:LocalStore
 @ObservedObject var music:AppleMusicService
 @ObservedObject var calendar:CalendarService
 @ObservedObject var activity:CodexActivityService
 @ObservedObject var usage:CodexUsageService
 @ObservedObject var statistics:StatisticsStore
 let settings:() -> Void
 @State private var section="Inicio"
 @State private var selectedAI="Codex"
 @State private var dragging=false
 var body:some View {
 let expanded=model.state.expanded
 let width=expanded ? model.expandedSize.width : model.compactSize.width
 let centerWidth=min(width,model.notchWidth)
 let wingWidth=min(model.sideWidth,max(0,(width-centerWidth)/2))
 let playing=music.state.snapshot?.playing == true
 let reminder=calendar.reminder
 let reduced=preferences.value.reduceMotion || NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
 VStack(spacing:0) {
 if expanded {
 Color.clear.frame(height:model.headerHeight)
 HStack(spacing:width>=600 ? 10 : 5) {
 ForEach(["Inicio","Archivos","IA"],id:\.self) { tab in Button { section=tab } label: { HStack(spacing:4) { Image(systemName:tab == "Inicio" ? "square.grid.2x2.fill" : tab == "Archivos" ? "tray.fill" : "sparkles");if width>=600 { Text(tab) } }.padding(.horizontal,7).padding(.vertical,5).background(section == tab ? Color.white.opacity(0.12) : .clear,in:Capsule()) }.accessibilityLabel(tab).foregroundStyle(section == tab ? .white : .gray) }
 Spacer(minLength:0)
 Button { preferences.value.aiNotificationMode=preferences.value.aiNotificationMode.next } label: {
 Image(systemName:preferences.value.aiNotificationMode == .none ? "moon.fill" : preferences.value.aiNotificationMode == .visual ? "moon.stars.fill" : "moon")
 .frame(width:24,height:28)
 .foregroundStyle(preferences.value.aiNotificationMode == .sound ? Color.white : Color.mint)
 }
 .accessibilityLabel("Modo luna · avisos")
 .accessibilityValue(preferences.value.aiNotificationMode.title)
 .help(preferences.value.aiNotificationMode.title+" · Cambiar a "+preferences.value.aiNotificationMode.next.title)
 Button { model.toggle() } label: { Image(systemName:model.state.pinned ? "pin.fill" : "pin").frame(width:24,height:28) }.accessibilityLabel("Fijar")
 Button(action:settings) { Image(systemName:"gearshape").frame(width:24,height:28) }.accessibilityLabel("Ajustes")
 Button { model.close() } label: { Image(systemName:"xmark").frame(width:24,height:28) }.accessibilityLabel("Cerrar")
 }.buttonStyle(.plain).font(.system(size:11,weight:.medium))
 .padding(.horizontal,18).frame(height:30)
 } else {
 HStack(spacing:0) {
 if let event=reminder {
 HStack(spacing:5) { Image(systemName:"calendar").foregroundStyle(.mint);Text("\(calendar.reminderMinutes) min").font(.system(size:11,weight:.semibold)) }.frame(width:wingWidth)
 Spacer(minLength:0).frame(width:centerWidth)
 Text(event.title).font(.system(size:11,weight:.semibold)).lineLimit(1).padding(.horizontal,6).frame(width:wingWidth).help(event.title+" · "+event.start.formatted(date:.omitted,time:.shortened)).accessibilityLabel("Próximo evento: \(event.title), en \(calendar.reminderMinutes) minutos")
 } else {
 if playing { ArtworkView(music:music,size:20).frame(width:wingWidth) }
 Spacer(minLength:0).frame(width:centerWidth)
 if playing { Image(systemName:activity.latest != nil ? "checkmark" : activity.activeCount > 0 ? "ellipsis" : "waveform").font(.system(size:13)).frame(width:wingWidth) }
 }
 }.frame(height:model.headerHeight).frame(maxWidth:.infinity)
 }
 if expanded {
 VStack(spacing:8) {
 if activity.latest != nil && section == "IA" { Button("Codex ha terminado · Abrir") { activity.openCodex() }.buttonStyle(.plain).font(.caption).foregroundStyle(.mint) }
 if section == "Archivos" { ShelfView(store:local,model:model) }
 else if section == "Inicio" { HomeView(model:model,music:music,calendar:calendar,preferences:preferences,usage:usage,activity:activity,openCodex:{ selectedAI=$0;section="IA" }).frame(maxWidth:.infinity,maxHeight:.infinity) }
 else if section == "IA" { AIUsageView(usage:usage,activity:activity,statistics:statistics,selected:$selectedAI) }
 else { VStack(spacing:8) { Image(systemName:section == "Codex" ? "terminal" : "music.note").font(.largeTitle); Text(section == "Codex" ? "Conecta Codex desde Ajustes" : "Conecta Apple Music y Calendario desde Ajustes").foregroundStyle(.secondary) }.frame(maxWidth:.infinity,maxHeight:.infinity) }
 if let message=local.message { Text(message).font(.caption).foregroundStyle(.orange) }
 }.padding(.horizontal,18).padding(.top,8).padding(.bottom,12).frame(maxHeight:.infinity)
 .transition(.opacity.combined(with:.scale(scale:reduced ? 1 : 0.96,anchor:.top)))
 }
 }.frame(width:width,height:expanded ? model.expandedSize.height : model.compactSize.height,alignment:.top)
 .foregroundStyle(.white).background(.black,in:UnevenRoundedRectangle(bottomLeadingRadius:expanded ? 24 : 12,bottomTrailingRadius:expanded ? 24 : 12))
 .overlay {
 CompletionRailView(trigger:activity.completionPulse,enabled:preferences.value.aiVisualEnabled,reduceMotion:reduced,cornerRadius:expanded ? 24 : 12,notchWidth:model.notchWidth,notchHeight:model.headerHeight,physicalNotch:model.hasPhysicalNotch)
 }
 .overlay { if model.hovered && !expanded { UnevenRoundedRectangle(bottomLeadingRadius:12,bottomTrailingRadius:12).stroke(.white.opacity(0.16),lineWidth:1).allowsHitTesting(false) } }
 .scaleEffect(x:model.hovered && !expanded ? 1.035 : 1,y:model.hovered && !expanded ? 1.10 : 1,anchor:.top)
 .animation(reduced ? nil : .spring(response:0.28,dampingFraction:0.75),value:model.hovered)
 .shadow(color:.black.opacity(expanded ? 0.3 : 0),radius:12,y:6)
 .animation(reduced ? .easeOut(duration:0.15) : .spring(response:0.35,dampingFraction:0.9),value:model.compactSize)
 .animation(reduced ? .easeOut(duration:0.15) : .spring(response:expanded ? 0.38 : 0.32,dampingFraction:expanded ? 0.8 : 0.9),value:expanded)
 .frame(maxWidth:.infinity,maxHeight:.infinity,alignment:.top)
 // WindowServer passes fully transparent pixels through to the app underneath.
 // Paint the compact activation strip, including the area below the camera.
 .background(expanded ? Color.clear : Color.black.opacity(0.01))
 .preferredColorScheme(.dark)
 .contentShape(Rectangle())
 .contextMenu {
 Picker("Modo luna",selection:$preferences.value.aiNotificationMode) {
 ForEach(AINotificationMode.allCases,id:\.self) { mode in Text(mode.title).tag(mode) }
 }
 Button(model.state.pinned ? "Desfijar isla" : "Fijar isla") { model.toggle() }
 Divider()
 Button("Ajustes…",action:settings)
 Divider()
 Button("Salir de Isla") { NSApp.terminate(nil) }
 }
 .onChange(of:section) { _,value in model.trayMode = value == "Archivos" }
 .onExitCommand { model.close() }
 .onDrop(of:[UTType.fileURL],isTargeted:$dragging) { providers in section="Archivos"; model.enter(); return ShelfService.accept(providers,into:local) }
 .onChange(of:dragging) { _,active in if active { section="Archivos"; model.enter() } }
 }
}
