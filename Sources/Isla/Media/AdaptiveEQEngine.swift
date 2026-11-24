import AVFoundation
import AppKit
import AudioToolbox
import CoreAudio
import IslandCore
import os

/// Fixed-size stereo ring buffer shared between a Core Audio IOProc (writer) and a reader.
final class StereoRing: @unchecked Sendable {
    private let lock = NSLock()
    private let capacity: Int
    private var storage: [Float]
    private var readPos = 0
    private var writePos = 0
    private var primed = false

    init(frames: Int) {
        capacity = frames
        storage = [Float](repeating: 0, count: frames * 2)
    }

    func reset() {
        lock.lock(); defer { lock.unlock() }
        readPos = 0; writePos = 0; primed = false
    }

    /// `samples` is interleaved L,R.
    func write(_ samples: UnsafePointer<Float>, frames: Int) {
        lock.lock(); defer { lock.unlock() }
        if writePos - readPos + frames > capacity { readPos = writePos + frames - capacity }
        for frame in 0..<frames {
            let slot = (writePos + frame) % capacity
            storage[slot * 2] = samples[frame * 2]
            storage[slot * 2 + 1] = samples[frame * 2 + 1]
        }
        writePos += frames
    }

    /// Fills `left`/`right`; pads with silence while the buffer is (re)filling and trims drift.
    func pull(frames: Int, left: UnsafeMutablePointer<Float>, right: UnsafeMutablePointer<Float>, sampleRate: Double) {
        lock.lock(); defer { lock.unlock() }
        let prime = Int(sampleRate * 0.04)
        let latencyCap = Int(sampleRate * 0.35)
        var available = writePos - readPos
        if available > latencyCap { readPos = writePos - prime; available = prime }
        if !primed {
            if available >= prime { primed = true } else {
                for index in 0..<frames { left[index] = 0; right[index] = 0 }
                return
            }
        }
        let count = min(frames, available)
        for index in 0..<count {
            let slot = (readPos + index) % capacity
            left[index] = storage[slot * 2]
            right[index] = storage[slot * 2 + 1]
        }
        for index in count..<frames { left[index] = 0; right[index] = 0 }
        readPos += count
        if count < frames { primed = false }
    }

    /// Mono down-mix of everything written since the last drain.
    func drainMono() -> [Float] {
        lock.lock(); defer { lock.unlock() }
        let available = writePos - readPos
        guard available > 0 else { return [] }
        var mono = [Float](repeating: 0, count: available)
        for index in 0..<available {
            let slot = (readPos + index) % capacity
            mono[index] = (storage[slot * 2] + storage[slot * 2 + 1]) * 0.5
        }
        readPos = writePos
        return mono
    }
}

/// Isla's own equalizer. It taps one app's audio (the original output is muted while the tap
/// is read), measures its tonal balance, and plays it back through a 3-band EQ. Works the same
/// for Spotify and Apple Music and needs no access to their settings.
final class AdaptiveEQEngine: @unchecked Sendable {
    enum Failure: LocalizedError {
        case notRunning, unsupported(String)

        var errorDescription: String? {
            switch self {
            case .notRunning: "Abre la app de música y dale a reproducir."
            case .unsupported(let step):
                "No se pudo procesar el audio (\(step)). Permite a Isla capturar audio en Privacidad y seguridad."
            }
        }
    }

    private static let log = Logger(subsystem: "local.personal.isla", category: "eq")

    /// Called (off the main thread) when the adaptive algorithm picks new gains.
    var onAdapt: (@Sendable (SpectrumBalance.Gains) -> Void)?

    private let stateLock = NSLock()
    private var adaptiveOn = false
    private var bias = SpectrumBalance.Gains(bass: 0, mid: 0, treble: 0)
    private var current = SpectrumBalance.Gains(bass: 0, mid: 0, treble: 0)
    private var analyzer: SpectrumBalance?
    private var firstWindow = true
    private var rate = 48_000.0

    private let engine = AVAudioEngine()
    private let eq = AVAudioUnitEQ(numberOfBands: 3)
    private var sourceNode: AVAudioSourceNode?
    private let playRing = StereoRing(frames: 1 << 17)
    private let analysisRing = StereoRing(frames: 1 << 17)
    private let analysisQueue = DispatchQueue(label: "isla.eq.analysis", qos: .utility)
    private var timer: DispatchSourceTimer?
    private var configObserver: NSObjectProtocol?

