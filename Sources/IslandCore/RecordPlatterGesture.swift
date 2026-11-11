import CoreGraphics

/// Locks a two-finger trackpad gesture to either a linear disc change or a platter spin.
public enum RecordPlatterMode: Equatable, Sendable {
    case undecided, swipe, spin
}

public struct RecordPlatterClassifier: Equatable, Sendable {
    public var mode: RecordPlatterMode = .undecided
    public var translation: CGSize = .zero
    public var spinDegrees: Double = 0

    public init() {}

    /// Scroll deltas in view space, with the finger location relative to the disc centre.
    public mutating func addScroll(dx: CGFloat, dy: CGFloat, fromCenter: CGPoint, radius: CGFloat) {
        translation.width += dx
        translation.height += dy
        let r2 = max(Double(radius * radius) * 0.22, 64)
        // Tangential torque: rubbing around the centre turns the platter.
        spinDegrees += Double(fromCenter.x * dy - fromCenter.y * dx) / r2 * (180 / .pi)
        lockIfReady(radius: radius)
    }

    /// Native two-finger rotate gesture (degrees since the previous event).
    public mutating func addRotation(_ degrees: Double) {
        guard degrees.isFinite else { return }
        spinDegrees += degrees
        if mode == .undecided, abs(spinDegrees) >= 2.5 {
            mode = .spin
        }
    }

    public mutating func reset() {
        self = RecordPlatterClassifier()
    }

    private mutating func lockIfReady(radius: CGFloat) {
        guard mode == .undecided else { return }
        let swipeScore = abs(translation.width)
        let vertical = abs(translation.height)
        let spinScore = abs(spinDegrees) * Double(max(18, radius * 0.045))
        let threshold = max(12.0, Double(radius) * 0.028)
        guard max(Double(swipeScore), spinScore) >= threshold else { return }
        // A clearly horizontal two-finger pan always changes records, even when the
        // finger path also produces some tangential torque over the label.
        if swipeScore > vertical * 1.35, Double(swipeScore) >= threshold {
            mode = .swipe
        } else if spinScore >= Double(swipeScore) {
            mode = .spin
        } else {
            mode = .swipe
        }
    }
}
