import SwiftUI
import IslandCore

/// Half-clipped rotary disc selector on the window’s leading edge — no boxed panel.
/// Spins a **stable ordered** playlist ring with a short evenly spaced visible arc;
/// the main turntable never changes until Play.
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
    /// Continuous cursor in playlist-index space. Integer = snapped front track.
    @State private var cursor = 0.0
    @State private var artworks: [String: NSImage] = [:]
    @State private var busy = false
    @State private var status: String?
    @State private var turning = false
    @State private var turnOrigin = 0.0
    @State private var samples: [(Date, Double)] = []
    @State private var dragLastAngle: Double?
    @State private var snapTask: Task<Void, Never>?

    /// Fixed visual gap between neighbours — never pack the whole playlist onto 360°.
    private let slotSpacing = 28.0
    /// How many discs to either side of the front (7 total).
    private let sideSlots = 3
    private var radius: CGFloat { diameter * 0.34 }
    private var discSize: CGFloat { diameter * 0.24 }

    private var tracks: [MusicCassetteTrack] { catalog?.tracks ?? [] }

    /// Track at +X (middle of the visible half), including mid-spin preview.
    private var frontIndex: Int {
        guard !tracks.isEmpty else { return 0 }
        let count = tracks.count
        let moved = Int(cursor.rounded())
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
                Text(error ?? "Sin discos en la playlist")
                    .font(.caption2)
                    .foregroundStyle(palette.ink.opacity(0.65))
                    .multilineTextAlignment(.center)
                    .frame(width: diameter * 0.4)
                    .offset(x: diameter * 0.22)
            } else {
                carousel
                centerPlay
                selectionTitle
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

    /// Only a short evenly spaced arc — same playlist order, no full-ring packing.
    private var carousel: some View {
        let count = tracks.count
        return ZStack {
            ForEach(visibleEntries(count: count), id: \.index) { entry in
                let degrees = entry.delta * slotSpacing
                let theta = degrees * .pi / 180
                let depth = cos(theta)
                let atFront = abs(entry.delta) < 0.5
                ChangerDisc(
                    artwork: artworks[entry.track.id],
                    palette: palette,
                    emphasized: atFront
                )
                .frame(width: discSize, height: discSize)
                .opacity(0.35 + 0.65 * max(0.2, depth))
                .scaleEffect(atFront ? 1.06 : max(0.82, 0.92 + 0.08 * depth))
                .offset(x: radius * cos(theta), y: radius * sin(theta))
                .zIndex(depth * 10)
                .allowsHitTesting(false)
            }
        }
        .frame(width: diameter, height: diameter)
        .allowsHitTesting(false)
    }

    private var selectionTitle: some View {
        Group {
            if let frontTrack, !loading {
                // Sit outside the front disc, ~60° toward the top (not centered on the art).
                let lift = -60.0 * .pi / 180
                let clear = discSize * 0.58
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
                .foregroundStyle(.white)
                .compositingGroup()
                .blendMode(.difference)
                .frame(width: max(96, diameter * 0.4), alignment: .leading)
                .offset(
                    x: radius + clear * CGFloat(cos(lift)),
                    y: clear * CGFloat(sin(lift))
                )
                .allowsHitTesting(false)
                .accessibilityHidden(true)
            }
        }
    }

    private var centerPlay: some View {
        Button {
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

    private struct VisibleEntry {
        let index: Int
        let delta: Double
        let track: MusicCassetteTrack
    }

    private func visibleEntries(count: Int) -> [VisibleEntry] {
        guard count > 0 else { return [] }
        var entries: [VisibleEntry] = []
        // Unique playlist indices near the cursor (handles wrap + duplicates by index).
        var seen = Set<Int>()
        let span = min(sideSlots, max(count / 2, 0))
        for step in -span...span {
            let index = ((Int(cursor.rounded()) + step) % count + count) % count
            guard seen.insert(index).inserted else { continue }
            let delta = shortestIndexDelta(Double(index) - cursor, count: count)
            guard abs(delta) <= Double(sideSlots) + 0.6 else { continue }
            entries.append(VisibleEntry(index: index, delta: delta, track: tracks[index]))
        }
        // Mid-spin: also keep nearest indices by continuous delta so motion stays smooth.
        if entries.count < min(count, sideSlots * 2 + 1) {
            for index in 0..<count where !seen.contains(index) {
                let delta = shortestIndexDelta(Double(index) - cursor, count: count)
                if abs(delta) <= Double(sideSlots) + 0.6 {
                    seen.insert(index)
                    entries.append(VisibleEntry(index: index, delta: delta, track: tracks[index]))
                }
            }
        }
        return entries
    }

    private func shortestIndexDelta(_ raw: Double, count: Int) -> Double {
        guard count > 0 else { return 0 }
        var d = raw.truncatingRemainder(dividingBy: Double(count))
        if d > Double(count) / 2 { d -= Double(count) }
        if d <= -Double(count) / 2 { d += Double(count) }
        return d
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
            turnOrigin = cursor
            samples = [(Date(), cursor)]
        }
    }

    private func applyTorque(_ degrees: Double) {
        guard degrees.isFinite, degrees != 0, !tracks.isEmpty else { return }
        beginTurn()
        var transaction = Transaction()
        transaction.disablesAnimations = true
        withTransaction(transaction) {
            cursor += degrees / slotSpacing
        }
        samples.append((Date(), cursor))
        if samples.count > 12 { samples.removeFirst(samples.count - 12) }
    }

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
            cursor = turnOrigin
        }
    }

    private func commitFrontSelection(animated: Bool) {
        guard !tracks.isEmpty else {
            turning = false
            RecordGestureClaim.selectorActive = false
            return
        }
        var position = cursor
        let velocity = angularVelocity()
        if animated, !reduceMotion, abs(velocity) > 2 {
            position += velocity * 0.14
        }
        let count = tracks.count
        let next = ((Int(position.rounded()) % count) + count) % count
        let animation = (animated && !reduceMotion)
            ? Animation.interpolatingSpring(stiffness: 240, damping: 24)
            : nil
        withAnimation(animation) {
            cursor = Double(next)
        }
        turning = false
        RecordGestureClaim.selectorActive = false
        samples = []
        dragLastAngle = nil
        Task { await prefetch(around: next) }
    }

    private func angularVelocity() -> Double {
        guard samples.count >= 2, let first = samples.first, let last = samples.last else { return 0 }
        let dt = last.0.timeIntervalSince(first.0)
        guard dt > 0.02 else { return 0 }
        return (last.1 - first.1) / dt
    }

    private func reload() async {
        loading = true
        error = nil
        defer { loading = false }
        do {
            let catalog = try await service.changerCatalog()
            self.catalog = catalog
            let count = catalog.tracks.count
            if let match = catalog.tracks.firstIndex(where: {
                $0.title == currentTitle && (currentArtist == nil || currentArtist == $0.artist)
            }) {
                cursor = Double(match)
            } else {
                let current = Int(cursor.rounded())
                if count == 0 {
                    cursor = 0
                } else if current < 0 || current >= count {
                    cursor = 0
                } else {
                    cursor = Double(current)
                }
            }
            turning = false
            RecordGestureClaim.selectorActive = false
            await prefetch(around: Int(cursor.rounded()))
        } catch {
            catalog = nil
            self.error = error.localizedDescription
        }
    }

    private func nudgeSlots(_ delta: Int) {
        guard !tracks.isEmpty, delta != 0 else { return }
        snapTask?.cancel()
        let count = tracks.count
        let next = ((Int(cursor.rounded()) + delta) % count + count) % count
        withAnimation(reduceMotion ? nil : .snappy(duration: 0.28)) {
            cursor = Double(next)
        }
        Task { await prefetch(around: next) }
    }

    private func prefetch(around index: Int) async {
        guard !tracks.isEmpty else { return }
        let count = tracks.count
        for offset in -sideSlots...sideSlots {
            let track = tracks[((index + offset) % count + count) % count]
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
                .fill(Color(white: 0.07))
                .shadow(color: .black.opacity(emphasized ? 0.5 : 0.2), radius: emphasized ? 7 : 3, y: 2)
            if let artwork {
                Image(nsImage: artwork)
                    .resizable()
                    .scaledToFill()
            } else {
                // Quiet vinyl blank — never a bright “ghost” placeholder.
                Circle()
                    .fill(
                        RadialGradient(
                            colors: [Color(white: 0.16), Color(white: 0.05)],
                            center: .center,
                            startRadius: 2,
                            endRadius: 40
                        )
                    )
            }
        }
        .clipShape(Circle())
        .overlay {
            Circle().strokeBorder(.white.opacity(emphasized ? 0.35 : 0.1), lineWidth: emphasized ? 1.3 : 0.7)
        }
        .overlay {
            Circle().fill(.black).frame(width: 8, height: 8)
                .overlay(Circle().strokeBorder(.white.opacity(0.3), lineWidth: 0.6))
        }
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
            // Match inverted scroll so rotate gestures share the same sense of spin.
            let degrees = -Double(event.rotation)
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
            // Natural trackpad scroll felt inverted on the half-ring — flip torque sign.
            let direction: CGFloat = event.isDirectionInvertedFromDevice ? -1 : 1
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
