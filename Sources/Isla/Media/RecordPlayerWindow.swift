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
        if presentation.desktopEnabled { showDesktop() }
    }

    func toggleDesktop() {
        if presentation.desktopEnabled {
            desktopWindow?.saveFrame(usingName: desktopFrameName)
            desktopWindow?.close()
            desktopWindow = nil
            presentation.setDesktopEnabled(false)
        } else {
            showDesktop()
            if desktopWindow != nil { presentation.setDesktopEnabled(true) }
        }
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
        window.isReleasedWhenClosed = false
        window.contentMinSize = NSSize(width: 560, height: 480)
        window.collectionBehavior = [.fullScreenPrimary, .managed]
        window.appearance = NSAppearance(named: .darkAqua)
        window.titlebarAppearsTransparent = true
        window.backgroundColor = presentation.palette.background
        window.selectPalette = { [weak presentation] in presentation?.select($0) }
        presentation.onPaletteChange = { [weak window] in window?.backgroundColor = $0.background }
        window.delegate = self
        window.contentView = NSHostingView(rootView: RecordPlayerView(
            music: music, preferences: preferences, presentation: presentation
        ))
        window.center()
        window.setFrameAutosaveName("IslaRecordPlayer")
        self.window = window
        return window
    }

    func windowDidChangeOcclusionState(_ notification: Notification) { refreshVisibility() }
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
