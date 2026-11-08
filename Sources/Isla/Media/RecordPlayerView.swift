import SwiftUI
import IslandCore

enum RecordPlayerPalette: String, CaseIterable, Identifiable {
    case blue, amber

    var id: Self { self }
    var title: String { self == .blue ? "Azul" : "Ámbar" }
    var shortcut: String { self == .blue ? "1" : "2" }
    var background: NSColor {
        self == .blue ? NSColor(srgbRed: 0.045, green: 0.061, blue: 0.091, alpha: 1)
            : NSColor(srgbRed: 0.092, green: 0.061, blue: 0.043, alpha: 1)
    }
    var accent: Color { self == .blue ? Color(red: 0.48, green: 0.69, blue: 1) : Color(red: 0.98, green: 0.71, blue: 0.39) }
    var ink: Color { self == .blue ? Color(red: 0.92, green: 0.95, blue: 1) : Color(red: 1, green: 0.94, blue: 0.86) }
    var vinyl: Color { self == .blue ? Color(red: 0.055, green: 0.067, blue: 0.09) : Color(red: 0.10, green: 0.067, blue: 0.051) }
    var metal: Color { self == .blue ? Color(red: 0.63, green: 0.72, blue: 0.84) : Color(red: 0.78, green: 0.66, blue: 0.49) }
}

@MainActor struct RecordPlayerView: View {
    @ObservedObject var music: AppleMusicService
    @ObservedObject var preferences: PreferencesStore
    @ObservedObject var presentation: RecordPlayerPresentation
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @State private var artwork: NSImage?
    @State private var pendingCue: PendingCue?

    private struct PendingCue: Equatable {
        let trackID: String
        let fraction: Double?
        let issuedAt = Date()

        var angle: Double { fraction.map(RecordCue.angle(at:)) ?? 0 }

        func isConfirmed(by snapshot: MediaSnapshot) -> Bool {
            guard let fraction else { return !snapshot.playing }
            let target = min(max(0, snapshot.duration - 0.25), fraction * snapshot.duration)
            let elapsed = Date().timeIntervalSince(issuedAt)
            return snapshot.playing && snapshot.position >= target - 0.75
                && snapshot.position <= target + elapsed + 0.75
        }
    }

    private var palette: RecordPlayerPalette { presentation.palette }
    private var ink: Color { palette.ink }
    private var accent: Color { palette.accent }

    var body: some View {
        GeometryReader { proxy in
            let diameter = max(120, min(660, (proxy.size.width - 48) / 1.28, (proxy.size.height - 176) / 1.22))
            let snapshot = music.state.snapshot
            let ticking = presentation.isVisible && snapshot?.playing == true
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
        .background(Color(nsColor: palette.background).ignoresSafeArea())
        .preferredColorScheme(.dark)
        .onChange(of: music.state.artworkData, initial: true) { _, data in
            artwork = data.flatMap(NSImage.init(data:))
        }
        .onChange(of: music.state.snapshot) { _, snapshot in
            guard let cue = pendingCue else { return }
            if let snapshot, snapshot.trackID == cue.trackID, !cue.isConfirmed(by: snapshot) { return }
            pendingCue = nil
        }
        .onChange(of: music.error) { _, error in
            if error != nil { pendingCue = nil }
        }
        .task(id: pendingCue) {
            guard let cue = pendingCue else { return }
            try? await Task.sleep(for: .seconds(4))
            if !Task.isCancelled, pendingCue == cue { pendingCue = nil }
        }
    }

    private func turntable(diameter: CGFloat, snapshot: MediaSnapshot?, ticking: Bool, spinning: Bool) -> some View {
        let width = diameter * RecordCue.armWidth
        return TimelineView(.animation(minimumInterval: spinning ? 1.0 / 30 : 1, paused: !ticking)) { context in
            let elapsed = playbackSeconds(snapshot, at: context.date)
            let duration = snapshot?.duration ?? 0
            let progress = duration > 0 ? min(1, elapsed / duration) : 0
            let phase = elapsed.truncatingRemainder(dividingBy: 3.6) * 100
            let playing = snapshot?.playing == true
            VinylRecord(artwork: artwork, palette: palette)
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
                    let preview = pendingCue.flatMap { $0.trackID == snapshot?.trackID ? $0 : nil }
                    Tonearm(angle: preview?.angle ?? (playing ? RecordCue.angle(at: progress) : 0),
                            trackID: snapshot?.trackID, playing: playing, progress: progress,
                            canSeek: duration.isFinite && duration > 0, palette: palette,
                            animation: reduceMotion ? nil : .easeInOut(duration: 0.26),
                            tap: {
                                guard let snapshot else { return }
                                if playing {
                                    parkArm(for: snapshot)
                                } else {
                                    music.send(.playPause, trackID: snapshot.trackID)
                                }
                            },
                            drop: { fraction in
                                guard let snapshot else { return }
                                if let fraction {
                                    // Hold the chosen groove while Music reports the new position.
                                    pendingCue = PendingCue(trackID: snapshot.trackID, fraction: fraction)
                                    music.cue(to: fraction, trackID: snapshot.trackID)
                                } else if playing || pendingCue?.fraction != nil {
                                    parkArm(for: snapshot)
                                }
                            })
                    .frame(width: width, height: diameter)
                }
        }
        .frame(width: diameter, height: diameter)
    }

