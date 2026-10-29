import SwiftUI
@MainActor struct TimerView: View {
 @ObservedObject var store: TimerStore
 @State private var mode = "Cuenta atrás"
 private var minutes: Binding<Double> { Binding(get: { store.countdown.duration / 60 }, set: { store.configure(minutes:$0) }) }
 var body: some View {
  VStack(spacing:12) {
   Picker("Modo",selection:$mode) { Text("Cuenta atrás").tag("Cuenta atrás"); Text("Cronómetro").tag("Cronómetro") }.pickerStyle(.segmented).labelsHidden()
   if mode == "Cuenta atrás" {
    HStack { Text("Duración"); Stepper("\(Int(store.countdown.duration / 60)) min",value:minutes,in:1...180) }.disabled(store.countdown.isRunning)
    Text(store.finished ? "¡Tiempo cumplido!" : TimerStore.format(store.remaining,roundUp:true)).font(.system(size:34,weight:.medium,design:.rounded)).monospacedDigit().foregroundStyle(store.finished ? .mint : .white)
    HStack { Button(store.countdown.isRunning ? "Pausar" : "Iniciar",action:store.toggleCountdown).buttonStyle(.borderedProminent).tint(.mint); Button("Reiniciar",action:store.resetCountdown) }
   } else {
    Text(TimerStore.format(store.elapsed)).font(.system(size:34,weight:.medium,design:.rounded)).monospacedDigit()
    HStack { Button(store.stopwatch.isRunning ? "Pausar" : "Iniciar",action:store.toggleStopwatch).buttonStyle(.borderedProminent).tint(.mint); Button("Reiniciar",action:store.resetStopwatch) }
   }
   Spacer(minLength:0)
  }
 }
}
