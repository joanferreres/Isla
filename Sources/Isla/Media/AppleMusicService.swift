import SwiftUI
import Combine
import IslandCore

@MainActor final class AppleMusicService: ObservableObject {
    @Published var state = MediaState()
    @Published var error: String?
    @Published var enabled = false
    /// Prefetched playlist neighbours (IDs + raw bytes) when Music can resolve them.
    @Published private(set) var neighborArt = MusicNeighbors()
    /// Decoded covers ready for dual-disc preview — never decode during the gesture.
    @Published private(set) var previousCover: NSImage?
    @Published private(set) var nextCover: NSImage?

    let stream = SystemMediaStream()
    var receivedAt = Date()
    var retryStreamAfter = Date.distantPast
    let reader: any AppleMusicReading
    var timer: Timer?
    var observer: NSObjectProtocol?
    private var permissionDenied = false
    private var refreshing = false
    private var generation = 0
    private var neighborTask: Task<Void, Never>?
    private var coverTrail = RecordCoverTrail()
    private var lastCoverTrackID: String?
    private var pendingNavigation: RecordSwipe?

    init(reader: any AppleMusicReading = AppleMusicBridge()) { self.reader = reader }

    func connect() {
        guard !enabled else { return }
        permissionDenied = false
        enabled = true
        generation += 1
        observer = DistributedNotificationCenter.default().addObserver(
            forName: NSNotification.Name("com.apple.Music.playerInfo"), object: nil, queue: .main
        ) { [weak self] _ in Task { @MainActor in await self?.refresh() } }
        stream.onReply = { [weak self] reply in
            guard let self, self.enabled else { return }
            // MediaRemote is a nudge + cover source. Identity always comes from AppleScript
            // so changer / EQ / playlists keep Music persistent IDs.
            Task { @MainActor in
                if let bridge = self.reader as? AppleMusicBridge {
                    await bridge.cacheSystemArtwork(reply)
                }
                await self.refresh()
                if let data = reply.artwork, let id = self.state.snapshot?.trackID {
                    _ = self.state.acceptArtwork(data, for: id)
                    self.ingestCurrentCover(forceNeighbors: false)
                }
            }
        }
        stream.onStopped = { [weak self] in
            guard let self, self.enabled else { return }
            self.retryStreamAfter = Date().addingTimeInterval(60)
            self.startFallbackTimer()
            Task { await self.refresh() }
        }
        if !stream.start() {
            startFallbackTimer()
            Task { await refresh() }
        }
    }

    func startFallbackTimer() {
        guard timer == nil else { return }
        timer = Timer.scheduledTimer(withTimeInterval: 15, repeats: true) { [weak self] _ in
            Task { @MainActor in
                guard let self, self.enabled else { return }
                if Date() >= self.retryStreamAfter, self.stream.start() {
                    self.timer?.invalidate()
                    self.timer = nil
                    return
                }
                await self.refresh()
            }
        }
        timer?.tolerance = 3
    }

    func displayPosition(at date: Date) -> Double {
        guard let snapshot = state.snapshot else { return 0 }
        return min(snapshot.duration, max(0, snapshot.position + (snapshot.playing ? max(0, date.timeIntervalSince(receivedAt)) : 0)))
    }

    func pauseForSleep() {
        enabled = false
        generation += 1
        neighborTask?.cancel()
        neighborTask = nil
        timer?.invalidate()
        timer = nil
        stream.stop()
        if let observer { DistributedNotificationCenter.default().removeObserver(observer) }
        observer = nil
    }

    func disconnect() {
        enabled = false
        stream.stop()
        generation += 1
        neighborTask?.cancel()
        neighborTask = nil
        timer?.invalidate()
        timer = nil
        if let observer { DistributedNotificationCenter.default().removeObserver(observer) }
        observer = nil
        state.update(nil)
        neighborArt = MusicNeighbors()
        coverTrail.reset()
        publishCovers()
        lastCoverTrackID = nil
    }

    func refresh() async {
        // -1743 stays latched until disconnect()/connect() so we do not spam Music.
        guard enabled, !refreshing, !permissionDenied else { return }
        refreshing = true
        defer { refreshing = false }
        let current = generation
        guard await reader.isRunning() else {
            state.update(nil)
            neighborArt = MusicNeighbors()
            coverTrail.reset()
            publishCovers()
            error = nil
            return
        }
        do {
            let snapshot = try await reader.read()
            guard enabled, current == generation else { return }
            permissionDenied = false
            let changed = state.snapshot?.trackID != snapshot?.trackID
            state.update(snapshot)
            receivedAt = Date()
            error = nil
            if let snapshot, changed || state.artworkData == nil {
                let data = try await reader.artwork(trackID: snapshot.trackID)
                let latest = try await reader.read()
                guard enabled, current == generation else { return }
                state.update(latest)
                receivedAt = Date()
                if let data, latest?.trackID == snapshot.trackID {
                    _ = self.state.acceptArtwork(data, for: snapshot.trackID)
                }
            }
            ingestCurrentCover(forceNeighbors: changed || neighborArt.nextTrackID == nil)
            if changed || neighborArt.nextTrackID == nil || neighborArt.previousTrackID == nil {
                scheduleNeighborPrefetch(generation: current)
            }
        } catch {
            guard enabled, current == generation else { return }
            self.error = error.localizedDescription
            if (error as? MusicFailure)?.code == -1743 {
                permissionDenied = true
                // Keep last good snapshot; only stop the fallback timer while denied.
                timer?.invalidate()
                timer = nil
                return
            }
            state.update(nil)
            neighborArt = MusicNeighbors()
            coverTrail.reset()
            publishCovers()
        }
    }

