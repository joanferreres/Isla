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

    var bandNumbers: ClosedRange<Int> {
        switch self {
        case .bass: 1...4
        case .mid: 5...7
        case .treble: 8...10
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
    init(maximum: Double?) { unitsPerDecibel = maximum == 12 ? 1 : 100 }
    func decibels(_ value: Double) -> Double { value / unitsPerDecibel }
}

/// Single owner for Music EQ apply.
/// Bands: killable osascript into Manual. On + preset: AX only (AS `EQ enabled` lies on modern Music).
actor MusicEqualizer {
    private struct Controls {
        let toggle: AXUIElement
        let popup: AXUIElement
        let sliders: [AXUIElement]
        let values: [Double]
        let scale: MusicEqualizerScale

        func gains(for values: [Double]) -> [MixerBand: Double] {
            Dictionary(uniqueKeysWithValues: MixerBand.allCases.map { band in
                let slice = values[band.sliderIndices]
                let average = slice.reduce(0, +) / Double(slice.count)
                return (band, scale.decibels(average).rounded())
            })
        }
    }

    enum Failure: LocalizedError {
        case access, closed, unresponsive, preset, silent, superseded

        var errorDescription: String? {
            switch self {
            case .access: "macOS necesita que autorices a Isla en Accesibilidad para ajustar el sonido de Música."
            case .closed: "Música no abrió el ecualizador. Vuelve a intentar el ajuste."
            case .unresponsive: "Música no confirmó el cambio de ecualización."
            case .preset: "Música no aplicó ese preset del ecualizador."
            case .silent: "El ecualizador de Música no quedó activo; el sonido no cambia."
            case .superseded: "Otro ajuste de EQ lo sustituyó."
            }
        }
    }

    private let manualPreset = "Manual"
    private var desired: [MixerBand: Double] = Dictionary(
        uniqueKeysWithValues: MixerBand.allCases.map { ($0, 0.0) }
    )
    private var latchedPreset: String?
    private var writeGeneration = 0

    func read() throws -> [MixerBand: Double] {
        if let name = try? currentPresetName(), !name.isEmpty,
           let bands = try? readPresetBands(name) {
            desired = gainsFromBands(bands)
            return desired
        }
        if let controls = try? findControls() {
            desired = controls.gains(for: controls.values)
            return desired
        }
        desired = try readManualGains()
        return desired
    }

    func presetNames() throws -> [String] {
        let text = try appleScriptString("""
            tell application "Music"
              set ns to name of every EQ preset
              set AppleScript's text item delimiters to linefeed
              set out to ns as text
              set AppleScript's text item delimiters to ""
              return out
            end tell
            """)
        let names = text.split(whereSeparator: \.isNewline)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
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

    func invalidatePendingWrites() { writeGeneration += 1 }

    func set(_ gain: Double, for band: MixerBand) async throws -> [MixerBand: Double] {
        let generation = beginWrite()
        guard gain.isFinite else { throw Failure.unresponsive }
        desired[band] = min(12, max(-12, gain)).rounded()
        return try await applyManual(generation: generation)
    }

    func setAll(_ gains: [MixerBand: Double]) async throws -> [MixerBand: Double] {
        let generation = beginWrite()
        for band in MixerBand.allCases {
            let value = gains[band] ?? desired[band] ?? 0
            guard value.isFinite else { throw Failure.unresponsive }
            desired[band] = min(12, max(-12, value)).rounded()
        }
        return try await applyManual(generation: generation)
    }

    func selectPreset(_ name: String) async throws -> [MixerBand: Double] {
        let generation = beginWrite()
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { throw Failure.preset }
        desired = gainsFromBands(try readPresetBands(trimmed))
        try await armPlayback(
            preset: trimmed,
            rewriteManual: trimmed.caseInsensitiveCompare(manualPreset) == .orderedSame,
            generation: generation
        )
        return desired
    }

    func reset() async throws -> [MixerBand: Double] {
        let generation = beginWrite()
        desired = Dictionary(uniqueKeysWithValues: MixerBand.allCases.map { ($0, 0.0) })
        try writeManualBands(from: desired)
        try check(generation)
        if let controls = try? await openControls() {
            if number(controls.toggle, kAXValueAttribute) == 1 {
                _ = AXUIElementPerformAction(controls.toggle, kAXPressAction as CFString)
            }
            parkEqualizerWindows()
        }
        latchedPreset = nil
        return desired
    }

    func reassertPlayback() async throws {
        let generation = beginWrite()
        let preset = latchedPreset ?? manualPreset
        if isArmed(preset: preset) { return }
        try await armPlayback(
            preset: preset,
            rewriteManual: preset.caseInsensitiveCompare(manualPreset) == .orderedSame,
            generation: generation
        )
    }

    // MARK: - Apply

    private func beginWrite() -> Int {
        writeGeneration += 1
        return writeGeneration
    }

    private func check(_ generation: Int) throws {
        if generation != writeGeneration { throw Failure.superseded }
    }

    private func applyManual(generation: Int) async throws -> [MixerBand: Double] {
        try writeManualBands(from: desired)
        try await armPlayback(preset: manualPreset, rewriteManual: true, generation: generation)
        return desired
    }

    /// One path: open EQ UI → On checkbox lit → preset selected → optional Manual rewrite.
    private func armPlayback(preset: String, rewriteManual: Bool, generation: Int) async throws {
        guard AXIsProcessTrusted() else { throw Failure.access }
        try check(generation)
        NSRunningApplication.runningApplications(withBundleIdentifier: "com.apple.Music")
            .first?
            .activate()
        unparkEqualizerWindows()
        var controls = try await openControls()
        try check(generation)
        try turnOn(controls.toggle)
        try check(generation)
        controls = try findControls()
        if popupTitle(controls.popup)?.caseInsensitiveCompare(preset) != .orderedSame {
            try await selectPreset(preset, popup: controls.popup)
            try check(generation)
            controls = try findControls()
            try turnOn(controls.toggle)
        }
        if rewriteManual {
            try writeManualBands(from: desired)
            try await Task.sleep(for: .milliseconds(60))
            try check(generation)
            try writeManualBands(from: desired)
        }
        guard isArmed(preset: preset) else { throw Failure.silent }
        latchedPreset = preset
        parkEqualizerWindows()
    }

    /// Ground truth for audible EQ on this Music build: the On checkbox, not AS `EQ enabled`.
    private func isArmed(preset: String) -> Bool {
        guard let controls = try? findControls(),
              number(controls.toggle, kAXValueAttribute) == 1 else { return false }
        if let title = popupTitle(controls.popup),
           title.caseInsensitiveCompare(preset) == .orderedSame {
            return true
        }
        if let name = try? currentPresetName(),
           name.caseInsensitiveCompare(preset) == .orderedSame {
            return true
        }
        return false
    }

    private func turnOn(_ toggle: AXUIElement) throws {
        if number(toggle, kAXValueAttribute) == 1 { return }
        guard AXUIElementPerformAction(toggle, kAXPressAction as CFString) == .success else {
            throw Failure.unresponsive
        }
        usleep(80_000)
        if let live = try? findControls(), number(live.toggle, kAXValueAttribute) == 1 { return }
        // Desync: press again after re-resolve.
        if let live = try? findControls() {
            _ = AXUIElementPerformAction(live.toggle, kAXPressAction as CFString)
            usleep(80_000)
            if let again = try? findControls(), number(again.toggle, kAXValueAttribute) == 1 { return }
        }
        throw Failure.silent
    }

    // MARK: - Manual bands (osascript, killable)

    private func readManualGains() throws -> [MixerBand: Double] {
        gainsFromBands(try readPresetBands(manualPreset))
    }

    private func gainsFromBands(_ bands: [Double]) -> [MixerBand: Double] {
        Dictionary(uniqueKeysWithValues: MixerBand.allCases.map { band in
            let slice = band.bandNumbers.map { bands[$0] }
            let average = slice.reduce(0, +) / Double(slice.count)
            return (band, average.rounded())
        })
    }

    private func readPresetBands(_ name: String) throws -> [Double] {
        let escaped = escapeAppleScript(name)
        // Return integer hundredths with "|" so locale decimal commas cannot split fields.
        let text = try appleScriptString("""
            tell application "Music"
              set p to first EQ preset whose name is "\(escaped)"
              set vals to {preamp of p, band 1 of p, band 2 of p, band 3 of p, band 4 of p, band 5 of p, band 6 of p, band 7 of p, band 8 of p, band 9 of p, band 10 of p}
              set out to ""
              repeat with v in vals
                set cents to (round (v * 100)) as integer
                if out is "" then
                  set out to (cents as text)
                else
                  set out to out & "|" & (cents as text)
                end if
              end repeat
              return out
            end tell
            """)
        let parts = text.split(separator: "|").map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
        guard parts.count == 11 else { throw Failure.preset }
        return try parts.map {
            guard let cents = Int($0) else { throw Failure.preset }
            return min(12, max(-12, Double(cents) / 100))
        }
    }

    private func writeManualBands(from gains: [MixerBand: Double]) throws {
        var bands = Array(repeating: 0.0, count: 11)
        for band in MixerBand.allCases {
            let value = gains[band] ?? 0
            for number in band.bandNumbers { bands[number] = value }
        }
        func n(_ i: Int) -> String {
            String(format: "%.2f", locale: Locale(identifier: "en_US_POSIX"), bands[i])
        }
        _ = try appleScriptString("""
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
            """)
    }

    // MARK: - AX

    private func openControls() async throws -> Controls {
        if let controls = try? findControls() { return controls }
        revealEqualizerWindow()
        for _ in 0..<4 {
            try await Task.sleep(for: .milliseconds(60))
            if let controls = try? findControls() { return controls }
        }
        try openWithShortcut()
        for _ in 0..<10 {
            try await Task.sleep(for: .milliseconds(80))
            if let controls = try? findControls() { return controls }
        }
        throw Failure.closed
    }

    private func revealEqualizerWindow() {
        _ = try? appleScriptString("""
            tell application "Music"
              try
                if (count of EQ windows) > 0 then
                  set visible of EQ window 1 to true
                end if
              end try
            end tell
            """)
    }

    private func unparkEqualizerWindows() {
        guard let app = try? musicApplication() else { return }
        for window in elements(app, kAXWindowsAttribute) where isEqualizerWindow(window) {
            _ = AXUIElementSetAttributeValue(window, kAXMinimizedAttribute as CFString, kCFBooleanFalse)
            var point = CGPoint(x: 120, y: 120)
            if let value = AXValueCreate(.cgPoint, &point) {
                _ = AXUIElementSetAttributeValue(window, kAXPositionAttribute as CFString, value)
            }
        }
    }

    private func parkEqualizerWindows() {
        guard let app = try? musicApplication() else { return }
        for window in elements(app, kAXWindowsAttribute) where isEqualizerWindow(window) {
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
        return children.filter { role($0) == kAXSliderRole }.count == 11
            && children.contains(where: { role($0) == kAXPopUpButtonRole })
            && children.contains(where: { role($0) == kAXCheckBoxRole })
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

    private func findControls() throws -> Controls {
        let app = try musicApplication()
        for window in elements(app, kAXWindowsAttribute) {
            let children = elements(window, kAXChildrenAttribute)
            let sliders = children.filter { role($0) == kAXSliderRole }
            let boxes = children.filter { role($0) == kAXCheckBoxRole }
            guard sliders.count == 11,
                  let popup = children.first(where: { role($0) == kAXPopUpButtonRole }),
                  let toggle = boxes.first else { continue }
            let scale = MusicEqualizerScale(maximum: number(sliders[0], kAXMaxValueAttribute))
            let values = sliders.compactMap { number($0, kAXValueAttribute) }
            guard values.count == sliders.count,
                  values.allSatisfy({ (-12...12).contains(scale.decibels($0)) }) else { continue }
            return Controls(toggle: toggle, popup: popup, sliders: sliders, values: values, scale: scale)
        }
        throw Failure.closed
    }

    private func popupTitle(_ popup: AXUIElement) -> String? {
        for key in [kAXValueAttribute, kAXTitleAttribute, kAXDescriptionAttribute] {
            if let text = attribute(popup, key) as? String {
                let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
                if !trimmed.isEmpty { return trimmed }
            }
        }
        return nil
    }

    private func selectPreset(_ name: String, popup: AXUIElement) async throws {
        if popupTitle(popup)?.caseInsensitiveCompare(name) == .orderedSame { return }
        guard AXUIElementPerformAction(popup, kAXPressAction as CFString) == .success else {
            throw Failure.preset
        }
        var item: AXUIElement?
        for _ in 0..<8 {
            try await Task.sleep(for: .milliseconds(50))
            item = findMenuItem(named: name, under: popup)
            if item == nil, let app = try? musicApplication() {
                item = findMenuItem(named: name, under: app)
            }
            if item != nil { break }
        }
        guard let item,
              AXUIElementPerformAction(item, kAXPressAction as CFString) == .success else {
            _ = AXUIElementPerformAction(popup, kAXCancelAction as CFString)
            throw Failure.preset
        }
        for _ in 0..<6 {
            try await Task.sleep(for: .milliseconds(40))
            if popupTitle(popup)?.caseInsensitiveCompare(name) == .orderedSame { return }
            if let title = try? findControls(), popupTitle(title.popup)?.caseInsensitiveCompare(name) == .orderedSame {
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

    // MARK: - osascript (killable)

    private func appleScriptString(_ source: String) throws -> String {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
        process.arguments = ["-e", source]
        let stdout = Pipe()
        let stderr = Pipe()
        process.standardOutput = stdout
        process.standardError = stderr
        try process.run()
        let deadline = Date().addingTimeInterval(3.5)
        while process.isRunning, Date() < deadline {
            Thread.sleep(forTimeInterval: 0.02)
        }
        if process.isRunning {
            process.terminate()
            throw Failure.unresponsive
        }
        let err = String(data: stderr.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
        if err.contains("-1743") || err.localizedCaseInsensitiveContains("not allowed") {
            throw Failure.access
        }
        guard process.terminationStatus == 0 else { throw Failure.unresponsive }
        return String(data: stdout.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8)?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
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
