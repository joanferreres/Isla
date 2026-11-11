import SwiftUI
import IslandCore

/// Two-finger platter control: horizontal scrub swaps records; torque/rotate spins the disc.
/// Mouse left-drag is intentionally unused so spinning never requires a click.
struct RecordPlatterGestures: ViewModifier {
    let diameter: CGFloat
    let reduceMotion: Bool
    let trackID: String?
    let spinEnabled: Bool
    @Binding var holding: Bool
    @Binding var rotation: Double
    let onSwapPreview: (CGFloat) -> Void
    let onSwapFinish: (RecordSwipe?, String) -> Void
    let onSpinRelease: (_ degreesPerSecond: Double) -> Void

    @State private var classifier = RecordPlatterClassifier()
    @State private var samples: [(Date, Double)] = []
    @State private var spinOrigin = 0.0

    func body(content: Content) -> some View {
        content
            .background {
                RecordTrackpadSurface(
                    enabled: trackID != nil || spinEnabled,
                    onScroll: { dx, dy, location in
                        handleScroll(dx: dx, dy: dy, location: location)
                    },
                    onRotate: { degrees in
                        handleRotate(degrees)
                    },
                    onFinish: { cancelled in
                        finish(cancelled: cancelled)
                    }
                )
                .frame(width: diameter, height: diameter)
                .allowsHitTesting(false)
                .id(trackID ?? "platter")
            }
            .onChange(of: trackID) { _, _ in
                classifier.reset()
                onSwapPreview(0)
            }
    }

    private func handleScroll(dx: CGFloat, dy: CGFloat, location: CGPoint) {
        let center = CGPoint(x: diameter / 2, y: diameter / 2)
        let fromCenter = CGPoint(x: location.x - center.x, y: location.y - center.y)
        let before = classifier.mode
        classifier.addScroll(dx: dx, dy: dy, fromCenter: fromCenter, radius: diameter / 2)
        applyModeChange(from: before)
        publish()
    }

    private func handleRotate(_ degrees: Double) {
        let before = classifier.mode
        classifier.addRotation(degrees)
        applyModeChange(from: before)
        publish()
    }

    private func applyModeChange(from before: RecordPlatterMode) {
        guard classifier.mode != before else { return }
        if classifier.mode == .spin {
            if !holding {
                holding = true
                spinOrigin = rotation
                samples = [(Date(), classifier.spinDegrees)]
            }
            onSwapPreview(0)
        } else if classifier.mode == .swipe {
            if holding {
                holding = false
                rotation = spinOrigin
                samples = []
                onSpinRelease(0)
            }
        }
    }

    private func publish() {
        switch classifier.mode {
        case .undecided:
            break
        case .swipe:
            onSwapPreview(swipePreview(classifier.translation))
        case .spin:
            guard spinEnabled else { return }
            if !holding {
                holding = true
                spinOrigin = rotation
            }
            rotation = spinOrigin + classifier.spinDegrees
            let now = Date()
            samples.append((now, classifier.spinDegrees))
            samples = samples.filter { now.timeIntervalSince($0.0) <= 0.16 }
        }
    }

    private func finish(cancelled: Bool) {
        let mode = classifier.mode
        let translation = classifier.translation
        let track = trackID
        let velocity = Self.velocity(samples)
        classifier.reset()
        samples = []
        switch mode {
        case .swipe:
            onSwapPreview(0)
            if cancelled || track == nil {
                onSwapFinish(nil, track ?? "")
            } else {
                onSwapFinish(RecordSwipe(translation: translation, diameter: diameter), track!)
            }
        case .spin:
            holding = false
            onSpinRelease(cancelled || reduceMotion ? 0 : velocity)
        case .undecided:
            onSwapPreview(0)
            if holding {
                holding = false
                onSpinRelease(0)
            }
        }
    }

    private func swipePreview(_ distance: CGSize) -> CGFloat {
        guard abs(distance.width) > abs(distance.height) else { return 0 }
        let limit = diameter * 0.62
        return max(-limit, min(limit, distance.width * 0.72))
    }

    private static func velocity(_ samples: [(Date, Double)]) -> Double {
        guard let first = samples.first, let last = samples.last, samples.count >= 2 else { return 0 }
        let dt = last.0.timeIntervalSince(first.0)
        guard dt > 0.01 else { return 0 }
        return (last.1 - first.1) / dt
    }
}

// Keep the old name available for call sites that still import it conceptually.
typealias RecordSwipeGesture = RecordPlatterGestures
