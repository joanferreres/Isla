import SwiftUI
import IslandCore
@MainActor struct AIAccountRing:View {
 @ObservedObject var service:AIUsageService
 var size:CGFloat=32
 var body:some View {
 let fraction=service.enabled ? service.snapshot?.windows.first?.usedFraction : nil
 ZStack {
 Circle().stroke(.white.opacity(0.10),lineWidth:3)
 if let fraction { Circle().trim(from:0,to:fraction).stroke(service.stale ? Color.gray : .mint,style:StrokeStyle(lineWidth:3,lineCap:.round)).rotationEffect(.degrees(-90)) }
 if let url=NSWorkspace.shared.urlForApplication(withBundleIdentifier:service.provider == .cursor ? "com.todesktop.230313mzl4w4u92" : "com.anthropic.claudefordesktop") {
 Image(nsImage:NSWorkspace.shared.icon(forFile:url.path)).resizable().scaledToFit().frame(width:size*0.62,height:size*0.62).clipShape(RoundedRectangle(cornerRadius:4))
 } else { Image(systemName:service.provider == .cursor ? "cursorarrow" : "asterisk").font(.system(size:size*0.45,weight:.medium)).foregroundStyle(service.provider == .claude ? .orange : .white) }
 }.frame(width:size,height:size).accessibilityLabel("Consumo de \(service.provider.title)").accessibilityValue(fraction.map{"\(Int($0*100)) por ciento consumido"} ?? "Sin datos")
 }
}
@MainActor struct AIHomeAccount:View {
 @ObservedObject var service:AIUsageService
 let open:() -> Void
 var body:some View {
 Button(action:open) {
 HStack(spacing:9) {
 AIAccountRing(service:service)
 VStack(alignment:.leading,spacing:3) {
 Text(service.provider.title).font(.system(size:12,weight:.semibold))
 Text(service.snapshot?.windows.first.map{"\(Int($0.remainingPercent)) % libre"+(service.stale ? " · antiguo" : "")} ?? (service.loading ? "Consultando…" : "Sin datos")).font(.system(size:10)).foregroundStyle(.secondary).lineLimit(1)
 }
 Spacer(minLength:0)
 }.frame(maxWidth:.infinity,alignment:.leading).contentShape(Rectangle())
 }.buttonStyle(.plain).help(service.error ?? "Ver límites de \(service.provider.title)")
 }
}
@MainActor struct AIHomeRow:View {
 @ObservedObject var usage:CodexUsageService
 @ObservedObject var activity:CodexActivityService
 @ObservedObject var preferences:PreferencesStore
 @ObservedObject private var cursor=AIUsageAccounts.shared.cursor
 @ObservedObject private var claude=AIUsageAccounts.shared.claude
 let open:(String) -> Void
 var vertical=false
 var body:some View {
 let showCodex=preferences.value.showCodexOnHome && usage.notchReady
 let showCursor=preferences.value.showCursorOnHome && preferences.value.cursorEnabled && cursor.notchReady
 let showClaude=preferences.value.showClaudeOnHome && preferences.value.claudeEnabled && claude.notchReady
 let layout=vertical ? AnyLayout(VStackLayout(alignment:.leading,spacing:10)) : AnyLayout(HStackLayout(spacing:14))
 layout {
 if showCodex {
 Button { open("Codex") } label: {
 HStack(spacing:9) {
 CodexUsageRing(fraction:usage.snapshot?.homeUsage?.usedFraction,stale:usage.stale,size:32,reduceMotion:preferences.value.reduceMotion)
 VStack(alignment:.leading,spacing:3) {
 Text("Codex").font(.system(size:12,weight:.semibold))
 Text(usage.snapshot?.homeUsage.map{"\(Int($0.remainingPercent)) % libre"} ?? "Sin datos").font(.system(size:10)).foregroundStyle(.secondary).lineLimit(1)
 };Spacer(minLength:0)
 }.frame(maxWidth:.infinity,alignment:.leading).contentShape(Rectangle())
 }.buttonStyle(.plain)
 }
 if showCursor { AIHomeAccount(service:cursor,open:{ open("Cursor") }) }
 if showClaude { AIHomeAccount(service:claude,open:{ open("Claude") }) }
 }.frame(height:vertical ? nil : 38).clipped()
 }
 static func showsAny(preferences:Preferences,usage:CodexUsageService,cursor:AIUsageService,claude:AIUsageService) -> Bool {
 (preferences.showCodexOnHome && usage.notchReady)
 || (preferences.showCursorOnHome && preferences.cursorEnabled && cursor.notchReady)
 || (preferences.showClaudeOnHome && preferences.claudeEnabled && claude.notchReady)
 }
}
@MainActor struct AIUsageView:View {
 @ObservedObject var usage:CodexUsageService
 @ObservedObject var activity:CodexActivityService
 @ObservedObject var statistics:StatisticsStore
 @ObservedObject private var cursor=AIUsageAccounts.shared.cursor
 @ObservedObject private var claude=AIUsageAccounts.shared.claude
 @Binding var selected:String
 var body:some View {
 let tabs=readyTabs
 VStack(spacing:8) {
 if tabs.isEmpty {
 VStack(spacing:8) {
 Image(systemName:"sparkles").font(.largeTitle)
 Text("Ninguna cuenta de IA lista").font(.headline)
 Text("Conecta Codex, Cursor o Claude en Ajustes → IA. Solo aparecen en el notch cuando la consulta de límites funciona.").font(.caption).foregroundStyle(.secondary).multilineTextAlignment(.center)
 }.frame(maxWidth:.infinity,maxHeight:.infinity)
 } else {
 Picker("Cuenta de IA",selection:$selected) {
 ForEach(tabs,id:\.self) { tab in Text(tab).tag(tab) }
 }.pickerStyle(.segmented)
 .onAppear { if !tabs.contains(selected) { selected=tabs[0] } }
 .onChange(of:tabs) { _, next in if !next.contains(selected),let first=next.first { selected=first } }
 if selected == "Codex" { CodexView(usage:usage,activity:activity,statistics:statistics) }
 else if selected == "Cursor" { AIAccountDetail(service:cursor) }
 else if selected == "Claude" { AIAccountDetail(service:claude) }
 }
 }
 }
 private var readyTabs:[String] {
 var tabs:[String]=[]
 if usage.notchReady { tabs.append("Codex") }
 if cursor.notchReady { tabs.append("Cursor") }
 if claude.notchReady { tabs.append("Claude") }
 return tabs
 }
}
@MainActor struct AIAccountDetail:View {
 @ObservedObject var service:AIUsageService
 var body:some View {
 ScrollView {
 VStack(alignment:.leading,spacing:10) {
 HStack { AIAccountRing(service:service);Text(service.provider.title).font(.headline);Spacer();Button { Task { await service.refresh(interactive:true) } } label: { Image(systemName:"arrow.clockwise") }.buttonStyle(.plain).disabled(!service.enabled || service.loading).accessibilityLabel("Actualizar \(service.provider.title)") }
 if service.provider == .claude { Text("Límites de Claude Desktop y Claude Code con la misma cuenta").font(.caption).foregroundStyle(.secondary) }
 if !service.enabled { Text("Conecta \(service.provider.title) en Ajustes → IA.").foregroundStyle(.secondary) }
 if service.loading { ProgressView().controlSize(.small) }
 if let snapshot=service.snapshot {
 ForEach(snapshot.windows) { window in
 VStack(alignment:.leading,spacing:4) {
 HStack { Text(service.provider.label(window.id));Spacer();Text("\(Int(window.remainingPercent)) % restante").monospacedDigit() }
 ProgressView(value:window.usedFraction).tint(service.stale ? .gray : .mint)
 if let reset=window.resetsAt { Text("Reinicio: \(reset.formatted(date:.abbreviated,time:.shortened))").font(.caption2).foregroundStyle(.secondary) }
 }
 }
 Text("\(service.stale ? "Dato antiguo · " : "")Actualizado \(snapshot.fetchedAt.formatted(date:.omitted,time:.shortened))").font(.caption2).foregroundStyle(.secondary)
 }
 if let error=service.error { Text(error).font(.caption).foregroundStyle(.orange) }
 }.font(.system(size:12)).frame(maxWidth:.infinity,alignment:.leading)
 }
 }
}
@MainActor struct AIAccountSettings:View {
 @ObservedObject var service:AIUsageService
 @Binding var enabled:Bool
 @Binding var showOnHome:Bool
 var body:some View {
 Section {
 HStack(spacing:12) { AIAccountRing(service:service,size:44);VStack(alignment:.leading,spacing:4) { Text(service.provider.title).font(.headline);Text(service.provider == .claude ? "Claude Desktop o Claude Code (mismos límites)" : "Usa tu sesión de la app de Cursor").font(.caption).foregroundStyle(.secondary) } }
 Toggle("Conectar \(service.provider.title)",isOn:$enabled)
 Toggle("Mostrar \(service.provider.title) en Inicio",isOn:$showOnHome).disabled(!service.notchReady)
 if !service.notchReady,enabled {
 Text("No se muestra en el notch hasta que la consulta de límites funcione (pulsa Actualizar).").font(.caption).foregroundStyle(.secondary)
 }
 if let error=service.error { Text(error).font(.caption).foregroundStyle(.orange) }
 if enabled {
 if service.provider == .claude {
 Button(service.accessRequested ? "Volver a conectar Claude" : "Permitir acceso a Claude") { Task { await service.refresh(interactive:true) } }.disabled(service.loading)
 Text("Límites: app Claude (sesión Desktop) o «claude auth login». El EQ también acepta API key (Ajustes → Música o ANTHROPIC_API_KEY).").font(.caption).foregroundStyle(.secondary)
 }
 if service.provider == .cursor {
 Text("Isla lee la sesión cifrada de la app Cursor; macOS puede pedir acceso a «Cursor Safe Storage».").font(.caption).foregroundStyle(.secondary)
 }
 Button("Actualizar \(service.provider.title)") { Task { await service.refresh(interactive:true) } }.disabled(service.loading)
 }
 } header: { Text(service.provider.title) }
 }
}
