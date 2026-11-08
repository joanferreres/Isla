import SwiftUI
import IslandCore

@MainActor struct RecordPlayerView: View {
    @ObservedObject var music: AppleMusicService
    @ObservedObject var preferences: PreferencesStore
    @ObservedObject var visibility: RecordPlayerVisibility
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var artwork: NSImage?

    private let ink = Color(red: 0.95, green: 0.91, blue: 0.83)
    private let brass = Color(red: 0.84, green: 0.69, blue: 0.44)
    private let base = Color(red: 0.085, green: 0.077, blue: 0.067)

    var body: some View {
        GeometryReader { proxy in
            let wide = proxy.size.width >= 820
            let margin = min(64, max(22, proxy.size.width * 0.045))
            let width = proxy.size.width - 2 * margin
            let height = proxy.size.height - 2 * margin
            let diameter = max(150, min(660, wide
                ? min(width * 0.54 / 1.13, height)
                : min(width / 1.13, height - 210)))
            let snapshot = music.state.snapshot
            let ticking = visibility.isVisible && snapshot?.playing == true
            let spinning = ticking && !reduceMotion && !preferences.value.reduceMotion
            Group {
                if wide {
                    HStack(spacing: min(64, width * 0.055)) {
                        turntable(diameter: diameter, playing: snapshot?.playing == true, spinning: spinning)
                        information(snapshot, wide: true, ticking: ticking)
                    }
                } else {
                    VStack(spacing: 18) {
                        turntable(diameter: diameter, playing: snapshot?.playing == true, spinning: spinning)
                        information(snapshot, wide: false, ticking: ticking)
                    }
                }
            }
            .frame(width: width, height: height)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .foregroundStyle(ink)
        .background(base.ignoresSafeArea())
        .preferredColorScheme(.dark)
        .onChange(of: music.state.artworkData, initial: true) { _, data in
            artwork = data.flatMap(NSImage.init(data:))
        }
    }

    private func turntable(diameter: CGFloat, playing: Bool, spinning: Bool) -> some View {
        let width = diameter * 1.13
        return ZStack(alignment: .leading) {
            TimelineView(.animation(minimumInterval: 1.0 / 30, paused: !spinning)) { context in
                VinylRecord(artwork: artwork, brass: brass)
                    .frame(width: diameter, height: diameter)
                    .rotationEffect(.degrees((music.displayPosition(at: context.date) * 200).truncatingRemainder(dividingBy: 360)))
            }
            Tonearm(playing: playing, brass: brass)
                .frame(width: width, height: diameter)
        }
        .frame(width: width, height: diameter)
        .accessibilityHidden(true)
    }

    private func information(_ snapshot: MediaSnapshot?, wide: Bool, ticking: Bool) -> some View {
        VStack(alignment: wide ? .leading : .center, spacing: wide ? 16 : 8) {
            Label("Apple Music", systemImage: "music.note")
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(brass)
            VStack(alignment: wide ? .leading : .center, spacing: 5) {
                Text(snapshot?.title ?? "Sin música")
                    .font(.system(size: wide ? 44 : 26, weight: .medium, design: .serif))
                    .lineLimit(wide ? 3 : 1)
                    .minimumScaleFactor(0.75)
                    .accessibilityAddTraits(.isHeader)
                if let snapshot, !snapshot.artist.isEmpty {
                    Text(snapshot.artist).font(.system(size: wide ? 18 : 14))
                        .foregroundStyle(ink.opacity(0.72)).lineLimit(1)
                }
            }
            if let snapshot {
                if snapshot.duration > 0 {
                    TimelineView(.animation(minimumInterval: 1, paused: !ticking)) { context in
                        let elapsed = music.displayPosition(at: context.date)
                        VStack(spacing: 5) {
                            ProgressView(value: elapsed, total: snapshot.duration)
                                .tint(brass)
                                .accessibilityLabel("Progreso de reproducción")
                            HStack {
                                Text(clock(elapsed)); Spacer(); Text(clock(snapshot.duration))
                            }
                            .font(.caption.monospacedDigit()).foregroundStyle(ink.opacity(0.68))
                        }
                    }
                    .frame(maxWidth: wide ? .infinity : 350)
                }
                transport(playing: snapshot.playing)
            } else {
                Text(preferences.value.musicEnabled ? "Reproduce una canción en Música." : "Conecta Apple Music para ver la canción y la carátula.")
                    .font(.callout).foregroundStyle(ink.opacity(0.72))
                    .multilineTextAlignment(wide ? .leading : .center)
                if preferences.value.musicEnabled {
                    Button("Abrir Música") {
                        if let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: "com.apple.Music") {
                            NSWorkspace.shared.openApplication(at: url, configuration: .init()) { _, _ in }
                        }
                    }
                } else {
                    Button("Conectar Apple Music") { preferences.value.musicEnabled = true }
                }
            }
            if let error = music.error {
                Text(error).font(.caption).foregroundStyle(brass).lineLimit(2)
            }
        }
        .frame(maxWidth: .infinity, alignment: wide ? .leading : .center)
    }

