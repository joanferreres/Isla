import AppKit
import ApplicationServices

actor SpotifyEqualizer {
    private static let frequencies = ["60", "150", "400", "1000", "2400", "15000"]

    func apply(_ gain: Double, band: MixerBand?) async throws -> [MixerBand: Double] {
        guard AXIsProcessTrusted() else { throw MusicEqualizer.Failure.access }
        guard let pid = await MainActor.run(body: {
            NSRunningApplication.runningApplications(withBundleIdentifier: "com.spotify.client").first?.processIdentifier
        }) else { throw MusicFailure(message: "Abre Spotify para ajustar el sonido.") }
        let app = AXUIElementCreateApplication(pid)
        AXUIElementSetMessagingTimeout(app, 0.3)
        guard let window = (attribute(app, kAXWindowsAttribute) as? [AXUIElement])?.first else {
            throw MusicFailure(message: "Abre la ventana de Spotify.")
        }
        var controls = findControls(window)
        if controls == nil,
           let value = attribute(app, kAXMenuBarAttribute), CFGetTypeID(value) == AXUIElementGetTypeID(),
           let menu = children(value as! AXUIElement).first(where: { label($0) == "Spotify" }),
           let settings = children(menu).flatMap(children).first(where: {
               (attribute($0, "AXMenuItemCmdChar") as? String) == ","
           }) {
            if AXUIElementPerformAction(settings, kAXPressAction as CFString) == .success {
                for _ in 0..<10 {
                    try await Task.sleep(for: .milliseconds(100))
                    controls = findControls(window)
                    if controls != nil { break }
                }
            }
        }
        guard let (toggle, sliders) = controls else {
            throw MusicFailure(message: "Abre Ajustes → Reproducción en Spotify para encontrar el ecualizador.")
        }
        try Task.checkCancellation()
        let bands = MixerBand.allCases
        if number(toggle) != 1 {
            guard AXUIElementPerformAction(toggle, kAXPressAction as CFString) == .success else {
                throw MusicFailure(message: "Spotify no pudo activar su ecualizador.")
            }
            // Spotify updates the checkbox asynchronously; give it a moment before the sliders.
            for _ in 0..<6 where number(toggle) != 1 {
                try await Task.sleep(for: .milliseconds(50))
            }
        }
        for (index, slider) in sliders.enumerated() where band == nil || bands[index / 2] == band {
            let lower = (attribute(slider, kAXMinValueAttribute) as? NSNumber)?.doubleValue ?? -12
            let upper = (attribute(slider, kAXMaxValueAttribute) as? NSNumber)?.doubleValue ?? 12
            let target = min(upper, max(lower, gain))
            guard AXUIElementSetAttributeValue(slider, kAXValueAttribute as CFString, NSNumber(value: target)) == .success,
                  let actual = number(slider), abs(actual - target) < 0.51 else {
                throw MusicFailure(message: "Spotify no confirmó el cambio del ecualizador.")
            }
        }
        guard number(toggle) == 1 else { throw MusicFailure(message: "El ecualizador de Spotify sigue desactivado.") }
        return Dictionary(uniqueKeysWithValues: bands.enumerated().map { index, band in
            (band, (((number(sliders[index * 2]) ?? 0) + (number(sliders[index * 2 + 1]) ?? 0)) / 2).rounded())
        })
    }

    private func findControls(_ window: AXUIElement) -> (AXUIElement, [AXUIElement])? {
        var toggle: AXUIElement?
        var sliders: [String: AXUIElement] = [:]
        var pending = [window]
        while let element = pending.popLast() {
            let role = attribute(element, kAXRoleAttribute) as? String
            if role == kAXCheckBoxRole, ["equalizer", "ecualizador", "equalitzador"].contains(label(element).lowercased()) {
                toggle = element
            } else if role == kAXSliderRole {
                let frequency = label(element).filter { $0.isASCII && $0.isNumber }
                if Self.frequencies.contains(frequency) { sliders[frequency] = element }
            }
            if let toggle, sliders.count == Self.frequencies.count {
                return (toggle, Self.frequencies.compactMap { sliders[$0] })
            }
            if role != kAXTableRole, role != kAXOutlineRole { pending.append(contentsOf: children(element).reversed()) }
        }
        return nil
    }

    private func label(_ element: AXUIElement) -> String {
        for key in [kAXTitleAttribute, kAXDescriptionAttribute] {
            if let value = attribute(element, key) as? String, !value.isEmpty { return value }
        }
        return ""
    }

    private func number(_ element: AXUIElement) -> Double? {
        (attribute(element, kAXValueAttribute) as? NSNumber)?.doubleValue
    }

    private func children(_ element: AXUIElement) -> [AXUIElement] {
        attribute(element, kAXChildrenAttribute) as? [AXUIElement] ?? []
    }

    private func attribute(_ element: AXUIElement, _ key: String) -> CFTypeRef? {
        var value: CFTypeRef?
        return AXUIElementCopyAttributeValue(element, key as CFString, &value) == .success ? value : nil
    }
}