    private func parkArm(for snapshot: MediaSnapshot) {
        pendingCue = PendingCue(trackID: snapshot.trackID, fraction: nil)
        music.send(.pause, trackID: snapshot.trackID)
    }

    private func playbackSeconds(_ snapshot: MediaSnapshot?, at date: Date) -> Double {
        guard let snapshot, snapshot.position.isFinite else { return 0 }
        let running = snapshot.playing ? max(0, date.timeIntervalSince(music.receivedAt)) : 0
        return max(0, snapshot.position + running)
    }

    private func trackHeading(_ snapshot: MediaSnapshot?) -> some View {
        VStack(spacing: 4) {
            Label("Apple Music", systemImage: "music.note")
                .font(.caption.weight(.medium))
                .foregroundStyle(accent)
            Text(snapshot?.title ?? "Sin música")
                .font(.largeTitle.weight(.semibold))
                .foregroundStyle(.primary)
                .lineLimit(1)
                .minimumScaleFactor(0.75)
                .accessibilityAddTraits(.isHeader)
            if let snapshot, !snapshot.artist.isEmpty {
                Text(snapshot.artist).font(.subheadline)
                    .foregroundStyle(.secondary).lineLimit(1)
            }
        }
        .frame(maxWidth: 540)
        .allowsHitTesting(false)
    }

    private func playbackBar(_ snapshot: MediaSnapshot?, ticking: Bool) -> some View {
        let controls = HStack(spacing: 16) {
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
                    .multilineTextAlignment(.leading)
                if preferences.value.musicEnabled {
                    playerButton {
                        if let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: "com.apple.Music") {
                            NSWorkspace.shared.openApplication(at: url, configuration: .init()) { _, _ in }
                        }
                    } label: {
                        Text("Abrir Música")
                    }
                } else {
                    playerButton(tint: accent) {
                        preferences.value.musicEnabled = true
                    } label: {
                        Text("Conectar Apple Music")
                    }
                }
            }
            Divider().frame(height: 22).accessibilityHidden(true)
            paletteSelector
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 6)
        .frame(maxWidth: 560)
        return VStack(spacing: 5) {
            if let error = music.error {
                Text(error).font(.caption).foregroundStyle(accent).lineLimit(2)
            }
            playbackMaterial(controls)
        }
    }

    private var paletteSelector: some View {
        HStack(spacing: 6) {
            ForEach(RecordPlayerPalette.allCases) { item in
                playerButton(tint: item == palette ? item.accent : nil) {
                    presentation.select(item)
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: item == palette ? "checkmark" : "circle.fill")
                            .font(.caption2.weight(.semibold))
                            .foregroundStyle(item == palette ? Color.primary : item.accent)
                            .frame(width: 9)
                        Text("⌘\(item.shortcut)").font(.caption.monospacedDigit())
                    }
                }
                .accessibilityLabel("Ambiente \(item.title)")
                .accessibilityAddTraits(item == palette ? .isSelected : [])
                .help("Ambiente \(item.title) · ⌘\(item.shortcut)")
            }
        }
        .fixedSize(horizontal: true, vertical: false)
    }

    @ViewBuilder private func playbackMaterial<Content: View>(_ content: Content) -> some View {
        let shape = Capsule()
        if reduceTransparency {
            content.background(Color(white: 0.15), in: shape)
        } else if #available(macOS 26.0, *) {
            RecordPlaybackGlass(content: content)
        } else {
            content.background(.regularMaterial, in: shape)
        }
    }

    private func transport(playing: Bool) -> some View {
        HStack(spacing: 6) {
            playerButton { music.send(.previous) } label: {
                Image(systemName: "backward.end.fill")
            }
            .accessibilityLabel("Canción anterior")
            playerButton(tint: accent) { music.send(.playPause) } label: {
                Image(systemName: playing ? "pause.fill" : "play.fill")
                    .font(.body.weight(.semibold))
            }
            .accessibilityLabel(playing ? "Pausar" : "Reproducir")
            playerButton { music.send(.next) } label: {
                Image(systemName: "forward.end.fill")
            }
            .accessibilityLabel("Siguiente canción")
        }
    }

    @ViewBuilder private func playerButton<Label: View>(
        tint: Color? = nil, action: @escaping () -> Void, @ViewBuilder label: () -> Label
    ) -> some View {
        let button = Button(action: action) {
            label().frame(minWidth: 24, minHeight: 32)
        }
        .buttonBorderShape(.capsule)
        if #available(macOS 26.0, *), !reduceTransparency {
            if let tint {
                button.buttonStyle(.glassProminent).tint(tint)
            } else {
                button.buttonStyle(.glass)
            }
        } else if let tint {
            button.buttonStyle(.borderedProminent).tint(tint)
        } else {
            button.buttonStyle(.bordered)
        }
    }

    private func clock(_ seconds: Double) -> String {
        guard seconds.isFinite, seconds >= 0, seconds < Double(Int.max) else { return "–:––" }
        let total = Int(seconds)
        return String(format: "%d:%02d", total / 60, total % 60)
    }
}

