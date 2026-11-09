import CoreGraphics

public enum RecordSwipe {
    case previous, next

    public init?(translation: CGSize, diameter: CGFloat) {
        let horizontal = abs(translation.width)
        guard horizontal >= max(36, diameter * 0.13),
              horizontal > abs(translation.height) * 1.5 else { return nil }
        self = translation.width < 0 ? .next : .previous
    }
}
