import Combine
import Foundation
import IslandCore

/// Decides when Isla's own equalizer runs and exposes its state to the UI.
/// Lives for the whole app, so the sound keeps being processed with the notch closed.
@MainActor final class AdaptiveEQController: ObservableObject {
    static let shared = AdaptiveEQController()

    @Published private(set) var gains: [MixerBand: Double] = Dictionary(uniqueKeysWithValues: MixerBand.allCases.map { ($0, 0.0) })
    @Published private(set) var status: String?
    @Published private(set) var running = false
    /// Mirrors the "EQ Adaptative" preference so views outside the mixer can show it.
    @Published private(set) var adaptive = false

    private let engine = AdaptiveEQEngine()
    private let outputMonitor = MusicAudioOutputMonitor()
    private var preferences: PreferencesStore?
    private var music: AppleMusicService?
    private var cancellables = Set<AnyCancellable>()
    private var runningKey: String?
    private var lastTrackID: String?
    private var failedKey: String?
    private var retryTask: Task<Void, Never>?
    /// Gains the user dialled by hand (any non-zero value keeps the engine running).
    private var manual: [MixerBand: Double] = [:]

    var outputLabel: String { outputMonitor.output.shortLabel }

    func configure(preferences: PreferencesStore, music: AppleMusicService) {
        guard self.preferences == nil else { return }
        self.preferences = preferences
        self.music = music
        engine.onAdapt = { [weak self] adapted in
            Task { @MainActor in self?.adopt(adapted) }
        }
        outputMonitor.setActive(true)
        outputMonitor.$output.dropFirst().sink { [weak self] _ in self?.reconcile() }.store(in: &cancellables)
        preferences.$value.map { [$0.musicEnabled, $0.musicClaudeEQEnabled] }.removeDuplicates()
            .sink { [weak self] _ in self?.reconcile() }.store(in: &cancellables)
        music.$state.sink { [weak self] _ in self?.reconcile() }.store(in: &cancellables)
        reconcile()
    }

    // MARK: Commands from the mixer

    func enableAdaptive() {
        manual = [:]
        preferences?.value.musicClaudeEQEnabled = true
        engine.resetAnalysis()
        reconcile()
    }

    func setManual(_ band: MixerBand, _ value: Double) {
        var next = gains
        next[band] = min(12, max(-12, value.rounded()))
        manual = next
        gains = next
        preferences?.value.musicClaudeEQEnabled = false
        engine.setGains(.init(bass: next[.bass] ?? 0, mid: next[.mid] ?? 0, treble: next[.treble] ?? 0))
        reconcile()
    }

    func resetFlat() {
        manual = [:]
        gains = Dictionary(uniqueKeysWithValues: MixerBand.allCases.map { ($0, 0.0) })
        preferences?.value.musicClaudeEQEnabled = false
        engine.setGains(.init(bass: 0, mid: 0, treble: 0))
        reconcile()
    }

    // MARK: Engine lifecycle

    private func adopt(_ adapted: SpectrumBalance.Gains) {
        guard preferences?.value.musicClaudeEQEnabled == true else { return }
        gains = [.bass: adapted.bass, .mid: adapted.mid, .treble: adapted.treble]
        status = "Adaptative · \(outputLabel)"
    }

    private func reconcile() {
        guard let preferences, let music else { return }
        let value = preferences.value
        let adaptive = value.musicClaudeEQEnabled
        if self.adaptive != adaptive { self.adaptive = adaptive }
        let manualActive = manual.values.contains { $0 != 0 }
        guard value.musicEnabled, let snapshot = music.state.snapshot, adaptive || manualActive else {
            stopEngine()
            if !adaptive { status = nil }
            return
        }
        let output = outputMonitor.output
        engine.configure(adaptive: adaptive, bias: output.eqBias)
        if snapshot.trackID != lastTrackID {
            lastTrackID = snapshot.trackID
            if adaptive { engine.resetAnalysis() }
        }
        let bundle = snapshot.source == .spotify ? "com.spotify.client" : "com.apple.Music"
        let key = "\(bundle)|\(output.uid)"
        guard !running || key != runningKey else { return }
        // Do not hammer the audio system after a failure for the same app/output.
        guard failedKey != key || snapshot.playing else { return }
        start(bundle: bundle, key: key)
    }

    private func start(bundle: String, key: String) {
        let initial = SpectrumBalance.Gains(bass: gains[.bass] ?? 0, mid: gains[.mid] ?? 0, treble: gains[.treble] ?? 0)
        do {
            try engine.start(bundleID: bundle, initial: initial)
            running = true
            runningKey = key
            failedKey = nil
            retryTask?.cancel()
            status = "Adaptative · \(outputLabel)"
        } catch {
            running = false
            runningKey = nil
            failedKey = key
            status = error.localizedDescription
            scheduleRetry()
        }
    }

    private func scheduleRetry() {
        retryTask?.cancel()
        retryTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(5))
            guard !Task.isCancelled else { return }
            self?.reconcile()
        }
    }

    private func stopEngine() {
        retryTask?.cancel()
        guard running else { return }
        engine.stop()
        running = false
        runningKey = nil
    }
}
