import SwiftUI
import IslandCore

/// Half-clipped rotary disc selector on the window’s leading edge — no boxed panel.
/// Two-finger torque spins a **stable ordered** ring; the main turntable never changes
/// until Play. The disc at +X (middle of the visible right half) is the selection.
struct RecordDiscChanger: View {
    let palette: RecordPlayerPalette
    let reduceMotion: Bool
    let diameter: CGFloat
    let currentTitle: String?
    let currentArtist: String?
    let onPlay: (MusicCassetteTrack, NSImage?) async -> String?

    @State private var service = MusicPlaylistService()
    @State private var catalog: MusicPlaylistCatalog?
    @State private var error: String?
    @State private var loading = true
    /// Snapped index at the +X front slot when `ringAngle == 0`.
    @State private var selected = 0
    /// Continuous orbit angle. Tracks keep a fixed order; only this angle moves.
    @State private var ringAngle = 0.0
    @State private var artworks: [String: NSImage] = [:]
    @State private var busy = false
    @State private var status: String?
    @State private var turning = false
    @State private var turnOrigin = 0.0
    @State private var samples: [(Date, Double)] = []
    @State private var dragLastAngle: Double?
    @State private var snapTask: Task<Void, Never>?

    /// Angular spacing for the full ordered playlist on one ring.
    private var spacing: Double {
        let count = max(tracks.count, 1)
        return 360.0 / Double(count)
    }
    private var radius: CGFloat { diameter * 0.32 }
    private var discSize: CGFloat {
        // Shrink a bit when many tracks share the ring so neighbours don’t paint over each other.
        let count = max(tracks.count, 1)
        let chord = radius * CGFloat(sin(spacing * .pi / 180))
        return min(diameter * 0.28, max(diameter * 0.14, chord * 1.65))
    }

    private var tracks: [MusicCassetteTrack] { catalog?.tracks ?? [] }

    /// Track currently at the right-hand front (+X), including mid-spin preview.
    /// Absolute index on the ordered ring — never a remapped window.
    private var frontIndex: Int {
        guard !tracks.isEmpty else { return 0 }
        let count = tracks.count
        let moved = Int((-ringAngle / spacing).rounded())
        return ((moved % count) + count) % count
    }

    private var frontTrack: MusicCassetteTrack? {
        guard tracks.indices.contains(frontIndex) else { return nil }
        return tracks[frontIndex]
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
            if let frontTrack, !loading {
                VStack(alignment: .leading, spacing: 2) {
                    Text(frontTrack.title)
                        .font(.caption2.weight(.semibold))
                        .lineLimit(2)
                    if !frontTrack.artist.isEmpty {
                        Text(frontTrack.artist)
                            .font(.caption2)
                            .lineLimit(1)
                    }
                }
                // Negative / inverted against whatever sits behind (disc art + panel).
                .foregroundStyle(.white)
                .blendMode(.difference)
                .frame(width: max(96, diameter * 0.42), alignment: .leading)
                .offset(x: diameter * 0.52, y: 0)
                .allowsHitTesting(false)
                .accessibilityHidden(true)
            }
            if let status {
                Text(status)
                    .font(.caption2)
                    .foregroundStyle(palette.accent)
                    .lineLimit(2)
                    .frame(width: diameter * 0.42)
                    .offset(x: diameter * 0.52, y: diameter * 0.28)
            }
        }
        .frame(width: diameter, height: diameter)
        .background {
            ChangerTurnSurface(
                onTorque: { degrees in applyTorque(degrees) },
                onFinish: { cancelled in scheduleSnap(cancelled: cancelled) }
            )
            .frame(width: diameter, height: diameter)
            .allowsHitTesting(false)
        }
        .gesture(angularDrag)
        .contentShape(Path(CGRect(x: diameter * 0.5, y: 0, width: diameter * 0.5, height: diameter)))
        .help(frontTrack.map { "\($0.title) — gira para elegir; Play para el plato" } ?? "Cambiador de discos")
        // Reload when now-playing changes (after Play), never while browsing the ring.
        .task(id: "\(currentTitle ?? "")|\(currentArtist ?? "")") { await reload() }
        .onDisappear {
            snapTask?.cancel()
            RecordGestureClaim.selectorActive = false
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Cambiador de discos")
        .accessibilityValue(frontTrack.map(\.title) ?? "")
        .accessibilityHint("Gira con dos dedos; Play pone esa canción en el tocadiscos")
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
            .allowsHitTesting(false)
    }

