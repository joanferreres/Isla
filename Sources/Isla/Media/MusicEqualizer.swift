import AppKit
import ApplicationServices
import Carbon.HIToolbox

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

struct MusicEqualizerScale {
    let unitsPerDecibel: Double

    init(maximum: Double?) {
        // Music's current sliders expose ±1200 AX units for ±12 dB.
        unitsPerDecibel = maximum == 12 ? 1 : 100
    }

    func decibels(_ value: Double) -> Double { value / unitsPerDecibel }
    func nativeValue(_ decibels: Double) -> Double { decibels * unitsPerDecibel }
}

actor MusicEqualizer {
    private struct Controls {
        let toggle: AXUIElement
        let sliders: [AXUIElement]
        let values: [Double]
        let scale: MusicEqualizerScale

        func gains(for values: [Double]) -> [MixerBand: Double] {
            Dictionary(uniqueKeysWithValues: MixerBand.allCases.map { band in
                let bandValues = values[band.sliderIndices]
                let average = bandValues.reduce(0, +) / Double(bandValues.count)
                return (band, scale.decibels(average).rounded())
            })
        }
    }

    enum Adjustment: Sendable {
        case relative(Double), reset
    }

    enum Failure: LocalizedError {
        case access, closed, unresponsive

        var errorDescription: String? {
            switch self {
            case .access: "macOS necesita que autorices a Isla en Accesibilidad para ajustar el sonido de Música."
            case .closed: "Música no abrió el ecualizador. Vuelve a intentar el ajuste."
            case .unresponsive: "Música no confirmó el cambio de ecualización."
            }
        }
    }

    func read() throws -> [MixerBand: Double] {
        let controls = try findControls()
        return controls.gains(for: controls.values)
    }

    private func openFromMenu() throws -> Bool {
        let app = try musicApplication()
        guard let menuBar = attribute(app, kAXMenuBarAttribute),
              CFGetTypeID(menuBar) == AXUIElementGetTypeID() else { return false }
        for heading in elements(unsafeDowncast(menuBar, to: AXUIElement.self), kAXChildrenAttribute) {
            for menu in elements(heading, kAXChildrenAttribute) {
                if let item = elements(menu, kAXChildrenAttribute).first(where: {
                    let title = (attribute($0, kAXTitleAttribute) as? String)?.lowercased()
                    return ["equalizer", "equaliser", "ecualizador", "equalitzador"].contains(title ?? "")
                        || (attribute($0, kAXMenuItemCmdCharAttribute) as? String)?.lowercased() == "e"
                        && number($0, kAXMenuItemCmdModifiersAttribute) == 2
                }), AXUIElementPerformAction(item, kAXPressAction as CFString) == .success { return true }
            }
        }
        return false
    }

    private func openWithShortcut() throws {
        let app = try musicApplication()
        var pid: pid_t = 0
        guard AXUIElementGetPid(app, &pid) == .success, pid > 0,
              let down = CGEvent(keyboardEventSource: nil, virtualKey: CGKeyCode(kVK_ANSI_E), keyDown: true),
              let up = CGEvent(keyboardEventSource: nil, virtualKey: CGKeyCode(kVK_ANSI_E), keyDown: false) else {
            throw Failure.closed
        }
        for event in [down, up] {
            event.flags = [.maskCommand, .maskAlternate]
            event.postToPid(pid)
        }
    }

    func adjust(_ adjustment: Adjustment, for band: MixerBand) async throws -> [MixerBand: Double] {
        let controls = try await openControlsIfNeeded()
        let gain: Double
        switch adjustment {
        case .relative(let delta):
            guard delta.isFinite, let baseline = controls.gains(for: controls.values)[band] else {
                throw Failure.unresponsive
            }
            gain = min(12, max(-12, baseline + delta))
        case .reset: gain = 0
        }
        return try apply(gain, to: band.sliderIndices, enabled: true, controls: controls)
    }

    func reset() async throws -> [MixerBand: Double] {
        let controls = try await openControlsIfNeeded()
        return try apply(0, to: controls.sliders.indices, enabled: false, controls: controls)
    }

    private func apply(_ gain: Double, to indices: Range<Int>, enabled: Bool, controls: Controls) throws -> [MixerBand: Double] {
        guard let originalSwitch = number(controls.toggle, kAXValueAttribute) else { throw Failure.unresponsive }
        let nativeGain = controls.scale.nativeValue(gain)
        let changed = indices.filter { controls.values[$0] != nativeGain }
        var values = controls.values
        do {
            for index in changed {
                let slider = controls.sliders[index]
                guard AXUIElementSetAttributeValue(slider, kAXValueAttribute as CFString, NSNumber(value: nativeGain)) == .success else {
                    throw Failure.unresponsive
                }
            }
            // Reload the curve through Music's own switch after changing native slider values.
            if !changed.isEmpty { try setEnabled(false, on: controls.toggle) }
            try setEnabled(enabled, on: controls.toggle)
            for index in changed {
                guard let actual = number(controls.sliders[index], kAXValueAttribute),
                      abs(controls.scale.decibels(actual) - gain) < 0.1 else { throw Failure.unresponsive }
                values[index] = actual
            }
        } catch {
            for index in changed {
                _ = AXUIElementSetAttributeValue(controls.sliders[index], kAXValueAttribute as CFString,
                                                 NSNumber(value: controls.values[index]))
            }
            try? setEnabled(originalSwitch == 1, on: controls.toggle)
            throw error
        }
        return controls.gains(for: values)
    }

    private func setEnabled(_ enabled: Bool, on toggle: AXUIElement) throws {
        let target = enabled ? 1.0 : 0.0
        guard let current = number(toggle, kAXValueAttribute) else { throw Failure.unresponsive }
        if current == target { return }
        guard AXUIElementPerformAction(toggle, kAXPressAction as CFString) == .success,
              number(toggle, kAXValueAttribute) == target else { throw Failure.unresponsive }
    }

    private func openControlsIfNeeded() async throws -> Controls {
        do { return try findControls() }
        catch Failure.closed {
            let pressed = try openFromMenu()
            if pressed, let controls = try await waitForControls(attempts: 5) { return controls }
            try openWithShortcut()
            if let controls = try await waitForControls(attempts: 8) { return controls }
            throw Failure.closed
        }
    }

    private func waitForControls(attempts: Int) async throws -> Controls? {
        for _ in 0..<attempts {
            try await Task.sleep(for: .milliseconds(120))
            do { return try findControls() }
            catch Failure.closed { continue }
        }
        return nil
    }

    private func findControls() throws -> Controls {
        let app = try musicApplication()
        let windows = elements(app, kAXWindowsAttribute)
        for window in windows {
            let children = elements(window, kAXChildrenAttribute)
            let sliders = children.filter { role($0) == kAXSliderRole }
            // The equalizer has a preset selector, an on/off control and 11 gain sliders.
            guard sliders.count == 11,
                  children.contains(where: { role($0) == kAXPopUpButtonRole }),
                  let toggle = children.first(where: { role($0) == kAXCheckBoxRole }) else { continue }
            let scale = MusicEqualizerScale(maximum: number(sliders[0], kAXMaxValueAttribute))
            let values = sliders.compactMap { number($0, kAXValueAttribute) }
            guard values.count == sliders.count,
                  values.allSatisfy({ (-12...12).contains(scale.decibels($0)) }) else { continue }
            return Controls(toggle: toggle, sliders: sliders, values: values, scale: scale)
        }
        throw Failure.closed
    }

    private func musicApplication() throws -> AXUIElement {
        guard AXIsProcessTrusted() else { throw Failure.access }
        guard let pid = NSRunningApplication.runningApplications(withBundleIdentifier: "com.apple.Music").first?.processIdentifier else {
            throw Failure.closed
        }
        let app = AXUIElementCreateApplication(pid)
        AXUIElementSetMessagingTimeout(app, 0.35)
        return app
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
