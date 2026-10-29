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
 Text(service.enabled ? service.snapshot?.windows.first.map{"\(Int($0.remainingPercent)) % libre"+(service.stale ? " · antiguo" : "")} ?? (service.loading ? "Consultando…" : "Sin datos") : "Desconectado").font(.system(size:10)).foregroundStyle(.secondary).lineLimit(1)
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
 let open:(String) -> Void
 var vertical=false
 var body:some View {
 let layout=vertical ? AnyLayout(VStackLayout(alignment:.leading,spacing:10)) : AnyLayout(HStackLayout(spacing:14))
 layout {
 if preferences.value.showCodexOnHome {
 Button { open("Codex") } label: {
 HStack(spacing:9) {
 CodexUsageRing(fraction:usage.enabled ? usage.snapshot?.homeUsage?.usedFraction : nil,stale:usage.stale,size:32,reduceMotion:preferences.value.reduceMotion)
 VStack(alignment:.leading,spacing:3) {
 Text("Codex").font(.system(size:12,weight:.semibold))
 Text(usage.enabled ? usage.snapshot?.homeUsage.map{"\(Int($0.remainingPercent)) % libre"} ?? "Sin datos" : "Desconectado").font(.system(size:10)).foregroundStyle(.secondary).lineLimit(1)
 };Spacer(minLength:0)
 }.frame(maxWidth:.infinity,alignment:.leading).contentShape(Rectangle())
 }.buttonStyle(.plain)
 }
 if preferences.value.showCursorOnHome && preferences.value.cursorEnabled { AIHomeAccount(service:AIUsageAccounts.shared.cursor,open:{ open("Cursor") }) }
 if preferences.value.showClaudeOnHome && preferences.value.claudeEnabled { AIHomeAccount(service:AIUsageAccounts.shared.claude,open:{ open("Claude") }) }
 }.frame(height:vertical ? nil : 38).clipped()
 }
}
@MainActor struct AIUsageView:View {
 @ObservedObject var usage:CodexUsageService
 @ObservedObject var activity:CodexActivityService
 @ObservedObject var statistics:StatisticsStore
 @Binding var selected:String
 var body:some View {
 VStack(spacing:8) {
 Picker("Cuenta de IA",selection:$selected) { Text("Codex").tag("Codex");Text("Cursor").tag("Cursor");Text("Claude").tag("Claude") }.pickerStyle(.segmented)
 if selected == "Codex" { CodexView(usage:usage,activity:activity,statistics:statistics) }
 else if selected == "Cursor" { AIAccountDetail(service:AIUsageAccounts.shared.cursor) }
 else { AIAccountDetail(service:AIUsageAccounts.shared.claude) }
 }
 }
}
@MainActor struct AIAccountDetail:View {
 @ObservedObject var service:AIUsageService
 var body:some View {
 ScrollView {
 VStack(alignment:.leading,spacing:10) {
 HStack { AIAccountRing(service:service);Text(service.provider.title).font(.headline);Spacer();Button { Task { await service.refresh() } } label: { Image(systemName:"arrow.clockwise") }.buttonStyle(.plain).disabled(!service.enabled || service.loading).accessibilityLabel("Actualizar \(service.provider.title)") }
 if service.provider == .claude { Text("Límites de Claude Code y de Claude con la misma cuenta").font(.caption).foregroundStyle(.secondary) }
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
 HStack(spacing:12) { AIAccountRing(service:service,size:44);VStack(alignment:.leading,spacing:4) { Text(service.provider.title).font(.headline);Text(service.provider == .claude ? "Claude y Claude Code con la misma cuenta" : "Usa tu sesión de la app de Cursor").font(.caption).foregroundStyle(.secondary) } }
 Toggle("Conectar \(service.provider.title)",isOn:$enabled)
 Toggle("Mostrar \(service.provider.title) en Inicio",isOn:$showOnHome)
 if let error=service.error { Text(error).font(.caption).foregroundStyle(.orange) }
 if enabled {
 if service.provider == .claude && !service.accessRequested {
 Button("Permitir acceso a Claude") { Task { await service.refresh(interactive:true) } }.disabled(service.loading)
 Text("Se lee la sesión de Claude Code. La autorización se recuerda. No se volverá a pedir automáticamente.").font(.caption).foregroundStyle(.secondary)
 }
 Button("Actualizar \(service.provider.title)") { Task { await service.refresh() } }.disabled(service.loading)
 }
 } header: { Text(service.provider.title) }
 }
}
