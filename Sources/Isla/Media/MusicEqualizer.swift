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

    /// Music EQ preset band numbers (1…10). Preamp is separate.
    var bandNumbers: ClosedRange<Int> {
        switch self {
        case .bass: 1...4
        case .mid: 5...7
        case .treble: 8...10
        }
    }

    /// AX equalizer sliders: index 0 = preamp, 1…10 = bands.
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

/// Drives Music EQ through the modifiable **Manual** preset via AppleScript.
/// AX is only used to turn EQ On and select Manual when needed; the native
/// Equalizer window may stay hidden/closed afterward — band writes still apply.
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

    private let manualPreset = "Manual"
    private var desired: [MixerBand: Double] = Dictionary(
        uniqueKeysWithValues: MixerBand.allCases.map { ($0, 0.0) }
    )

    func read() throws -> [MixerBand: Double] {
        if let gains = try? readManualGains() {
            desired = gains
            return gains
        }
        let controls = try findControls()
        let gains = controls.gains(for: controls.values)
        desired = gains
        return gains
    }

    func presetNames() throws -> [String] {
        let source = """
        tell application "Music" to get name of every EQ preset
        """
        let descriptor = try runAppleScript(source)
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
        if let title = try? appleScriptString("""
            tell application "Music"
              try
                return name of current EQ preset
              on error
                return ""
              end try
            end tell
            """), !title.isEmpty {
            return title
        }
        if let controls = try? findControls() {
            return popupTitle(controls.popup)
        }
        return nil
    }

    func set(_ gain: Double, for band: MixerBand) async throws -> [MixerBand: Double] {
        guard gain.isFinite else { throw Failure.unresponsive }
        desired[band] = min(12, max(-12, gain)).rounded()
        try writeManualBands(from: desired)
        try await ensureManualEQEnabled()
        // Re-write after enabling Manual so Music applies the curve to playback.
        try writeManualBands(from: desired)
        return desired
    }

    /// Activates a factory (or Manual) EQ preset by name and leaves EQ On.
    /// AppleScript cannot set `current EQ preset` on modern Music — AX popup is required.
    /// Does **not** rewrite Manual when choosing a factory preset (that was silently no-op’ing audio).
    func selectPreset(_ name: String) async throws -> [MixerBand: Double] {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { throw Failure.preset }
        let bands = try readPresetBands(trimmed)
        desired = gainsFromBands(bands)
        try await activateNamedPreset(trimmed)
        return desired
    }

    func reset() async throws -> [MixerBand: Double] {
        desired = Dictionary(uniqueKeysWithValues: MixerBand.allCases.map { ($0, 0.0) })
        try writeManualBands(from: desired)
        // Prefer disabling via AX when possible; Manual stays flat either way.
        if let controls = try? await openControlsIfNeeded() {
            try? setEnabled(false, on: controls.toggle)
            hideEqualizerWindow()
        }
        return desired
    }

    // MARK: - AppleScript Manual preset (works with EQ window hidden/closed)

    private func readManualGains() throws -> [MixerBand: Double] {
        gainsFromBands(try readPresetBands(manualPreset))
    }

    private func gainsFromBands(_ bands: [Double]) -> [MixerBand: Double] {
        // bands[0] = preamp, bands[1...10] = EQ bands
        Dictionary(uniqueKeysWithValues: MixerBand.allCases.map { band in
            let slice = band.bandNumbers.map { bands[$0] }
            let average = slice.reduce(0, +) / Double(slice.count)
            return (band, average.rounded())
        })
    }

    private func readPresetBands(_ name: String) throws -> [Double] {
        let escaped = escapeAppleScript(name)
        let source = """
        tell application "Music"
          set p to first EQ preset whose name is "\(escaped)"
          return {preamp of p, band 1 of p, band 2 of p, band 3 of p, band 4 of p, band 5 of p, band 6 of p, band 7 of p, band 8 of p, band 9 of p, band 10 of p}
        end tell
        """
        let descriptor = try runAppleScript(source)
        guard descriptor.numberOfItems == 11 else { throw Failure.preset }
        var values: [Double] = []
        for index in 1...11 {
            let value = descriptor.atIndex(index)?.doubleValue
                ?? Double(descriptor.atIndex(index)?.stringValue ?? "")
            guard let value, value.isFinite else { throw Failure.preset }
            values.append(min(12, max(-12, value)))
        }
        return values
    }

    private func writeManualBands(from gains: [MixerBand: Double]) throws {
        var bands = Array(repeating: 0.0, count: 11)
        for band in MixerBand.allCases {
            let value = gains[band] ?? 0
            for number in band.bandNumbers {
                bands[number] = value
            }
        }
        try writeManualRaw(bands)
    }

    private func writeManualRaw(_ bands: [Double]) throws {
        guard bands.count == 11 else { throw Failure.unresponsive }
        func n(_ index: Int) -> String {
            String(format: "%.2f", locale: Locale(identifier: "en_US_POSIX"), bands[index])
        }
        let source = """
        tell application "Music"
          set p to first EQ preset whose name is "\(manualPreset)"
          set preamp of p to \(n(0))
          set band 1 of p to \(n(1))
          set band 2 of p to \(n(2))
          set band 3 of p to \(n(3))
          set band 4 of p to \(n(4))
          set band 5 of p to \(n(5))
          set band 6 of p to \(n(6))
          set band 7 of p to \(n(7))
          set band 8 of p to \(n(8))
          set band 9 of p to \(n(9))
          set band 10 of p to \(n(10))
        end tell
        """
        _ = try runAppleScript(source)
    }

    /// Make sure EQ is On and Manual is the active preset. Band values themselves
    /// are already on Manual via AppleScript; this only wires playback to them.
    private func ensureManualEQEnabled() async throws {
        if isEQEnabledAndPreset(manualPreset) { return }
        try await activateNamedPreset(manualPreset)
    }

    private func isEQEnabledAndPreset(_ name: String) -> Bool {
        appleScriptBool("""
            tell application "Music"
              try
                if EQ enabled is false then return false
                try
                  return (name of current EQ preset is "\(escapeAppleScript(name))")
                on error
                  return false
                end try
              on error
                return false
              end try
            end tell
            """) == true
    }

    /// Reveal EQ UI briefly, turn EQ On, select `name` in the preset popup, then hide again.
    private func activateNamedPreset(_ name: String) async throws {
        revealEqualizerWindow()
        let controls = try await openControlsIfNeeded()
        try setEnabled(true, on: controls.toggle)
        let live = try findControls()
        if popupTitle(live.popup)?.caseInsensitiveCompare(name) != .orderedSame {
            try await selectPresetViaPopup(name, popup: live.popup)
        }
        // Confirm via AX (AppleScript often cannot read current EQ preset while window was hidden).
        let confirmed = try findControls()
        if popupTitle(confirmed.popup)?.caseInsensitiveCompare(name) != .orderedSame {
            try await selectPresetViaPopup(name, popup: confirmed.popup)
            let again = try findControls()
            guard popupTitle(again.popup)?.caseInsensitiveCompare(name) == .orderedSame else {
                hideEqualizerWindow()
                throw Failure.preset
            }
        }
        hideEqualizerWindow()
        parkEqualizerWindows()
    }

    private func revealEqualizerWindow() {
        _ = try? runAppleScript("""
        tell application "Music"
          try
            if (count of EQ windows) > 0 then
              set visible of EQ window 1 to true
            end if
          end try
        end tell
        """)
    }

    private func hideEqualizerWindow() {
        _ = try? runAppleScript("""
        tell application "Music"
          try
            repeat with w in EQ windows
              set visible of w to false
            end repeat
          end try
        end tell
        """)
    }

    // MARK: - AX helpers (enable / open only)

    private func setEnabled(_ enabled: Bool, on toggle: AXUIElement) throws {
        let target = enabled ? 1.0 : 0.0
        guard let current = number(toggle, kAXValueAttribute) else { throw Failure.unresponsive }
        if current == target { return }
        guard AXUIElementPerformAction(toggle, kAXPressAction as CFString) == .success,
              number(toggle, kAXValueAttribute) == target else { throw Failure.unresponsive }
    }

    private func openControlsIfNeeded() async throws -> Controls {
        do {
            return try findControls()
        } catch Failure.closed {
            revealEqualizerWindow()
            if let controls = try await waitForControls(attempts: 4) {
                return controls
            }
            let pressed = try openFromMenu()
            if pressed, let controls = try await waitForControls(attempts: 6) {
                return controls
            }
            try openWithShortcut()
            if let controls = try await waitForControls(attempts: 10) {
                return controls
            }
            throw Failure.closed
        }
    }

    private func parkEqualizerWindows() {
        guard let app = try? musicApplication() else { return }
        for window in elements(app, kAXWindowsAttribute) where isEqualizerWindow(window) {
            _ = AXUIElementSetAttributeValue(window, kAXMinimizedAttribute as CFString, kCFBooleanFalse)
            var point = CGPoint(x: -12_000, y: -12_000)
            if let value = AXValueCreate(.cgPoint, &point) {
                _ = AXUIElementSetAttributeValue(window, kAXPositionAttribute as CFString, value)
            }
        }
    }

    private func isEqualizerWindow(_ window: AXUIElement) -> Bool {
        let title = ((attribute(window, kAXTitleAttribute) as? String) ?? "").lowercased()
        if ["equalizer", "equaliser", "ecualizador", "equalitzador"].contains(where: { title.contains($0) }) {
            return true
        }
        let children = elements(window, kAXChildrenAttribute)
        let sliders = children.filter { role($0) == kAXSliderRole }
        return sliders.count == 11
            && children.contains(where: { role($0) == kAXPopUpButtonRole })
            && children.contains(where: { role($0) == kAXCheckBoxRole })
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
            try await Task.sleep(for: .milliseconds(90))
            do {
                return try findControls()
            } catch Failure.closed {
                revealEqualizerWindow()
                continue
            }
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
        var item: AXUIElement?
        for _ in 0..<8 {
            try await Task.sleep(for: .milliseconds(60))
            item = findMenuItem(named: name, under: popup)
            if item == nil, let app = try? musicApplication() {
                item = findMenuItem(named: name, under: app)
            }
            if item != nil { break }
        }
        guard let item else {
            _ = AXUIElementPerformAction(popup, kAXCancelAction as CFString)
            throw Failure.preset
        }
        guard AXUIElementPerformAction(item, kAXPressAction as CFString) == .success else {
            _ = AXUIElementPerformAction(popup, kAXCancelAction as CFString)
            throw Failure.preset
        }
        for _ in 0..<6 {
            try await Task.sleep(for: .milliseconds(50))
            if popupTitle(popup)?.caseInsensitiveCompare(name) == .orderedSame { return }
            // Popup title attribute can lag; re-resolve controls.
            if let title = try? findControls(),
               popupTitle(title.popup)?.caseInsensitiveCompare(name) == .orderedSame {
                return
            }
        }
        throw Failure.preset
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

    // MARK: - AppleScript plumbing

    private func runAppleScript(_ source: String) throws -> NSAppleEventDescriptor {
        var error: NSDictionary?
        guard let descriptor = NSAppleScript(source: source)?.executeAndReturnError(&error) else {
            if (error?[NSAppleScript.errorNumber] as? Int) == -1743 { throw Failure.access }
            throw Failure.unresponsive
        }
        if let code = error?[NSAppleScript.errorNumber] as? Int, code != 0 {
            if code == -1743 { throw Failure.access }
            throw Failure.unresponsive
        }
        return descriptor
    }

    private func appleScriptString(_ source: String) throws -> String {
        let descriptor = try runAppleScript(source)
        return descriptor.stringValue?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    }

    private func appleScriptBool(_ source: String) -> Bool? {
        guard let descriptor = try? runAppleScript(source) else { return nil }
        if descriptor.descriptorType == typeBoolean || descriptor.descriptorType == typeTrue || descriptor.descriptorType == typeFalse {
            return descriptor.booleanValue
        }
        if let text = descriptor.stringValue?.lowercased() {
            if text == "true" || text == "yes" { return true }
            if text == "false" || text == "no" { return false }
        }
        return nil
    }

    private func escapeAppleScript(_ value: String) -> String {
        value.replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
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
