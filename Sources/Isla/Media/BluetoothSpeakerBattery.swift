import CoreAudio
import SwiftUI

@MainActor final class BluetoothSpeakerBattery: ObservableObject {
    struct Reading: Equatable {
        let name: String
        let percent: Int

        var symbol: String {
            let step = Int((Double(percent) / 25).rounded()) * 25
            return "battery.\(step)percent"
        }
    }

    @Published private(set) var reading: Reading?
    private var listener: AudioObjectPropertyListenerBlock?
    private var refresh: Task<Void, Never>?
    private var route: BluetoothAudioRoute?
    private var address = AudioObjectPropertyAddress(
        mSelector: kAudioHardwarePropertyDefaultOutputDevice,
        mScope: kAudioObjectPropertyScopeGlobal,
        mElement: kAudioObjectPropertyElementMain
    )

    func setVisible(_ visible: Bool) {
        let system = AudioObjectID(kAudioObjectSystemObject)
        if visible, listener == nil {
            let block: AudioObjectPropertyListenerBlock = { [weak self] _, _ in
                Task { @MainActor in
                    guard let self, self.listener != nil else { return }
                    self.routeChanged()
                }
            }
            guard AudioObjectAddPropertyListenerBlock(system, &address, .main, block) == noErr else { return }
            listener = block
            routeChanged()
        } else if !visible, let listener {
            AudioObjectRemovePropertyListenerBlock(system, &address, .main, listener)
            self.listener = nil
            route = nil
            refresh?.cancel()
            refresh = nil
            reading = nil
        }
    }

    private func routeChanged() {
        let next = BluetoothAudioRoute.current()
        guard next != route else { return }
        route = next
        refresh?.cancel()
        reading = nil
        guard let next else { return }
        refresh = Task { [weak self] in
            while !Task.isCancelled {
                let percent = await Task.detached(priority: .utility) { next.readBattery() }.value
                guard !Task.isCancelled else { return }
                let result = percent.map { Reading(name: next.name, percent: $0) }
                if self?.reading != result { self?.reading = result }
                do { try await Task.sleep(for: .seconds(120), tolerance: .seconds(15)) } catch { return }
            }
        }
    }
}

struct BluetoothAudioRoute: Equatable, Sendable {
    let uid: String
    let name: String

    static func current() -> Self? {
        var device = AudioDeviceID(kAudioObjectUnknown)
        guard read(AudioObjectID(kAudioObjectSystemObject), kAudioHardwarePropertyDefaultOutputDevice, into: &device),
              device != kAudioObjectUnknown else { return nil }
        var transport: UInt32 = 0
        guard read(device, kAudioDevicePropertyTransportType, into: &transport),
              transport == kAudioDeviceTransportTypeBluetooth || transport == kAudioDeviceTransportTypeBluetoothLE else { return nil }
        var uid: Unmanaged<CFString>?
        var name: Unmanaged<CFString>?
        guard read(device, kAudioDevicePropertyDeviceUID, into: &uid), let uid else { return nil }
        let identifier = uid.takeRetainedValue() as String
        guard read(device, kAudioObjectPropertyName, into: &name), let name else { return nil }
        return Self(uid: identifier, name: name.takeRetainedValue() as String)
    }

    private static func read<T>(_ object: AudioObjectID, _ selector: AudioObjectPropertySelector, into value: inout T) -> Bool {
        var address = AudioObjectPropertyAddress(mSelector: selector, mScope: kAudioObjectPropertyScopeGlobal,
                                                 mElement: kAudioObjectPropertyElementMain)
        var size = UInt32(MemoryLayout<T>.size)
        return withUnsafeMutableBytes(of: &value) { buffer in
            AudioObjectGetPropertyData(object, &address, 0, nil, &size, buffer.baseAddress!) == noErr
        }
    }

    func readBattery() -> Int? {
        let output = Pipe()
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/sbin/system_profiler")
        process.arguments = ["SPBluetoothDataType", "-json", "-detailLevel", "basic", "-timeout", "5"]
        process.standardOutput = output
        process.standardError = FileHandle.nullDevice
        do { try process.run() } catch { return nil }
        let data = output.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        guard process.terminationStatus == 0 else { return nil }
        return battery(in: data)
    }

    func battery(in data: Data) -> Int? {
        guard let report = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let adapters = report["SPBluetoothDataType"] as? [[String: Any]] else { return nil }
        let devices = adapters.flatMap { $0["device_connected"] as? [[String: [String: Any]]] ?? [] }
            .flatMap { $0.map { (name: $0.key, fields: $0.value) } }
        let uid = uid.lowercased().filter(\.isHexDigit)
        let byAddress = devices.filter {
            let address = ($0.fields["device_address"] as? String ?? "").lowercased().filter(\.isHexDigit)
            return address.count == 12 && uid.contains(address)
        }
        let matches = byAddress.isEmpty ? devices.filter { $0.name == name } : byAddress
        guard matches.count == 1 else { return nil }
        let field = matches[0].fields["device_batteryLevelMain"]
        let percent = (field as? String).flatMap { Int($0.trimmingCharacters(in: CharacterSet(charactersIn: "% "))) }
            ?? (field as? Int)
        return percent.flatMap { (0...100).contains($0) ? $0 : nil }
    }
}
