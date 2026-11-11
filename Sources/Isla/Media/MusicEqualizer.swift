import AppKit
import ApplicationServices
import Carbon.HIToolbox

enum MixerBand: String, CaseIterable, Sendable {
    case bass, mid, treble

    var title: String {
        switch self {
        case .bass: "Graves"
        case .mid: "Medios"
        case .treble: "Agudos"
        }
    }

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
        unitsPerDecibel = maximum == 12 ? 1 : 100
    }

    func decibels(_ value: Double) -> Double { value / unitsPerDecibel }
    func nativeValue(_ decibels: Double) -> Double { decibels * unitsPerDecibel }
}

actor MusicEqualizer {
    private struct Controls {
        let toggle: AXUIElement
        let popup: AXUIElement
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

    enum Failure: LocalizedError {
        case access, closed, unresponsive, preset

        var errorDescription: String? {
            switch self {
            case .access: "macOS necesita que autorices a Isla en Accesibilidad para ajustar el sonido de Música."
            case .closed: "Música no abrió el ecualizador. Vuelve a intentar el ajuste."
            case .unresponsive: "Música no confirmó el cambio de ecualización."
            case .preset: "Música no aplicó ese preset del ecualizador."
            }
        }
    }

    func read() throws -> [MixerBand: Double] {
        let controls = try findControls()
        return controls.gains(for: controls.values)
    }

    /// Factory / built-in EQ preset names from Music (AppleScript).
    func presetNames() throws -> [String] {
        let source = """
        tell application "Music" to get name of every EQ preset
        """
        var error: NSDictionary?
        guard let descriptor = NSAppleScript(source: source)?.executeAndReturnError(&error) else {
            if (error?[NSAppleScript.errorNumber] as? Int) == -1743 { throw Failure.access }
            throw Failure.unresponsive
        }
        var names: [String] = []
        if descriptor.descriptorType == typeAEList || descriptor.numberOfItems > 0 {
            for index in 1...max(descriptor.numberOfItems, 0) {
                if let name = descriptor.atIndex(index)?.stringValue?
                    .trimmingCharacters(in: .whitespacesAndNewlines), !name.isEmpty {
                    names.append(name)
                }
            }
        } else if let name = descriptor.stringValue?.trimmingCharacters(in: .whitespacesAndNewlines),
                  !name.isEmpty {
            names = [name]
        }
        guard !names.isEmpty else { throw Failure.preset }
        return names
    }

    func currentPresetName() throws -> String? {
        let controls = try findControls()
        return popupTitle(controls.popup)
    }

    func set(_ gain: Double, for band: MixerBand) async throws -> [MixerBand: Double] {
        guard gain.isFinite else { throw Failure.unresponsive }
        let controls = try await openControlsIfNeeded()
        return try apply(min(12, max(-12, gain)), to: band.sliderIndices, enabled: true, controls: controls)
    }

    /// Applies a Music EQ preset and leaves EQ enabled so it keeps working with Isla closed.
    func selectPreset(_ name: String) async throws -> [MixerBand: Double] {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { throw Failure.preset }
        let controls = try await openControlsIfNeeded()
        do {
            try await selectPresetViaPopup(trimmed, popup: controls.popup)
        } catch {
            try applyPresetBands(trimmed)
        }
        let live = try findControls()
        try setEnabled(true, on: live.toggle)
        let confirmed = try findControls()
        return confirmed.gains(for: confirmed.values)
    }

    func reset() async throws -> [MixerBand: Double] {
        let controls = try await openControlsIfNeeded()
        return try apply(0, to: controls.sliders.indices, enabled: false, controls: controls)
    }

    private func apply(_ gain: Double, to indices: Range<Int>, enabled: Bool, controls: Controls) throws -> [MixerBand: Double] {
        guard let originalSwitch = number(controls.toggle, kAXValueAttribute) else { throw Failure.unresponsive }
        // Enabling first preserves Music's selected curve. Cycling the switch
        // after a write can reload the preset and undo the user's adjustment.
        // Re-resolve controls afterwards: toggling can rebuild the equalizer AX tree
        // and leave the previous slider references unable to accept writes.
        do {
            try setEnabled(enabled, on: controls.toggle)
        } catch {
            try? setEnabled(originalSwitch == 1, on: controls.toggle)
            throw error
        }
        let live: Controls
        do {
            live = try findControls()
        } catch {
            try? setEnabled(originalSwitch == 1, on: controls.toggle)
            throw error
        }
        let nativeGain = live.scale.nativeValue(gain)
        let changed = indices.filter { live.values[$0] != nativeGain }
        var values = live.values
        do {
            for index in changed {
                let slider = live.sliders[index]
                guard AXUIElementSetAttributeValue(slider, kAXValueAttribute as CFString, NSNumber(value: nativeGain)) == .success else {
                    throw Failure.unresponsive
                }
            }
            for index in changed {
                guard let actual = number(live.sliders[index], kAXValueAttribute),
                      abs(live.scale.decibels(actual) - gain) <= 0.51 else { throw Failure.unresponsive }
                values[index] = actual
            }
        } catch {
            for index in changed {
                _ = AXUIElementSetAttributeValue(live.sliders[index], kAXValueAttribute as CFString,
                                                 NSNumber(value: live.values[index]))
            }
            try? setEnabled(originalSwitch == 1, on: live.toggle)
            throw error
        }
        return live.gains(for: values)
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
        for window in elements(app, kAXWindowsAttribute) {
            let children = elements(window, kAXChildrenAttribute)
            let sliders = children.filter { role($0) == kAXSliderRole }
            guard sliders.count == 11,
                  let popup = children.first(where: { role($0) == kAXPopUpButtonRole }),
                  let toggle = children.first(where: { role($0) == kAXCheckBoxRole }) else { continue }
            let scale = MusicEqualizerScale(maximum: number(sliders[0], kAXMaxValueAttribute))
            let values = sliders.compactMap { number($0, kAXValueAttribute) }
            guard values.count == sliders.count,
                  values.allSatisfy({ (-12...12).contains(scale.decibels($0)) }) else { continue }
            return Controls(toggle: toggle, popup: popup, sliders: sliders, values: values, scale: scale)
        }
        throw Failure.closed
    }

    private func popupTitle(_ popup: AXUIElement) -> String? {
        let keys = [kAXValueAttribute, kAXTitleAttribute, kAXDescriptionAttribute, kAXValueDescriptionAttribute]
        for key in keys {
            if let text = attribute(popup, key) as? String {
                let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
                if !trimmed.isEmpty { return trimmed }
            }
        }
        return nil
    }

    private func selectPresetViaPopup(_ name: String, popup: AXUIElement) async throws {
        if popupTitle(popup)?.caseInsensitiveCompare(name) == .orderedSame { return }
        guard AXUIElementPerformAction(popup, kAXPressAction as CFString) == .success else {
            throw Failure.preset
        }
        try await Task.sleep(for: .milliseconds(120))
        guard let item = findMenuItem(named: name, under: popup)
                ?? findMenuItem(named: name, under: try musicApplication()) else {
            _ = AXUIElementPerformAction(popup, kAXCancelAction as CFString)
            throw Failure.preset
        }
        guard AXUIElementPerformAction(item, kAXPressAction as CFString) == .success else {
            throw Failure.preset
        }
        try await Task.sleep(for: .milliseconds(80))
        if let title = popupTitle(popup), title.caseInsensitiveCompare(name) != .orderedSame {
            // Some builds keep the previous title briefly; band fallback still available to caller.
            throw Failure.preset
        }
    }

    private func findMenuItem(named name: String, under root: AXUIElement) -> AXUIElement? {
        find(in: root, depth: 8) { element in
            guard role(element) == kAXMenuItemRole || role(element) == kAXStaticTextRole else { return false }
            let title = (attribute(element, kAXTitleAttribute) as? String)
                ?? (attribute(element, kAXDescriptionAttribute) as? String)
                ?? ""
            return title.trimmingCharacters(in: .whitespacesAndNewlines)
                .caseInsensitiveCompare(name) == .orderedSame
        }
    }

    private func find(in element: AXUIElement, depth: Int, matching: (AXUIElement) -> Bool) -> AXUIElement? {
        if matching(element) { return element }
        guard depth > 0 else { return nil }
        for child in elements(element, kAXChildrenAttribute) {
            if let match = find(in: child, depth: depth - 1, matching: matching) { return match }
        }
        return nil
    }

    /// Fallback: push factory preset band values onto the open EQ window (leaves EQ On).
    private func applyPresetBands(_ name: String) throws {
        let escaped = name.replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
        let source = """
        tell application "Music"
          set p to first EQ preset whose name is "\(escaped)"
          return {preamp of p, band 1 of p, band 2 of p, band 3 of p, band 4 of p, band 5 of p, band 6 of p, band 7 of p, band 8 of p, band 9 of p, band 10 of p}
        end tell
        """
        var error: NSDictionary?
        guard let descriptor = NSAppleScript(source: source)?.executeAndReturnError(&error),
              descriptor.numberOfItems == 11 else {
            throw Failure.preset
        }
        var decibels: [Double] = []
        for index in 1...11 {
            let value = descriptor.atIndex(index)?.doubleValue
                ?? Double(descriptor.atIndex(index)?.stringValue ?? "")
            guard let value, value.isFinite else { throw Failure.preset }
            decibels.append(value)
        }
        let live = try findControls()
        try setEnabled(true, on: live.toggle)
        let controls = try findControls()
        for (index, db) in decibels.enumerated() {
            let clamped = min(12, max(-12, db))
            let native = controls.scale.nativeValue(clamped)
            guard AXUIElementSetAttributeValue(controls.sliders[index], kAXValueAttribute as CFString,
                                               NSNumber(value: native)) == .success else {
                throw Failure.unresponsive
            }
        }
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
