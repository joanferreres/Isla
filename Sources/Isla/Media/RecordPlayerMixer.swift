import SwiftUI
import IslandCore

struct RecordPlayerMixer: View {
    let music: AppleMusicService
    @ObservedObject var preferences: PreferencesStore
    let palette: RecordPlayerPalette
    let active: Bool

    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @ObservedObject private var eq = AdaptiveEQController.shared
    /// Apple Music's own factory presets (driven through Music's equalizer window).
    @State private var equalizer = MusicEqualizer()
    @State private var presets: [String] = []
    @State private var selectedPreset: String?
    @State private var presetMode = false
    @State private var presetGains: [MixerBand: Double] = [:]
    @State private var showAccess = false
    @State private var offeredAccess = false
    @State private var presetError: String?
    @State private var volume: Int?
    @State private var confirmedVolume: Int?
    @State private var volumeRequest: Int?
    @State private var volumeError: String?

    private var supportsPresets: Bool { music.state.snapshot?.source != .spotify }
    private var displayGains: [MixerBand: Double] { presetMode ? presetGains : eq.gains }

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
                        EQKnob(title: band.title, gain: displayGains[band], accent: palette.accent) { value in
                            adjust(value, band: band)
                        }
                        .disabled(!active)
                    }
                }
                volumeFader
            }
            .fixedSize(horizontal: false, vertical: true)
            if !presetMode, let status = eq.status {
                Text(status)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }
            if let volumeError {
                Text(volumeError).font(.caption2).foregroundStyle(.secondary)
            }
            if let presetError {
                Text(presetError).font(.caption2).foregroundStyle(.secondary)
            }
        }
        .padding(.horizontal, 10)
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
        .task(id: "\(active)|\(supportsPresets)|\(music.sourceTitle)") {
            guard active else { return }
            await readVolume()
            if supportsPresets { await loadPresets() } else { presetMode = false; selectedPreset = nil }
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

    @ViewBuilder private var presetMenu: some View {
        let adaptive = preferences.value.musicClaudeEQEnabled
        let label = presetMode ? (selectedPreset ?? "Preset") : (adaptive ? "Adaptative" : "Manual")
        let menu = Menu {
            Button("Adaptative") { chooseAdaptive() }
            if supportsPresets, !presets.isEmpty {
                Divider()
                ForEach(presets, id: \.self) { name in
                    Button(name) { applyPreset(name) }
                }
            }
        } label: {
            HStack(spacing: 4) {
                Image(systemName: adaptive && !presetMode ? "waveform.path" : "slider.horizontal.3")
                Text(label).lineLimit(1)
            }
            .font(.caption.weight(.medium))
            .frame(maxWidth: 132, alignment: .leading)
        }
        .controlSize(.small)
        .disabled(!active)
        .accessibilityLabel("Estilo del ecualizador")
        .help("Adaptative analiza la música y la salida (altavoces, auriculares, AirPods) y ajusta el sonido solo. Un toque manual lo desactiva.")
        if #available(macOS 26.0, *), !reduceTransparency {
            menu.menuStyle(.borderlessButton)
        } else {
            menu
        }
    }

    @ViewBuilder private var resetButton: some View {
        let button = Button {
            leavePreset()
            eq.resetFlat()
        } label: {
            Image(systemName: "arrow.counterclockwise")
                .font(.caption.weight(.medium))
                .frame(width: 20, height: 18)
        }
        .controlSize(.small)
        .buttonBorderShape(.capsule)
        .accessibilityLabel("Restablecer ecualizador")
        .help("Poner graves, medios y agudos a cero")
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
        .accessibilityLabel("Volumen de \(music.sourceTitle)")
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
        guard active else { return }
        leavePreset()
        eq.setManual(band, target)
    }

    private func chooseAdaptive() {
        leavePreset()
        eq.enableAdaptive()
    }

    /// Leaving an Apple Music preset puts Music's own EQ flat so it never stacks with Isla's.
    private func leavePreset() {
        guard presetMode else { return }
        presetMode = false
        selectedPreset = nil
        Task { _ = try? await equalizer.reset() }
    }

    private func applyPreset(_ name: String) {
        guard active else { return }
        eq.resetFlat()
        presetMode = true
        selectedPreset = name
        presetError = nil
        Task {
            do {
                await equalizer.invalidatePendingWrites()
                presetGains = try await equalizer.selectPreset(name)
            } catch {
                let failure = (error as? MusicEqualizer.Failure) ?? .unresponsive
                presetMode = false
                selectedPreset = nil
                presetError = failure.localizedDescription
                if failure == .access, !offeredAccess {
                    offeredAccess = true
                    showAccess = true
                }
            }
        }
    }

    private func loadPresets() async {
        do {
            let names = try await equalizer.presetNames()
            guard !Task.isCancelled else { return }
            presets = names
        } catch {
            if !Task.isCancelled, let failure = error as? MusicEqualizer.Failure, failure == .access, !offeredAccess {
                offeredAccess = true
                showAccess = true
            }
        }
    }
}
