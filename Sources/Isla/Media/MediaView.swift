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
 Text(music.state.snapshot?.title ?? (music.enabled ? "Música en pausa" : "Música")).font(.system(size:12,weight:.semibold)).lineLimit(1)
 Text(music.state.snapshot?.artist ?? (music.enabled ? "Elige una canción" : "Conectar en Ajustes")).font(.caption2).foregroundStyle(.secondary).lineLimit(1)
 }.frame(maxWidth:.infinity,alignment:.leading)
 if music.enabled,music.state.snapshot != nil { EQModeMenu() }
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

/// Labelled audio-mode pill for the notch: readable without knowing what the icon means.
@MainActor struct EQModeMenu:View {
 @ObservedObject private var eq=AdaptiveEQController.shared
 var body:some View {
 Menu {
 Text("Tipo de audio")
 Divider()
 Button { eq.enableAdaptive() } label: { Label("Adaptativo · se ajusta a la canción y a tu salida",systemImage:eq.adaptive ? "checkmark.circle.fill" : "waveform.path") }
 Button { eq.resetFlat() } label: { Label("Original · sin ecualizar",systemImage:eq.adaptive ? "speaker.wave.2" : "checkmark.circle.fill") }
 } label: {
 HStack(spacing:5) {
 Image(systemName:eq.adaptive ? "waveform.path.ecg" : "speaker.wave.2.fill").font(.system(size:11,weight:.semibold))
 VStack(alignment:.leading,spacing:0) {
 Text("AUDIO").font(.system(size:7,weight:.bold)).tracking(0.8).opacity(0.65)
 Text(eq.adaptive ? "Adaptativo" : "Original").font(.system(size:11,weight:.semibold))
 }
 Image(systemName:"chevron.down").font(.system(size:8,weight:.bold)).opacity(0.7)
 }
 .foregroundStyle(eq.adaptive ? Color.cyan : Color.white)
 .padding(.horizontal,9).padding(.vertical,5)
 .background(Capsule().fill((eq.adaptive ? Color.cyan : Color.white).opacity(0.14)))
 .overlay(Capsule().strokeBorder((eq.adaptive ? Color.cyan : Color.white).opacity(0.35),lineWidth:1))
 }
 .menuStyle(.borderlessButton).menuIndicator(.hidden).fixedSize()
 .accessibilityLabel("Tipo de audio")
 .help(eq.adaptive ? "Adaptativo: ajusta graves, medios y agudos a cada canción y a tu salida (altavoces, auriculares, AirPods)" : "Original: sin ecualizar")
 }
}
