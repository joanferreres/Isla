import SwiftUI
import IslandCore
@MainActor struct ArtworkView:View {
 @ObservedObject var music:AppleMusicService
 let size:CGFloat
 @State private var artwork:NSImage?
 var body:some View {
 Group { if let artwork { Image(nsImage:artwork).resizable().scaledToFill() } else { Image(systemName:"music.note").resizable().scaledToFit().padding(size*0.22).foregroundStyle(.gray).background(Color(white:0.12)) } }
 .frame(width:size,height:size).clipShape(RoundedRectangle(cornerRadius:size < 30 ? 4 : 14)).accessibilityLabel("Carátula de la canción actual")
 .onChange(of:music.state.artworkData,initial:true) { _,data in artwork=data.flatMap(NSImage.init(data:)) }
 }
}
@MainActor struct MediaView:View {
 @ObservedObject var music:AppleMusicService
 let island:IslandModel
 var body:some View {
 VStack(alignment:.leading,spacing:6) {
 HStack(alignment:.center,spacing:10) {
 ArtworkView(music:music,size:42)
 VStack(alignment:.leading,spacing:4) {
 Text(music.state.snapshot?.title ?? (music.enabled ? "Apple Music en pausa" : "Apple Music")).font(.system(size:12,weight:.semibold)).lineLimit(1)
 Text(music.state.snapshot?.artist ?? (music.enabled ? "Elige una canción" : "Conectar en Ajustes")).font(.caption2).foregroundStyle(.secondary).lineLimit(1)
 }.frame(maxWidth:.infinity,alignment:.leading)
 }
 if let snapshot=music.state.snapshot {
 TimelineView(.animation(minimumInterval:1,paused:!music.enabled || !snapshot.playing)) { context in ProgressView(value:music.displayPosition(at:context.date),total:max(1,snapshot.duration)).tint(.white) }
 HStack(spacing:0) {
 Button { music.send(.previous) } label: { Image(systemName:"backward.fill") }.accessibilityLabel("Anterior")
 .frame(maxWidth:.infinity)
 Button { music.send(.playPause) } label: { Image(systemName:snapshot.playing ? "pause.fill" : "play.fill") }.accessibilityLabel(snapshot.playing ? "Pausar" : "Reproducir")
 .frame(maxWidth:.infinity)
 Button { music.send(.next) } label: { Image(systemName:"forward.fill") }.accessibilityLabel("Siguiente")
 .frame(maxWidth:.infinity)
 if music.enabled {
 RecordPlaylistPicker(track:snapshot,island:island).id(snapshot.trackID)
 .frame(maxWidth:.infinity)
 }
 }.buttonStyle(.plain).font(.system(size:16)).frame(maxWidth:.infinity,minHeight:24)
 }
 if let error=music.error { Text(error).font(.caption2).foregroundStyle(.orange).lineLimit(3) }
 Spacer(minLength:0)
 }
 }
}
