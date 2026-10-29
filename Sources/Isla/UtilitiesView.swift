import SwiftUI
@MainActor struct UtilitiesView: View {
 @ObservedObject var store: LocalStore
 @ObservedObject var timer: TimerStore
 @State private var tab = "Notas"
 var body: some View {
  VStack(spacing: 10) {
   Picker("Utilidad",selection: $tab) { ForEach(["Notas","Tareas","Reloj"], id: \.self) { Text($0) } }.pickerStyle(.segmented).labelsHidden()
   switch tab {
   case "Tareas": TodosView(store: store)
   case "Reloj": TimerView(store: timer)
   default: NotesView(store: store)
   }
  }
 }
}