    private var tapID = AudioObjectID(kAudioObjectUnknown)
    private var deviceID = AudioObjectID(kAudioObjectUnknown)
    private var procID: AudioDeviceIOProcID?
    private(set) var isRunning = false

    init() {
        let bands = eq.bands
        bands[0].filterType = .lowShelf; bands[0].frequency = 140; bands[0].bypass = false
        bands[1].filterType = .parametric; bands[1].frequency = 1_000; bands[1].bandwidth = 2; bands[1].bypass = false
        bands[2].filterType = .highShelf; bands[2].frequency = 5_000; bands[2].bypass = false
    }

    // MARK: Control

    func configure(adaptive: Bool, bias: SpectrumBalance.Gains) {
        stateLock.lock(); defer { stateLock.unlock() }
        adaptiveOn = adaptive
        self.bias = bias
    }

    func setGains(_ gains: SpectrumBalance.Gains) {
        stateLock.lock()
        current = gains
        stateLock.unlock()
        apply(gains)
    }

    /// New track: re-measure quickly and jump straight to the new correction.
    func resetAnalysis() {
        stateLock.lock(); defer { stateLock.unlock() }
        analyzer = SpectrumBalance(sampleRate: rate)
        firstWindow = true
    }

    private func apply(_ gains: SpectrumBalance.Gains) {
        let bands = eq.bands
        bands[0].gain = Float(gains.bass)
        bands[1].gain = Float(gains.mid)
        bands[2].gain = Float(gains.treble)
        // Headroom so boosted bands do not clip.
        eq.globalGain = Float(-0.6 * max(0, gains.bass, gains.mid, gains.treble))
    }

    // MARK: Start / stop

    func start(bundleID: String, initial: SpectrumBalance.Gains) throws {
        stop()
        let processes = Self.audioProcesses(bundleID: bundleID)
        guard !processes.isEmpty else { throw Failure.notRunning }

        let description = CATapDescription(stereoMixdownOfProcesses: processes)
        description.uuid = UUID()
        description.muteBehavior = .mutedWhenTapped
        description.isPrivate = true
        var newTap = AudioObjectID(kAudioObjectUnknown)
        guard AudioHardwareCreateProcessTap(description, &newTap) == noErr else { throw Failure.unsupported("tap") }
        tapID = newTap

        do {
            try startPipeline(description: description, initial: initial)
            isRunning = true
            Self.log.info("EQ engine started for \(bundleID, privacy: .public) (\(processes.count) processes)")
        } catch {
            stop()
            Self.log.error("EQ engine failed: \(error.localizedDescription, privacy: .public)")
            throw error
        }
    }

