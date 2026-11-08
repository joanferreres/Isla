import SwiftUI
import IslandCore

@MainActor enum RecordPlayerPalette {
    static let background = NSColor(srgbRed: 0.045, green: 0.061, blue: 0.091, alpha: 1)
    static let accent = Color(red: 0.48, green: 0.69, blue: 1.0)
    static let ink = Color(red: 0.92, green: 0.95, blue: 1.0)
}

@MainActor struct RecordPlayerView: View {
    @ObservedObject var music: AppleMusicService
    @ObservedObject var preferences: PreferencesStore
    @ObservedObject var visibility: RecordPlayerVisibility
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @State private var artwork: NSImage?

    private let ink = RecordPlayerPalette.ink
    private let accent = RecordPlayerPalette.accent

    var body: some View {
        GeometryReader { proxy in
            let diameter = max(120, min(660, (proxy.size.width - 48) / 1.28, proxy.size.height - 246))
            let snapshot = music.state.snapshot
            let ticking = visibility.isVisible && snapshot?.playing == true
            let spinning = ticking && !reduceMotion
            ZStack {
                turntable(diameter: diameter, snapshot: snapshot, ticking: ticking, spinning: spinning)
                VStack {
                    trackHeading(snapshot)
                    Spacer(minLength: 0)
                    playbackBar(snapshot, ticking: ticking)
                }
                .padding(.horizontal, 24)
                .padding(.vertical, 14)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .foregroundStyle(ink)
        .background(Color(nsColor: RecordPlayerPalette.background).ignoresSafeArea())
        .preferredColorScheme(.dark)
        .onChange(of: music.state.artworkData, initial: true) { _, data in
            artwork = data.flatMap(NSImage.init(data:))
        }
    }

    private func turntable(diameter: CGFloat, snapshot: MediaSnapshot?, ticking: Bool, spinning: Bool) -> some View {
        let width = diameter * 1.13
        return TimelineView(.animation(minimumInterval: spinning ? 1.0 / 30 : 1, paused: !ticking)) { context in
            let elapsed = playbackSeconds(snapshot, at: context.date)
            let duration = snapshot?.duration ?? 0
            let progress = duration > 0 ? min(1, elapsed / duration) : 0
            let phase = elapsed.truncatingRemainder(dividingBy: 3.6) * 100
            let playing = snapshot?.playing == true
            VinylRecord(artwork: artwork, accent: accent)
                .frame(width: diameter, height: diameter)
                .rotationEffect(.degrees(reduceMotion ? 0 : phase))
                .background {
                    if spinning {
                        RecordSoundWaves(diameter: diameter, elapsed: elapsed, accent: accent)
                            .frame(width: diameter * 1.22, height: diameter * 1.22)
                            .allowsHitTesting(false)
                    }
                }
                .accessibilityHidden(true)
                .overlay(alignment: .topLeading) {
                    Tonearm(angle: playing ? 18 + 24 * progress : 0, playing: playing, accent: accent) {
                        music.send(.pause)
                    }
                    .frame(width: width, height: diameter)
                    .animation(reduceMotion ? nil : .easeInOut(duration: 0.34), value: playing)
                }
        }
        .frame(width: diameter, height: diameter)
    }

    private func playbackSeconds(_ snapshot: MediaSnapshot?, at date: Date) -> Double {
        guard let snapshot, snapshot.position.isFinite else { return 0 }
        let running = snapshot.playing ? max(0, date.timeIntervalSince(music.receivedAt)) : 0
        return max(0, snapshot.position + running)
    }

    private func trackHeading(_ snapshot: MediaSnapshot?) -> some View {
        VStack(spacing: 4) {
            Label("Apple Music", systemImage: "music.note")
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(accent)
            Text(snapshot?.title ?? "Sin música")
                .font(.system(.largeTitle, design: .serif).weight(.medium))
                .lineLimit(1)
                .minimumScaleFactor(0.75)
                .accessibilityAddTraits(.isHeader)
            if let snapshot, !snapshot.artist.isEmpty {
                Text(snapshot.artist).font(.subheadline)
                    .foregroundStyle(ink.opacity(0.72)).lineLimit(1)
            }
        }
        .frame(maxWidth: 540)
        .allowsHitTesting(false)
    }

    private func playbackBar(_ snapshot: MediaSnapshot?, ticking: Bool) -> some View {
        let controls = VStack(spacing: 5) {
            if let snapshot {
                transport(playing: snapshot.playing)
                if snapshot.duration > 0 {
                    TimelineView(.animation(minimumInterval: 1, paused: !ticking)) { context in
                        let elapsed = music.displayPosition(at: context.date)
                        HStack(spacing: 10) {
                            Text(clock(elapsed))
                            ProgressView(value: elapsed, total: snapshot.duration)
                                .tint(accent)
                                .accessibilityLabel("Progreso de reproducción")
                            Text(clock(snapshot.duration))
                        }
                        .font(.caption.monospacedDigit()).foregroundStyle(ink.opacity(0.72))
                    }
                }
            } else {
                Text(preferences.value.musicEnabled ? "Reproduce una canción en Música." : "Conecta Apple Music para ver la canción y la carátula.")
                    .font(.callout).foregroundStyle(ink.opacity(0.72))
                    .multilineTextAlignment(.center)
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
                Text(error).font(.caption).foregroundStyle(accent).lineLimit(2)
            }
        }
        .padding(.horizontal, 22)
        .padding(.vertical, 10)
        .frame(maxWidth: 460)
        return playbackMaterial(controls)
    }

    @ViewBuilder private func playbackMaterial<Content: View>(_ content: Content) -> some View {
        let shape = RoundedRectangle(cornerRadius: 24)
        if reduceTransparency {
            content.background(Color(white: 0.15), in: shape)
        } else if #available(macOS 26.0, *) {
            content.glassEffect(.regular.tint(accent.opacity(0.14)), in: shape)
        } else {
            content.background(.regularMaterial, in: shape)
        }
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
                    .background(accent, in: Circle())
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

private struct RecordSoundWaves: View {
    let diameter: CGFloat
    let elapsed: Double
    let accent: Color

    var body: some View {
        Canvas { context, size in
            let center = CGPoint(x: size.width / 2, y: size.height / 2)
            let cycle = elapsed / 3.2
            for index in 0..<3 {
                let offset = cycle + Double(index) / 3
                let phase = offset.truncatingRemainder(dividingBy: 1)
                let radius = diameter * (0.501 + 0.092 * phase)
                let opacity = sin(.pi * phase) * (1 - 0.55 * phase)
                var wave = Path()
                for sample in 0..<96 {
                    let angle = Double(sample) * 2 * .pi / 96
                    let ripple = sin(9 * angle - 2 * .pi * phase) + 0.45 * sin(13 * angle + Double(index))
                    let distance = radius + diameter * 0.0035 * ripple
                    let point = CGPoint(x: center.x + distance * cos(angle), y: center.y + distance * sin(angle))
                    if sample == 0 { wave.move(to: point) } else { wave.addLine(to: point) }
                }
                wave.closeSubpath()
                context.stroke(wave, with: .color(accent.opacity(0.12 * opacity)), lineWidth: 4)
                context.stroke(wave, with: .color(accent.opacity(0.56 * opacity)), lineWidth: 1.15)
            }
        }
    }
}

private struct VinylRecord: View {
    let artwork: NSImage?
    let accent: Color

    var body: some View {
        GeometryReader { proxy in
            let size = proxy.size.width
            ZStack {
                Circle().fill(Color(red: 0.055, green: 0.067, blue: 0.09))
                Canvas { context, dimensions in
                    let center = CGPoint(x: dimensions.width / 2, y: dimensions.height / 2)
                    for index in 0..<44 {
                        let radius = size * (0.195 + Double(index) * 0.00675)
                        let ring = CGRect(x: center.x - radius, y: center.y - radius, width: radius * 2, height: radius * 2)
                        context.stroke(Path(ellipseIn: ring), with: .color(.white.opacity(index.isMultiple(of: 7) ? 0.18 : 0.064)), lineWidth: 0.65)
                    }
                }
                Circle().strokeBorder(.white.opacity(0.16), lineWidth: 1)
                Group {
                    if let artwork {
                        Image(nsImage: artwork).resizable().scaledToFill()
                    } else {
                        Circle().fill(accent.opacity(0.78))
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
    let angle: Double
    let playing: Bool
    let accent: Color
    let lift: () -> Void

    var body: some View {
        Canvas { context, size in
            let d = size.height
            let pivot = CGPoint(x: d * 1.025, y: d * 0.145)
            let elbow = CGPoint(x: d * 1.047, y: d * 0.64)
            let tip = CGPoint(x: d * 1.008, y: d * 0.876)
            let metal = Color(red: 0.63, green: 0.72, blue: 0.84)
            func circle(_ center: CGPoint, _ radius: CGFloat) -> Path {
                Path(ellipseIn: CGRect(x: center.x - radius, y: center.y - radius, width: radius * 2, height: radius * 2))
            }
            var arm = Path(); arm.move(to: pivot)
            arm.addQuadCurve(to: elbow, control: CGPoint(x: d * 1.057, y: d * 0.53))
            arm.addLine(to: tip)
            context.stroke(arm, with: .color(.black.opacity(0.5)), style: StrokeStyle(lineWidth: d * 0.022, lineCap: .round, lineJoin: .round))
            context.stroke(arm, with: .color(metal), style: StrokeStyle(lineWidth: d * 0.010, lineCap: .round, lineJoin: .round))
            context.fill(circle(pivot, d * 0.042), with: .color(Color(white: 0.17)))
            context.stroke(circle(pivot, d * 0.034), with: .color(metal), lineWidth: 1)
            context.fill(circle(pivot, d * 0.012), with: .color(accent))
            let cartridge = CGRect(x: tip.x - d * 0.015, y: tip.y - d * 0.038, width: d * 0.03, height: d * 0.046)
            context.fill(Path(roundedRect: cartridge, cornerRadius: d * 0.004), with: .color(metal))
            context.fill(circle(tip, d * 0.007), with: .color(accent))
        }
        .accessibilityHidden(true)
        .overlay {
            if playing {
                GeometryReader { proxy in
                    let d = proxy.size.height
                    Button(action: lift) {
                        Color.clear.frame(width: 44, height: 44).contentShape(Circle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Levantar la aguja y pausar")
                    .help("Pulsa o arrastra para levantar la aguja")
                    .simultaneousGesture(DragGesture(minimumDistance: 6).onEnded { _ in lift() })
                    .position(x: d * 1.008, y: d * 0.865)
                }
            }
        }
        .rotationEffect(.degrees(angle), anchor: UnitPoint(x: 1.025 / 1.13, y: 0.145))
    }
}
