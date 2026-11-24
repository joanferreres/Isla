import SwiftUI
import IslandCore

@MainActor struct RecordPlayerView: View {
    @ObservedObject var music: AppleMusicService
    @ObservedObject var preferences: PreferencesStore
    @ObservedObject var presentation: RecordPlayerPresentation
    @Environment(\.accessibilityReduceMotion) private var systemReduceMotion
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @StateObject private var speakerBattery = BluetoothSpeakerBattery()
    @State private var artwork: NSImage?
    @State private var showsAmbiences = false
    @State private var changerEpoch = 0
    @State private var shuffleOn = false
    @State private var shuffleBusy = false
    @State private var pendingCue: PendingCue?
    @State private var swapOffset: CGFloat = 0
    @State private var swapCommit: RecordSwipe?
    /// Bumped on every committed swipe so an older fold-back timer cannot undo a newer swipe.
    @State private var swapToken = 0
    @State private var outgoingArtwork: NSImage?
    @State private var holdingPlatter = false
    @State private var manualRotation = 0.0
    @State private var spinBias = 0.0
    @State private var frozenPhase = 0.0
    @State private var lastPhase = 0.0
    @State private var coastVelocity = 0.0
    /// Mechanical hand-off when loading a disc from the changer onto the platter.
    @State private var changerHandOff: ChangerHandOff?

