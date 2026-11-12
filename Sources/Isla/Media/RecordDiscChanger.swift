import SwiftUI
import IslandCore

/// Half-clipped rotary disc selector — physical CD-changer feel.
/// Rest: tight stack. Hover: wide fan with depth. Click a disc to play.
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
    @State private var prefetchTask: Task<Void, Never>?
    /// 0 = stacked rest, 1 = fully fanned (hover / turning).
    @State private var fan: CGFloat = 0

    private let sideSlots = 4

    private var tracks: [MusicCassetteTrack] { catalog?.tracks ?? [] }

    /// Rest vs hover: spacing and orbit interpolate so the change is obvious.
    private var slotSpacing: Double { Double(18 + 44 * fan) } // 18° → 62°
    private var radius: CGFloat { diameter * (0.28 + 0.20 * fan) } // 0.28 → 0.48
    private var discSize: CGFloat { diameter * (0.26 - 0.04 * fan) }

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
                selectionTitle
                if busy {
                    ProgressView().controlSize(.small)
                        .offset(x: diameter * 0.22)
                }
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
        .onHover { inside in
            setFan(inside || turning ? 1 : 0)
        }
        .help(frontTrack.map { "\($0.title) — pasa el cursor para abrir el abanico; clic para reproducir" } ?? "Cambiador de discos")
        .task(id: "\(currentTitle ?? "")|\(currentArtist ?? "")") { await reload() }
        .onDisappear {
            snapTask?.cancel()
            prefetchTask?.cancel()
            RecordGestureClaim.selectorActive = false
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Cambiador de discos")
        .accessibilityValue(frontTrack.map(\.title) ?? "")
        .accessibilityHint("Pasa el cursor para desplegar; haz clic en un disco para reproducirlo")
        .accessibilityAdjustableAction { direction in
            switch direction {
            case .increment: nudgeSlots(1)
            case .decrement: nudgeSlots(-1)
            @unknown default: break
            }
        }
        .accessibilityAction(.default) {
            if let frontTrack { play(frontTrack) }
        }
    }

    private var ringWell: some View {
        ZStack {
            Circle()
                .strokeBorder(palette.metal.opacity(0.12 + 0.2 * fan), lineWidth: 1.2)
            // Soft well shadow so the fan reads against the panel.
            Circle()
                .fill(
                    RadialGradient(
                        colors: [.black.opacity(0.35 * fan), .clear],
                        center: .center,
                        startRadius: diameter * 0.08,
                        endRadius: diameter * 0.48
                    )
                )
        }
        .frame(width: diameter * 0.94, height: diameter * 0.94)
        .allowsHitTesting(false)
    }

    private var carousel: some View {
        let count = tracks.count
        let spacing = slotSpacing
        let orbit = radius
        let size = discSize
        return ZStack {
            ForEach(visibleEntries(count: count), id: \.index) { entry in
                let degrees = entry.delta * spacing
                let theta = degrees * .pi / 180
                // Perspective: front faces you; neighbours yaw away and shrink.
                let depth = cos(theta)
                let atFront = abs(entry.delta) < 0.45
                let yaw = degrees * (0.55 + 0.35 * Double(fan)) // stronger tilt when fanned
                let scale = atFront
                    ? 1.0 + 0.12 * fan
                    : max(0.55, 0.72 + 0.28 * depth)
                let lift = CGFloat(-abs(entry.delta)) * diameter * 0.01 * fan
                Button {
                    play(entry.track, selecting: entry.index)
                } label: {
                    ChangerDisc(
                        artwork: artworks[entry.track.id],
                        palette: palette,
                        emphasized: atFront,
                        fanned: fan > 0.4
                    )
                    .frame(width: size, height: size)
                    .rotation3DEffect(
                        .degrees(yaw),
                        axis: (x: 0, y: 1, z: 0),
                        anchor: .center,
                        anchorZ: 0,
                        perspective: 0.55
                    )
                    .scaleEffect(scale)
                    .opacity(0.4 + 0.6 * max(0.15, depth))
                    .shadow(
                        color: .black.opacity(0.25 + 0.45 * fan * max(0, depth)),
                        radius: 4 + 10 * fan,
                        x: CGFloat(sin(theta)) * 4 * fan,
                        y: 6 + 8 * fan
                    )
                }
                .buttonStyle(.plain)
                .disabled(busy)
                .offset(
                    x: orbit * cos(theta),
                    y: orbit * sin(theta) + lift
                )
                .zIndex(100 + depth * 40 - abs(entry.delta))
                .accessibilityLabel(entry.track.title)
                .accessibilityHint("Reproduce en el tocadiscos")
            }
        }
        .frame(width: diameter, height: diameter)
    }

    private var selectionTitle: some View {
        Group {
            if let frontTrack, !loading {
                let angle = -60.0 * .pi / 180
                let orbit = diameter * 0.52
                let furtherRight = diameter * 0.18
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
                .frame(width: max(100, diameter * 0.42), alignment: .leading)
                .offset(
                    x: orbit * CGFloat(cos(angle)) + furtherRight,
                    y: orbit * CGFloat(sin(angle))
                )
                .allowsHitTesting(false)
                .accessibilityHidden(true)
            }
        }
    }

    private func setFan(_ target: CGFloat) {
        let value = min(1, max(0, target))
        guard abs(fan - value) > 0.01 else { return }
        withAnimation(reduceMotion ? nil : .interpolatingSpring(stiffness: 220, damping: 22)) {
            fan = value
        }
    }

    private func play(_ track: MusicCassetteTrack, selecting index: Int? = nil) {
        setFan(1)
        if let index {
            snapTask?.cancel()
            withAnimation(reduceMotion ? nil : .snappy(duration: 0.22)) {
                cursor = Double(index)
            }
        } else {
            commitFrontSelection(animated: false)
        }
        Task {
            busy = true
            status = nil
            defer { busy = false }
            if let message = await onPlay(track, artworks[track.id]) {
                status = message
            }
        }
    }

    private struct VisibleEntry {
        let index: Int
        let delta: Double
        let track: MusicCassetteTrack
    }

    private func visibleEntries(count: Int) -> [VisibleEntry] {
        guard count > 0 else { return [] }
        var entries: [VisibleEntry] = []
        var seen = Set<Int>()
        let span = min(sideSlots, max(count / 2, 0))
        for step in -span...span {
            let index = ((Int(cursor.rounded()) + step) % count + count) % count
            guard seen.insert(index).inserted else { continue }
            let delta = shortestIndexDelta(Double(index) - cursor, count: count)
            guard abs(delta) <= Double(sideSlots) + 0.6 else { continue }
            entries.append(VisibleEntry(index: index, delta: delta, track: tracks[index]))
        }
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
        setFan(1)
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
            cursor += degrees / max(slotSpacing, 1)
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
        setFan(0)
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
            // Eagerly warm every cover so the fan never shows blank vinyl.
            prefetchAllCovers()
        } catch {
            catalog = nil
            self.error = error.localizedDescription
        }
    }

    private func nudgeSlots(_ delta: Int) {
        guard !tracks.isEmpty, delta != 0 else { return }
        snapTask?.cancel()
        setFan(1)
        let count = tracks.count
        let next = ((Int(cursor.rounded()) + delta) % count + count) % count
        withAnimation(reduceMotion ? nil : .snappy(duration: 0.28)) {
            cursor = Double(next)
        }
    }

    /// Fetch artwork for the entire changer catalog (bounded concurrency).
    private func prefetchAllCovers() {
        prefetchTask?.cancel()
        let pending = tracks.filter { artworks[$0.id] == nil }
        guard !pending.isEmpty else { return }
        let service = service
        prefetchTask = Task { @MainActor in
            await withTaskGroup(of: (String, NSImage?).self) { group in
                var iterator = pending.makeIterator()
                let workers = min(6, pending.count)
                for _ in 0..<workers {
                    guard let track = iterator.next() else { break }
                    let trackID = track.id
                    group.addTask {
                        let data = try? await service.artwork(trackID: trackID)
                        return (trackID, data.flatMap(NSImage.init(data:)))
                    }
                }
                while let (id, image) = await group.next() {
                    if Task.isCancelled { break }
                    if let image { artworks[id] = image }
                    if let track = iterator.next() {
                        let trackID = track.id
                        group.addTask {
                            let data = try? await service.artwork(trackID: trackID)
                            return (trackID, data.flatMap(NSImage.init(data:)))
                        }
                    }
                }
            }
        }
    }
}

