import SwiftUI
@MainActor struct CodexView:View {
 @ObservedObject var usage:CodexUsageService
 @ObservedObject var activity:CodexActivityService
 @ObservedObject var statistics:StatisticsStore
 var body:some View {
 ScrollView { VStack(alignment:.leading,spacing:12) {
 HStack(spacing:10) { CodexUsageRing(fraction:usage.enabled ? usage.snapshot?.homeUsage?.usedFraction : nil,stale:usage.stale,size:34); VStack(alignment:.leading,spacing:3) { Text("Codex").font(.headline);Text(activity.activeCount > 0 ? "\(activity.activeCount) turnos en curso" : "Límites y estadísticas").font(.caption).foregroundStyle(.secondary) };Spacer();Button { Task { await usage.refresh() } } label: { Image(systemName:"arrow.clockwise") }.buttonStyle(.plain).disabled(usage.loading || !usage.enabled).accessibilityLabel("Actualizar uso") }
 if !usage.enabled { Text("Conecta Codex en Ajustes").foregroundStyle(.secondary) }
 if usage.loading { ProgressView().controlSize(.small) }
 if let snapshot=usage.snapshot {
 ForEach(snapshot.windows) { window in
 VStack(alignment:.leading,spacing:4) { HStack { Text(label(window.id));Spacer();Text("\(Int(window.remainingPercent)) % restante").monospacedDigit() };ProgressView(value:window.usedFraction,total:1).tint(usage.stale ? .gray : window.usedFraction < 0.5 ? .mint : window.usedFraction < 0.7 ? .yellow : .orange);if let reset=window.resetsAt { Text("Reinicio: \(reset.formatted(date:.abbreviated,time:.shortened))").font(.caption2).foregroundStyle(.secondary) } }
 }
 if let balance=snapshot.creditRemaining { Text("Saldo: \(balance.formatted()) \(snapshot.creditUnit ?? "")") }
 Text("\(usage.stale ? "Dato antiguo · " : "")Actualizado \(snapshot.fetchedAt.formatted(date:.omitted,time:.shortened))").font(.caption2).foregroundStyle(usage.stale ? .orange : .gray)
 }
 if let error=usage.error { Text(error).font(.caption).foregroundStyle(.orange) }
 StatisticsView(statistics:statistics)
 Text("Sesiones locales detectadas: \(activity.foundSessions)").font(.caption2).foregroundStyle(.secondary)
 }.font(.system(size:12)).frame(maxWidth:.infinity,alignment:.leading) }
 .onAppear { if let date=usage.snapshot?.fetchedAt,Date().timeIntervalSince(date)>60 { Task { await usage.refresh() } } }
 }
 func label(_ id:String) -> String { switch id { case "primary_window":return "Ventana corta";case "secondary_window":return "Ventana semanal";case "review_primary_window":return "Revisión de código · ventana corta";case "review_secondary_window":return "Revisión de código · semanal";default:return id.replacingOccurrences(of:"_",with:" ") } }
}