    private func startPipeline(description: CATapDescription, initial: SpectrumBalance.Gains) throws {
        var formatAddress = AudioObjectPropertyAddress(
            mSelector: kAudioTapPropertyFormat,
            mScope: kAudioObjectPropertyScopeGlobal, mElement: kAudioObjectPropertyElementMain)
        var format = AudioStreamBasicDescription()
        var formatSize = UInt32(MemoryLayout<AudioStreamBasicDescription>.size)
        guard AudioObjectGetPropertyData(tapID, &formatAddress, 0, nil, &formatSize, &format) == noErr,
              format.mSampleRate > 0 else { throw Failure.unsupported("formato") }
        let sampleRate = format.mSampleRate
        let channels = max(1, Int(format.mChannelsPerFrame))
        let interleaved = format.mFormatFlags & kAudioFormatFlagIsNonInterleaved == 0

        stateLock.lock()
        rate = sampleRate
        current = initial
        analyzer = SpectrumBalance(sampleRate: sampleRate)
        firstWindow = true
        stateLock.unlock()
        playRing.reset(); analysisRing.reset()
        apply(initial)

        // Playback graph first (silent until audio arrives), so the original is never muted
        // without something ready to play it.
        guard let playFormat = AVAudioFormat(standardFormatWithSampleRate: sampleRate, channels: 2) else {
            throw Failure.unsupported("formato de salida")
        }
        let ring = playRing
        let node = AVAudioSourceNode(format: playFormat) { _, _, frameCount, audioBufferList -> OSStatus in
            let buffers = UnsafeMutableAudioBufferListPointer(audioBufferList)
            guard buffers.count >= 2,
                  let left = buffers[0].mData?.assumingMemoryBound(to: Float.self),
                  let right = buffers[1].mData?.assumingMemoryBound(to: Float.self) else { return noErr }
            ring.pull(frames: Int(frameCount), left: left, right: right, sampleRate: sampleRate)
            return noErr
        }
        sourceNode = node
        engine.attach(node)
        engine.attach(eq)
        engine.connect(node, to: eq, format: playFormat)
        engine.connect(eq, to: engine.mainMixerNode, format: playFormat)
        do { try engine.start() } catch { throw Failure.unsupported("motor") }
        configObserver = NotificationCenter.default.addObserver(
            forName: .AVAudioEngineConfigurationChange, object: engine, queue: .main
        ) { [weak self] _ in
            guard let self, self.isRunning else { return }
            try? self.engine.start()
        }

        var uidRef: Unmanaged<CFString>?
        let outputUID = Self.defaultOutputUID(&uidRef)
        var aggregate: [String: Any] = [
            kAudioAggregateDeviceNameKey: "Isla Adaptive EQ",
            kAudioAggregateDeviceUIDKey: UUID().uuidString,
            kAudioAggregateDeviceIsPrivateKey: true,
            kAudioAggregateDeviceIsStackedKey: false,
            kAudioAggregateDeviceTapAutoStartKey: true,
            kAudioAggregateDeviceTapListKey: [["uid": description.uuid.uuidString, "drift": true]],
        ]
        if let outputUID {
            aggregate[kAudioAggregateDeviceMainSubDeviceKey] = outputUID
            aggregate[kAudioAggregateDeviceSubDeviceListKey] = [[kAudioSubDeviceUIDKey: outputUID]]
        }
        var newDevice = AudioObjectID(kAudioObjectUnknown)
        guard AudioHardwareCreateAggregateDevice(aggregate as CFDictionary, &newDevice) == noErr else {
            throw Failure.unsupported("dispositivo")
        }
        deviceID = newDevice

        let analysis = analysisRing
        let queue = DispatchQueue(label: "isla.eq.io", qos: .userInteractive)
        var newProc: AudioDeviceIOProcID?
        let status = AudioDeviceCreateIOProcIDWithBlock(&newProc, deviceID, queue) { _, input, _, _, _ in
            let buffers = UnsafeMutableAudioBufferListPointer(UnsafeMutablePointer(mutating: input))
            guard let first = buffers.first, let data = first.mData else { return }
            let floats = data.assumingMemoryBound(to: Float.self)
            if interleaved {
                let frames = Int(first.mDataByteSize) / MemoryLayout<Float>.size / channels
                guard frames > 0 else { return }
                if channels == 2 {
                    ring.write(floats, frames: frames)
                    analysis.write(floats, frames: frames)
                } else {
                    // Mono or surround: use the first two channels (duplicate for mono).
                    var stereo = [Float](repeating: 0, count: frames * 2)
                    for frame in 0..<frames {
                        stereo[frame * 2] = floats[frame * channels]
                        stereo[frame * 2 + 1] = floats[frame * channels + (channels > 1 ? 1 : 0)]
                    }
                    ring.write(stereo, frames: frames)
                    analysis.write(stereo, frames: frames)
                }
            } else if buffers.count >= 2, let rightData = buffers[1].mData {
                let frames = Int(first.mDataByteSize) / MemoryLayout<Float>.size
                let right = rightData.assumingMemoryBound(to: Float.self)
                var stereo = [Float](repeating: 0, count: frames * 2)
                for frame in 0..<frames { stereo[frame * 2] = floats[frame]; stereo[frame * 2 + 1] = right[frame] }
                ring.write(stereo, frames: frames)
                analysis.write(stereo, frames: frames)
            }
        }
        guard status == noErr, let newProc else { throw Failure.unsupported("lectura") }
        procID = newProc
        guard AudioDeviceStart(deviceID, newProc) == noErr else { throw Failure.unsupported("inicio") }

        let source = DispatchSource.makeTimerSource(queue: analysisQueue)
        source.schedule(deadline: .now() + 0.5, repeating: 0.25)
        source.setEventHandler { [weak self] in self?.tick() }
        source.resume()
        timer = source
    }