    private struct ChangerHandOff {
        let outgoing: NSImage?
        let incoming: NSImage?
        var progress: CGFloat
    }

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
            // Half the disc selector sits outside the left window edge (clipsToBounds).
            let selectorDiameter: CGFloat = min(320, max(220, proxy.size.height * 0.55))
            let diameter = max(120, min(660,
                                        (proxy.size.width - 294 - selectorDiameter * 0.35) / 1.22,
                                        (proxy.size.height - 176) / 1.22))
            let snapshot = music.state.snapshot
            let ticking = presentation.isVisible && music.enabled && snapshot?.playing == true
            let spinning = ticking && !reduceMotion
            ZStack(alignment: .leading) {
                ZStack {
                    HStack(spacing: diameter * 0.14 + 14) {
                        turntable(diameter: diameter, snapshot: snapshot, ticking: ticking, spinning: spinning)
                            .overlay {
                                changerHandOffOverlay(diameter: diameter)
                            }
                        RecordPlayerMixer(
                            music: music,
                            preferences: preferences,
                            palette: palette,
                            active: presentation.isVisible && music.enabled
                        )
                            .frame(width: 220)
                    }
                    .padding(.leading, max(diameter * 0.08, selectorDiameter * 0.28))
                    VStack {
                        trackHeading(snapshot)
                        Spacer(minLength: 0)
                        playbackBar(snapshot, ticking: ticking)
                    }
                    .padding(.horizontal, 24)
                    .padding(.vertical, 14)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)

                if music.enabled,snapshot != nil,changerHandOff == nil {
                    RecordDiscChanger(
                        palette: palette,
                        reduceMotion: reduceMotion,
                        diameter: selectorDiameter,
                        currentTitle: snapshot?.title,
                        currentArtist: snapshot?.artist,
                        onPlay: { track, incoming, data in
                            await loadDiscFromChanger(trackID: track.id, incoming: incoming, primed: data)
                        }
                    )
                    .id(changerEpoch)
                    // Center on the leading edge → only the inner half stays on-screen.
                    .offset(x: -selectorDiameter * 0.5)
                    .frame(maxHeight: .infinity, alignment: .center)
                    .zIndex(30)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .foregroundStyle(ink)
        .background(Color(nsColor: palette.background).ignoresSafeArea())
        .preferredColorScheme(.dark)
        .onChange(of: presentation.isVisible, initial: true) { _, visible in
            speakerBattery.setVisible(visible)
            if visible { music.ensureNeighborCovers() }
        }
        .onDisappear { speakerBattery.setVisible(false) }
        .onChange(of: music.state.artworkData, initial: true) { _, data in
            if let image = data.flatMap(NSImage.init(data:)) {
                artwork = image
            } else if changerHandOff == nil {
                // Mid hand-off: keep the incoming changer cover — don't flash the old/empty art.
                artwork = nil
            }
        }
        .onChange(of: music.state.snapshot?.trackID, initial: true) { previous, trackID in
            if trackID != nil {
                if swapCommit != nil {
                    // New record landed: drop the outgoing disc and centre the incoming art.
                    let settle = reduceMotion ? nil : Animation.snappy(duration: 0.28)
                    withAnimation(settle) {
                        swapOffset = 0
                        swapCommit = nil
                        outgoingArtwork = nil
                    }
                    manualRotation = 0
                    spinBias = 0
                    coastVelocity = 0
                } else if let handOff = changerHandOff {
                    // Land the chosen cover on the platter immediately, then dismiss the overlay.
                    if let incoming = handOff.incoming { artwork = incoming }
                    let settle = reduceMotion ? nil : Animation.snappy(duration: 0.26)
                    withAnimation(settle) { changerHandOff = nil }
                    manualRotation = 0
                    spinBias = 0
                    coastVelocity = 0
                } else if previous != nil, previous != trackID {
                    manualRotation = 0
                    spinBias = 0
                    coastVelocity = 0
                }
                // Warm next/previous covers as soon as the landed track is known.
                music.ensureNeighborCovers()
            }
        }
        .onChange(of: music.state.snapshot) { _, snapshot in
            guard let cue = pendingCue else { return }
            if let snapshot, snapshot.trackID == cue.trackID, !cue.isConfirmed(by: snapshot) { return }
            pendingCue = nil
        }
        .onChange(of: holdingPlatter) { _, holding in
            if holding {
                frozenPhase = lastPhase
                coastVelocity = 0
            }
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
        let swapping = abs(swapOffset) > 0.5 || swapCommit != nil
        // Stay scheduled while audio is playing so the tonearm/progress keep moving.
        // Also tick while the platter is coasting after a hand spin.
        let coasting = abs(coastVelocity) > 1
        let live = ticking || coasting || holdingPlatter
        return TimelineView(.animation(minimumInterval: (spinning || coasting) ? 1.0 / 60 : 1, paused: !live)) { context in
            // Same clock as the progress bar, so the needle and the bar never disagree.
            let elapsed = music.displayPosition(at: context.date)
            let duration = snapshot?.duration ?? 0
            let progress = duration > 0 ? min(1, elapsed / duration) : 0
            // 33⅓ rpm = 200°/s. When paused (or Reduce Motion) the platter stays where it stopped
            // instead of snapping back to 0°; resuming continues from the same groove.
            let phase = spinning ? (elapsed * Self.degreesPerSecond).truncatingRemainder(dividingBy: 360) : lastPhase
            let platterPhase = (holdingPlatter || coasting) ? frozenPhase : phase
            let rotation = platterPhase + manualRotation + spinBias
            let playing = snapshot?.playing == true
            let incoming = incomingArtwork(for: swapOffset, commit: swapCommit)
            let frontArt = outgoingArtwork ?? artwork
            ZStack {
                if ticking && !swapping {
                    RecordSoundWaves(diameter: diameter,
                                     elapsed: spinning && !holdingPlatter ? elapsed : 0.8,
                                     accent: accent)
                        .frame(width: diameter * 1.22, height: diameter * 1.22)
                        .allowsHitTesting(false)
                }
                if swapping {
                    VinylRecord(artwork: incoming, palette: palette, rotation: rotation * 0.35)
                        .frame(width: diameter, height: diameter)
                        .scaleEffect(0.94 + 0.06 * min(1, abs(swapOffset) / max(1, diameter * 0.55)))
                        .offset(x: incomingOffset(swapOffset, diameter: diameter))
                        .opacity(0.88)
                        .allowsHitTesting(false)
                }
                VinylRecord(artwork: frontArt, palette: palette, rotation: rotation)
                    .frame(width: diameter, height: diameter)
                    .rotationEffect(.degrees(Double(swapOffset / max(1, diameter)) * 16))
                    .offset(x: swapOffset)
                    .opacity(swapping ? max(0.35, 1 - abs(swapOffset) / max(1, diameter * 0.9)) : 1)
            }
            .frame(width: diameter, height: diameter)
            .contentShape(Circle())
            .coordinateSpace(name: "recordPlatter")
            .modifier(RecordPlatterGestures(
                diameter: diameter,
                reduceMotion: reduceMotion,
                trackID: music.enabled ? snapshot?.trackID : nil,
                spinEnabled: music.enabled && snapshot != nil && !swapping,
                holding: $holdingPlatter,
                rotation: $manualRotation,
                onSwapPreview: { offset in
                    guard swapCommit == nil else { return }
                    swapOffset = offset
                    if abs(offset) < 0.5 { outgoingArtwork = nil }
                    else if outgoingArtwork == nil { outgoingArtwork = artwork }
                },
                onSwapFinish: { swipe, trackID in
                    finishSwap(swipe, trackID: trackID, diameter: diameter)
                },
                onSpinRelease: { velocity in
                    // frozenPhase was captured when the hand went down.
                    if abs(velocity) > 40 {
                        coastVelocity = max(-720, min(720, velocity))
                    } else {
                        spinBias = (frozenPhase + manualRotation + spinBias) - phase
                        manualRotation = 0
                        coastVelocity = 0
                    }
                }
            ))
            .accessibilityHidden(true)
            .overlay(alignment: .topLeading) {
                let preview = pendingCue.flatMap { $0.trackID == snapshot?.trackID ? $0 : nil }
                Tonearm(angle: preview?.angle ?? (playing ? RecordCue.angle(at: progress) : 0),
                        trackID: snapshot?.trackID, playing: playing, progress: progress,
                        canSeek: duration.isFinite && duration > 0 && !swapping, palette: palette,
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
            .onChange(of: context.date) { _, _ in
                if coasting, !holdingPlatter {
                    manualRotation += coastVelocity / 60
                    coastVelocity *= 0.935
                    if abs(coastVelocity) <= 8 {
                        spinBias = (frozenPhase + manualRotation + spinBias) - phase
                        manualRotation = 0
                        coastVelocity = 0
                    }
                } else if !holdingPlatter {
                    lastPhase = phase
                }
            }
        }
        .frame(width: diameter, height: diameter)
    }

    /// 33⅓ rpm, shared with the desktop turntable so both spin at the same speed.
    static let degreesPerSecond = 360.0 * (100.0 / 3.0) / 60.0

    private func parkArm(for snapshot: MediaSnapshot) {
        pendingCue = PendingCue(trackID: snapshot.trackID, fraction: nil)
        music.send(.pause, trackID: snapshot.trackID)
    }

    private func incomingArtwork(for offset: CGFloat, commit: RecordSwipe?) -> NSImage? {
        // Prefer the eagerly decoded trail covers so the second disc is never blank
        // while we convert Data → NSImage mid-gesture.
        let towardNext = commit.map { $0 == .next } ?? (offset < 0)
        return towardNext ? music.nextCover : music.previousCover
    }

    private func incomingOffset(_ offset: CGFloat, diameter: CGFloat) -> CGFloat {
        let park = diameter * 0.92
        if offset == 0, swapCommit == nil { return park }
        let towardNext = swapCommit.map { $0 == .next } ?? (offset < 0)
        let start = towardNext ? park : -park
        return start + offset
    }

    private func finishSwap(_ swipe: RecordSwipe?, trackID: String, diameter: CGFloat) {
        guard let swipe else {
            let animation = reduceMotion ? nil : Animation.snappy(duration: 0.24)
            withAnimation(animation) {
                swapOffset = 0
                outgoingArtwork = nil
            }
            return
        }
        outgoingArtwork = outgoingArtwork ?? artwork
        let exit = (swipe == .next ? -1 : 1) * diameter * 1.02
        let animation = reduceMotion ? nil : Animation.snappy(duration: 0.32)
        withAnimation(animation) {
            swapOffset = exit
            swapCommit = swipe
        }
        swapToken += 1
        let token = swapToken
        music.send(swipe == .next ? .next : .previous, trackID: trackID)
        // If Music never changes track, fold the preview back.
        Task { @MainActor in
            try? await Task.sleep(for: .seconds(2.4))
            guard swapToken == token, swapCommit == swipe else { return }
            withAnimation(reduceMotion ? nil : .snappy(duration: 0.28)) {
                swapOffset = 0
                swapCommit = nil
                outgoingArtwork = nil
            }
        }
    }

    private func trackHeading(_ snapshot: MediaSnapshot?) -> some View {
        VStack(spacing: 4) {
            Label(snapshot?.source.title ?? "Música", systemImage:snapshot?.source.symbol ?? "music.note")
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
                Text(preferences.value.musicEnabled ? "Reproduce una canción en Apple Music o Spotify." : "Conecta Música para ver la canción y la carátula.")
                    .font(.callout).foregroundStyle(ink.opacity(0.72))
                    .multilineTextAlignment(.leading)
                if preferences.value.musicEnabled {
                    playerButton {
                        music.openPreferredPlayer(preferences.value.musicSource)
                    } label: {
                        Text(preferences.value.musicSource == .spotify ? "Abrir Spotify" : "Abrir Música")
                    }
                } else {
                    playerButton(tint: accent) {
                        preferences.value.musicEnabled = true
                    } label: {
                        Text("Conectar música")
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
            if music.enabled {
                shuffleButton
            }
            if music.enabled,snapshot != nil {
                RecordQueuePlaylistButton {
                    // playPlaylist turns Music shuffle off — mirror that in the toggle.
                    shuffleOn = false
                    changerEpoch += 1
                }
            }
            if let snapshot,music.enabled {
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
            if !visible {
                showsAmbiences = false
                changerHandOff = nil
            }
        }
    }

    @ViewBuilder private var shuffleButton: some View {
        let button = Button {
            guard !shuffleBusy else { return }
            shuffleBusy = true
            let target = !shuffleOn
            Task {
                defer { shuffleBusy = false }
                do {
                    shuffleOn = try await music.shuffle(target)
                    music.error = nil
                } catch {
                    music.error = error.localizedDescription
                }
            }
        } label: {
            Group {
                if shuffleBusy {
                    ProgressView().controlSize(.small)
                } else {
                    Image(systemName: "shuffle")
                }
            }
            .frame(minWidth: 24, minHeight: 32)
        }
        .buttonBorderShape(.capsule)
        .disabled(shuffleBusy)
        .accessibilityLabel(shuffleOn ? "Desactivar aleatorio" : "Activar aleatorio")
        .accessibilityValue(shuffleOn ? "Activado" : "Desactivado")
        .help(shuffleOn
              ? "Aleatorio activado — pulsa para desactivar. Elegir una playlist lo apaga."
              : "Aleatorio desactivado — pulsa para activar el shuffle")
        .task(id: presentation.isVisible) {
            guard presentation.isVisible, music.enabled else { return }
            if let enabled = try? await music.shuffle() {
                shuffleOn = enabled
            }
        }
        if #available(macOS 26.0, *), !reduceTransparency {
            if shuffleOn {
                button.buttonStyle(.glassProminent).tint(accent)
            } else {
                button.buttonStyle(.glass)
            }
        } else if shuffleOn {
            button.buttonStyle(.borderedProminent).tint(accent)
        } else {
            button.buttonStyle(.bordered)
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

    /// Animate the playing disc off the platter and the chosen disc onto it, then cue Music.
    private func loadDiscFromChanger(trackID: String, incoming: NSImage?, primed: Data?) async -> String? {
        let outgoing = artwork
        // Paint the main disc from the fan cover immediately — don't wait on Music.
        if let incoming { artwork = incoming }
        music.primeArtwork(primed, for: trackID)
        withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.55)) {
            changerHandOff = ChangerHandOff(outgoing: outgoing, incoming: incoming, progress: 0)
        }
        // Drive progress so the playing disc leaves and the chosen disc lands.
        withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.55)) {
            changerHandOff = ChangerHandOff(outgoing: outgoing, incoming: incoming, progress: 1)
        }
        if !reduceMotion {
            try? await Task.sleep(for: .milliseconds(520))
        }
        do {
            try await music.playPlaylistTrack(trackID, primedCover: primed)
            if let incoming { artwork = incoming }
            return nil
        } catch {
            withAnimation(reduceMotion ? nil : .snappy(duration: 0.25)) {
                changerHandOff = nil
            }
            return error.localizedDescription
        }
    }

    @ViewBuilder
    private func changerHandOffOverlay(diameter: CGFloat) -> some View {
        if let handOff = changerHandOff {
            let travel = diameter * 0.92
            let size = diameter * 0.78
            ZStack {
                if let outgoing = handOff.outgoing {
                    Image(nsImage: outgoing)
                        .resizable()
                        .scaledToFill()
                        .frame(width: size, height: size)
                        .clipShape(Circle())
                        .overlay(Circle().strokeBorder(.white.opacity(0.15), lineWidth: 1))
                        // Changer lives on the left — disc leaves toward it.
                        .offset(x: -travel * handOff.progress, y: -travel * 0.12 * handOff.progress)
                        .opacity(1 - Double(handOff.progress))
                        .scaleEffect(1 - 0.18 * handOff.progress)
                        .allowsHitTesting(false)
                }
                if let incoming = handOff.incoming {
                    Image(nsImage: incoming)
                        .resizable()
                        .scaledToFill()
                        .frame(width: size, height: size)
                        .clipShape(Circle())
                        .overlay(Circle().strokeBorder(.white.opacity(0.2), lineWidth: 1))
                        .offset(x: -travel * (1 - handOff.progress), y: travel * 0.08 * (1 - handOff.progress))
                        .opacity(0.35 + 0.65 * Double(handOff.progress))
                        .scaleEffect(0.82 + 0.18 * handOff.progress)
                        .allowsHitTesting(false)
                }
            }
            .allowsHitTesting(false)
        }
    }
}