@available(macOS 26.0, *)
private struct RecordPlaybackGlass<Content: View>: NSViewRepresentable {
    let content: Content

    func makeNSView(context: Context) -> NSGlassEffectView {
        let glass = NSGlassEffectView()
        glass.style = .clear
        glass.cornerRadius = 28
        if #available(macOS 27.0, *) { glass.effectIsInteractive = true }
        let controls = NSHostingView(rootView: content)
        controls.autoresizingMask = [.width, .height]
        glass.contentView = controls
        return glass
    }

    func updateNSView(_ glass: NSGlassEffectView, context: Context) {
        (glass.contentView as? NSHostingView<Content>)?.rootView = content
    }

    func sizeThatFits(_ proposal: ProposedViewSize, nsView: NSGlassEffectView, context: Context) -> CGSize? {
        let fittingHeight = nsView.contentView?.fittingSize.height ?? 0
        return CGSize(width: min(proposal.width ?? 560, 560), height: max(56, fittingHeight))
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
    let palette: RecordPlayerPalette

    var body: some View {
        GeometryReader { proxy in
            let size = proxy.size.width
            ZStack {
                Circle().fill(palette.vinyl)
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
                        Circle().fill(palette.accent.opacity(0.78))
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
    let trackID: String?
    let playing: Bool
    let progress: Double
    let canSeek: Bool
    let palette: RecordPlayerPalette
    let animation: Animation?
    let tap: () -> Void
    let drop: (Double?) -> Void
    @GestureState private var dragPoint: CGPoint?

    var body: some View {
        let cueAngle = dragPoint.map(RecordCue.angle(toward:)) ?? angle
        return Canvas { context, size in
            let d = size.height
            let pivot = CGPoint(x: d * RecordCue.pivot.x, y: d * RecordCue.pivot.y)
            let elbow = CGPoint(x: d * 1.047, y: d * 0.64)
            let tip = CGPoint(x: d * RecordCue.needle.x, y: d * RecordCue.needle.y)
            let metal = palette.metal
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
            context.fill(circle(pivot, d * 0.012), with: .color(palette.accent))
            let cartridge = CGRect(x: tip.x - d * 0.015, y: tip.y - d * 0.038, width: d * 0.03, height: d * 0.046)
            context.fill(Path(roundedRect: cartridge, cornerRadius: d * 0.004), with: .color(metal))
            context.fill(circle(tip, d * 0.007), with: .color(palette.accent))
        }
        .rotationEffect(.degrees(cueAngle), anchor: UnitPoint(x: RecordCue.pivot.x / RecordCue.armWidth, y: RecordCue.pivot.y))
        .animation(dragPoint == nil ? animation : nil, value: dragPoint == nil)
        .animation(dragPoint == nil ? animation : nil, value: trackID)
        .animation(dragPoint == nil ? animation : nil, value: playing)
        .accessibilityHidden(true)
        .overlay {
            if let trackID {
                GeometryReader { proxy in
                    let d = proxy.size.height
                    let tip = RecordCue.tip(at: cueAngle)
                    Button(action: tap) {
                        Color.clear.frame(width: 44, height: 44).contentShape(Circle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(playing ? "Levantar la aguja y pausar" : "Bajar la aguja y reproducir")
                    .accessibilityAdjustableAction { direction in
                        guard canSeek else { return }
                        switch direction {
                        case .increment: drop(min(1, progress + 0.05))
                        case .decrement: drop(max(0, progress - 0.05))
                        @unknown default: break
                        }
                    }
                    .help(canSeek ? "Arrastra la aguja a otro surco para saltar a ese punto" : "Pulsa para pausar o reproducir")
                    .highPriorityGesture(
                        DragGesture(minimumDistance: 6, coordinateSpace: .named("recordCue"))
                            .updating($dragPoint) { value, point, _ in
                                if canSeek { point = CGPoint(x: value.location.x / d, y: value.location.y / d) }
                            }
                            .onEnded { value in
                                guard canSeek else { return }
                                drop(RecordCue.progress(at: CGPoint(x: value.location.x / d, y: value.location.y / d)))
                            }
                    )
                    .position(x: d * tip.x, y: d * tip.y)
                }
                .id(trackID)
            }
        }
        .coordinateSpace(name: "recordCue")
    }
}
