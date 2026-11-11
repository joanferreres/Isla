import SwiftUI
import IslandCore

/// Half-clipped rotary disc selector on the window’s leading edge — no boxed panel.
/// Two-finger torque / rotate spins the ring around its centre like a turntable.
/// The disc at +X (middle of the visible right half) is selected; Play loads it.
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
    /// Index of the track parked at the +X “front” slot (middle of the visible half).
    @State private var selected = 0
    /// Continuous ring angle in degrees. 0 = selected track at +X.
    @State private var ringAngle = 0.0
    @State private var artworks: [String: NSImage] = [:]
    @State private var busy = false
    @State private var status: String?
    @State private var turning = false
    @State private var turnOrigin = 0.0
    @State private var samples: [(Date, Double)] = []
    @State private var dragLastAngle: Double?

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
        // Full-size invisible turn surface — offsets alone never expand layout, so this
        // must be an explicit diameter×diameter sibling (not a .background of offset discs).
        .background {
            ChangerTurnSurface(
                onTorque: { degrees in applyTorque(degrees) },
                onFinish: { cancelled in finishTurn(cancelled: cancelled) }
            )
            .frame(width: diameter, height: diameter)
            .allowsHitTesting(false)
        }
        .gesture(angularDrag)
        .contentShape(Path(CGRect(x: diameter * 0.5, y: 0, width: diameter * 0.5, height: diameter)))
        .help(selectedTrack.map { "\($0.title) — gira con dos dedos" } ?? "Cambiador de discos")
        .task(id: "\(currentTitle ?? "")|\(currentArtist ?? "")") { await reload() }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Cambiador de discos")
        .accessibilityValue(selectedTrack.map(\.title) ?? "")
        .accessibilityHint("Gira con dos dedos; el disco de la derecha es el seleccionado")
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
                    let angle = (Double(index) * step + ringAngle) * .pi / 180
                    Circle()
                        .strokeBorder(Color.white.opacity(0.04), lineWidth: 1)
                        .frame(width: discSize + 6, height: discSize + 6)
                        .offset(x: radius * cos(angle), y: radius * sin(angle))
                }
            }
            .allowsHitTesting(false)
    }

    private var carousel: some View {
        let visible = min(slotCount, max(tracks.count, 0))
        return ZStack {
            ForEach(0..<visible, id: \.self) { slot in
                let track = tracks[(selected + slot) % tracks.count]
                // θ=0 → +X (into the player) = middle of the visible right half.
                let theta = (Double(slot) * step + ringAngle) * .pi / 180
                let depth = max(0.12, cos(theta))
                let atFront = abs(shortest(Double(slot) * step + ringAngle)) < step * 0.4
                ChangerDisc(
                    artwork: artworks[track.id],
                    palette: palette,
                    emphasized: atFront && !turning
                )
                .frame(width: discSize, height: discSize)
                .opacity(0.28 + 0.72 * depth)
                .offset(x: radius * cos(theta), y: radius * sin(theta))
                .zIndex(depth * 10)
                .allowsHitTesting(false)
                .id("\(slot)-\(track.id)")
            }
        }
        .frame(width: diameter, height: diameter)
        .allowsHitTesting(false)
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
        .accessibilityHint("Reproduce el disco de la derecha y lo pone en el tocadiscos")
        .zIndex(50)
    }

    private var angularDrag: some Gesture {
        DragGesture(minimumDistance: 2)
            .onChanged { value in
                // Only drag on the visible half.
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
                finishTurn(cancelled: false)
            }
    }

    private func beginTurn() {
        if !turning {
            turning = true
            turnOrigin = ringAngle
            samples = [(Date(), ringAngle)]
        }
    }

    private func applyTorque(_ degrees: Double) {
        guard degrees.isFinite, degrees != 0, !tracks.isEmpty else { return }
        beginTurn()
        // Live follow — no animation lag so the ring tracks the fingers.
        var transaction = Transaction()
        transaction.disablesAnimations = true
        withTransaction(transaction) {
            ringAngle += degrees
        }
        samples.append((Date(), ringAngle))
        if samples.count > 12 { samples.removeFirst(samples.count - 12) }
    }

    private func finishTurn(cancelled: Bool) {
        defer {
            turning = false
            samples = []
            dragLastAngle = nil
        }
        guard !tracks.isEmpty else {
            ringAngle = turnOrigin
            return
        }
        if cancelled {
            withAnimation(reduceMotion ? nil : .snappy(duration: 0.2)) {
                ringAngle = turnOrigin
            }
            return
        }
        var angle = ringAngle
        let velocity = angularVelocity()
        if !reduceMotion, abs(velocity) > 60 {
            angle += velocity * 0.16
        }
        // Negative angle advances selection (clockwise when +X is front).
        let slotsMoved = (-angle / step).rounded()
        let count = tracks.count
        let next = ((selected + Int(slotsMoved)) % count + count) % count
        let animation = reduceMotion ? nil : Animation.interpolatingSpring(stiffness: 240, damping: 24)
        withAnimation(animation) {
            selected = next
            ringAngle = 0
        }
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
            self.catalog = catalog
            if let match = catalog.tracks.firstIndex(where: {
                $0.title == currentTitle && (currentArtist == nil || currentArtist == $0.artist)
            }) {
                selected = match
            } else {
                selected = 0
            }
            ringAngle = 0
            turning = false
            await prefetch(around: selected)
        } catch {
            catalog = nil
            self.error = error.localizedDescription
        }
    }

    private func nudgeSlots(_ delta: Int) {
        guard !tracks.isEmpty, delta != 0 else { return }
        let count = tracks.count
        withAnimation(reduceMotion ? nil : .snappy(duration: 0.28)) {
            selected = ((selected + delta) % count + count) % count
            ringAngle = 0
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

/// Full-diameter trackpad surface: scroll torque + rotate around the ring centre.
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
                self?.handle(event)
                return event
            }
        }

        func stop() {
            if active {
                active = false
                onFinish?(true)
            }
            if let monitor { NSEvent.removeMonitor(monitor) }
            monitor = nil
        }

        private func handle(_ event: NSEvent) {
            guard let window, event.window === window else { return }
            if event.type == .rotate {
                handleRotate(event)
            } else {
                handleScroll(event)
            }
        }

        /// Visible half = right half of this diameter×diameter view (into the player).
        private func insideVisibleHalf(_ point: CGPoint) -> Bool {
            guard bounds.width > 8, bounds.height > 8 else { return false }
            guard point.x >= bounds.midX - 2 else { return false }
            let dx = point.x - bounds.midX
            let dy = point.y - bounds.midY
            return hypot(dx, dy) <= max(bounds.width, bounds.height) * 0.55
        }

        private func handleRotate(_ event: NSEvent) {
            let point = convert(event.locationInWindow, from: nil)
            if event.phase.contains(.began) || event.phase.contains(.mayBegin) {
                active = insideVisibleHalf(point)
            } else if !active, event.phase.isEmpty || event.phase.contains(.changed) {
                active = insideVisibleHalf(point)
            }
            guard active else { return }
            if event.phase.contains(.cancelled) {
                active = false
                DispatchQueue.main.async { self.onFinish?(true) }
                return
            }
            let degrees = Double(event.rotation)
            if degrees != 0 {
                DispatchQueue.main.async { self.onTorque?(degrees) }
            }
            if event.phase.contains(.ended) {
                active = false
                DispatchQueue.main.async { self.onFinish?(false) }
            }
        }

        private func handleScroll(_ event: NSEvent) {
            guard event.hasPreciseScrollingDeltas else { return }
            // Allow light momentum so a flick still feels physical; ignore heavy coast.
            if event.momentumPhase.contains(.changed) || event.momentumPhase.contains(.ended) {
                return
            }
            let point = convert(event.locationInWindow, from: nil)
            if event.phase.contains(.began) || event.phase.contains(.mayBegin) {
                active = insideVisibleHalf(point)
            } else if !active {
                active = insideVisibleHalf(point)
            }
            guard active else { return }
            if event.phase.contains(.cancelled) {
                active = false
                DispatchQueue.main.async { self.onFinish?(true) }
                return
            }
            let direction: CGFloat = event.isDirectionInvertedFromDevice ? 1 : -1
            let dx = direction * event.scrollingDeltaX
            let dy = direction * event.scrollingDeltaY
            let fromCenter = CGPoint(x: point.x - bounds.midX, y: point.y - bounds.midY)
            let span = max(Double(bounds.width), 120)
            let r2 = max(span * span * 0.12, 36)
            // Tangential torque; gain bumped so the half-ring feels as lively as the platter.
            let degrees = Double(fromCenter.x * dy - fromCenter.y * dx) / r2 * (180 / .pi) * 1.35
            if abs(degrees) > 0.01 {
                DispatchQueue.main.async { self.onTorque?(degrees) }
            }
            if event.phase.contains(.ended) {
                active = false
                DispatchQueue.main.async { self.onFinish?(false) }
            }
        }
    }
}
