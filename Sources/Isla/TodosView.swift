import SwiftUI
@MainActor struct TodosView: View {
 @ObservedObject var store: LocalStore
 @State private var title = ""
 func add() { store.addTask(title); title = "" }
 var body: some View {
  VStack(spacing: 10) {
   HStack {
    TextField("Nueva tarea",text:$title).textFieldStyle(.roundedBorder).onSubmit(add).accessibilityLabel("Nueva tarea")
    Button("Añadir",action:add).disabled(title.trimmingCharacters(in:.whitespacesAndNewlines).isEmpty)
   }
   ScrollView {
    LazyVStack(spacing:8) {
     if store.document.tasks.isEmpty { Text("Tus tareas aparecerán aquí.").foregroundStyle(.secondary).padding(.top,20) }
     ForEach($store.document.tasks) { $task in
      HStack {
       Toggle(isOn:$task.completed) { Text(task.title).strikethrough(task.completed).foregroundStyle(task.completed ? .secondary : .primary) }.toggleStyle(.checkbox)
       Spacer()
       Button { store.document.tasks.removeAll { $0.id == task.id }; store.scheduleSave() } label: { Image(systemName:"trash") }.buttonStyle(.plain).accessibilityLabel("Eliminar tarea: \(task.title)")
      }.padding(10).background(.white.opacity(0.06),in:RoundedRectangle(cornerRadius:8))
     }
    }
   }
  }
 }
}
