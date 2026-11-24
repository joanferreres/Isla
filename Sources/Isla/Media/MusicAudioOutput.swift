import CoreAudio
import IslandCore
import SwiftUI

/// Where Music / system audio is currently routed.
enum MusicAudioOutputKind: String, Sendable, Equatable {
    case builtInSpeakers
    case airPods
    case headphones
    case bluetooth
    case other
}

struct MusicAudioOutput: Equatable, Sendable {
    var kind: MusicAudioOutputKind
    var name: String
    var uid: String

    var shortLabel: String {
        switch kind {
        case .builtInSpeakers: "Altavoces"
        case .airPods: "AirPods"
        case .headphones: "Auriculares"
        case .bluetooth, .other: name.isEmpty ? "Salida" : name
        }
    }

    static let unknown = Self(kind: .other, name: "Salida", uid: "")

    static func current() -> Self {
        var device = AudioDeviceID(kAudioObjectUnknown)
        guard read(AudioObjectID(kAudioObjectSystemObject), kAudioHardwarePropertyDefaultOutputDevice, into: &device),
              device != kAudioObjectUnknown,
              device != 0 else {
            return .unknown
        }

        var transport: UInt32 = 0
        _ = read(device, kAudioDevicePropertyTransportType, into: &transport)

        var uidRef: Unmanaged<CFString>?
        var nameRef: Unmanaged<CFString>?
        let uid = read(device, kAudioDevicePropertyDeviceUID, into: &uidRef)
            ? (uidRef?.takeRetainedValue() as String? ?? "")
            : ""
        let name = read(device, kAudioObjectPropertyName, into: &nameRef)
            ? (nameRef?.takeRetainedValue() as String? ?? "Salida")
            : "Salida"
        let lowered = name.lowercased()
        // Do not query kAudioDevicePropertyDataSourceNameForID — on some macOS
        // builds / devices CoreAudio's HAL SIGSEGVs inside GetPropertyData, and
        // that killed Isla the moment the turntable mixer appeared.

        let kind: MusicAudioOutputKind
        if looksLikeAirPods(lowered) {
            kind = .airPods
        } else if transport == kAudioDeviceTransportTypeBluetooth || transport == kAudioDeviceTransportTypeBluetoothLE {
            kind = looksLikeHeadphones(lowered) ? .headphones : .bluetooth
        } else if transport == kAudioDeviceTransportTypeBuiltIn
                    || lowered.contains("macbook")
                    || lowered.contains("imac")
                    || lowered.contains("speaker")
                    || lowered.contains("altavoz") {
            kind = looksLikeHeadphones(lowered) ? .headphones : .builtInSpeakers
        } else if looksLikeHeadphones(lowered) {
            kind = .headphones
        } else {
            kind = .other
        }

        return Self(kind: kind, name: name, uid: uid)
    }

    /// How the playback device shifts the target curve (dB): AirPods and headphones already
    /// emphasise bass and can be bright; small Mac speakers need a little more low end.
    var eqBias: SpectrumBalance.Gains {
        switch kind {
        case .airPods: .init(bass: -2, mid: 1, treble: -1)
        case .headphones, .bluetooth: .init(bass: -1, mid: 0, treble: 0)
        case .builtInSpeakers: .init(bass: 1, mid: 0, treble: 0)
        case .other: .init(bass: 0, mid: 0, treble: 0)
        }
    }

    private static func looksLikeAirPods(_ text: String) -> Bool {
        text.contains("airpods") || text.contains("airpod")
    }

    private static func looksLikeHeadphones(_ text: String) -> Bool {
        text.contains("headphone") || text.contains("auricular") || text.contains("earphone")
            || text.contains("beats") || text.contains("headset")
    }

    private static func clamp(_ value: Double) -> Double {
        min(12, max(-12, value.rounded()))
    }

    private static func read<T>(_ object: AudioObjectID, _ selector: AudioObjectPropertySelector, into value: inout T) -> Bool {
        var address = AudioObjectPropertyAddress(
            mSelector: selector,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        guard AudioObjectHasProperty(object, &address) else { return false }
        var size = UInt32(MemoryLayout<T>.size)
        return withUnsafeMutableBytes(of: &value) { buffer in
            guard let base = buffer.baseAddress else { return false }
            return AudioObjectGetPropertyData(object, &address, 0, nil, &size, base) == noErr
        }
    }
}

/// Publishes the default output route so the adaptive EQ can re-tune on AirPods ↔ speakers.
@MainActor final class MusicAudioOutputMonitor: ObservableObject {
    /// Start inert — probing CoreAudio during SwiftUI StateObject init has crashed the HAL.
    @Published private(set) var output = MusicAudioOutput.unknown

    private var listener: AudioObjectPropertyListenerBlock?
    private var address = AudioObjectPropertyAddress(
        mSelector: kAudioHardwarePropertyDefaultOutputDevice,
        mScope: kAudioObjectPropertyScopeGlobal,
        mElement: kAudioObjectPropertyElementMain
    )

    func setActive(_ active: Bool) {
        let system = AudioObjectID(kAudioObjectSystemObject)
        if active, listener == nil {
            refresh()
            let block: AudioObjectPropertyListenerBlock = { [weak self] _, _ in
                Task { @MainActor in self?.refresh() }
            }
            if AudioObjectAddPropertyListenerBlock(system, &address, .main, block) == noErr {
                listener = block
            }
        } else if !active, let listener {
            AudioObjectRemovePropertyListenerBlock(system, &address, .main, listener)
            self.listener = nil
        }
    }

    private func refresh() {
        let next = MusicAudioOutput.current()
        if next != output { output = next }
    }
}
