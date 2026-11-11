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
    @State private var eqRevision = 0
    @State private var showAccess = false
    @State private var offeredAccess = false
    @State private var volume: Int?
    @State private var confirmedVolume: Int?
    @State private var volumeRequest: Int?
    @State private var volumeError: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            resetButton
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
            if let volumeError {
                Text(volumeError).font(.caption2).foregroundStyle(.secondary)
            }
        }
        .padding(.horizontal, 10)
        .help(eqFailure?.localizedDescription ?? "")
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
            guard active else { return }
            await readVolume()
            if let current = try? await equalizer.read(), !Task.isCancelled, !changingEQ {
                gains = current
                eqFailure = nil
            }
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

    @ViewBuilder private var resetButton: some View {
        let button = Button {
            let neutral = Dictionary(uniqueKeysWithValues: MixerBand.allCases.map { ($0, 0.0) })
            applyEQ(preview: neutral) { try await equalizer.reset() }
        } label: {
            Image(systemName: "arrow.counterclockwise")
                .font(.caption.weight(.medium))
                .frame(width: 20, height: 18)
        }
        .controlSize(.small)
        .buttonBorderShape(.capsule)
        .accessibilityLabel("Restablecer ecualizador")
        .help("Poner graves, medios y agudos a cero")
        .disabled(!active || changingEQ)
        .padding(.leading, 9)
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
        var preview = gains
        preview[band] = min(12, max(-12, target))
        applyEQ(preview: preview) { try await equalizer.set(preview[band] ?? 0, for: band) }
    }

    private func applyEQ(preview: [MixerBand: Double], operation: @escaping () async throws -> [MixerBand: Double]) {
        guard active else { return }
        let confirmed = gains
        gains = preview
        eqRevision += 1
        let revision = eqRevision
        changingEQ = true
        Task {
            do {
                let result = try await operation()
                if revision == eqRevision {
                    gains = result
                    eqFailure = nil
                }
            } catch {
                if revision == eqRevision {
                    gains = confirmed
                    let failure = (error as? MusicEqualizer.Failure) ?? .unresponsive
                    eqFailure = failure
                    if failure == .access, !offeredAccess {
                        offeredAccess = true
                        showAccess = true
                    }
                }
            }
            if revision == eqRevision { changingEQ = false }
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
                    preview = min(12, max(-12, (gain ?? 0) + delta(drag.translation)))
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
