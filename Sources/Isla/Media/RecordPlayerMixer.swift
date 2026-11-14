import SwiftUI
import IslandCore

struct RecordPlayerMixer: View {
    let music: AppleMusicService
    @ObservedObject var preferences: PreferencesStore
    let palette: RecordPlayerPalette
    let active: Bool

    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @State private var equalizer = MusicEqualizer()
    @State private var claudeEQ = MusicClaudeEQService()
    @State private var gains: [MixerBand: Double] = [:]
    @State private var eqFailure: MusicEqualizer.Failure?
    @State private var eqRevision = 0
    @State private var showAccess = false
    @State private var offeredAccess = false
    @State private var volume: Int?
    @State private var confirmedVolume: Int?
    @State private var volumeRequest: Int?
    @State private var volumeError: String?
    @State private var presets: [String] = []
    @State private var selectedPreset: String?
    @State private var claudeStatus: String?
    @State private var lastClaudeTrackID: String?
    @State private var lastClaudeOutputKey: String?
    /// Normalized genre currently driving EQ (Music library or last Claude label).
    @State private var currentGenreKey: String?
    @State private var lastAppliedAdvice: MusicClaudeEQService.Advice?
    @StateObject private var audioOutput = MusicAudioOutputMonitor()

    /// Style entry in the EQ menu — enables Claude auto-EQ (not a Music factory preset).
    private static let claudeStyleName = "Claude"

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                presetMenu
                Spacer(minLength: 0)
                resetButton
            }
            HStack(spacing: 15) {
                VStack(spacing: 7) {
                    ForEach(MixerBand.allCases, id: \.self) { band in
                        EQKnob(title: band.title, gain: gains[band], accent: palette.accent) { value in
                            adjust(value, band: band)
                        }
                        .disabled(!active)
                    }
                }
                volumeFader
            }
            .fixedSize(horizontal: false, vertical: true)
            if preferences.value.musicClaudeEQEnabled {
                Text(claudeStatus ?? "Estilo Claude — EQ según música y salida (\(audioOutput.output.shortLabel))")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }
            if let volumeError {
                Text(volumeError).font(.caption2).foregroundStyle(.secondary)
            }
        }
        .padding(.horizontal, 10)
        .help(eqFailure?.localizedDescription ?? claudeStatus ?? "")
        .alert("Controlar el ecualizador de Música", isPresented: $showAccess) {
            Button("Abrir Accesibilidad") {
                if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") {
                    NSWorkspace.shared.open(url)
                }
            }
            Button("Ahora no", role: .cancel) {}
        } message: {
            Text(MusicEqualizer.Failure.access.localizedDescription)
        }
        .task(id: active) {
            audioOutput.setActive(active)
            guard active else { return }
            await readVolume()
            await loadPresets()
            if let current = try? await equalizer.read(), !Task.isCancelled {
                gains = current
                eqFailure = nil
            }
            if preferences.value.musicClaudeEQEnabled {
                selectedPreset = Self.claudeStyleName
            } else if let name = try? await equalizer.currentPresetName(), !Task.isCancelled {
                selectedPreset = name
            }
        }
        .onChange(of: preferences.value.musicClaudeEQEnabled) { _, enabled in
            if enabled {
                selectedPreset = Self.claudeStyleName
                lastClaudeTrackID = nil
                lastClaudeOutputKey = nil
                currentGenreKey = nil
                lastAppliedAdvice = nil
            } else if selectedPreset == Self.claudeStyleName {
                selectedPreset = nil
            }
        }
        .onChange(of: audioOutput.output) { _, _ in
            // Re-tune when switching AirPods ↔ speakers (or any default output).
            lastClaudeTrackID = nil
            lastClaudeOutputKey = nil
            currentGenreKey = nil
            lastAppliedAdvice = nil
        }
        .task(id: volumeRequest) {
            guard let target = volumeRequest else { return }
            do {
                try await Task.sleep(for: .milliseconds(70))
                let actual = try await music.mixerVolume(target)
                if !Task.isCancelled {
                    volume = actual
                    confirmedVolume = actual
                    volumeError = nil
                }
            } catch {
                if !Task.isCancelled {
                    volume = confirmedVolume
                    volumeError = error.localizedDescription
                }
            }
            if !Task.isCancelled { volumeRequest = nil }
        }
        .task(id: autoEQTaskID) {
            await applyClaudeEQIfNeeded()
        }
    }

    private var autoEQTaskID: String {
        let track = music.state.snapshot?.trackID ?? ""
        let enabled = preferences.value.musicClaudeEQEnabled && active && music.enabled
        let route = "\(audioOutput.output.kind.rawValue)|\(audioOutput.output.uid)"
        return "\(enabled)|\(track)|\(route)"
    }

    @ViewBuilder private var presetMenu: some View {
        let label = preferences.value.musicClaudeEQEnabled
            ? Self.claudeStyleName
            : (selectedPreset ?? "Estilo EQ")
        let menu = Menu {
            Button(Self.claudeStyleName) { enableClaudeStyle() }
            if !presets.isEmpty { Divider() }
            if presets.isEmpty {
                Text("Sin presets de Música").foregroundStyle(.secondary)
            } else {
                ForEach(presets, id: \.self) { name in
                    Button(name) { applyPreset(name) }
                }
            }
        } label: {
            HStack(spacing: 4) {
                Image(systemName: preferences.value.musicClaudeEQEnabled ? "sparkles" : "slider.horizontal.3")
                Text(label)
                    .lineLimit(1)
            }
            .font(.caption.weight(.medium))
            .frame(maxWidth: 132, alignment: .leading)
        }
        .controlSize(.small)
        .disabled(!active)
        .accessibilityLabel("Estilo del ecualizador")
        .help("Elige «Claude» para auto-EQ por tipo de música, o un preset de fábrica de Música. Un toque manual cancela Claude al instante.")
        if #available(macOS 26.0, *), !reduceTransparency {
            menu.menuStyle(.borderlessButton)
        } else {
            menu
        }
    }

    @ViewBuilder private var resetButton: some View {
        let button = Button {
            preemptClaudeForUserEdit()
            let neutral = Dictionary(uniqueKeysWithValues: MixerBand.allCases.map { ($0, 0.0) })
            applyEQ(preview: neutral, userInitiated: true) {
                await equalizer.invalidatePendingWrites()
                let result = try await equalizer.reset()
                selectedPreset = try? await equalizer.currentPresetName()
                return result
            }
        } label: {
            Image(systemName: "arrow.counterclockwise")
                .font(.caption.weight(.medium))
                .frame(width: 20, height: 18)
        }
        .controlSize(.small)
        .buttonBorderShape(.capsule)
        .accessibilityLabel("Restablecer ecualizador")
        .help("Poner graves, medios y agudos a cero y desactivar el EQ de Música")
        .disabled(!active)
        if #available(macOS 26.0, *), !reduceTransparency {
            button.buttonStyle(.glass)
        } else {
            button.buttonStyle(.bordered)
        }
    }

    private var volumeFader: some View {
        VStack(spacing: 4) {
            Text("VOL").font(.caption2.weight(.semibold)).tracking(0.7).foregroundStyle(.secondary)
            GeometryReader { proxy in
                let inset = 15.0
                let travel = max(1, proxy.size.height - 2 * inset)
                let level = Double(volume ?? 0) / 100
                ZStack {
                    VStack {
                        ForEach(0..<9) { index in
                            Capsule().fill(.secondary.opacity(0.45))
                                .frame(width: index.isMultiple(of: 4) ? 46 : 30, height: 1)
                            if index < 8 { Spacer(minLength: 0) }
                        }
                    }
                    .padding(.vertical, inset)
                    Capsule().fill(.black.opacity(0.85))
                        .strokeBorder(palette.metal.opacity(0.3), lineWidth: 1)
                        .frame(width: 9)
                    RoundedRectangle(cornerRadius: 3)
                        .fill(.linearGradient(colors: [palette.metal, palette.vinyl], startPoint: .top, endPoint: .bottom))
                        .strokeBorder(palette.metal.opacity(0.6), lineWidth: 1)
                        .overlay {
                            VStack(spacing: 2) {
                                Capsule().fill(.black.opacity(0.55))
                                Capsule().fill(palette.ink.opacity(0.85))
                                Capsule().fill(.black.opacity(0.55))
                            }.frame(width: 34, height: 10)
                        }
                        .shadow(color: .black.opacity(0.45), radius: 2, y: 2)
                        .frame(width: 47, height: 26)
                        .position(x: proxy.size.width / 2, y: inset + travel * (1 - level))
                }
                .contentShape(Rectangle())
                .gesture(DragGesture(minimumDistance: 0).onChanged { drag in
                    setVolume(Int((100 * (1 - (drag.location.y - inset) / travel)).rounded()))
                })
            }
            .frame(width: 56, height: 178)
            .opacity(volume == nil ? 0.45 : 1)
            .allowsHitTesting(active && volume != nil)
            Text(volume.map { "\($0) %" } ?? "·")
                .font(.caption2.monospacedDigit())
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Volumen de Música")
        .accessibilityValue(volume.map { "\($0) por ciento" } ?? "No disponible")
        .accessibilityAdjustableAction { direction in
            guard let volume else { return }
            switch direction {
            case .increment: setVolume(volume + 5)
            case .decrement: setVolume(volume - 5)
            @unknown default: break
            }
        }
    }

    private func readVolume() async {
        do {
            let actual = try await music.mixerVolume()
            guard !Task.isCancelled, volumeRequest == nil else { return }
            volume = actual
            confirmedVolume = actual
            volumeError = nil
        } catch {
            if !Task.isCancelled { volumeError = error.localizedDescription }
        }
    }

    private func setVolume(_ level: Int) {
        guard active, volume != nil else { return }
        let target = min(100, max(0, level))
        guard volume != target else { return }
        volume = target
        volumeRequest = target
    }

    private func adjust(_ target: Double, band: MixerBand) {
        // Manual knob preempts Claude immediately — never wait on an in-flight auto-EQ latch.
        preemptClaudeForUserEdit()
        var preview = gains
        for missing in MixerBand.allCases where preview[missing] == nil { preview[missing] = 0 }
        preview[band] = min(12, max(-12, target))
        applyEQ(preview: preview, userInitiated: true) {
            await equalizer.invalidatePendingWrites()
            let result = try await equalizer.setAll(preview)
            selectedPreset = try? await equalizer.currentPresetName() ?? "Manual"
            return result
        }
    }

    private func enableClaudeStyle() {
        preferences.value.musicClaudeEQEnabled = true
        selectedPreset = Self.claudeStyleName
        lastClaudeTrackID = nil
        lastClaudeOutputKey = nil
        currentGenreKey = nil
        lastAppliedAdvice = nil
        claudeStatus = "Estilo Claude — EQ según música y \(audioOutput.output.shortLabel)"
    }

    private func disableClaudeStyle() {
        guard preferences.value.musicClaudeEQEnabled else { return }
        preferences.value.musicClaudeEQEnabled = false
        claudeStatus = nil
    }

    /// Drop Claude ownership so any in-flight auto-EQ aborts before writing again.
    private func preemptClaudeForUserEdit() {
        disableClaudeStyle()
    }

    private func applyPreset(_ name: String) {
        preemptClaudeForUserEdit()
        applyEQ(preview: gains, userInitiated: true) {
            // Invalidate Claude's latch before this write joins the equalizer actor queue.
            await equalizer.invalidatePendingWrites()
            let result = try await equalizer.selectPreset(name)
            selectedPreset = name
            return result
        }
    }

    private func loadPresets() async {
        do {
            let names = try await equalizer.presetNames()
            guard !Task.isCancelled else { return }
            presets = names
        } catch {
            if !Task.isCancelled {
                let failure = (error as? MusicEqualizer.Failure) ?? .unresponsive
                eqFailure = failure
                if failure == .access, !offeredAccess {
                    offeredAccess = true
                    showAccess = true
                }
            }
        }
    }

    private func applyEQ(
        preview: [MixerBand: Double],
        successStatus: String? = nil,
        userInitiated: Bool = false,
        operation: @escaping () async throws -> [MixerBand: Double]
    ) {
        guard active else { return }
        let confirmed = gains
        let confirmedPreset = selectedPreset
        let confirmedStatus = claudeStatus
        gains = preview
        eqRevision += 1
        let revision = eqRevision
        Task {
            do {
                let result = try await operation()
                if revision == eqRevision {
                    gains = result
                    eqFailure = nil
                    if let successStatus { claudeStatus = successStatus }
                }
            } catch let failure as MusicEqualizer.Failure where failure == .superseded {
                // Newer write won — leave that revision's preview alone.
            } catch {
                if revision == eqRevision {
                    gains = confirmed
                    selectedPreset = confirmedPreset
                    let failure = (error as? MusicEqualizer.Failure) ?? .unresponsive
                    eqFailure = failure
                    if successStatus != nil {
                        claudeStatus = failure.localizedDescription
                    } else if !userInitiated, confirmedStatus != nil,
                              failure == .silent || failure == .access {
                        claudeStatus = failure.localizedDescription
                    }
                    if failure == .access, !offeredAccess {
                        offeredAccess = true
                        showAccess = true
                    }
                }
            }
        }
    }

    private func applyClaudeEQIfNeeded() async {
        guard preferences.value.musicClaudeEQEnabled, active, music.enabled else {
            claudeStatus = nil
            return
        }
        guard let snapshot = music.state.snapshot, !snapshot.title.isEmpty else { return }
        let output = audioOutput.output
        let outputKey = "\(output.kind.rawValue)|\(output.uid)"
        if snapshot.trackID == lastClaudeTrackID, outputKey == lastClaudeOutputKey { return }

        let libraryGenre = snapshot.genre
        let libraryKey = MusicClaudeEQService.normalizeGenre(libraryGenre)

        // Same genre + same output → keep EQ curve, skip Claude/API tokens.
        // Still reassert EQ On — Music sometimes leaves the equalizer off after a track change.
        if !libraryKey.isEmpty,
           libraryKey == currentGenreKey,
           outputKey == lastClaudeOutputKey,
           lastAppliedAdvice != nil {
            lastClaudeTrackID = snapshot.trackID
            let status = "\(lastAppliedAdvice?.genre ?? libraryGenre) · mismo género · \(output.shortLabel)"
            do {
                try await equalizer.reassertPlayback()
                if !Task.isCancelled {
                    claudeStatus = status
                    eqFailure = nil
                }
            } catch {
                guard !Task.isCancelled else { return }
                let failure = (error as? MusicEqualizer.Failure) ?? .unresponsive
                eqFailure = failure
                claudeStatus = failure.localizedDescription
                // Allow retry on the next tick / same track when latch was silent.
                if failure == .silent || failure == .access || failure == .closed {
                    lastClaudeTrackID = nil
                }
                if failure == .access, !offeredAccess {
                    offeredAccess = true
                    showAccess = true
                }
            }
            return
        }
        if !libraryKey.isEmpty,
           let cached = await claudeEQ.cachedAdvice(genre: libraryGenre, output: output) {
            guard preferences.value.musicClaudeEQEnabled, active else { return }
            applyClaudeAdvice(cached, outputLabel: output.shortLabel, reused: true)
            currentGenreKey = libraryKey
            lastAppliedAdvice = cached
            lastClaudeTrackID = snapshot.trackID
            lastClaudeOutputKey = outputKey
            return
        }

        try? await Task.sleep(for: .milliseconds(450))
        guard !Task.isCancelled else { return }
        // Manual preempt flips Claude off; skip if the user already took ownership.
        guard preferences.value.musicClaudeEQEnabled, active else { return }
        guard music.state.snapshot?.trackID == snapshot.trackID else { return }
        if presets.isEmpty { await loadPresets() }
        claudeStatus = "Claude EQ · \(output.shortLabel)…"
        do {
            let advice = try await claudeEQ.advise(
                title: snapshot.title,
                artist: snapshot.artist,
                presets: presets,
                output: output,
                musicGenre: libraryGenre,
                interactiveAuth: false
            )
            guard !Task.isCancelled, music.state.snapshot?.trackID == snapshot.trackID else { return }
            // User may have grabbed Manual/knobs while Claude was thinking.
            guard preferences.value.musicClaudeEQEnabled, active else { return }
            applyClaudeAdvice(advice, outputLabel: output.shortLabel, reused: false)
            currentGenreKey = !libraryKey.isEmpty ? libraryKey : MusicClaudeEQService.normalizeGenre(advice.genre)
            lastAppliedAdvice = advice
            lastClaudeTrackID = snapshot.trackID
            lastClaudeOutputKey = outputKey
        } catch let failure as MusicClaudeEQService.Failure {
            guard !Task.isCancelled else { return }
            claudeStatus = failure.localizedDescription
            // Auth can be fixed mid-session — allow retry on the same track.
            if case .auth = failure { return }
            lastClaudeTrackID = snapshot.trackID
        } catch {
            guard !Task.isCancelled else { return }
            claudeStatus = error.localizedDescription
            lastClaudeTrackID = snapshot.trackID
        }
    }

    private func applyClaudeAdvice(_ advice: MusicClaudeEQService.Advice, outputLabel: String, reused: Bool) {
        guard preferences.value.musicClaudeEQEnabled else { return }
        if let preset = advice.preset {
            // Don't preview Claude's numeric guess then replace it with the
            // factory preset averages — that "weird switch" looked like snap-back.
            let status = reused
                ? "\(advice.genre) · \(preset) · mismo género · \(outputLabel)"
                : "\(advice.genre) · \(preset) · \(outputLabel) · \(advice.provider)"
            claudeStatus = "Aplicando \(preset)…"
            applyEQ(preview: gains, successStatus: status) {
                guard preferences.value.musicClaudeEQEnabled else {
                    throw MusicEqualizer.Failure.superseded
                }
                let result = try await equalizer.selectPreset(preset)
                guard preferences.value.musicClaudeEQEnabled else {
                    throw MusicEqualizer.Failure.superseded
                }
                selectedPreset = Self.claudeStyleName
                return result
            }
        } else {
            let target: [MixerBand: Double] = [
                .bass: advice.bass, .mid: advice.mid, .treble: advice.treble
            ]
            let status = reused
                ? "\(advice.genre) · bandas · mismo género · \(outputLabel)"
                : "\(advice.genre) · bandas · \(outputLabel) · \(advice.provider)"
            claudeStatus = "Aplicando bandas…"
            applyEQ(preview: target, successStatus: status) {
                guard preferences.value.musicClaudeEQEnabled else {
                    throw MusicEqualizer.Failure.superseded
                }
                let result = try await equalizer.setAll(target)
                guard preferences.value.musicClaudeEQEnabled else {
                    throw MusicEqualizer.Failure.superseded
                }
                selectedPreset = Self.claudeStyleName
                return result
            }
        }
    }
}