    func stop() {
        timer?.cancel(); timer = nil
        if let configObserver { NotificationCenter.default.removeObserver(configObserver) }
        configObserver = nil
        if let procID, deviceID != kAudioObjectUnknown {
            AudioDeviceStop(deviceID, procID)
            AudioDeviceDestroyIOProcID(deviceID, procID)
        }
        procID = nil
        if deviceID != kAudioObjectUnknown { AudioHardwareDestroyAggregateDevice(deviceID) }
        deviceID = AudioObjectID(kAudioObjectUnknown)
        // Destroying the tap hands the app's own audio straight back.
        if tapID != kAudioObjectUnknown { AudioHardwareDestroyProcessTap(tapID) }
        tapID = AudioObjectID(kAudioObjectUnknown)
        if engine.isRunning { engine.stop() }
        if let sourceNode { engine.detach(sourceNode) }
        sourceNode = nil
        if engine.attachedNodes.contains(eq) { engine.detach(eq) }
        isRunning = false
    }

    // MARK: Adaptive loop

    private func tick() {
        let mono = analysisRing.drainMono()
        guard !mono.isEmpty else { return }
        stateLock.lock()
        guard adaptiveOn, let analyzer else { stateLock.unlock(); return }
        analyzer.feed(mono)
        let needed = firstWindow ? 3.0 : 8.0
        guard analyzer.analysedSeconds >= needed, let result = analyzer.result() else { stateLock.unlock(); return }
        let target = SpectrumBalance.gains(for: result, outputBias: bias)
        var next = target
        if !firstWindow {
            func blend(_ old: Double, _ new: Double) -> Double { (old * 0.5 + new * 0.5).rounded() }
            next = .init(bass: blend(current.bass, target.bass), mid: blend(current.mid, target.mid),
                         treble: blend(current.treble, target.treble))
        }
        firstWindow = false
        current = next
        self.analyzer = SpectrumBalance(sampleRate: rate)
        stateLock.unlock()
        apply(next)
        onAdapt?(next)
    }

    // MARK: Core Audio helpers

    /// Audio-HAL process objects belonging to the app (main process and helpers).
    private static func audioProcesses(bundleID: String) -> [AudioObjectID] {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyProcessObjectList,
            mScope: kAudioObjectPropertyScopeGlobal, mElement: kAudioObjectPropertyElementMain)
        var size: UInt32 = 0
        let system = AudioObjectID(kAudioObjectSystemObject)
        guard AudioObjectGetPropertyDataSize(system, &address, 0, nil, &size) == noErr, size > 0 else { return [] }
        var objects = [AudioObjectID](repeating: 0, count: Int(size) / MemoryLayout<AudioObjectID>.size)
        guard AudioObjectGetPropertyData(system, &address, 0, nil, &size, &objects) == noErr else { return [] }
        return objects.filter { object in
            var bundleAddress = AudioObjectPropertyAddress(
                mSelector: kAudioProcessPropertyBundleID,
                mScope: kAudioObjectPropertyScopeGlobal, mElement: kAudioObjectPropertyElementMain)
            var ref: Unmanaged<CFString>?
            var refSize = UInt32(MemoryLayout<Unmanaged<CFString>?>.size)
            guard AudioObjectGetPropertyData(object, &bundleAddress, 0, nil, &refSize, &ref) == noErr,
                  let id = ref?.takeRetainedValue() as String? else { return false }
            return id == bundleID || id.hasPrefix(bundleID + ".")
        }
    }

    private static func defaultOutputUID(_ ref: inout Unmanaged<CFString>?) -> String? {
        var device = AudioDeviceID(kAudioObjectUnknown)
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDefaultOutputDevice,
            mScope: kAudioObjectPropertyScopeGlobal, mElement: kAudioObjectPropertyElementMain)
        var size = UInt32(MemoryLayout<AudioDeviceID>.size)
        guard AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, &size, &device) == noErr,
              device != kAudioObjectUnknown else { return nil }
        var uidAddress = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyDeviceUID,
            mScope: kAudioObjectPropertyScopeGlobal, mElement: kAudioObjectPropertyElementMain)
        var uidSize = UInt32(MemoryLayout<Unmanaged<CFString>?>.size)
        guard AudioObjectGetPropertyData(device, &uidAddress, 0, nil, &uidSize, &ref) == noErr else { return nil }
        return ref?.takeRetainedValue() as String?
    }
}
