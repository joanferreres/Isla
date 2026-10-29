import SwiftUI
@MainActor struct NotesView: View {
 @ObservedObject var store: LocalStore
 var body: some View {
  ZStack(alignment: .topLeading) {
   TextEditor(text: $store.document.note).scrollContentBackground(.hidden).font(.body).padding(6).accessibilityLabel("Nota personal")
   if store.document.note.isEmpty { Text("Escribe una nota…").foregroundStyle(.secondary).padding(12).allowsHitTesting(false) }
  }.background(.white.opacity(0.06),in:RoundedRectangle(cornerRadius:12))
 }
}
