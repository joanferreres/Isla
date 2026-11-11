import SwiftUI

/// Left-button drag that turns the platter around its centre, like holding a real record.
/// Auto-spin pauses while the disc is held; audio keeps playing. Tonearm seeking stays separate.
struct RecordSpinGesture: ViewModifier {
    let diameter: CGFloat
    let enabled: Bool
    let reduceMotion: Bool
    @Binding var holding: Bool
    @Binding var rotation: Double
    var onRelease: (_ degreesPerSecond: Double) -> Void

    @State private var lastAngle: Double?
    @State private var samples: [(Date, Double)] = []

    @ViewBuilder func body(content: Content) -> some View {
        // Regular gesture so the tonearm tip (high-priority) still wins for seeking.
        if enabled {
            content.gesture(drag)
        } else {
            content
        }
    }

    private var drag: some Gesture {
        DragGesture(minimumDistance: 2, coordinateSpace: .named("recordPlatter"))
            .onChanged { value in
                let center = CGPoint(x: diameter / 2, y: diameter / 2)
                let degrees = Self.degrees(from: value.location, center: center)
                let now = Date()
                if !holding {
                    holding = true
                    lastAngle = degrees
                    samples = [(now, degrees)]
                    return
                }
                guard let previous = lastAngle else {
                    lastAngle = degrees
                    samples = [(now, degrees)]
                    return
                }
                rotation += Self.shortestDelta(from: previous, to: degrees)
                lastAngle = degrees
                samples.append((now, degrees))
                samples = samples.filter { now.timeIntervalSince($0.0) <= 0.16 }
            }
            .onEnded { _ in
                let velocity = Self.velocity(samples)
                lastAngle = nil
                samples = []
                holding = false
                onRelease(reduceMotion ? 0 : velocity)
            }
    }

    private static func degrees(from point: CGPoint, center: CGPoint) -> Double {
        atan2(point.y - center.y, point.x - center.x) * 180 / .pi
    }

    private static func shortestDelta(from previous: Double, to current: Double) -> Double {
        var delta = current - previous
        if delta > 180 { delta -= 360 }
        if delta < -180 { delta += 360 }
        return delta
    }

    private static func velocity(_ samples: [(Date, Double)]) -> Double {
        guard let first = samples.first, let last = samples.last, samples.count >= 2 else { return 0 }
        let dt = last.0.timeIntervalSince(first.0)
        guard dt > 0.01 else { return 0 }
        return shortestDelta(from: first.1, to: last.1) / dt
    }
}
