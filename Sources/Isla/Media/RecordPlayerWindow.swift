import AppKit
import SwiftUI

@MainActor final class RecordPlayerVisibility: ObservableObject {
    @Published var isVisible = false
}

@MainActor final class RecordPlayerWindow: NSObject, NSWindowDelegate {
    private let music: AppleMusicService
    private let preferences: PreferencesStore
    private let visibility = RecordPlayerVisibility()
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
        let window = NSWindow(
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
        window.backgroundColor = RecordPlayerPalette.background
        window.delegate = self
        window.contentView = NSHostingView(rootView: RecordPlayerView(
            music: music, preferences: preferences, visibility: visibility
        ))
        window.center()
        window.setFrameAutosaveName("IslaRecordPlayer")
        self.window = window
        return window
    }

    func windowDidChangeOcclusionState(_ notification: Notification) { refreshVisibility() }
    func windowDidMiniaturize(_ notification: Notification) { visibility.isVisible = false }
    func windowDidDeminiaturize(_ notification: Notification) { refreshVisibility() }
    func windowWillClose(_ notification: Notification) { visibility.isVisible = false }

    private func refreshVisibility() {
        guard let window else { return }
        let visible = window.isVisible && !window.isMiniaturized && window.occlusionState.contains(.visible)
        if visibility.isVisible != visible { visibility.isVisible = visible }
    }
}
