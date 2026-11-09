import AppKit
import WidgetKit
import IslandCore

@MainActor final class RecordWidgetState {
    private static let installedBuildKey = "recordWidgetInstalledBuild"

    private struct Track: Encodable {
        let title: String
        let artist: String
        let artwork: Data?
        let playing: Bool
    }

    private var identity: String?
    private var previousArtwork: Data?
    private var wasPlaying = false

    init(defaults: UserDefaults = .standard) {
        guard let build = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String,
              defaults.string(forKey: Self.installedBuildKey) != build else { return }

        if Self.stopStaleExtension() {
            defaults.set(build, forKey: Self.installedBuildKey)
        }
        // LaunchServices updates the extension descriptor asynchronously after an app replacement.
        // Give it time to forget the old bundle before requesting the first new timeline.
        DispatchQueue.main.asyncAfter(deadline: .now() + 5) {
            WidgetCenter.shared.reloadTimelines(ofKind: "IslaRecord")
        }
    }

    private static func stopStaleExtension() -> Bool {
        let executable = Bundle.main.bundleURL
            .appendingPathComponent("Contents/PlugIns/IslaWidget.appex/Contents/MacOS/IslaWidget")
            .path
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/pkill")
        process.arguments = ["-TERM", "-f", executable]
        do {
            try process.run()
            process.waitUntilExit()
            return process.terminationStatus == 0 || process.terminationStatus == 1
        } catch {
            return false
        }
    }
    private var written = false

    func update(_ state: MediaState) {
        let next = state.snapshot?.trackID
        let playing = state.snapshot?.playing == true
        guard !written || identity != next || previousArtwork != state.artworkData || wasPlaying != playing else { return }
        let directory = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Isla/Widget", isDirectory: true)
        let url = directory.appendingPathComponent("record.json")
        do {
            if let snapshot = state.snapshot {
                try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
                let artwork = state.artworkData.flatMap { $0.count <= 1_000_000 ? $0 : nil }
                let track = Track(title: snapshot.title, artist: snapshot.artist, artwork: artwork, playing: playing)
                try JSONEncoder().encode(track).write(to: url, options: .atomic)
            } else if FileManager.default.fileExists(atPath: url.path) {
                try FileManager.default.removeItem(at: url)
            }
            written = true
            identity = next
            previousArtwork = state.artworkData
            wasPlaying = playing
            WidgetCenter.shared.reloadTimelines(ofKind: "IslaRecord")
        } catch {
            // Try again on the next media update.
        }
    }
}