    private var carousel: some View {
        let count = tracks.count
        let spacing = self.spacing
        // Absolute ordered ring: track i is always at angle i×spacing + ringAngle.
        // Identities never remap between slots — artwork orbits with its own index.
        return ZStack {
            ForEach(Array(tracks.enumerated()), id: \.element.id) { index, track in
                let degrees = Double(index) * spacing + ringAngle
                let theta = degrees * .pi / 180
                let depth = cos(theta)
                // Draw the front hemisphere (and a little past) so the half-edge clip reads as a sequence.
                if depth > -0.2 {
                    let atFront = abs(shortest(degrees)) < max(spacing * 0.55, 8)
                    ChangerDisc(
                        artwork: artworks[track.id],
                        palette: palette,
                        emphasized: atFront
                    )
                    .frame(width: discSize, height: discSize)
                    .opacity(0.25 + 0.75 * max(0.15, depth))
                    .offset(x: radius * cos(theta), y: radius * sin(theta))
                    .zIndex(depth * 10)
                    .allowsHitTesting(false)
                }
            }
        }
        .frame(width: diameter, height: diameter)
        .allowsHitTesting(false)
    }

    private var centerPlay: some View {
        Button {
            // Commit the front preview, then hand off — platter changes only here.
            let track = frontTrack
            commitFrontSelection(animated: false)
            guard let track else { return }
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
        .disabled(busy || frontTrack == nil)
        .offset(x: diameter * 0.02)
        .accessibilityLabel("Play")
        .accessibilityHint("Reproduce la canción seleccionada en el tocadiscos")
        .zIndex(50)
    }

    private var angularDrag: some Gesture {
        DragGesture(minimumDistance: 2)
            .onChanged { value in
                guard value.location.x >= diameter * 0.5 else { return }
                let center = CGPoint(x: diameter / 2, y: diameter / 2)
                let angle = atan2(value.location.y - center.y, value.location.x - center.x) * 180 / .pi
                if dragLastAngle == nil {
                    beginTurn()
                    dragLastAngle = angle
                    return
                }
                var delta = angle - (dragLastAngle ?? angle)
                if delta > 180 { delta -= 360 }
                if delta < -180 { delta += 360 }
                dragLastAngle = angle
                applyTorque(delta)
            }
            .onEnded { _ in
                dragLastAngle = nil
                scheduleSnap(cancelled: false)
            }
    }

    private func beginTurn() {
        snapTask?.cancel()
        snapTask = nil
        if !turning {
            turning = true
            RecordGestureClaim.selectorActive = true
            turnOrigin = ringAngle
            samples = [(Date(), ringAngle)]
        }
    }

    private func applyTorque(_ degrees: Double) {
        guard degrees.isFinite, degrees != 0, !tracks.isEmpty else { return }
        beginTurn()
        var transaction = Transaction()
        transaction.disablesAnimations = true
        withTransaction(transaction) {
            ringAngle += degrees
        }
        samples.append((Date(), ringAngle))
        if samples.count > 12 { samples.removeFirst(samples.count - 12) }
    }

    /// Trackpad fires `.ended` between finger strokes — debounce so we don't remap mid-browse.
    private func scheduleSnap(cancelled: Bool) {
        snapTask?.cancel()
        if cancelled {
            snapTask = nil
            cancelTurn()
            return
        }
        snapTask = Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(150))
            guard !Task.isCancelled else { return }
            commitFrontSelection(animated: true)
        }
    }

    private func cancelTurn() {
        turning = false
        RecordGestureClaim.selectorActive = false
        samples = []
        dragLastAngle = nil
        withAnimation(reduceMotion ? nil : .snappy(duration: 0.2)) {
            ringAngle = turnOrigin
        }
    }

    /// Snap so some playlist index sits at +X; order of `tracks` is unchanged.
    private func commitFrontSelection(animated: Bool) {
        guard !tracks.isEmpty else {
            turning = false
            RecordGestureClaim.selectorActive = false
            return
        }
        var angle = ringAngle
        let velocity = angularVelocity()
        if animated, !reduceMotion, abs(velocity) > 60 {
            angle += velocity * 0.14
        }
        let count = tracks.count
        let spacing = self.spacing
        let next = ((Int((-angle / spacing).rounded()) % count) + count) % count
        let snapped = -Double(next) * spacing
        let animation = (animated && !reduceMotion)
            ? Animation.interpolatingSpring(stiffness: 240, damping: 24)
            : nil
        withAnimation(animation) {
            selected = next
            ringAngle = snapped
        }
        turning = false
        RecordGestureClaim.selectorActive = false
        samples = []
        dragLastAngle = nil
        Task { await prefetch(around: selected) }
    }

    private func angularVelocity() -> Double {
        guard samples.count >= 2, let first = samples.first, let last = samples.last else { return 0 }
        let dt = last.0.timeIntervalSince(first.0)
        guard dt > 0.02 else { return 0 }
        return (last.1 - first.1) / dt
    }

    private func shortest(_ degrees: Double) -> Double {
        var v = degrees.truncatingRemainder(dividingBy: 360)
        if v > 180 { v -= 360 }
        if v < -180 { v += 360 }
        return v
    }

    private func reload() async {
        loading = true
        error = nil
        defer { loading = false }
        do {
            let catalog = try await service.changerCatalog()
            // Keep a stable ordered list for the session; only replace wholesale on reload.
            self.catalog = catalog
            if let match = catalog.tracks.firstIndex(where: {
                $0.title == currentTitle && (currentArtist == nil || currentArtist == $0.artist)
            }) {
                selected = match
            } else if selected >= catalog.tracks.count {
                selected = 0
            }
            ringAngle = -Double(selected) * (360.0 / Double(max(catalog.tracks.count, 1)))
            turning = false
            RecordGestureClaim.selectorActive = false
            await prefetch(around: selected)
        } catch {
            catalog = nil
            self.error = error.localizedDescription
        }
    }

    private func nudgeSlots(_ delta: Int) {
        guard !tracks.isEmpty, delta != 0 else { return }
        snapTask?.cancel()
        let count = tracks.count
        let spacing = self.spacing
        withAnimation(reduceMotion ? nil : .snappy(duration: 0.28)) {
            selected = ((selected + delta) % count + count) % count
            ringAngle = -Double(selected) * spacing
        }
        Task { await prefetch(around: selected) }
    }

    private func prefetch(around index: Int) async {
        guard !tracks.isEmpty else { return }
        let count = tracks.count
        // Warm covers around the front of the absolute ring.
        for offset in -3...3 {
            let track = tracks[((index + offset) % count + count) % count]
            guard artworks[track.id] == nil else { continue }
            if let data = try? await service.artwork(trackID: track.id),
               let image = NSImage(data: data) {
                artworks[track.id] = image
            }
        }
    }
}

