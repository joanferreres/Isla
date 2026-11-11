import SwiftUI
import IslandCore

/// Half-clipped rotary disc selector on the window’s leading edge — no boxed panel.
/// Two-finger scroll / drag rotates; Play loads the front disc onto the turntable.
struct RecordDiscChanger: View {
    let palette: RecordPlayerPalette
    let reduceMotion: Bool
    let diameter: CGFloat
    let currentTitle: String?
    let currentArtist: String?
    /// Called with the chosen track and its artwork (for the platter hand-off animation).
    let onPlay: (MusicCassetteTrack, NSImage?) async -> String?

    @State private var service = MusicPlaylistService()
    @State private var catalog: MusicPlaylistCatalog?
    @State private var error: String?
    @State private var loading = true
    @State private var selected = 0
    @State private var artworks: [String: NSImage] = [:]
    @State private var busy = false
    @State private var status: String?
    @GestureState private var dragAngle: Double = 0

    private let slotCount = 6
    private var step: Double { 360.0 / Double(slotCount) }
    private var radius: CGFloat { diameter * 0.32 }
    private var discSize: CGFloat { diameter * 0.28 }

    private var tracks: [MusicCassetteTrack] { catalog?.tracks ?? [] }
    private var selectedTrack: MusicCassetteTrack? {
        guard tracks.indices.contains(selected) else { return nil }
        return tracks[selected]
    }

    var body: some View {
        ZStack {
            ringWell
            if loading {
                ProgressView().controlSize(.small)
                    .offset(x: diameter * 0.22)
            } else if tracks.isEmpty {
                Text(error ?? "Sin discos")
                    .font(.caption2)
                    .foregroundStyle(palette.ink.opacity(0.65))
                    .multilineTextAlignment(.center)
                    .frame(width: diameter * 0.4)
                    .offset(x: diameter * 0.22)
            } else {
                carousel
                centerPlay
            }
            if let status {
                Text(status)
                    .font(.caption2)
                    .foregroundStyle(palette.accent)
                    .lineLimit(2)
                    .frame(width: diameter * 0.42)
                    .offset(x: diameter * 0.22, y: diameter * 0.42)
            }
        }
        .frame(width: diameter, height: diameter)
        // Only the on-screen (trailing) half is hittable.
        .contentShape(Path(CGRect(x: diameter * 0.5, y: 0, width: diameter * 0.5, height: diameter)))
        .help(selectedTrack.map { "\($0.title) — dos dedos para girar" } ?? "Cambiador de discos")
        .task(id: "\(currentTitle ?? "")|\(currentArtist ?? "")") { await reload() }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Cambiador de discos")
        .accessibilityValue(selectedTrack.map(\.title) ?? "")
        .accessibilityHint("Desliza con dos dedos para cambiar de disco")
        .accessibilityAdjustableAction { direction in
            switch direction {
            case .increment: nudgeSlots(1)
            case .decrement: nudgeSlots(-1)
            @unknown default: break
            }
        }
    }

    private var ringWell: some View {
        Circle()
            .strokeBorder(palette.metal.opacity(0.18), lineWidth: 1)
            .frame(width: diameter * 0.92, height: diameter * 0.92)
            .overlay {
                ForEach(0..<slotCount, id: \.self) { index in
                    // θ=0 sits at +X (into the screen) so the selected disc is fully visible.
                    let angle = Double(index) * step * .pi / 180
                    Circle()
                        .strokeBorder(Color.white.opacity(0.04), lineWidth: 1)
                        .frame(width: discSize + 6, height: discSize + 6)
                        .offset(x: radius * cos(angle), y: radius * sin(angle))
                }
            }
            .allowsHitTesting(false)
    }

    private var carousel: some View {
        let visible = min(slotCount, tracks.count)
        return ZStack {
            ForEach(0..<visible, id: \.self) { offset in
                let track = tracks[(selected + offset) % tracks.count]
                let theta = (Double(offset) * step - dragAngle) * .pi / 180
                // Selected (offset 0) at +X into the player; left half is clipped off-screen.
                let depth = max(0.15, cos(theta))
                ChangerDisc(
                    artwork: artworks[track.id],
                    palette: palette,
                    emphasized: offset == 0 && abs(dragAngle) < step * 0.35
                )
                .frame(width: discSize, height: discSize)
                .opacity(0.35 + 0.65 * depth)
                .offset(x: radius * cos(theta), y: radius * sin(theta))
                .zIndex(depth * 10)
                .allowsHitTesting(false)
                .id(track.id)
            }
        }
        .gesture(drag)
        .background {
            ChangerTrackpadWheel { delta in
                // Two-finger scroll on the visible half rotates the ring.
                nudgeSlots(Int((Double(delta) * 0.05).rounded()))
            }
        }
    }

