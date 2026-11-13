import AppKit
import Combine
import SwiftUI

@MainActor final class RecordPlayerPresentation: ObservableObject {
    @Published var isVisible = false
    @Published var isDesktopVisible = false
    @Published private(set) var desktopEnabled = UserDefaults.standard.bool(forKey: "recordPlayer.desktopEnabled")
    @Published private(set) var palette = UserDefaults.standard.string(forKey: "recordPlayer.palette")
        .flatMap(RecordPlayerPalette.init(rawValue:)) ?? .blue
    var onPaletteChange: ((RecordPlayerPalette) -> Void)?

    func setDesktopEnabled(_ enabled: Bool) {
        desktopEnabled = enabled
        UserDefaults.standard.set(enabled, forKey: "recordPlayer.desktopEnabled")
    }

    func select(_ palette: RecordPlayerPalette) {
        guard self.palette != palette else { return }
        self.palette = palette
        UserDefaults.standard.set(palette.rawValue, forKey: "recordPlayer.palette")
        onPaletteChange?(palette)
    }
}

private final class RecordPlayerNativeWindow: NSWindow {
    var selectPalette: ((RecordPlayerPalette) -> Void)?

    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        let modifiers = event.modifierFlags.intersection([.command, .option, .control, .shift])
        if isKeyWindow, modifiers == .command, let selectPalette,
           let palette = RecordPlayerPalette.allCases.first(where: { $0.shortcut == event.charactersIgnoringModifiers }) {
            selectPalette(palette)
            return true
        }
        return super.performKeyEquivalent(with: event)
    }
}

private final class RecordPlayerDesktopPanel: NSPanel {
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}

@MainActor final class RecordPlayerWindow: NSObject, NSWindowDelegate {
    private let music: AppleMusicService
    private let preferences: PreferencesStore
    private let presentation = RecordPlayerPresentation()
    private var window: NSWindow?
    private var desktopWindow: NSPanel?
    private let desktopFrameName = "IslaRecordDesktop"

    var desktopEnabled: AnyPublisher<Bool, Never> { presentation.$desktopEnabled.eraseToAnyPublisher() }

    init(music: AppleMusicService, preferences: PreferencesStore) {
        self.music = music
        self.preferences = preferences
    }

    func show() {
        let window = self.window ?? makeWindow()
        NSApp.activate(ignoringOtherApps: true)
        if window.isMiniaturized { window.deminiaturize(nil) }
        window.makeKeyAndOrderFront(nil)
        refreshVisibility()
    }

    func restoreDesktop() {
        applyDesktopEnabled(preferences.value.recordDesktopEnabled)
    }

    /// Keeps the desktop panel in sync with Ajustes → Módulos.
    func applyDesktopEnabled(_ enabled: Bool) {
        if enabled {
            if desktopWindow == nil { showDesktop() }
            if desktopWindow != nil { presentation.setDesktopEnabled(true) }
            else { presentation.setDesktopEnabled(false) }
        } else {
            desktopWindow?.saveFrame(usingName: desktopFrameName)
            desktopWindow?.close()
            desktopWindow = nil
            presentation.setDesktopEnabled(false)
        }
    }

    func toggleDesktop() {
        applyDesktopEnabled(!presentation.desktopEnabled)
        preferences.value.recordDesktopEnabled = presentation.desktopEnabled
    }