    private func transport(playing: Bool) -> some View {
        HStack(spacing: 10) {
            Button { music.send(.previous) } label: {
                Image(systemName: "backward.end.fill").frame(width: 44, height: 44)
            }.accessibilityLabel("Canción anterior")
            Button { music.send(.playPause) } label: {
                Image(systemName: playing ? "pause.fill" : "play.fill")
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(Color.black)
                    .frame(width: 50, height: 50)
                    .background(brass, in: Circle())
            }.accessibilityLabel(playing ? "Pausar" : "Reproducir")
            Button { music.send(.next) } label: {
                Image(systemName: "forward.end.fill").frame(width: 44, height: 44)
            }.accessibilityLabel("Siguiente canción")
        }
        .buttonStyle(.borderless)
    }

    private func clock(_ seconds: Double) -> String {
        guard seconds.isFinite, seconds >= 0, seconds < Double(Int.max) else { return "–:––" }
        let total = Int(seconds)
        return String(format: "%d:%02d", total / 60, total % 60)
    }
}

private struct VinylRecord: View {
    let artwork: NSImage?
    let brass: Color

    var body: some View {
        GeometryReader { proxy in
            let size = proxy.size.width
            ZStack {
                Circle().fill(Color(white: 0.075))
                Canvas { context, dimensions in
                    let center = CGPoint(x: dimensions.width / 2, y: dimensions.height / 2)
                    for index in 0..<44 {
                        let radius = size * (0.195 + Double(index) * 0.00675)
                        let ring = CGRect(x: center.x - radius, y: center.y - radius, width: radius * 2, height: radius * 2)
                        context.stroke(Path(ellipseIn: ring), with: .color(.white.opacity(index.isMultiple(of: 7) ? 0.19 : 0.065)), lineWidth: 0.65)
                    }
                }
                Circle().strokeBorder(.white.opacity(0.16), lineWidth: 1)
                Group {
                    if let artwork {
                        Image(nsImage: artwork).resizable().scaledToFill()
                    } else {
                        Circle().fill(brass.opacity(0.78))
                            .overlay(Circle().strokeBorder(.black.opacity(0.30), lineWidth: 1).padding(size * 0.04))
                    }
                }
                .frame(width: size * 0.36, height: size * 0.36)
                .clipShape(Circle())
                .overlay(Circle().strokeBorder(.black.opacity(0.45), lineWidth: 1))
                Circle().fill(.black).frame(width: size * 0.022, height: size * 0.022)
                    .overlay(Circle().strokeBorder(.white.opacity(0.3), lineWidth: 1))
            }
        }
    }
}

private struct Tonearm: View {
    let playing: Bool
    let brass: Color

    var body: some View {
        Canvas { context, size in
            let d = size.height
            let pivot = CGPoint(x: d * 1.025, y: d * 0.145)
            let elbow = CGPoint(x: d * (playing ? 0.965 : 1.025), y: d * 0.52)
            let tip = CGPoint(x: d * (playing ? 0.805 : 1.025), y: d * 0.705)
            func circle(_ center: CGPoint, _ radius: CGFloat) -> Path {
                Path(ellipseIn: CGRect(x: center.x - radius, y: center.y - radius, width: radius * 2, height: radius * 2))
            }
            var arm = Path(); arm.move(to: pivot); arm.addLine(to: elbow); arm.addLine(to: tip)
            context.stroke(arm, with: .color(.black.opacity(0.5)), style: StrokeStyle(lineWidth: d * 0.022, lineCap: .round, lineJoin: .round))
            context.stroke(arm, with: .color(brass), style: StrokeStyle(lineWidth: d * 0.010, lineCap: .round, lineJoin: .round))
            context.fill(circle(pivot, d * 0.042), with: .color(Color(white: 0.17)))
            context.stroke(circle(pivot, d * 0.034), with: .color(brass.opacity(0.75)), lineWidth: 1)
            context.fill(circle(pivot, d * 0.012), with: .color(brass))
            context.fill(circle(tip, d * 0.014), with: .color(brass))
        }
    }
}
