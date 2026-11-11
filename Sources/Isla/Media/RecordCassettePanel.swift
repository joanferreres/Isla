import SwiftUI
import IslandCore

/// Side-deploying cassette shell with a rotatable CD carousel of the current Music playlist.
struct RecordCassettePanel: View {
    let palette: RecordPlayerPalette
    let reduceMotion: Bool
    let currentTitle: String?
    let currentArtist: String?
    let onClose: () -> Void
    let onPlay: (MusicCassetteTrack) async -> String?

    @State private var service = MusicPlaylistService()
    @State private var catalog: MusicPlaylistCatalog?
    @State private var error: String?
    @State private var loading = true
    @State private var selected = 0
    @State private var rotation: Double = 0
    @State private var artworks: [String: NSImage] = [:]
    @State private var busy = false
    @State private var status: String?
    @GestureState private var dragAngle: Double = 0

    private var tracks: [MusicCassetteTrack] { catalog?.tracks ?? [] }
    private var selectedTrack: MusicCassetteTrack? {
        guard tracks.indices.contains(selected) else { return nil }
        return tracks[selected]
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            header
            cassetteWindow
            if let selectedTrack {
                VStack(alignment: .leading, spacing: 4) {
                    Text(selectedTrack.title)
                        .font(.headline.weight(.semibold))
                        .lineLimit(2)
                    Text(selectedTrack.artist.isEmpty ? "Sin artista" : selectedTrack.artist)
                        .font(.subheadline)
                        .foregroundStyle(palette.ink.opacity(0.65))
                        .lineLimit(1)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                playButton(for: selectedTrack)
            } else if loading {
                ProgressView("Cargando cinta…").controlSize(.small)
                    .frame(maxWidth: .infinity, minHeight: 88)
            } else {
                Text(error ?? "No hay canciones en la playlist actual.")
                    .font(.callout)
                    .foregroundStyle(palette.ink.opacity(0.7))
                    .frame(maxWidth: .infinity, minHeight: 88, alignment: .leading)
            }
            if let status {
                Text(status).font(.caption2).foregroundStyle(palette.accent).lineLimit(2)
            }
        }
        .padding(18)
        .frame(width: 320)
        .background(cassetteShell)
        .overlay(alignment: .leading) {
            Capsule()
                .fill(palette.metal.opacity(0.55))
                .frame(width: 5, height: 72)
                .offset(x: -2)
                .allowsHitTesting(false)
        }
        .task { await reload() }
    }

    private var header: some View {
        HStack(spacing: 10) {
            Image(systemName: "cassette.fill")
                .font(.title3.weight(.semibold))
                .foregroundStyle(palette.accent)
            VStack(alignment: .leading, spacing: 2) {
                Text("Cinta")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(palette.accent)
                Text(catalog?.name ?? "Playlist")
                    .font(.callout.weight(.medium))
                    .lineLimit(1)
            }
            Spacer(minLength: 0)
            Button(action: onClose) {
                Image(systemName: "xmark")
                    .font(.caption.weight(.bold))
                    .frame(width: 28, height: 28)
            }
            .buttonStyle(.borderless)
            .accessibilityLabel("Cerrar cinta")
        }
    }