private struct ChangerDisc: View {
    let artwork: NSImage?
    let palette: RecordPlayerPalette
    let emphasized: Bool
    var fanned: Bool = false

    var body: some View {
        ZStack {
            // Disc edge / thickness hint.
            Circle()
                .fill(Color(white: 0.02))
                .offset(x: fanned ? 2.5 : 1, y: fanned ? 2 : 1)
            Circle()
                .fill(Color(white: 0.07))
            if let artwork {
                Image(nsImage: artwork)
                    .resizable()
                    .scaledToFill()
            } else {
                Circle()
                    .fill(
                        RadialGradient(
                            colors: [Color(white: 0.18), Color(white: 0.05)],
                            center: .center,
                            startRadius: 2,
                            endRadius: 48
                        )
                    )
            }
            // Vinyl sheen.
            Circle()
                .fill(
                    AngularGradient(
                        colors: [
                            .white.opacity(0.0),
                            .white.opacity(emphasized ? 0.18 : 0.06),
                            .white.opacity(0.0),
                            .white.opacity(emphasized ? 0.1 : 0.03),
                            .white.opacity(0.0),
                        ],
                        center: .center
                    )
                )
                .blendMode(.screen)
            Circle()
                .strokeBorder(
                    LinearGradient(
                        colors: [.white.opacity(emphasized ? 0.55 : 0.22), .white.opacity(0.05)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ),
                    lineWidth: emphasized ? 1.6 : 0.8
                )
            // Spindle hole.
            Circle()
                .fill(.black)
                .frame(width: emphasized ? 11 : 9, height: emphasized ? 11 : 9)
                .overlay(Circle().strokeBorder(.white.opacity(0.35), lineWidth: 0.7))
        }
        .clipShape(Circle())
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
