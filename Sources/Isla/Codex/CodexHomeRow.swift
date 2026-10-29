import SwiftUI
import IslandCore

/// CodeNotch's visual convention: a grey track, usage clockwise from twelve,
/// and a separate, explicit activity status. Unknown usage never draws a zero arc.
struct CodexUsageRing:View {
 let fraction:Double?
 var stale=false
 var size:CGFloat=44
 var reduceMotion=false
 @Environment(\.accessibilityReduceMotion) private var systemReduceMotion
 var ink:Color { stale ? .gray : (fraction ?? 0) < 0.5 ? .mint : (fraction ?? 0) < 0.7 ? .yellow : .orange }
 var body:some View {
 ZStack {
 Circle().strokeBorder(Color.primary.opacity(0.12),lineWidth:size*0.132)
 if let fraction {
 Circle().inset(by:size*0.066).trim(from:0,to:max(0,min(1,fraction)))
 .stroke(ink,style:StrokeStyle(lineWidth:size*0.068,lineCap:.round)).rotationEffect(.degrees(-90))
 }
 CodexLogo().fill(.primary,style:FillStyle(eoFill:true)).frame(width:size*0.38,height:size*0.38)
 }.frame(width:size,height:size).opacity(stale ? 0.55 : 1)
 .animation(reduceMotion || systemReduceMotion ? nil : .easeOut(duration:0.3),value:fraction)
 .accessibilityHidden(true)
 }
}
@MainActor struct CodexHomeRow:View {
 @ObservedObject var usage:CodexUsageService
 @ObservedObject var activity:CodexActivityService
 var reduceMotion=false
 let open:() -> Void
 var body:some View {
 TimelineView(.periodic(from:.now,by:30)) { context in
 let window=usage.enabled ? usage.snapshot?.homeUsage : nil
 let stale=usage.stale || (usage.snapshot.map { context.date.timeIntervalSince($0.fetchedAt)>600 } ?? false)
 Button(action:open) {
 HStack(spacing:12) {
 VStack(spacing:2) {
 CodexUsageRing(fraction:window?.usedFraction,stale:stale,size:36,reduceMotion:reduceMotion)
 Text(window.map { "\(Int($0.usedFraction*100)) %" } ?? "—").font(.system(size:10,weight:.medium)).monospacedDigit().foregroundStyle(stale ? .gray : .white)
 }
 VStack(alignment:.leading,spacing:3) {
 Text("Codex").font(.system(size:12,weight:.semibold))
 Text(status(stale:stale)).font(.caption2).foregroundStyle(activity.activeCount > 0 ? .mint : .secondary).lineLimit(1)
 }.layoutPriority(1)
 Spacer(minLength:4)
 VStack(alignment:.trailing,spacing:3) {
 if let window {
 Text("\(Int(window.remainingPercent)) % libre").font(.system(size:12,weight:.medium)).monospacedDigit()
 Text("Ventana corta\(stale ? " · dato antiguo" : "")").font(.caption2).foregroundStyle(stale ? .orange : .secondary)
 } else {
 Text(usage.enabled ? "Sin lectura" : "Sin conectar").font(.caption).foregroundStyle(.secondary)
 }
 }
 Image(systemName:"chevron.right").font(.system(size:10,weight:.semibold)).foregroundStyle(.tertiary)
 }.contentShape(Rectangle())
 }.buttonStyle(.plain)
 .help("El anillo muestra el consumo de la ventana corta. Pulsa para ver límites, reinicios y estadísticas.")
 .accessibilityLabel("Codex, \(window.map { "\(Int($0.usedFraction*100)) por ciento consumido" } ?? "consumo no disponible"), \(status(stale:stale)). Ver detalles")
 }.frame(height:54).fixedSize(horizontal:false,vertical:true)
 }
 private func status(stale:Bool) -> String {
 if !usage.enabled { return "Conectar en Ajustes" }
 if activity.activeCount > 0 { return "\(activity.activeCount) en curso" }
 if activity.latest != nil { return "Ha terminado" }
 if usage.loading { return "Actualizando…" }
 if usage.error != nil { return stale ? "Lectura antigua · revisar conexión" : "Revisar conexión" }
 return stale ? "Lectura antigua" : "Sin turnos en curso"
 }
}