    private var centerPlay: some View {
        Button {
            guard let track = selectedTrack else { return }
            Task {
                busy = true
                status = nil
                defer { busy = false }
                if let message = await onPlay(track, artworks[track.id]) {
                    status = message
                }
            }
        } label: {
            ZStack {
                Circle()
                    .fill(Color(white: 0.1).opacity(0.9))
                    .overlay(Circle().strokeBorder(palette.metal.opacity(0.4), lineWidth: 1))
                    .frame(width: diameter * 0.2, height: diameter * 0.2)
                if busy {
                    ProgressView().controlSize(.small)
                } else {
                    Image(systemName: "play.fill")
                        .font(.body.weight(.bold))
                        .foregroundStyle(palette.accent)
                        .offset(x: 1)
                }
            }
        }
        .buttonStyle(.plain)
        .disabled(busy || selectedTrack == nil)
        .offset(x: diameter * 0.02)
        .accessibilityLabel("Play")
        .accessibilityHint("Pone el disco seleccionado en el tocadiscos")
        .zIndex(50)
    }

    private var drag: some Gesture {
        DragGesture(minimumDistance: 3)
            .updating($dragAngle) { value, angle, _ in
                // Vertical drag also spins — natural when only the right half is visible.
                let dominant = abs(value.translation.height) > abs(value.translation.width)
                    ? value.translation.height
                    : value.translation.width
                angle = Double(dominant) * 0.4
            }
            .onEnded { value in
                let dominant = abs(value.translation.height) > abs(value.translation.width)
                    ? value.translation.height
                    : value.translation.width
                nudgeSlots(Int((Double(dominant) * 0.4 / step).rounded()))
            }
    }

    private func reload() async {
        loading = true
        error = nil
        defer { loading = false }
        do {
            let catalog = try await service.changerCatalog()
            self.catalog = catalog
            if let match = catalog.tracks.firstIndex(where: {
                $0.title == currentTitle && (currentArtist == nil || currentArtist == $0.artist)
            }) {
                selected = match
            } else {
                selected = 0
            }
            await prefetch(around: selected)
        } catch {
            catalog = nil
            self.error = error.localizedDescription
        }
    }

    private func nudgeSlots(_ delta: Int) {
        guard !tracks.isEmpty, delta != 0 else { return }
        let count = tracks.count
        let animation = reduceMotion ? nil : Animation.snappy(duration: 0.28)
        withAnimation(animation) {
            selected = ((selected + delta) % count + count) % count
        }
        Task { await prefetch(around: selected) }
    }

    private func prefetch(around index: Int) async {
        guard !tracks.isEmpty else { return }
        let count = tracks.count
        for offset in 0..<min(slotCount, count) {
            let track = tracks[(index + offset) % count]
            guard artworks[track.id] == nil else { continue }
            if let data = try? await service.artwork(trackID: track.id),
               let image = NSImage(data: data) {
                artworks[track.id] = image
            }
        }
    }
}

private struct ChangerDisc: View {
    let artwork: NSImage?
    let palette: RecordPlayerPalette
    let emphasized: Bool

    var body: some View {
        ZStack {
            Circle()
                .fill(Color(white: 0.08))
                .shadow(color: .black.opacity(emphasized ? 0.5 : 0.2), radius: emphasized ? 7 : 3, y: 2)
            if let artwork {
                Image(nsImage: artwork)
                    .resizable()
                    .scaledToFill()
            } else {
                Circle().fill(palette.accent.opacity(0.7))
            }
        }
        .clipShape(Circle())
        .overlay {
            Circle().strokeBorder(.white.opacity(emphasized ? 0.35 : 0.12), lineWidth: emphasized ? 1.3 : 0.7)
        }
        .overlay {
            Circle().fill(.black).frame(width: 8, height: 8)
                .overlay(Circle().strokeBorder(.white.opacity(0.3), lineWidth: 0.6))
        }
        .scaleEffect(emphasized ? 1.05 : 1)
    }
}

private struct ChangerTrackpadWheel: NSViewRepresentable {
    let onDelta: (CGFloat) -> Void
    func makeNSView(context: Context) -> Surface { Surface() }
    func updateNSView(_ view: Surface, context: Context) { view.onDelta = onDelta }
    static func dismantleNSView(_ view: Surface, coordinator: ()) { view.stop() }

    final class Surface: NSView {
        var onDelta: ((CGFloat) -> Void)?
        private var monitor: Any?
        private var accum: CGFloat = 0
        override func hitTest(_ point: NSPoint) -> NSView? { nil }
        override func viewWillMove(toWindow newWindow: NSWindow?) {
            stop(); super.viewWillMove(toWindow: newWindow)
        }
        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            guard window != nil, monitor == nil else { return }
            monitor = NSEvent.addLocalMonitorForEvents(matching: .scrollWheel) { [weak self] event in
                self?.handle(event); return event
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
            // Only the visible (right) half of this view counts as the selector.
            guard bounds.contains(point), point.x >= bounds.midX else { return }
            let direction: CGFloat = event.isDirectionInvertedFromDevice ? 1 : -1
            let delta = direction * (abs(event.scrollingDeltaX) > abs(event.scrollingDeltaY)
                ? event.scrollingDeltaX : event.scrollingDeltaY)
            accum += delta
            let threshold: CGFloat = 16
            if abs(accum) >= threshold {
                onDelta?(accum)
                accum = 0
            }
        }
    }
}
