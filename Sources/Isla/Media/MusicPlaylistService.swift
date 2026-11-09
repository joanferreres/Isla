import AppKit
import ApplicationServices
import IslandCore
import OSLog

actor MusicPlaylistService {
    private let bridge = AppleMusicBridge()
    private let logger = Logger(subsystem: "local.personal.isla", category: "Playlists")

    func playlists() async throws -> [MusicPlaylist] {
        try await (bridge.query("playlists").playlists ?? []).sorted {
            $0.name.localizedStandardCompare($1.name) == .orderedAscending
        }
    }

    /// Returns false when the song was already in the selected playlist.
    func add(_ track: MediaSnapshot, to playlist: MusicPlaylist, unambiguousName: Bool) async throws -> Bool {
        let request = MusicPlaylistRequest(playlistID: playlist.id, track: track)
        guard let argument = request.argument else { throw MusicFailure(message: "No se pudo identificar la canción.") }
        if try await bridge.query("playlistContainsTrack", argument: argument).playlistContainsTrack == true {
            return false
        }
        do {
            _ = try await bridge.query("playlistAddTrack", argument: argument)
        } catch let failure as MusicFailure where failure.code == -10006 || failure.code == -1728 {
            guard unambiguousName else {
                throw MusicFailure(message: "Hay varias playlists con ese nombre. Elige la correcta directamente en Música.")
            }
            try await addThroughMusicMenu(track, playlist: playlist)
        }
        for attempt in 0..<3 {
            if try await bridge.query("playlistContainsTrack", argument: argument).playlistContainsTrack == true {
                return true
            }
            if attempt < 2 { try await Task.sleep(for: .milliseconds(300)) }
        }
        throw MusicFailure(message: "Música no confirmó la adición. Comprueba la playlist antes de volver a intentarlo.")
    }

    private func addThroughMusicMenu(_ track: MediaSnapshot, playlist: MusicPlaylist) async throws {
        guard AXIsProcessTrusted() else {
            throw MusicFailure(message: "Permite Isla en Accesibilidad para añadir canciones del catálogo.")
        }
        guard let music = NSRunningApplication.runningApplications(withBundleIdentifier: "com.apple.Music").first else {
            throw MusicFailure(message: "Abre Música para añadir la canción.")
        }
        let app = AXUIElementCreateApplication(music.processIdentifier)
        AXUIElementSetMessagingTimeout(app, 0.45)
        var raised = false
        defer {
            if raised, music.isActive { NSRunningApplication.current.activate(options: []) }
        }
        var candidate = player(in: app, track: track)
        if candidate == nil, let url = music.bundleURL {
            raised = !music.isActive
            let configuration = NSWorkspace.OpenConfiguration()
            configuration.activates = true
            _ = try? await NSWorkspace.shared.openApplication(at: url, configuration: configuration)
            for _ in 0..<8 {
                try await Task.sleep(for: .milliseconds(200))
                candidate = player(in: app, track: track)
                if candidate != nil { break }
            }
        }
        guard let (player, more) = candidate else {
            throw MusicFailure(message: "Abre la ventana principal de Música y vuelve a intentarlo con la misma canción.")
        }
        _ = AXUIElementPerformAction(more, kAXPressAction as CFString)
        var menu: AXUIElement?
        for _ in 0..<6 {
            menu = find(in: player, depth: 5) { self.identifier($0) == "addToPlaylistBaseAction:" }
            if menu != nil { break }
            try await Task.sleep(for: .milliseconds(80))
        }
        defer {
            if let contextMenu = children(player).first(where: { self.string($0, kAXRoleAttribute) == kAXMenuRole }) {
                _ = AXUIElementPerformAction(contextMenu, kAXCancelAction as CFString)
            }
        }
        guard let menu, matches(track, in: player) || matchesNowPlaying(track) else {
            throw MusicFailure(message: "Música no abrió el menú de la canción actual.")
        }
        let name = playlist.name.trimmingCharacters(in: .whitespacesAndNewlines)
        let options = children(menu).flatMap { children($0) }.filter {
            identifier($0) == "doAddToPlaylistCommand:"
                && string($0, kAXTitleAttribute)?.trimmingCharacters(in: .whitespacesAndNewlines) == name
        }
        guard let choice = options.last,
              AXUIElementPerformAction(choice, kAXPressAction as CFString) == .success else {
            throw MusicFailure(message: "Esa playlist no aparece como disponible para la canción en Música.")
        }
    }

    private func player(in app: AXUIElement, track: MediaSnapshot) -> (AXUIElement, AXUIElement)? {
        let windows = children(app, kAXWindowsAttribute)
        let nowPlayingMatches = matchesNowPlaying(track)
        for window in windows {
            let player = find(in: window, depth: 12) {
                self.identifier($0)?.hasPrefix("Music.miniPlayer.contentView") == true
            } ?? window
            if let more = find(in: player, depth: 12, matching: { self.identifier($0) == "Music.miniPlayer.contextMenu" }),
               matches(track, in: player) || nowPlayingMatches {
                return (player, more)
            }
        }
        logger.debug("Could not match the current track menu. Windows: \(windows.count), now playing matched: \(nowPlayingMatches)")
        return nil
    }

    private func matchesNowPlaying(_ track: MediaSnapshot) -> Bool {
        guard let current = (try? SystemMediaArtwork().read())?.snapshot else { return false }
        if track.trackID.hasPrefix("mediaremote:") { return current.trackID == track.trackID }
        return current.title == track.title && current.artist == track.artist
    }

    private func matches(_ track: MediaSnapshot, in player: AXUIElement) -> Bool {
        guard let title = find(in: player, depth: 4, matching: { self.identifier($0) == "Music.miniPlayer.title" }),
              (string(title, kAXDescriptionAttribute) ?? string(title, kAXTitleAttribute)) == track.title else { return false }
        guard !track.artist.isEmpty else { return true }
        guard let subtitle = find(in: player, depth: 4, matching: { self.identifier($0) == "Music.miniPlayer.subtitle" }),
              let text = string(subtitle, kAXDescriptionAttribute) ?? string(subtitle, kAXTitleAttribute) else { return false }
        return text == track.artist || text.hasPrefix(track.artist + " — ")
    }

    private func find(in element: AXUIElement, depth: Int, matching: (AXUIElement) -> Bool) -> AXUIElement? {
        if matching(element) { return element }
        guard depth > 0, ![kAXTableRole, kAXOutlineRole].contains(string(element, kAXRoleAttribute) ?? "") else {
            return nil
        }
        for child in children(element) {
            if let match = find(in: child, depth: depth - 1, matching: matching) { return match }
        }
        return nil
    }

    private func identifier(_ element: AXUIElement) -> String? { string(element, kAXIdentifierAttribute) }
    private func string(_ element: AXUIElement, _ key: String) -> String? { attribute(element, key) as? String }
    private func children(_ element: AXUIElement, _ key: String = kAXChildrenAttribute) -> [AXUIElement] {
        attribute(element, key) as? [AXUIElement] ?? []
    }
    private func attribute(_ element: AXUIElement, _ key: String) -> CFTypeRef? {
        var value: CFTypeRef?
        return AXUIElementCopyAttributeValue(element, key as CFString, &value) == .success ? value : nil
    }
}
