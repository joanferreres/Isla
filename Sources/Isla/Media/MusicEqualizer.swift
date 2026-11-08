import AppKit
import ApplicationServices

enum MixerBand: String, CaseIterable {
    case bass, mid, treble

    var title: String {
        switch self {
        case .bass: "Graves"
        case .mid: "Medios"
        case .treble: "Agudos"
        }
    }

    // Música orders the sliders from preamp and 32 Hz through 16 kHz.
    var sliderIndices: Range<Int> {
        switch self {
        case .bass: 1..<5
        case .mid: 5..<8
        case .treble: 8..<11
        }
    }
}

actor MusicEqualizer {
    enum Failure: LocalizedError {
        case access, closed, unresponsive

        var errorDescription: String? {
            switch self {
            case .access: "Permite a Isla acceder al ecualizador de Música."
            case .closed: "En Música, abre el ecualizador con ⌥⌘E y déjalo abierto."
            case .unresponsive: "Música no confirmó el cambio de ecualización."
            }
        }
    }

    func read() throws -> [MixerBand: Double] {
        try gains(findControls().sliders)
    }

    func set(_ gain: Double, for band: MixerBand) throws -> [MixerBand: Double] {
        let controls = try findControls()
        let sliders = controls.sliders[band.sliderIndices]
        guard gain.isFinite, (-12...12).contains(gain),
              let enabled = number(controls.toggle, kAXValueAttribute) else {
            throw Failure.unresponsive
        }
        let original = try sliders.map { slider in
            guard let value = number(slider, kAXValueAttribute) else { throw Failure.unresponsive }
            return value
        }
        do {
            for slider in sliders {
                guard AXUIElementSetAttributeValue(slider, kAXValueAttribute as CFString, NSNumber(value: gain)) == .success,
                      let actual = number(slider, kAXValueAttribute), abs(actual - gain) < 0.1 else {
                    throw Failure.unresponsive
                }
            }
            if enabled == 0 {
                guard AXUIElementPerformAction(controls.toggle, kAXPressAction as CFString) == .success,
                      number(controls.toggle, kAXValueAttribute) == 1 else { throw Failure.unresponsive }
            }
        } catch {
            for (slider, value) in zip(sliders, original) {
                _ = AXUIElementSetAttributeValue(slider, kAXValueAttribute as CFString, NSNumber(value: value))
            }
            throw error
        }
        return try gains(controls.sliders)
    }

    private func gains(_ sliders: [AXUIElement]) throws -> [MixerBand: Double] {
        let values = sliders.compactMap { number($0, kAXValueAttribute) }
        guard values.count == sliders.count else { throw Failure.unresponsive }
        return Dictionary(uniqueKeysWithValues: MixerBand.allCases.map { band in
            let values = values[band.sliderIndices]
            return (band, (values.reduce(0, +) / Double(values.count)).rounded())
        })
    }

    private func findControls() throws -> (toggle: AXUIElement, sliders: [AXUIElement]) {
        guard AXIsProcessTrusted() else { throw Failure.access }
        guard let pid = NSRunningApplication.runningApplications(withBundleIdentifier: "com.apple.Music").first?.processIdentifier else {
            throw Failure.closed
        }
        let app = AXUIElementCreateApplication(pid)
        AXUIElementSetMessagingTimeout(app, 0.35)
        for window in elements(app, kAXWindowsAttribute) {
            let children = elements(window, kAXChildrenAttribute)
            let sliders = children.filter { role($0) == kAXSliderRole }
            // Match the equalizer by its controls so the window works in any language.
            guard sliders.count == 11,
                  sliders.allSatisfy({ number($0, kAXMinValueAttribute) == -12 && number($0, kAXMaxValueAttribute) == 12 }),
                  let toggle = children.first(where: { role($0) == kAXCheckBoxRole }) else { continue }
            return (toggle, sliders)
        }
        throw Failure.closed
    }

    private func role(_ element: AXUIElement) -> String? { attribute(element, kAXRoleAttribute) as? String }
    private func elements(_ element: AXUIElement, _ key: String) -> [AXUIElement] {
        attribute(element, key) as? [AXUIElement] ?? []
    }
    private func number(_ element: AXUIElement, _ key: String) -> Double? {
        (attribute(element, key) as? NSNumber)?.doubleValue
    }
    private func attribute(_ element: AXUIElement, _ key: String) -> CFTypeRef? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, key as CFString, &value) == .success else { return nil }
        return value
    }
}