    /// Call when the turntable window opens so covers are warm before the first swipe.
    func ensureNeighborCovers() {
        guard enabled, state.snapshot != nil else { return }
        ingestCurrentCover(forceNeighbors: false)
        scheduleNeighborPrefetch(generation: generation)
    }

    private func ingestCurrentCover(forceNeighbors: Bool) {
        guard let snapshot = state.snapshot else { return }
        let image = state.artworkData.flatMap(NSImage.init(data:))
        let keys = RecordCoverTrail.keys(trackID: snapshot.trackID, title: snapshot.title, artist: snapshot.artist)
        let trackChanged = lastCoverTrackID != snapshot.trackID
        let navigation = trackChanged ? pendingNavigation : nil
        coverTrail.land(keys: keys, image: image, navigation: navigation)
        if trackChanged { pendingNavigation = nil }
        lastCoverTrackID = snapshot.trackID
        publishCovers()
        if forceNeighbors || trackChanged {
            scheduleNeighborPrefetch(generation: generation)
        }
    }

    private func scheduleNeighborPrefetch(generation current: Int) {
        neighborTask?.cancel()
        let anchorID = state.snapshot?.trackID
        neighborTask = Task { [reader] in
            guard !Task.isCancelled else { return }
            do {
                let neighbors = try await reader.neighbors()
                guard !Task.isCancelled, enabled, current == generation else { return }
                // Drop stale results if the track moved while AppleScript was working.
                guard state.snapshot?.trackID == anchorID else { return }
                applyNeighbors(neighbors ?? MusicNeighbors())
            } catch {
                guard !Task.isCancelled, enabled, current == generation else { return }
                if state.snapshot?.trackID == anchorID, neighborArt.nextTrackID != nil || neighborArt.previousTrackID != nil {
                    // Keep last good preview covers when a transient Music error happens.
                    return
                }
                neighborArt = MusicNeighbors()
            }
        }
    }

    private func applyNeighbors(_ neighbors: MusicNeighbors) {
        neighborArt = neighbors
        let previousImage = neighbors.previousArtwork.flatMap(NSImage.init(data:))
        let nextImage = neighbors.nextArtwork.flatMap(NSImage.init(data:))
        var previousKeys = Set<String>()
        var nextKeys = Set<String>()
        if let id = neighbors.previousTrackID { previousKeys.insert(id) }
        if let id = neighbors.nextTrackID { nextKeys.insert(id) }
        coverTrail.applyNeighbors(
            previousKeys: previousKeys, previousImage: previousImage,
            nextKeys: nextKeys, nextImage: nextImage
        )
        publishCovers()
    }

    private func publishCovers() {
        previousCover = coverTrail.previousCover
        nextCover = coverTrail.nextCover
    }

    func cue(to progress: Double, trackID: String) {
        guard progress.isFinite, let snapshot = state.snapshot, snapshot.trackID == trackID,
              snapshot.duration.isFinite, snapshot.duration > 0 else { return }
        let position = min(max(0, snapshot.duration - 0.25), max(0, progress) * snapshot.duration)
        send(.cue(seconds: position), trackID: trackID)
    }

    func mixerVolume(_ value: Int? = nil) async throws -> Int {
        guard enabled, !permissionDenied else {
            throw MusicFailure(message: "Conecta Apple Music para controlar su volumen.")
        }
        return try await reader.volume(value)
    }

    func playPlaylistTrack(_ trackID: String) async throws {
        guard enabled, !permissionDenied else {
            throw MusicFailure(message: "Conecta Apple Music para usar la cinta.")
        }
        let playlists = MusicPlaylistService()
        try await playlists.play(trackID: trackID)
        pendingNavigation = nil
        await refresh()
    }

    func send(_ command: MediaCommand, trackID: String? = nil) {
        guard !permissionDenied else { return }
        switch command {
        case .next: pendingNavigation = .next
        case .previous: pendingNavigation = .previous
        default: break
        }
        Task {
            do {
                guard await reader.isRunning() else { state.update(nil); return }
                guard trackID == nil || state.snapshot?.trackID == trackID else { return }
                try await reader.send(command)
                await refresh()
            } catch {
                self.error = error.localizedDescription
                pendingNavigation = nil
            }
        }
    }
}