    private func showDesktop() {
        guard desktopWindow == nil, let screen = window?.screen ?? NSScreen.main else { return }
        let size = CGSize(width: 242, height: 240)
        let visible = screen.visibleFrame
        let frame = CGRect(x: visible.maxX - size.width - 24, y: visible.minY + 24,
                           width: size.width, height: size.height)
        let panel = RecordPlayerDesktopPanel(contentRect: frame, styleMask: [.borderless, .nonactivatingPanel],
                                             backing: .buffered, defer: false)
        panel.title = "Tocadiscos en el escritorio"
        panel.isReleasedWhenClosed = false
        panel.level = NSWindow.Level(rawValue: Int(CGWindowLevelForKey(.desktopIconWindow)) + 1)
        panel.collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle, .fullScreenNone]
        panel.hidesOnDeactivate = false
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.appearance = NSAppearance(named: .darkAqua)
        panel.delegate = self
        panel.contentView = IslandHostingView(rootView: RecordDesktopView(
            music: music, preferences: preferences, presentation: presentation,
            openPlayer: { [weak self] in self?.show() },
            close: { [weak self] in self?.toggleDesktop() }
        ))
        if panel.setFrameUsingName(desktopFrameName),
           !NSScreen.screens.contains(where: { $0.visibleFrame.contains(panel.frame) }) {
            panel.setFrame(frame, display: false)
        }
        panel.setFrameAutosaveName(desktopFrameName)
        desktopWindow = panel
        panel.orderFrontRegardless()
        refreshVisibility()
    }

    private func makeWindow() -> NSWindow {
        let window = RecordPlayerNativeWindow(
            contentRect: NSRect(x: 0, y: 0, width: 1040, height: 650),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered, defer: false
        )
        window.title = "Tocadiscos · Isla"
        window.miniwindowTitle = "Tocadiscos · Isla"
        window.miniwindowImage = Self.turntableMiniwindowImage()
        window.isReleasedWhenClosed = false
        window.contentMinSize = NSSize(width: 560, height: 480)
        window.collectionBehavior = [.fullScreenPrimary, .managed]
        window.appearance = NSAppearance(named: .darkAqua)
        window.titlebarAppearsTransparent = true
        window.isOpaque = true
        window.backgroundColor = presentation.palette.background
        window.selectPalette = { [weak presentation] in presentation?.select($0) }
        presentation.onPaletteChange = { [weak window] in window?.backgroundColor = $0.background }
        window.delegate = self
        let hosting = IslandHostingView(rootView: RecordPlayerView(
            music: music, preferences: preferences, presentation: presentation
        ))
        // Clip the peek disc at the content edge so only the inner blank half is visible.
        hosting.clipsToBounds = true
        window.contentView = hosting
        window.center()
        window.setFrameAutosaveName("IslaRecordPlayer")
        self.window = window
        return window
    }

    /// Dock miniwindow mark: vinyl + Isla cyan→violet island, not a live window snapshot.
    private static func turntableMiniwindowImage() -> NSImage {
        let size = NSSize(width: 128, height: 128)
        return NSImage(size: size, flipped: false) { rect in
            let inset = rect.insetBy(dx: 6, dy: 6)
            NSColor(srgbRed: 0.06, green: 0.07, blue: 0.09, alpha: 1).setFill()
            NSBezierPath(roundedRect: inset, xRadius: 28, yRadius: 28).fill()

            let disc = NSBezierPath(ovalIn: inset.insetBy(dx: 14, dy: 14))
            NSColor(srgbRed: 0.08, green: 0.09, blue: 0.11, alpha: 1).setFill()
            disc.fill()
            NSColor(srgbRed: 0.18, green: 0.19, blue: 0.22, alpha: 1).setStroke()
            disc.lineWidth = 1.5
            disc.stroke()

            let center = CGPoint(x: inset.midX, y: inset.midY)
            for radius in stride(from: 18.0, through: 42.0, by: 5.0) {
                let ring = NSBezierPath(ovalIn: CGRect(x: center.x - radius, y: center.y - radius,
                                                       width: radius * 2, height: radius * 2))
                NSColor.white.withAlphaComponent(0.06).setStroke()
                ring.lineWidth = 1
                ring.stroke()
            }

            let label = CGRect(x: center.x - 18, y: center.y - 18, width: 36, height: 36)
            let cyan = NSColor(srgbRed: 0.05, green: 0.88, blue: 0.95, alpha: 1)
            let violet = NSColor(srgbRed: 0.66, green: 0.32, blue: 1, alpha: 1)
            let island = NSBezierPath(roundedRect: label.insetBy(dx: 2, dy: 10), xRadius: 8, yRadius: 8)
            NSGradient(starting: cyan, ending: violet)?.draw(in: island, angle: 0)
            NSColor(srgbRed: 0.04, green: 0.05, blue: 0.07, alpha: 1).setFill()
            NSBezierPath(roundedRect: label.insetBy(dx: 6, dy: 14), xRadius: 4, yRadius: 4).fill()
            NSColor.white.setFill()
            NSBezierPath(roundedRect: CGRect(x: center.x - 6, y: center.y - 1.5, width: 12, height: 3),
                         xRadius: 1.5, yRadius: 1.5).fill()

            let arm = NSBezierPath()
            arm.move(to: CGPoint(x: inset.maxX - 22, y: inset.maxY - 28))
            arm.line(to: CGPoint(x: center.x + 10, y: center.y + 6))
            NSColor(srgbRed: 0.72, green: 0.74, blue: 0.78, alpha: 1).setStroke()
            arm.lineWidth = 3
            arm.lineCapStyle = .round
            arm.stroke()
            NSColor(srgbRed: 0.9, green: 0.25, blue: 0.28, alpha: 1).setFill()
            NSBezierPath(ovalIn: CGRect(x: center.x + 6, y: center.y + 2, width: 7, height: 7)).fill()
            return true
        }
    }

    func windowDidChangeOcclusionState(_ notification: Notification) { refreshVisibility() }
    func windowWillMiniaturize(_ notification: Notification) {
        guard let window = notification.object as? NSWindow, window === self.window else { return }
        window.miniwindowTitle = "Tocadiscos · Isla"
        window.miniwindowImage = Self.turntableMiniwindowImage()
    }
    func windowDidMiniaturize(_ notification: Notification) { presentation.isVisible = false }
    func windowDidDeminiaturize(_ notification: Notification) { refreshVisibility() }
    func windowWillClose(_ notification: Notification) {
        if notification.object as? NSWindow === desktopWindow { presentation.isDesktopVisible = false }
        else { presentation.isVisible = false }
    }

    private func refreshVisibility() {
        let visible = isVisible(window)
        if presentation.isVisible != visible { presentation.isVisible = visible }
        let desktopVisible = isVisible(desktopWindow)
        if presentation.isDesktopVisible != desktopVisible { presentation.isDesktopVisible = desktopVisible }
    }

    private func isVisible(_ window: NSWindow?) -> Bool {
        guard let window else { return false }
        return window.isVisible && !window.isMiniaturized && window.occlusionState.contains(.visible)
    }
}
