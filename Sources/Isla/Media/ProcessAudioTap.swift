import AppKit
import AudioToolbox
import CoreAudio
import IslandCore

/// Listens to the audio of one app (Music / Spotify) through a Core Audio process tap and
/// measures its tonal balance. Nothing is recorded or stored; samples are analysed and dropped.
enum ProcessAudioTap {
    enum Failure: LocalizedError {
        case notRunning, unsupported(String), noAudio

        var errorDescription: String? {
            switch self {
            case .notRunning: "La app de música no está abierta."
            case .unsupported(let step): "No se pudo escuchar el audio (\(step)). Revisa el permiso de captura de audio."
            case .noAudio: "Sin audio que analizar: ¿está sonando? Permite a Isla capturar audio en Privacidad y seguridad."
            }
        }
    }

    static func measure(bundleID: String, seconds: Double = 6, timeout: Double = 25) async throws -> SpectrumBalance.Result {
        guard let app = NSRunningApplication.runningApplications(withBundleIdentifier: bundleID).first else {
            throw Failure.notRunning
        }
        var processObject = AudioObjectID(kAudioObjectUnknown)
        var pid = app.processIdentifier
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyTranslatePIDToProcessObject,
            mScope: kAudioObjectPropertyScopeGlobal, mElement: kAudioObjectPropertyElementMain)
        var size = UInt32(MemoryLayout<AudioObjectID>.size)
        guard AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &address,
                                         UInt32(MemoryLayout<pid_t>.size), &pid, &size, &processObject) == noErr,
              processObject != kAudioObjectUnknown else { throw Failure.notRunning }

        let description = CATapDescription(stereoMixdownOfProcesses: [processObject])
        description.uuid = UUID()
        description.muteBehavior = .unmuted
        description.isPrivate = true
        var tapID = AudioObjectID(kAudioObjectUnknown)
        guard AudioHardwareCreateProcessTap(description, &tapID) == noErr else { throw Failure.unsupported("tap") }
        defer { AudioHardwareDestroyProcessTap(tapID) }

        var formatAddress = AudioObjectPropertyAddress(
            mSelector: kAudioTapPropertyFormat,
            mScope: kAudioObjectPropertyScopeGlobal, mElement: kAudioObjectPropertyElementMain)
        var format = AudioStreamBasicDescription()
        var formatSize = UInt32(MemoryLayout<AudioStreamBasicDescription>.size)
        guard AudioObjectGetPropertyData(tapID, &formatAddress, 0, nil, &formatSize, &format) == noErr,
              format.mSampleRate > 0 else { throw Failure.unsupported("formato") }

        let aggregate: [String: Any] = [
            kAudioAggregateDeviceNameKey: "Isla EQ Tap",
            kAudioAggregateDeviceUIDKey: UUID().uuidString,
            kAudioAggregateDeviceIsPrivateKey: true,
            kAudioAggregateDeviceTapAutoStartKey: true,
            kAudioAggregateDeviceTapListKey: [[
                "uid": description.uuid.uuidString,
                "drift": true,
            ]],
        ]
        var deviceID = AudioObjectID(kAudioObjectUnknown)
        guard AudioHardwareCreateAggregateDevice(aggregate as CFDictionary, &deviceID) == noErr else {
            throw Failure.unsupported("dispositivo")
        }
        defer { AudioHardwareDestroyAggregateDevice(deviceID) }

        let analyzer = SpectrumBalance(sampleRate: format.mSampleRate)
        let channels = max(1, Int(format.mChannelsPerFrame))
        let interleaved = format.mFormatFlags & kAudioFormatFlagIsNonInterleaved == 0
        var procID: AudioDeviceIOProcID?
        let queue = DispatchQueue(label: "isla.eq.tap", qos: .utility)
        let status = AudioDeviceCreateIOProcIDWithBlock(&procID, deviceID, queue) { _, input, _, _, _ in
            let buffers = UnsafeMutableAudioBufferListPointer(UnsafeMutablePointer(mutating: input))
            guard let first = buffers.first, let data = first.mData else { return }
            let floats = data.assumingMemoryBound(to: Float.self)
            let count = Int(first.mDataByteSize) / MemoryLayout<Float>.size
            if interleaved, channels > 1 {
                let frames = count / channels
                var mono = [Float](repeating: 0, count: frames)
                for frame in 0..<frames {
                    var sum: Float = 0
                    for channel in 0..<channels { sum += floats[frame * channels + channel] }
                    mono[frame] = sum / Float(channels)
                }
                analyzer.feed(mono)
            } else {
                analyzer.feed(Array(UnsafeBufferPointer(start: floats, count: count)))
            }
        }
        guard status == noErr, let procID else { throw Failure.unsupported("lectura") }
        guard AudioDeviceStart(deviceID, procID) == noErr else {
            AudioDeviceDestroyIOProcID(deviceID, procID)
            throw Failure.unsupported("inicio")
        }
        defer {
            AudioDeviceStop(deviceID, procID)
            AudioDeviceDestroyIOProcID(deviceID, procID)
        }

        let deadline = Date().addingTimeInterval(timeout)
        while analyzer.analysedSeconds < seconds, Date() < deadline {
            try await Task.sleep(for: .milliseconds(250))
        }
        guard analyzer.analysedSeconds >= 1.5, let result = analyzer.result() else { throw Failure.noAudio }
        return result
    }
}
