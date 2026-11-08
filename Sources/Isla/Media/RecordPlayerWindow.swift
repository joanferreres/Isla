import AppKit
import SwiftUI

@MainActor final class RecordPlayerPresentation: ObservableObject {
    @Published var isVisible = false
    @Published private(set) var palette = UserDefaults.standard.string(forKey: "recordPlayer.palette")
        .flatMap(RecordPlayerPalette.init(rawValue:)) ?? .blue
    var onPaletteChange: ((RecordPlayerPalette) -> Void)?

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

@MainActor final class RecordPlayerWindow: NSObject, NSWindowDelegate {
    private let music: AppleMusicService
    private let preferences: PreferencesStore
    private let presentation = RecordPlayerPresentation()
    private var window: NSWindow?

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
    func windowWillClose(_ notification: Notification) { presentation.isVisible = false }

    private func refreshVisibility() {
        guard let window else { return }
        let visible = window.isVisible && !window.isMiniaturized && window.occlusionState.contains(.visible)
        if presentation.isVisible != visible { presentation.isVisible = visible }
    }
}
