import CoreAudio
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

    /// Compact hint for the Claude / ChatGPT EQ prompt.
    var promptHint: String {
        switch kind {
        case .builtInSpeakers:
            "Built-in Mac speakers («\(name)»). Fuller bass for room fill is OK; avoid muddy mids."
        case .airPods:
            "Apple AirPods / earbuds («\(name)»). They already emphasize bass and can sound harsh on top — prefer clarity in mids, keep bass conservative (−2…+2 unless genre needs more), and avoid bright treble spikes."
        case .headphones:
            "Headphones («\(name)»). Prefer a balanced curve; light bass lift OK, keep treble controlled."
        case .bluetooth:
            "Bluetooth headphones / speaker («\(name)»). Prefer a balanced curve; avoid heavy bass that Bluetooth compression muddies."
        case .other:
            "Output device «\(name)». Prefer a balanced, subtle EQ."
        }
    }

    static func current() -> Self {
        var device = AudioDeviceID(kAudioObjectUnknown)
        guard read(AudioObjectID(kAudioObjectSystemObject), kAudioHardwarePropertyDefaultOutputDevice, into: &device),
              device != kAudioObjectUnknown else {
            return Self(kind: .other, name: "Desconocida", uid: "")
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
        let source = dataSourceName(device)?.lowercased() ?? ""

        let kind: MusicAudioOutputKind
        if looksLikeAirPods(lowered) || looksLikeAirPods(source) {
            kind = .airPods
        } else if transport == kAudioDeviceTransportTypeBluetooth || transport == kAudioDeviceTransportTypeBluetoothLE {
            kind = looksLikeHeadphones(lowered) ? .headphones : .bluetooth
        } else if transport == kAudioDeviceTransportTypeBuiltIn
                    || lowered.contains("macbook")
                    || lowered.contains("imac")
                    || lowered.contains("speaker")
                    || lowered.contains("altavoz")
                    || source.contains("speaker")
                    || source.contains("altavoz") {
            if looksLikeHeadphones(lowered) || looksLikeHeadphones(source) {
                kind = .headphones
            } else {
                kind = .builtInSpeakers
            }
        } else if looksLikeHeadphones(lowered) || looksLikeHeadphones(source) {
            kind = .headphones
        } else {
            kind = .other
        }

        return Self(kind: kind, name: name, uid: uid)
    }

    /// Soft post-adjust so AirPods stay listenable even if the model over-boosts bass.
    func adapted(_ advice: MusicClaudeEQService.Advice) -> MusicClaudeEQService.Advice {
        var next = advice
        switch kind {
        case .airPods:
            next.bass = Self.clamp(advice.bass - 2)
            next.mid = Self.clamp(advice.mid + 1)
            next.treble = Self.clamp(advice.treble - 1)
        case .headphones, .bluetooth:
            next.bass = Self.clamp(advice.bass - 1)
        case .builtInSpeakers:
            next.bass = Self.clamp(advice.bass + 1)
        case .other:
            break
        }
        return next
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

    private static func dataSourceName(_ device: AudioDeviceID) -> String? {
        var source: UInt32 = 0
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyDataSource,
            mScope: kAudioObjectPropertyScopeOutput,
            mElement: kAudioObjectPropertyElementMain
        )
        var size = UInt32(MemoryLayout<UInt32>.size)
        guard AudioObjectGetPropertyData(device, &address, 0, nil, &size, &source) == noErr else { return nil }

        var nameAddress = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyDataSourceNameForID,
            mScope: kAudioObjectPropertyScopeOutput,
            mElement: kAudioObjectPropertyElementMain
        )
        var name: Unmanaged<CFString>?
        var nameSize = UInt32(MemoryLayout<Unmanaged<CFString>?>.size)
        var qualifier = source
        let qualifierSize = UInt32(MemoryLayout<UInt32>.size)
        guard AudioObjectGetPropertyData(device, &nameAddress, qualifierSize, &qualifier, &nameSize, &name) == noErr,
              let name else { return nil }
        return name.takeRetainedValue() as String
    }

    private static func read<T>(_ object: AudioObjectID, _ selector: AudioObjectPropertySelector, into value: inout T) -> Bool {
        var address = AudioObjectPropertyAddress(
            mSelector: selector,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var size = UInt32(MemoryLayout<T>.size)
        return withUnsafeMutableBytes(of: &value) { buffer in
            AudioObjectGetPropertyData(object, &address, 0, nil, &size, buffer.baseAddress!) == noErr
        }
    }
}

/// Publishes the default output route so Claude EQ can re-tune on AirPods ↔ speakers.
@MainActor final class MusicAudioOutputMonitor: ObservableObject {
    @Published private(set) var output = MusicAudioOutput.current()

    private var listener: AudioObjectPropertyListenerBlock?
    private var address = AudioObjectPropertyAddress(
        mSelector: kAudioHardwarePropertyDefaultOutputDevice,
        mScope: kAudioObjectPropertyScopeGlobal,
        mElement: kAudioObjectPropertyElementMain
    )

    func setActive(_ active: Bool) {
        let system = AudioObjectID(kAudioObjectSystemObject)
        if active, listener == nil {
            let block: AudioObjectPropertyListenerBlock = { [weak self] _, _ in
                Task { @MainActor in self?.refresh() }
            }
            guard AudioObjectAddPropertyListenerBlock(system, &address, .main, block) == noErr else { return }
            listener = block
            refresh()
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