private extension Array {
    subscript(safe index: Int) -> Element? {
        indices.contains(index) ? self[index] : nil
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

private struct ChangerTurnSurface: NSViewRepresentable {
    let onTorque: (Double) -> Void
    let onFinish: (Bool) -> Void

    func makeNSView(context: Context) -> Surface {
        let view = Surface()
        view.onTorque = onTorque
        view.onFinish = onFinish
        return view
    }

    func updateNSView(_ view: Surface, context: Context) {
        view.onTorque = onTorque
        view.onFinish = onFinish
    }

    static func dismantleNSView(_ view: Surface, coordinator: ()) { view.stop() }

    final class Surface: NSView {
        var onTorque: ((Double) -> Void)?
        var onFinish: ((Bool) -> Void)?
        private var monitor: Any?
        private var active = false

        override func hitTest(_ point: NSPoint) -> NSView? { nil }

        override func viewWillMove(toWindow newWindow: NSWindow?) {
            stop(); super.viewWillMove(toWindow: newWindow)
        }

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            guard window != nil, monitor == nil else { return }
            monitor = NSEvent.addLocalMonitorForEvents(matching: [.scrollWheel, .rotate]) { [weak self] event in
                guard let self else { return event }
                return self.handle(event)
            }
        }

        func stop() {
            if active {
                active = false
                RecordGestureClaim.selectorActive = false
                onFinish?(true)
            }
            if let monitor { NSEvent.removeMonitor(monitor) }
            monitor = nil
        }

        private func handle(_ event: NSEvent) -> NSEvent? {
            guard let window, event.window === window else { return event }
            if event.type == .rotate { return handleRotate(event) }
            return handleScroll(event)
        }

        private func insideVisibleHalf(_ point: CGPoint) -> Bool {
            guard bounds.width > 8, bounds.height > 8 else { return false }
            guard point.x >= bounds.midX - 2 else { return false }
            let dx = point.x - bounds.midX
            let dy = point.y - bounds.midY
            return hypot(dx, dy) <= max(bounds.width, bounds.height) * 0.55
        }

        private func handleRotate(_ event: NSEvent) -> NSEvent? {
            let point = convert(event.locationInWindow, from: nil)
            if event.phase.contains(.began) || event.phase.contains(.mayBegin) {
                active = insideVisibleHalf(point)
            } else if !active, event.phase.isEmpty || event.phase.contains(.changed) {
                active = insideVisibleHalf(point)
            }
            guard active else { return event }
            if event.phase.contains(.cancelled) {
                active = false
                DispatchQueue.main.async { self.onFinish?(true) }
                return nil
            }
            let degrees = Double(event.rotation)
            if degrees != 0 {
                DispatchQueue.main.async { self.onTorque?(degrees) }
            }
            if event.phase.contains(.ended) {
                active = false
                DispatchQueue.main.async { self.onFinish?(false) }
            }
            return nil
        }

        private func handleScroll(_ event: NSEvent) -> NSEvent? {
            guard event.hasPreciseScrollingDeltas else { return event }
            if event.momentumPhase.contains(.changed) || event.momentumPhase.contains(.ended) {
                return event
            }
            let point = convert(event.locationInWindow, from: nil)
            if event.phase.contains(.began) || event.phase.contains(.mayBegin) {
                active = insideVisibleHalf(point)
            } else if !active {
                active = insideVisibleHalf(point)
            }
            guard active else { return event }
            if event.phase.contains(.cancelled) {
                active = false
                DispatchQueue.main.async { self.onFinish?(true) }
                return nil
            }
            let direction: CGFloat = event.isDirectionInvertedFromDevice ? 1 : -1
            let dx = direction * event.scrollingDeltaX
            let dy = direction * event.scrollingDeltaY
            let fromCenter = CGPoint(x: point.x - bounds.midX, y: point.y - bounds.midY)
            let span = max(Double(bounds.width), 120)
            let r2 = max(span * span * 0.12, 36)
            let degrees = Double(fromCenter.x * dy - fromCenter.y * dx) / r2 * (180 / .pi) * 1.35
            if abs(degrees) > 0.01 {
                DispatchQueue.main.async { self.onTorque?(degrees) }
            }
            if event.phase.contains(.ended) {
                active = false
                DispatchQueue.main.async { self.onFinish?(false) }
            }
            return nil
        }
    }
}
