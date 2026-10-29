import SwiftUI
import Charts
@MainActor struct StatisticsView:View {
 @ObservedObject var statistics:StatisticsStore
 @State var days=7
 var body:some View {
 let start=Date().addingTimeInterval(-Double(days)*86400)
 let readings=statistics.history.readings.filter{$0.fetchedAt >= start}
 let completions=statistics.history.completions.filter{$0.timestamp >= start}
 VStack(alignment:.leading,spacing:8) {
 HStack { Text("Estadísticas locales").fontWeight(.semibold);Spacer();Picker("Periodo",selection:$days) { Text("7 días").tag(7);Text("30 días").tag(30) }.pickerStyle(.segmented).frame(width:135) }
 Text("\(completions.count) turnos completados desde la activación").font(.caption)
 let tokens=completions.compactMap(\.reportedTokens)
 if !tokens.isEmpty { Text("\(tokens.reduce(0,+).formatted()) tokens reportados · \(tokens.count) turnos con datos").font(.caption2).foregroundStyle(.secondary) }
 if readings.isEmpty { Text("El historial se guardará al recibir datos de uso.").font(.caption).foregroundStyle(.secondary) }
 else {
 Chart { ForEach(Array(readings.enumerated()),id:\.offset) { _,reading in ForEach(reading.windows) { window in
 PointMark(x:.value("Fecha",reading.fetchedAt),y:.value("Restante",window.remainingPercent)).foregroundStyle(by:.value("Ventana",window.id))
 } } }.chartYScale(domain:0...100).frame(height:110)
 Text("Lecturas de uso restante; los huecos no representan consumo cero.").font(.caption2).foregroundStyle(.secondary)
 }
 if let error=statistics.error { Text(error).font(.caption2).foregroundStyle(.orange) }
 }
 }
}
