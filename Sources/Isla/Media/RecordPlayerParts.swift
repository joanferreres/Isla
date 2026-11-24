import SwiftUI
import IslandCore

// Piezas visuales del tocadiscos: cristal, ondas, vinilo y brazo.

@available(macOS 26.0, *)
struct RecordPlaybackGlass<Content: View>: NSViewRepresentable {
    let content: Content

    func makeNSView(context: Context) -> NSGlassEffectView {
        let glass = NSGlassEffectView()
        glass.style = .clear
        glass.cornerRadius = 28
        if #available(macOS 27.0, *) { glass.effectIsInteractive = true }
        let controls = NSHostingView(rootView: content)
        controls.autoresizingMask = [.width, .height]
        glass.contentView = controls
        return glass
    }

    func updateNSView(_ glass: NSGlassEffectView, context: Context) {
        (glass.contentView as? NSHostingView<Content>)?.rootView = content
    }

    func sizeThatFits(_ proposal: ProposedViewSize, nsView: NSGlassEffectView, context: Context) -> CGSize? {
        let fittingHeight = nsView.contentView?.fittingSize.height ?? 0
        return CGSize(width: min(proposal.width ?? 560, 560), height: max(56, fittingHeight))
    }
}

struct RecordSoundWaves: View {
    let diameter: CGFloat
    let elapsed: Double
    let accent: Color

    // Each ring reuses the same outline. Only its size, angle and opacity change.
    private static let outline = Path { path in
        for sample in 0..<96 {
            let angle = Double(sample) * 2 * .pi / 96
            let radius = 1 + 0.007 * (sin(9 * angle) + 0.45 * sin(13 * angle))
            let point = CGPoint(x: radius * cos(angle), y: radius * sin(angle))
            if sample == 0 { path.move(to: point) } else { path.addLine(to: point) }
        }
        path.closeSubpath()
    }

    var body: some View {
        Canvas { context, size in
            let center = CGPoint(x: size.width / 2, y: size.height / 2)
            let cycle = elapsed / 3.2
            for index in 0..<3 {
                let offset = cycle + Double(index) / 3
                let phase = offset.truncatingRemainder(dividingBy: 1)
                let radius = diameter * (0.501 + 0.092 * phase)
                let opacity = sin(.pi * phase) * (1 - 0.55 * phase)
                let transform = CGAffineTransform(translationX: center.x, y: center.y)
                    .rotated(by: phase * 2 * .pi / 9)
                    .scaledBy(x: radius, y: radius)
                let wave = Self.outline.applying(transform)
                context.stroke(wave, with: .color(accent.opacity(0.56 * opacity)), lineWidth: 1.15)
            }
        }
    }
}

struct VinylRecord: View {
    let artwork: NSImage?
    let palette: RecordPlayerPalette
    let rotation: Double

    var body: some View {
        GeometryReader { proxy in
            let size = proxy.size.width
            ZStack {
                Circle().fill(palette.vinyl)
                Canvas { context, dimensions in
                    let center = CGPoint(x: dimensions.width / 2, y: dimensions.height / 2)
                    for index in 0..<44 {
                        let radius = size * (0.195 + Double(index) * 0.00675)
                        let ring = CGRect(x: center.x - radius, y: center.y - radius, width: radius * 2, height: radius * 2)
                        context.stroke(Path(ellipseIn: ring), with: .color(.white.opacity(index.isMultiple(of: 7) ? 0.18 : 0.064)), lineWidth: 0.65)
                    }
                }
                Circle().strokeBorder(.white.opacity(0.16), lineWidth: 1)
                Group {
                    if let artwork {
                        Image(nsImage: artwork).resizable().scaledToFill()
                    } else {
                        Circle().fill(palette.accent.opacity(0.78))
                            .overlay(Circle().strokeBorder(.black.opacity(0.30), lineWidth: 1).padding(size * 0.04))
                    }
                }
                .frame(width: size * 0.36, height: size * 0.36)
                .clipShape(Circle())
                .overlay(Circle().strokeBorder(.black.opacity(0.45), lineWidth: 1))
                Circle().fill(.black).frame(width: size * 0.022, height: size * 0.022)
                    .overlay(Circle().strokeBorder(.white.opacity(0.3), lineWidth: 1))
            }
            // Rotate the whole platter so the label and grooves move together.
            .rotationEffect(.degrees(rotation))
        }
    }
}

