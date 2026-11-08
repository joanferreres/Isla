import SwiftUI

struct RecordPlayerMixer: View {
    let music: AppleMusicService
    let palette: RecordPlayerPalette
    let active: Bool

    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @State private var equalizer = MusicEqualizer()
    @State private var gains: [MixerBand: Double] = [:]
    @State private var eqFailure: MusicEqualizer.Failure?
    @State private var changingEQ = false
    @State private var showSetup = false
    @State private var volume: Int?
    @State private var confirmedVolume: Int?
    @State private var volumeRequest: Int?
    @State private var volumeError: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("Mezclador", systemImage: "slider.vertical.3")
                .font(.headline)
                .accessibilityAddTraits(.isHeader)
            HStack(spacing: 12) {
                VStack(spacing: 7) {
                    ForEach(MixerBand.allCases, id: \.self) { band in
                        EQKnob(title: band.title, gain: gains[band], accent: palette.accent) { value in
                            adjust(value, band: band)
                        }
                        .disabled(changingEQ || eqFailure != nil)
                    }
                }
                Divider()
                volumeFader
            }
            .fixedSize(horizontal: false, vertical: true)
            if let eqFailure {
                setupButton(eqFailure)
            }
            if let volumeError {
                Text(volumeError).font(.caption2).foregroundStyle(.secondary)
            }
        }
        .padding(14)
        .background {
            let shape = RoundedRectangle(cornerRadius: 20)
            if reduceTransparency {
                shape.fill(Color(nsColor: palette.background)).strokeBorder(.white.opacity(0.24))
            } else if #available(macOS 26.0, *) {
                Color.clear.glassEffect(.regular, in: shape)
            } else {
                shape.fill(.regularMaterial)
            }
        }
        .task(id: active) {
            guard active else { return }
            await readVolume()
            await readEQ()
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
    }

    private var volumeFader: some View {
        VStack(spacing: 4) {
            Image(systemName: "speaker.wave.2").font(.caption)
            GeometryReader { proxy in
                let travel = max(1, proxy.size.height - 20)
                let level = Double(volume ?? 0) / 100
                ZStack {
                    VStack {
                        ForEach(0..<9) { index in
                            Capsule().fill(.secondary.opacity(0.45))
                                .frame(width: index.isMultiple(of: 4) ? 32 : 22, height: 1)
                            if index < 8 { Spacer(minLength: 0) }
                        }
                    }
                    .padding(.vertical, 10)
                    Capsule().fill(.black.opacity(0.75)).frame(width: 6)
                    Capsule().fill(palette.accent.opacity(0.7))
                        .frame(width: 4, height: travel * level)
                        .frame(maxHeight: .infinity, alignment: .bottom)
                        .padding(.bottom, 10)
                    RoundedRectangle(cornerRadius: 4)
                        .fill(.linearGradient(colors: [palette.metal, palette.vinyl], startPoint: .top, endPoint: .bottom))
                        .overlay(Capsule().fill(palette.ink).frame(width: 22, height: 1))
                        .frame(width: 32, height: 18)
                        .position(x: proxy.size.width / 2, y: 10 + travel * (1 - level))
                }
                .contentShape(Rectangle())
                .gesture(DragGesture(minimumDistance: 0).onChanged { drag in
                    setVolume(Int((100 * (1 - (drag.location.y - 10) / travel)).rounded()))
                })
            }
            .frame(width: 44, height: 118)
            .opacity(volume == nil ? 0.45 : 1)
            .allowsHitTesting(active && volume != nil)
            Text(volume.map { "\($0) %" } ?? "—")
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

    @ViewBuilder private func setupButton(_ failure: MusicEqualizer.Failure) -> some View {
        let button = Button("Configurar EQ", systemImage: "slider.horizontal.3") {
            Task {
                await readEQ()
                showSetup = eqFailure != nil
            }
        }
        if #available(macOS 26.0, *), !reduceTransparency {
            button.buttonStyle(.glass).popover(isPresented: $showSetup) { setup(failure) }
        } else {
            button.buttonStyle(.bordered).popover(isPresented: $showSetup) { setup(failure) }
        }
    }

    private func setup(_ failure: MusicEqualizer.Failure) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Ecualizador de Música").font(.headline)
            Text(failure.localizedDescription).font(.callout)
            if failure == .access {
                if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") {
                    Link("Abrir Accesibilidad", destination: url)
                }
            } else if failure == .closed {
                Button("Abrir Música") {
                    guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: "com.apple.Music") else { return }
                    NSWorkspace.shared.openApplication(at: url, configuration: .init()) { _, _ in }
                }
            }
            Button("Comprobar") {
                Task {
                    await readEQ()
                    showSetup = eqFailure != nil
                }
            }
        }
        .padding(16)
        .frame(width: 255, alignment: .leading)
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

    private func readEQ() async {
        do {
            gains = try await equalizer.read()
            eqFailure = nil
        } catch {
            eqFailure = (error as? MusicEqualizer.Failure) ?? .unresponsive
        }
    }

    private func adjust(_ gain: Double, band: MixerBand) {
        guard !changingEQ else { return }
        let previous = gains[band]
        gains[band] = gain
        changingEQ = true
        Task {
            defer { changingEQ = false }
            do {
                gains = try await equalizer.set(gain, for: band)
                eqFailure = nil
            } catch {
                gains[band] = previous
                eqFailure = (error as? MusicEqualizer.Failure) ?? .unresponsive
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

    private var displayedGain: Double? { adjustment ?? gain }

    var body: some View {
        HStack(spacing: 7) {
            ZStack {
                Circle().trim(from: 0, to: 0.75)
                    .stroke(.secondary.opacity(0.55), style: StrokeStyle(lineWidth: 2, lineCap: .round))
                    .rotationEffect(.degrees(135))
                Circle().fill(.linearGradient(colors: [Color(white: 0.28), Color(white: 0.10)],
                                              startPoint: .top, endPoint: .bottom))
                    .strokeBorder(.white.opacity(0.22))
                    .padding(4)
                Capsule().fill(accent)
                    .frame(width: 2, height: 8)
                    .offset(y: -10)
                    .rotationEffect(.degrees((displayedGain ?? 0) * 11.25))
            }
            .frame(width: 36, height: 36)
            .frame(width: 44, height: 44)
            .contentShape(Rectangle())
            .gesture(DragGesture(minimumDistance: 3)
                .updating($adjustment) { drag, preview, _ in preview = target(drag.translation) }
                .onEnded { drag in
                    if let value = target(drag.translation) { apply(value) }
                })
            .onTapGesture(count: 2) { if gain != nil { apply(0) } }
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.callout.weight(.medium))
                Text(displayedGain.map { "\($0 > 0 ? "+" : "")\(Int($0)) dB" } ?? "—")
                    .font(.caption2.monospacedDigit())
                    .foregroundStyle(.secondary)
            }
            .frame(width: 48, alignment: .leading)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(title)
        .accessibilityValue(displayedGain.map { "\(Int($0)) decibelios" } ?? "No disponible")
        .accessibilityAdjustableAction { direction in
            guard let gain else { return }
            switch direction {
            case .increment: apply(min(12, gain + 1))
            case .decrement: apply(max(-12, gain - 1))
            @unknown default: break
            }
        }
    }

    private func target(_ translation: CGSize) -> Double? {
        gain.map { min(12, max(-12, ($0 + (translation.width - translation.height) / 5).rounded())) }
    }
}