    private var cassetteWindow: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(Color.black.opacity(0.55))
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .strokeBorder(palette.metal.opacity(0.35), lineWidth: 1)
            if tracks.isEmpty {
                Image(systemName: "opticaldisc")
                    .font(.largeTitle)
                    .foregroundStyle(palette.ink.opacity(0.25))
            } else {
                GeometryReader { proxy in
                    let size = min(proxy.size.width, proxy.size.height)
                    carousel(size: size)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
                .padding(12)
            }
        }
        .frame(height: 210)
        .contentShape(Rectangle())
        .gesture(carouselDrag)
        .background {
            CassetteTrackpadWheel { delta in
                guard !tracks.isEmpty else { return }
                rotate(by: Double(delta) * 0.55)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Carrusel de discos de la playlist")
        .accessibilityValue(selectedTrack.map { "\($0.title), de \($0.artist)" } ?? "Vacío")
        .accessibilityAdjustableAction { direction in
            guard !tracks.isEmpty else { return }
            switch direction {
            case .increment: select(selected + 1)
            case .decrement: select(selected - 1)
            @unknown default: break
            }
        }
    }

    private func carousel(size: CGFloat) -> some View {
        let count = max(tracks.count, 1)
        let step = 360.0 / Double(count)
        let angle = rotation + dragAngle
        return ZStack {
            ForEach(Array(tracks.enumerated()), id: \.element.id) { index, track in
                let delta = shortest(Double(index) * step - angle)
                let normalized = abs(delta) / 180
                let depth = 1 - min(1, normalized)
                let radius = size * 0.28
                let radians = delta * .pi / 180
                let discSize = size * (0.42 + 0.22 * depth)
                CassetteDisc(
                    artwork: artworks[track.id],
                    palette: palette,
                    emphasized: index == selected
                )
                .frame(width: discSize, height: discSize)
                .opacity(0.28 + 0.72 * depth)
                .scaleEffect(0.82 + 0.18 * depth)
                .offset(x: radius * sin(radians), y: radius * 0.22 * (1 - cos(radians)))
                .zIndex(depth * 100)
                .allowsHitTesting(false)
            }
        }
        .onChange(of: angle) { _, value in
            syncSelection(to: value, step: step)
        }
    }

    private var carouselDrag: some Gesture {
        DragGesture(minimumDistance: 4)
            .updating($dragAngle) { value, angle, _ in
                angle = Double(value.translation.width) * -0.35
            }
            .onEnded { value in
                rotate(by: Double(value.translation.width) * -0.35)
            }
    }

    private func playButton(for track: MusicCassetteTrack) -> some View {
        Button {
            Task {
                busy = true
                status = nil
                defer { busy = false }
                if let message = await onPlay(track) {
                    status = message
                } else {
                    status = nil
                    onClose()
                }
            }
        } label: {
            HStack(spacing: 8) {
                Image(systemName: "opticaldisc.fill")
                Text(busy ? "Poniendo…" : "Poner en el tocadiscos")
                    .fontWeight(.semibold)
            }
            .frame(maxWidth: .infinity, minHeight: 40)
        }
        .buttonStyle(.borderedProminent)
        .tint(palette.accent)
        .disabled(busy)
        .accessibilityHint("Reproduce esta canción en el tocadiscos de Isla")
    }

    private var cassetteShell: some View {
        RoundedRectangle(cornerRadius: 26, style: .continuous)
            .fill(
                LinearGradient(
                    colors: [
                        Color(nsColor: palette.background).opacity(0.92),
                        Color(white: 0.08),
                        Color(nsColor: palette.background)
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            )
            .overlay {
                RoundedRectangle(cornerRadius: 26, style: .continuous)
                    .strokeBorder(palette.metal.opacity(0.45), lineWidth: 1.2)
            }
            .shadow(color: .black.opacity(0.45), radius: 18, x: -8, y: 10)
    }

    private func reload() async {
        loading = true
        error = nil
        status = nil
        defer { loading = false }
        do {
            let catalog = try await service.currentCatalog()
            self.catalog = catalog
            if let match = catalog.tracks.firstIndex(where: {
                $0.title == currentTitle && (currentArtist == nil || currentArtist == $0.artist)
            }) {
                selected = match
                rotation = Double(match) * (360.0 / Double(max(catalog.tracks.count, 1)))
            }
            await prefetchArtwork(around: selected, in: catalog.tracks)
        } catch {
            catalog = nil
            self.error = error.localizedDescription
        }
    }

    private func rotate(by degrees: Double) {
        guard !tracks.isEmpty else { return }
        let step = 360.0 / Double(tracks.count)
        let animation = reduceMotion ? nil : Animation.interactiveSpring(response: 0.32, dampingFraction: 0.86)
        withAnimation(animation) {
            rotation += degrees
            syncSelection(to: rotation, step: step)
            rotation = Double(selected) * step
        }
        Task { await prefetchArtwork(around: selected, in: tracks) }
    }

    private func select(_ index: Int) {
        guard !tracks.isEmpty else { return }
        let count = tracks.count
        selected = ((index % count) + count) % count
        let step = 360.0 / Double(count)
        let animation = reduceMotion ? nil : Animation.snappy(duration: 0.28)
        withAnimation(animation) { rotation = Double(selected) * step }
        Task { await prefetchArtwork(around: selected, in: tracks) }
    }

    private func syncSelection(to angle: Double, step: Double) {
        guard !tracks.isEmpty else { return }
        var index = Int((angle / step).rounded()) % tracks.count
        if index < 0 { index += tracks.count }
        if selected != index {
            selected = index
            Task { await prefetchArtwork(around: selected, in: tracks) }
        }
    }

    private func shortest(_ degrees: Double) -> Double {
        var value = degrees.truncatingRemainder(dividingBy: 360)
        if value > 180 { value -= 360 }
        if value < -180 { value += 360 }
        return value
    }

    private func prefetchArtwork(around index: Int, in tracks: [MusicCassetteTrack]) async {
        guard !tracks.isEmpty else { return }
        let count = tracks.count
        let neighbors = (-2...2).map { offset in
            tracks[((index + offset) % count + count) % count]
        }
        for track in neighbors where artworks[track.id] == nil {
            if let data = try? await service.artwork(trackID: track.id),
               let image = NSImage(data: data) {
                artworks[track.id] = image
            }
        }
    }
}

private struct CassetteDisc: View {
    let artwork: NSImage?
    let palette: RecordPlayerPalette
    let emphasized: Bool

    var body: some View {
        ZStack {
            Circle()
                .fill(palette.vinyl)
                .overlay {
                    Circle().strokeBorder(.white.opacity(emphasized ? 0.28 : 0.12), lineWidth: emphasized ? 1.4 : 0.8)
                }
            if let artwork {
                Image(nsImage: artwork)
                    .resizable()
                    .scaledToFill()
                    .frame(width: 54, height: 54)
                    .clipShape(Circle())
                    .overlay(Circle().strokeBorder(.black.opacity(0.4), lineWidth: 1))
            } else {
                Circle()
                    .fill(palette.accent.opacity(0.75))
                    .frame(width: 54, height: 54)
                    .overlay(Circle().strokeBorder(.black.opacity(0.35), lineWidth: 1))
            }
            Circle()
                .fill(.black)
                .frame(width: 8, height: 8)
                .overlay(Circle().strokeBorder(.white.opacity(0.35), lineWidth: 0.8))
        }
        .shadow(color: .black.opacity(emphasized ? 0.55 : 0.25), radius: emphasized ? 10 : 4, y: 3)
    }
}

/// Trackpad wheel over the cassette window only — never attached to the main platter.
private struct CassetteTrackpadWheel: NSViewRepresentable {
    let onDelta: (CGFloat) -> Void

    func makeNSView(context: Context) -> Surface { Surface() }
    func updateNSView(_ view: Surface, context: Context) { view.onDelta = onDelta }
    static func dismantleNSView(_ view: Surface, coordinator: ()) { view.stop() }

    final class Surface: NSView {
        var onDelta: ((CGFloat) -> Void)?
        private var monitor: Any?

        override func hitTest(_ point: NSPoint) -> NSView? { nil }

        override func viewWillMove(toWindow newWindow: NSWindow?) {
            stop()
            super.viewWillMove(toWindow: newWindow)
        }

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            guard window != nil, monitor == nil else { return }
            monitor = NSEvent.addLocalMonitorForEvents(matching: .scrollWheel) { [weak self] event in
                self?.handle(event)
                return event
            }
        }

        func stop() {
            if let monitor { NSEvent.removeMonitor(monitor) }
            monitor = nil
        }

        private func handle(_ event: NSEvent) {
            guard let window, event.window === window,
                  event.hasPreciseScrollingDeltas, event.momentumPhase.isEmpty else { return }
            let point = convert(event.locationInWindow, from: nil)
            guard bounds.contains(point) else { return }
            let direction: CGFloat = event.isDirectionInvertedFromDevice ? 1 : -1
            let delta = direction * (abs(event.scrollingDeltaX) > abs(event.scrollingDeltaY)
                ? event.scrollingDeltaX
                : event.scrollingDeltaY)
            if delta != 0 { onDelta?(delta) }
        }
    }
}
