import SwiftUI
import IslandCore

/// Onkyo-style sliding drawer with a rotary multi-disc carousel.
struct RecordDiscChanger: View {
    let palette: RecordPlayerPalette
    let reduceMotion: Bool
    let currentTitle: String?
    let currentArtist: String?
    let onClose: () -> Void
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

    private var tracks: [MusicCassetteTrack] { catalog?.tracks ?? [] }
    private var selectedTrack: MusicCassetteTrack? {
        guard tracks.indices.contains(selected) else { return nil }
        return tracks[selected]
    }

    var body: some View {
        VStack(spacing: 12) {
            trayChrome
            ZStack {
                trayWell
                if loading {
                    ProgressView().controlSize(.small)
                } else if tracks.isEmpty {
                    Text(error ?? "Música no expone una playlist con discos ahora.")
                        .font(.callout)
                        .foregroundStyle(palette.ink.opacity(0.7))
                        .multilineTextAlignment(.center)
                        .padding(24)
                } else {
                    carousel
                    centerPlay
                }
            }
            .frame(width: 340, height: 340)
            if let selectedTrack {
                VStack(spacing: 2) {
                    Text(selectedTrack.title)
                        .font(.subheadline.weight(.semibold))
                        .lineLimit(1)
                    Text(selectedTrack.artist.isEmpty ? " " : selectedTrack.artist)
                        .font(.caption)
                        .foregroundStyle(palette.ink.opacity(0.65))
                        .lineLimit(1)
                }
                .frame(maxWidth: .infinity)
            }
            if let status {
                Text(status).font(.caption2).foregroundStyle(palette.accent).lineLimit(2)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
        .frame(width: 372)
        .background(drawerShell)
        .task { await reload() }
    }

    private var trayChrome: some View {
        HStack {
            Text((catalog?.name ?? "Cambiador").uppercased())
                .font(.caption2.weight(.bold))
                .tracking(1.2)
                .foregroundStyle(palette.metal)
            Spacer()
            Button(action: onClose) {
                Image(systemName: "chevron.right")
                    .font(.caption.weight(.bold))
                    .frame(width: 28, height: 28)
            }
            .buttonStyle(.borderless)
            .accessibilityLabel("Guardar cambiador")
        }
    }

    private var trayWell: some View {
        Circle()
            .fill(
                RadialGradient(
                    colors: [Color(white: 0.16), Color(white: 0.05)],
                    center: .center,
                    startRadius: 20,
                    endRadius: 170
                )
            )
            .overlay {
                Circle().strokeBorder(palette.metal.opacity(0.28), lineWidth: 1.2)
            }
            .overlay {
                ForEach(0..<slotCount, id: \.self) { index in
                    let angle = Double(index) * step * .pi / 180
                    Circle()
                        .strokeBorder(Color.white.opacity(0.06), lineWidth: 1)
                        .frame(width: 96, height: 96)
                        .offset(x: 108 * cos(angle - .pi / 2), y: 108 * sin(angle - .pi / 2))
                }
            }
    }

    private var carousel: some View {
        let visible = min(slotCount, tracks.count)
        return ZStack {
            ForEach(0..<visible, id: \.self) { offset in
                let track = tracks[(selected + offset) % tracks.count]
                // Selected (offset 0) sits at the front/bottom of the ring.
                let theta = (Double(offset) * step - dragAngle) * .pi / 180
                let depth = max(0.2, cos(theta))
                ChangerDisc(
                    artwork: artworks[track.id],
                    palette: palette,
                    emphasized: offset == 0 && abs(dragAngle) < step * 0.35
                )
                .frame(width: 92, height: 92)
                .opacity(0.4 + 0.6 * depth)
                .offset(x: 108 * sin(theta), y: 108 * cos(theta))
                .zIndex(depth * 10)
                .allowsHitTesting(false)
                .id(track.id)
            }
        }
        .contentShape(Circle())
        .gesture(drag)
        .background {
            ChangerTrackpadWheel { delta in
                nudgeSlots(Int((Double(delta) * 0.04).rounded()))
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Cambiador de discos")
        .accessibilityValue(selectedTrack.map(\.title) ?? "")
        .accessibilityAdjustableAction { direction in
            switch direction {
            case .increment: nudgeSlots(1)
            case .decrement: nudgeSlots(-1)
            @unknown default: break
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
                    .fill(Color(white: 0.12))
                    .overlay(Circle().strokeBorder(palette.metal.opacity(0.5), lineWidth: 1.2))
                    .frame(width: 78, height: 78)
                if busy {
                    ProgressView().controlSize(.small)
                } else {
                    Image(systemName: "play.fill")
                        .font(.title2.weight(.bold))
                        .foregroundStyle(palette.accent)
                        .offset(x: 2)
                }
            }
        }
        .buttonStyle(.plain)
        .disabled(busy || selectedTrack == nil)
        .accessibilityLabel("Play")
        .accessibilityHint("Pone el disco seleccionado en el tocadiscos")
        .zIndex(50)
    }

    private var drawerShell: some View {
        RoundedRectangle(cornerRadius: 18, style: .continuous)
            .fill(Color(white: 0.07))
            .overlay {
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .strokeBorder(Color.white.opacity(0.08), lineWidth: 1)
            }
            .shadow(color: .black.opacity(0.5), radius: 22, x: -10, y: 8)
    }

    private var drag: some Gesture {
        DragGesture(minimumDistance: 3)
            .updating($dragAngle) { value, angle, _ in
                // Horizontal drag spins the carousel (positive = next track).
                angle = Double(value.translation.width) * 0.45
            }
            .onEnded { value in
                let delta = Double(value.translation.width) * 0.45
                let slots = Int((delta / step).rounded())
                nudgeSlots(slots)
            }
    }

    private func reload() async {
        loading = true
        error = nil
        defer { loading = false }
        do {
            let catalog = try await service.currentCatalog()
            self.catalog = catalog
            if let match = catalog.tracks.firstIndex(where: {
                $0.title == currentTitle && (currentArtist == nil || currentArtist == $0.artist)
            }) {
                selected = match
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
                .shadow(color: .black.opacity(emphasized ? 0.55 : 0.25), radius: emphasized ? 8 : 3, y: 2)
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
            Circle().strokeBorder(.white.opacity(emphasized ? 0.35 : 0.12), lineWidth: emphasized ? 1.4 : 0.8)
        }
        .overlay {
            Circle().fill(.black).frame(width: 10, height: 10)
                .overlay(Circle().strokeBorder(.white.opacity(0.3), lineWidth: 0.7))
        }
        .scaleEffect(emphasized ? 1.06 : 1)
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
            guard bounds.contains(point) else { return }
            let direction: CGFloat = event.isDirectionInvertedFromDevice ? 1 : -1
            let delta = direction * (abs(event.scrollingDeltaX) > abs(event.scrollingDeltaY)
                ? event.scrollingDeltaX : event.scrollingDeltaY)
            accum += delta
            let threshold: CGFloat = 18
            if abs(accum) >= threshold {
                onDelta?(accum)
                accum = 0
            }
        }
    }
}

/// Peeking disc tip on the trailing edge — press to eject the changer tray.
struct RecordDiscChangerPeek: View {
    let palette: RecordPlayerPalette
    let artwork: NSImage?
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            ZStack {
                Circle()
                    .fill(palette.vinyl)
                if let artwork {
                    Image(nsImage: artwork)
                        .resizable()
                        .scaledToFill()
                        .frame(width: 36, height: 36)
                        .clipShape(Circle())
                } else {
                    Circle()
                        .fill(palette.accent.opacity(0.75))
                        .frame(width: 36, height: 36)
                }
                Circle().fill(.black).frame(width: 6, height: 6)
            }
            .frame(width: 72, height: 72)
            .overlay(Circle().strokeBorder(.white.opacity(0.2), lineWidth: 1))
            .shadow(color: .black.opacity(0.4), radius: 8, x: -2, y: 2)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Abrir cambiador de discos")
        .help("Saca el cambiador de discos de la playlist")
    }
}
