import AppKit
import IslandCore

struct MusicPlaylist: Codable, Identifiable, Sendable {
    let id: String
    let name: String
}

struct MusicPlaylistRequest: Codable, Sendable {
    let playlistID: String
    let track: MediaSnapshot

    var argument: String? {
        (try? JSONEncoder().encode(self)).flatMap { String(data: $0, encoding: .utf8) }
    }
}

@MainActor enum MusicPlaylistScripts {
    static func run(_ operation: String, argument: String?) -> MusicReply? {
        guard ["playlists", "playlistContainsTrack", "playlistAddTrack", "playPlaylist", "playShuffle"].contains(operation) else { return nil }
        guard !NSRunningApplication.runningApplications(withBundleIdentifier: "com.apple.Music").isEmpty else {
            return MusicReply(error: "Abre Música para ver tus playlists.")
        }
        do {
            if operation == "playShuffle" {
                _ = try execute("""
                tell application "Music"
                    set shuffle enabled to true
                    set shuffle mode to songs
                    try
                        set pl to current playlist
                        play pl
                    on error
                        set t to some track of library playlist 1
                        play t
                    end try
                end tell
                """)
                return MusicReply()
            }
            if operation == "playPlaylist" {
                guard let argument, validID(argument) else {
                    throw MusicFailure(message: "No se pudo identificar la playlist.")
                }
                _ = try execute("""
                tell application "Music"
                    set destination to get first user playlist whose persistent ID is "\(argument)"
                    play destination
                end tell
                """)
                return MusicReply()
            }
            if operation == "playlists" {
                let rows = try execute("""
                tell application "Music"
                    set resultRows to {}
                    repeat with entry in (get every user playlist)
                        try
                            if (smart of entry is false) and (special kind of entry is none) and (genius of entry is false) then
                                set end of resultRows to {persistent ID of entry, name of entry}
                            end if
                        end try
                    end repeat
                    return resultRows
                end tell
                """)
                return MusicReply(playlists: items(rows).compactMap { row in
                    guard let id = row.atIndex(1)?.stringValue, validID(id),
                          let name = row.atIndex(2)?.stringValue, !name.isEmpty else { return nil }
                    return MusicPlaylist(id: id, name: name)
                })
            }
            guard let argument, let request = try? JSONDecoder().decode(MusicPlaylistRequest.self, from: Data(argument.utf8)),
                  validID(request.playlistID) else { throw MusicFailure(message: "No se pudo identificar la playlist.") }
            if operation == "playlistContainsTrack" {
                let rows = try execute("""
                tell application "Music"
                    set destination to get first user playlist whose persistent ID is "\(request.playlistID)"
                    if (count of tracks of destination) is 0 then return {{}, {}}
                    return {name of every track of destination, artist of every track of destination}
                end tell
                """)
                guard let names = rows.atIndex(1), let artists = rows.atIndex(2) else {
                    throw MusicFailure(message: "Música no confirmó la canción en la playlist.")
                }
                let matches = zip(items(names), items(artists)).contains { name, artist in
                    name.stringValue == request.track.title && artist.stringValue == request.track.artist
                }
                return MusicReply(playlistContainsTrack: matches)
            }
            let song = try execute("""
            tell application "Music"
                set songToAdd to get current track
                return {persistent ID of songToAdd, name of songToAdd, artist of songToAdd}
            end tell
            """)
            guard let songID = song.atIndex(1)?.stringValue, validID(songID),
                  song.atIndex(2)?.stringValue == request.track.title,
                  song.atIndex(3)?.stringValue == request.track.artist,
                  request.track.trackID.hasPrefix("mediaremote:") || request.track.trackID == songID else {
                throw MusicFailure(message: "La canción cambió. Abre de nuevo el selector.")
            }
            _ = try execute("""
            tell application "Music"
                set songToAdd to get current track
                if persistent ID of songToAdd is not "\(songID)" then error "Track changed" number -2700
                set destination to get first user playlist whose persistent ID is "\(request.playlistID)"
                duplicate songToAdd to destination
            end tell
            """)
            return MusicReply()
        } catch {
            return MusicReply(error: error.localizedDescription, errorCode: (error as? MusicFailure)?.code)
        }
    }

    private static func items(_ descriptor: NSAppleEventDescriptor) -> [NSAppleEventDescriptor] {
        (0..<descriptor.numberOfItems).compactMap { descriptor.atIndex($0 + 1) }
    }

    private static func validID(_ id: String) -> Bool {
        !id.isEmpty && id.utf8.count <= 32 && id.utf8.allSatisfy {
            (48...57).contains($0) || (65...70).contains($0) || (97...102).contains($0)
        }
    }

    private static func execute(_ source: String) throws -> NSAppleEventDescriptor {
        var info: NSDictionary?
        if let result = NSAppleScript(source: source)?.executeAndReturnError(&info), info == nil { return result }
        let code = info?[NSAppleScript.errorNumber] as? Int
        let message: String
        switch code {
        case -1743: message = "Permite a Isla controlar Música en Privacidad y seguridad → Automatización."
        case -2700: message = "La canción cambió. Abre de nuevo el selector."
        default: message = "Música no pudo completar la operación de playlist."
        }
        throw MusicFailure(message: message, code: code)
    }
}