private struct EQKnob: View {
    let title: String
    let gain: Double?
    let accent: Color
    let apply: (Double) -> Void

    @GestureState private var adjustment: Double?
    @FocusState private var focused: Bool

    private var displayedGain: Double? { adjustment ?? gain }

    var body: some View {
        HStack(spacing: 7) {
            ZStack {
                Circle().trim(from: 0, to: 0.75)
                    .stroke(.secondary.opacity(0.55), style: StrokeStyle(lineWidth: 2, lineCap: .round))
                    .rotationEffect(.degrees(135))
                Circle().fill(.linearGradient(colors: [Color(white: 0.30), Color(white: 0.08)],
                                              startPoint: .topLeading, endPoint: .bottomTrailing))
                    .strokeBorder(.white.opacity(0.28), style: StrokeStyle(lineWidth: 3, dash: [1, 1.8]))
                    .padding(4)
                    .shadow(color: .black.opacity(0.5), radius: 1, y: 2)
                Capsule().fill(accent)
                    .frame(width: 3, height: 12)
                    .offset(y: -17)
                    .rotationEffect(.degrees((displayedGain ?? 0) * 11.25))
                if focused, adjustment == nil {
                    Circle().strokeBorder(accent.opacity(0.65), lineWidth: 1.5)
                }
            }
            .frame(width: 54, height: 54)
            .frame(width: 60, height: 60)
            .contentShape(Rectangle())
            .gesture(DragGesture(minimumDistance: 3)
                .updating($adjustment) { drag, preview, _ in
                    // Snap the preview to whole dB so releasing never visually
                    // jumps from a fractional drag back to the committed value.
                    preview = min(12, max(-12, (gain ?? 0) + delta(drag.translation))).rounded()
                }
                .onEnded { drag in
                    let target = min(12, max(-12, (gain ?? 0) + delta(drag.translation))).rounded()
                    if target != gain { apply(target) }
                })
            .onTapGesture(count: 2) { apply(0) }
            .focusable()
            .focusEffectDisabled()
            .focused($focused)
            .onMoveCommand { direction in
                switch direction {
                case .up, .right: apply(min(12, (gain ?? 0) + 1))
                case .down, .left: apply(max(-12, (gain ?? 0) - 1))
                @unknown default: break
                }
            }
            Text(title).font(.callout.weight(.medium))
                .frame(width: 48, alignment: .leading)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(title)
        .accessibilityValue(displayedGain.map { "\(Int($0)) decibelios" } ?? "No disponible")
        .accessibilityAdjustableAction { direction in
            switch direction {
            case .increment: apply(min(12, (gain ?? 0) + 1))
            case .decrement: apply(max(-12, (gain ?? 0) - 1))
            @unknown default: break
            }
        }
    }

    private func delta(_ translation: CGSize) -> Double {
        (translation.width - translation.height) / 6
    }
}
