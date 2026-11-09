import SwiftUI
import IslandCore

enum RecordPlayerPalette: String, CaseIterable, Identifiable {
    case noir, blue, amber, emerald, lilac, ruby, silver, turquoise, copper, lime

    var id: Self { self }

    private var style: (title: String, shortcut: String, background: UInt32, accent: UInt32, ink: UInt32, vinyl: UInt32, metal: UInt32) {
        switch self {
        case .noir:    ("Noir",      "0", 0x101012, 0xF6F4EF, 0xFCFBF8, 0x1C1C1F, 0x929399)
        case .blue:    ("Azul",      "1", 0x0B1017, 0x7AB0FF, 0xEBF2FF, 0x0E1117, 0xA1B8D6)
        case .amber:   ("Ámbar",     "2", 0x170F0B, 0xFAB563, 0xFFF0DB, 0x1A110D, 0xC7A87D)
        case .emerald: ("Esmeralda", "3", 0x0B1915, 0x72E2B3, 0xE1FFF2, 0x10231E, 0x90C2AB)
        case .lilac:   ("Lavanda",   "4", 0x171021, 0xC4ACFF, 0xF4EBFF, 0x1E172B, 0xBBAACE)
        case .ruby:    ("Rubí",      "5", 0x1E0D15, 0xFF8EA9, 0xFFEDF1, 0x2C1420, 0xD5A2AE)
        case .silver:  ("Plata",     "6", 0x141619, 0xD9E1EE, 0xF1F4F8, 0x22252A, 0xBDC6D3)
        case .turquoise: ("Turquesa", "7", 0x071A22, 0x59DBF0, 0xE1FBFF, 0x0C2730, 0x8BBBC5)
        case .copper:  ("Cobre",     "8", 0x21130E, 0xE99273, 0xFFF0E6, 0x302018, 0xBC937D)
        case .lime:    ("Lima",      "9", 0x171A0C, 0xD0EE69, 0xF7FFE1, 0x232813, 0xA6B87B)
        }
    }

    var title: String { style.title }
    var shortcut: String { style.shortcut }
    var background: NSColor { color(style.background) }
    var accent: Color { Color(nsColor: color(style.accent)) }
    var ink: Color { Color(nsColor: color(style.ink)) }
    var vinyl: Color { Color(nsColor: color(style.vinyl)) }
    var metal: Color { Color(nsColor: color(style.metal)) }

    private func color(_ rgb: UInt32) -> NSColor {
        NSColor(srgbRed: Double((rgb >> 16) & 0xFF) / 255,
                green: Double((rgb >> 8) & 0xFF) / 255,
                blue: Double(rgb & 0xFF) / 255, alpha: 1)
    }
}

@MainActor struct RecordPlayerView: View {
    @ObservedObject var music: AppleMusicService
    @ObservedObject var preferences: PreferencesStore
    @ObservedObject var presentation: RecordPlayerPresentation
    @Environment(\.accessibilityReduceMotion) private var systemReduceMotion
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @StateObject private var speakerBattery = BluetoothSpeakerBattery()
    @State private var artwork: NSImage?
    @State private var showsAmbiences = false
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
    private var reduceMotion: Bool { systemReduceMotion || preferences.value.reduceMotion }