struct Tonearm: View {
    let angle: Double
    let trackID: String?
    let playing: Bool
    let progress: Double
    let canSeek: Bool
    let palette: RecordPlayerPalette
    let animation: Animation?
    let tap: () -> Void
    let drop: (Double?) -> Void
    @GestureState private var dragPoint: CGPoint?

    var body: some View {
        let cueAngle = dragPoint.map(RecordCue.angle(toward:)) ?? angle
        return Canvas { context, size in
            let d = size.height
            let pivot = CGPoint(x: d * RecordCue.pivot.x, y: d * RecordCue.pivot.y)
            let elbow = CGPoint(x: d * 1.047, y: d * 0.64)
            let tip = CGPoint(x: d * RecordCue.needle.x, y: d * RecordCue.needle.y)
            let metal = palette.metal
            func circle(_ center: CGPoint, _ radius: CGFloat) -> Path {
                Path(ellipseIn: CGRect(x: center.x - radius, y: center.y - radius, width: radius * 2, height: radius * 2))
            }
            var arm = Path(); arm.move(to: pivot)
            arm.addQuadCurve(to: elbow, control: CGPoint(x: d * 1.057, y: d * 0.53))
            arm.addLine(to: tip)
            context.stroke(arm, with: .color(.black.opacity(0.5)), style: StrokeStyle(lineWidth: d * 0.022, lineCap: .round, lineJoin: .round))
            context.stroke(arm, with: .color(metal), style: StrokeStyle(lineWidth: d * 0.010, lineCap: .round, lineJoin: .round))
            context.fill(circle(pivot, d * 0.042), with: .color(Color(white: 0.17)))
            context.stroke(circle(pivot, d * 0.034), with: .color(metal), lineWidth: 1)
            context.fill(circle(pivot, d * 0.012), with: .color(palette.accent))
            let cartridge = CGRect(x: tip.x - d * 0.015, y: tip.y - d * 0.038, width: d * 0.03, height: d * 0.046)
            context.fill(Path(roundedRect: cartridge, cornerRadius: d * 0.004), with: .color(metal))
            context.fill(circle(tip, d * 0.007), with: .color(palette.accent))
        }
        .rotationEffect(.degrees(cueAngle), anchor: UnitPoint(x: RecordCue.pivot.x / RecordCue.armWidth, y: RecordCue.pivot.y))
        .animation(dragPoint == nil ? animation : nil, value: dragPoint == nil)
        .animation(dragPoint == nil ? animation : nil, value: trackID)
        .animation(dragPoint == nil ? animation : nil, value: playing)
        .accessibilityHidden(true)
        .allowsHitTesting(false)
        .overlay {
            if let trackID {
                GeometryReader { proxy in
                    let d = proxy.size.height
                    let tip = RecordCue.tip(at: cueAngle)
                    Button(action: tap) {
                        Color.clear.frame(width: 44, height: 44).contentShape(Circle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(playing ? "Levantar la aguja y pausar" : "Bajar la aguja y reproducir")
                    .accessibilityAdjustableAction { direction in
                        guard canSeek else { return }
                        switch direction {
                        case .increment: drop(min(1, progress + 0.05))
                        case .decrement: drop(max(0, progress - 0.05))
                        @unknown default: break
                        }
                    }
                    .help(canSeek ? "Arrastra la aguja a otro surco para saltar a ese punto" : "Pulsa para pausar o reproducir")
                    .highPriorityGesture(
                        DragGesture(minimumDistance: 6, coordinateSpace: .named("recordCue"))
                            .updating($dragPoint) { value, point, _ in
                                if canSeek { point = CGPoint(x: value.location.x / d, y: value.location.y / d) }
                            }
                            .onEnded { value in
                                guard canSeek else { return }
                                drop(RecordCue.progress(at: CGPoint(x: value.location.x / d, y: value.location.y / d)))
                            }
                    )
                    .position(x: d * tip.x, y: d * tip.y)
                }
                .id(trackID)
            }
        }
        .coordinateSpace(name: "recordCue")
    }
}
