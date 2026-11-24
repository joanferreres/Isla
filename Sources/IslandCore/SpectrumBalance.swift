import Accelerate
import Foundation

/// Local, token-free tonal balance analysis: averages the power spectrum of the audio it is
/// fed and turns it into bass / mid / treble corrections toward a "balanced" target curve.
public final class SpectrumBalance: @unchecked Sendable {
    public struct Result: Sendable, Equatable {
        /// Average level per octave of each band, in dB (relative scale).
        public var bassDB: Double
        public var midDB: Double
        public var trebleDB: Double
        public var seconds: Double
        public init(bassDB: Double, midDB: Double, trebleDB: Double, seconds: Double) {
            self.bassDB = bassDB; self.midDB = midDB; self.trebleDB = trebleDB; self.seconds = seconds
        }
    }

    /// Suggested gains in dB, one per mixer band.
    public struct Gains: Sendable, Equatable {
        public var bass: Double
        public var mid: Double
        public var treble: Double
        public init(bass: Double, mid: Double, treble: Double) {
            self.bass = bass; self.mid = mid; self.treble = treble
        }
    }

    /// Per-octave level of bass and treble relative to the mids in typical balanced music.
    public static let targetBassOffset = 4.0
    public static let targetTrebleOffset = -9.0
    /// Fraction of the measured error that is corrected (keeps the result subtle).
    public static let strength = 0.5
    public static let maxGain = 6.0

    private static let fftSize = 4096
    private static let log2Size = vDSP_Length(12)

    private let lock = NSLock()
    private let sampleRate: Double
    private let fft: FFTSetup?
    private let window: [Float]
    private var pending: [Float] = []
    private var power: [Double]
    private var frames = 0
    /// Frames quieter than this (mean square, ≈ −60 dBFS) are skipped — silence or fades.
    private let silenceThreshold: Float = 1e-6

    public init(sampleRate: Double) {
        self.sampleRate = max(8_000, sampleRate)
        fft = vDSP_create_fftsetup(Self.log2Size, FFTRadix(kFFTRadix2))
        var hann = [Float](repeating: 0, count: Self.fftSize)
        vDSP_hann_window(&hann, vDSP_Length(Self.fftSize), Int32(vDSP_HANN_NORM))
        window = hann
        power = [Double](repeating: 0, count: Self.fftSize / 2)
    }

    /// Seconds of non-silent audio analysed so far.
    public var analysedSeconds: Double {
        lock.lock(); defer { lock.unlock() }
        return Double(frames * Self.fftSize / 2) / sampleRate
    }

    /// Feed mono samples (interleaved stereo should be down-mixed by the caller).
    public func feed(_ samples: [Float]) {
        guard fft != nil else { return }
        lock.lock(); defer { lock.unlock() }
        pending.append(contentsOf: samples)
        let hop = Self.fftSize / 2
        while pending.count >= Self.fftSize {
            let frame = Array(pending[0..<Self.fftSize])
            pending.removeFirst(hop)
            analyse(frame)
        }
    }

    private func analyse(_ frame: [Float]) {
        var meanSquare: Float = 0
        vDSP_measqv(frame, 1, &meanSquare, vDSP_Length(frame.count))
        guard meanSquare > silenceThreshold, let fft else { return }

        var windowed = [Float](repeating: 0, count: Self.fftSize)
        vDSP_vmul(frame, 1, window, 1, &windowed, 1, vDSP_Length(Self.fftSize))

        let half = Self.fftSize / 2
        var real = [Float](repeating: 0, count: half)
        var imag = [Float](repeating: 0, count: half)
        var magnitudes = [Float](repeating: 0, count: half)
        real.withUnsafeMutableBufferPointer { realPointer in
            imag.withUnsafeMutableBufferPointer { imagPointer in
                var split = DSPSplitComplex(realp: realPointer.baseAddress!, imagp: imagPointer.baseAddress!)
                windowed.withUnsafeBufferPointer { pointer in
                    pointer.baseAddress!.withMemoryRebound(to: DSPComplex.self, capacity: half) {
                        vDSP_ctoz($0, 2, &split, 1, vDSP_Length(half))
                    }
                }
                vDSP_fft_zrip(fft, &split, 1, Self.log2Size, FFTDirection(kFFTDirection_Forward))
                vDSP_zvmags(&split, 1, &magnitudes, 1, vDSP_Length(half))
            }
        }
        for index in 0..<half { power[index] += Double(magnitudes[index]) }
        frames += 1
    }

    public func result() -> Result? {
        lock.lock(); defer { lock.unlock() }
        guard frames > 0 else { return nil }
        let binWidth = sampleRate / Double(Self.fftSize)
        func level(_ low: Double, _ high: Double) -> Double {
            let first = max(1, Int((low / binWidth).rounded(.up)))
            let last = min(power.count - 1, Int((high / binWidth).rounded(.down)))
            guard last >= first else { return -120 }
            var total = 0.0
            for index in first...last { total += power[index] }
            let octaves = log2(high / low)
            let perOctave = total / Double(frames) / octaves
            return 10 * log10(max(perOctave, 1e-12))
        }
        let nyquistLimit = min(12_000, sampleRate / 2 * 0.9)
        return Result(
            bassDB: level(60, 250),
            midDB: level(250, 4_000),
            trebleDB: level(4_000, nyquistLimit),
            seconds: Double(frames * Self.fftSize / 2) / sampleRate
        )
    }

    /// Correction toward the target curve. `currentGains` are the EQ gains already applied to the
    /// measured signal, so the measurement is "un-EQ'd" first and the result does not oscillate.
    public static func gains(for result: Result, currentGains: Gains = Gains(bass: 0, mid: 0, treble: 0), outputBias: Gains = Gains(bass: 0, mid: 0, treble: 0)) -> Gains {
        let bass = result.bassDB - currentGains.bass
        let mid = result.midDB - currentGains.mid
        let treble = result.trebleDB - currentGains.treble
        func limit(_ value: Double) -> Double { min(maxGain, max(-maxGain, value.rounded())) }
        // `outputBias` shifts the target for the playback device (AirPods, speakers, headphones…).
        return Gains(
            bass: limit((targetBassOffset - (bass - mid)) * strength + outputBias.bass),
            mid: limit(outputBias.mid),
            treble: limit((targetTrebleOffset - (treble - mid)) * strength + outputBias.treble)
        )
    }

    deinit {
        if let fft { vDSP_destroy_fftsetup(fft) }
    }
}
