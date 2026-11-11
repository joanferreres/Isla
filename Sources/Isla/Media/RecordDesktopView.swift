import SwiftUI
import IslandCore

struct RecordDesktopView: View {
    @ObservedObject var music: AppleMusicService
    @ObservedObject var preferences: PreferencesStore
    @ObservedObject var presentation: RecordPlayerPresentation
    let openPlayer: () -> Void
    let close: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var artwork: NSImage?

    var body: some View {
        let snapshot = music.state.snapshot
        let palette = presentation.palette
        let spinning = presentation.isDesktopVisible && music.enabled && snapshot?.playing == true
            && !reduceMotion && !preferences.value.reduceMotion
        VStack(spacing: 7) {
            HStack(spacing: 0) {
                Label("Tocadiscos", systemImage: "record.circle")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, minHeight: 30, alignment: .leading)
                    .contentShape(Rectangle())
                    .gesture(WindowDragGesture())
                    .help("Arrastra para mover el tocadiscos")
                control("Abrir tocadiscos completo", symbol: "arrow.up.left.and.arrow.down.right", action: openPlayer)
                control("Ocultar del escritorio", symbol: "xmark", action: close)
            }
            TimelineView(.animation(minimumInterval: 1.0 / 30, paused: !spinning)) { context in
                let phase = spinning ? music.displayPosition(at: context.date).truncatingRemainder(dividingBy: 3.6) * 100 : 0
                VinylRecord(artwork: artwork, palette: palette, rotation: phase)
                    .frame(width: 91, height: 91)
                    .accessibilityHidden(true)
            }
            VStack(spacing: 2) {
                Text(snapshot?.title ?? "Sin música")
                    .font(.callout.weight(.semibold))
                    .lineLimit(1)
                Text(snapshot?.artist ?? "Apple Music")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            .frame(maxWidth: .infinity)
            HStack(spacing: 12) {
                control("Canción anterior", symbol: "backward.end.fill") { music.send(.previous) }
                control(snapshot?.playing == true ? "Pausar" : "Reproducir",
                        symbol: snapshot?.playing == true ? "pause.fill" : "play.fill") {
                    music.send(.playPause)
                }
                .foregroundStyle(palette.accent)
                control("Siguiente canción", symbol: "forward.end.fill") { music.send(.next) }
            }
            .disabled(!music.enabled || snapshot == nil)
        }
        .padding(.horizontal, 13)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .foregroundStyle(palette.ink)
        .background {
            RoundedRectangle(cornerRadius: 20)
                .fill(Color(nsColor: palette.background))
                .strokeBorder(palette.metal.opacity(0.25), lineWidth: 1)
        }
        .preferredColorScheme(.dark)
        .onChange(of: music.state.artworkData, initial: true) { _, data in
            artwork = data.flatMap(NSImage.init(data:))
        }
    }

    private func control(_ title: String, symbol: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.callout.weight(.semibold))
                .frame(width: 38, height: 38)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(title)
        .help(title)
    }
}