    var body: some View {
        GeometryReader { proxy in
            let diameter = max(120, min(660, (proxy.size.width - 294) / 1.22, (proxy.size.height - 176) / 1.22))
            let snapshot = music.state.snapshot
            let ticking = presentation.isVisible && music.enabled && snapshot?.playing == true
            let spinning = ticking && !reduceMotion
            ZStack {
                HStack(spacing: diameter * 0.14 + 14) {
                    turntable(diameter: diameter, snapshot: snapshot, ticking: ticking, spinning: spinning)
                    RecordPlayerMixer(music: music, palette: palette,
                                      active: presentation.isVisible && music.enabled)
                        .frame(width: 220)
                }
                .padding(.leading, diameter * 0.11)
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
        .onChange(of: presentation.isVisible, initial: true) { _, visible in speakerBattery.setVisible(visible) }
        .onDisappear { speakerBattery.setVisible(false) }
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
        return TimelineView(.animation(minimumInterval: spinning ? 1.0 / 20 : 1, paused: !ticking)) { context in
            let elapsed = playbackSeconds(snapshot, at: context.date)
            let duration = snapshot?.duration ?? 0
            let progress = duration > 0 ? min(1, elapsed / duration) : 0
            let phase = elapsed.truncatingRemainder(dividingBy: 3.6) * 100
            let playing = snapshot?.playing == true
            VinylRecord(artwork: artwork, palette: palette, rotation: reduceMotion ? 0 : phase)
                .frame(width: diameter, height: diameter)
                .modifier(RecordSwipeGesture(diameter: diameter, reduceMotion: reduceMotion,
                                             trackID: music.enabled ? snapshot?.trackID : nil) { direction, trackID in
                    music.send(direction == .next ? .next : .previous, trackID: trackID)
                })
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
            if let battery = speakerBattery.reading {
                Label("\(battery.percent) %", systemImage: battery.symbol)
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
                    .fixedSize()
                    .accessibilityLabel("Batería de \(battery.name)")
                    .accessibilityValue("\(battery.percent) por ciento")
                    .help(battery.name)
            }
            if let snapshot, music.enabled {
                RecordPlaylistPicker(track: snapshot).id(snapshot.trackID)
            }
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
        playerButton {
            showsAmbiences = true
        } label: {
            Image(systemName: "command")
        }
        .accessibilityLabel("Elegir ambiente")
        .help("Mantén pulsado para ver los ambientes")
        .simultaneousGesture(LongPressGesture(minimumDuration: 0.35).onEnded { _ in
            showsAmbiences = true
        })
        .popover(isPresented: $showsAmbiences, arrowEdge: .top) {
            VStack(alignment: .leading, spacing: 12) {
                Text("Ambientes").font(.headline).accessibilityAddTraits(.isHeader)
                LazyVGrid(columns: [GridItem(.fixed(134)), GridItem(.fixed(134))], spacing: 8) {
                    ForEach(RecordPlayerPalette.allCases) { item in
                        ambienceButton(item)
                    }
                }
            }
            .fixedSize(horizontal: true, vertical: false)
            .padding(14)
            .onChange(of: palette) { _, _ in showsAmbiences = false }
        }
        .onChange(of: presentation.isVisible) { _, visible in
            if !visible { showsAmbiences = false }
        }
    }

    private func ambienceButton(_ item: RecordPlayerPalette) -> some View {
        let selected = item == palette
        return playerButton(tint: selected ? item.accent : nil) {
            presentation.select(item)
            showsAmbiences = false
        } label: {
            HStack(spacing: 8) {
                Circle()
                    .fill(item.vinyl)
                    .strokeBorder(item.metal, lineWidth: 1)
                    .overlay(Circle().fill(item.accent).frame(width: 8, height: 8))
                    .frame(width: 22, height: 22)
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 1) {
                    Text(item.title).font(.callout.weight(.medium))
                    Text("⌘\(item.shortcut)").font(.caption.monospacedDigit())
                        .foregroundStyle(selected ? .primary : .secondary)
                }
                Spacer(minLength: 0)
                if selected {
                    Image(systemName: "checkmark").font(.caption.weight(.semibold))
                }
            }
        }
        .accessibilityLabel(item.title)
        .accessibilityAddTraits(selected ? .isSelected : [])
        .keyboardShortcut(KeyEquivalent(Character(item.shortcut)), modifiers: .command)
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

    // Each ring reuses the same outline. Only its size, angle and opacity change.
    private static let outline = Path { path in
        for sample in 0..<96 {
            let angle = Double(sample) * 2 * .pi / 96
            let radius = 1 + 0.007 * (sin(9 * angle) + 0.45 * sin(13 * angle))
            let point = CGPoint(x: radius * cos(angle), y: radius * sin(angle))
            if sample == 0 { path.move(to: point) } else { path.addLine(to: point) }
        }
        path.closeSubpath()
    }

    var body: some View {
        Canvas { context, size in
            let center = CGPoint(x: size.width / 2, y: size.height / 2)
            let cycle = elapsed / 3.2
            for index in 0..<3 {
                let offset = cycle + Double(index) / 3
                let phase = offset.truncatingRemainder(dividingBy: 1)
                let radius = diameter * (0.501 + 0.092 * phase)
                let opacity = sin(.pi * phase) * (1 - 0.55 * phase)
                let transform = CGAffineTransform(translationX: center.x, y: center.y)
                    .rotated(by: phase * 2 * .pi / 9)
                    .scaledBy(x: radius, y: radius)
                let wave = Self.outline.applying(transform)
                context.stroke(wave, with: .color(accent.opacity(0.56 * opacity)), lineWidth: 1.15)
            }
        }
    }
}

struct VinylRecord: View {
    let artwork: NSImage?
    let palette: RecordPlayerPalette
    let rotation: Double

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
                .rotationEffect(.degrees(rotation))
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
        .allowsHitTesting(false)
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
