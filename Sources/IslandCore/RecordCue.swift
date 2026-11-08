import Foundation
import CoreGraphics

public enum RecordCue {
    // Coordinates are in units of the record diameter, with y increasing downwards.
    public static let pivot = CGPoint(x: 1.025, y: 0.145)
    public static let needle = CGPoint(x: 1.008, y: 0.876)
    public static let armWidth = 1.13

    public static func angle(at progress: Double) -> Double {
        18 + 24 * min(1, max(0, progress))
    }

    public static func tip(at angle: Double) -> CGPoint {
        let radians = angle * .pi / 180
        let x = needle.x - pivot.x
        let y = needle.y - pivot.y
        return CGPoint(x: pivot.x + x * cos(radians) - y * sin(radians),
                       y: pivot.y + x * sin(radians) + y * cos(radians))
    }

    public static func progress(at point: CGPoint) -> Double? {
        guard hypot(point.x - 0.5, point.y - 0.5) <= 0.5 else { return nil }
        let target = atan2(point.y - pivot.y, point.x - pivot.x)
        let resting = atan2(needle.y - pivot.y, needle.x - pivot.x)
        let degrees = atan2(sin(target - resting), cos(target - resting)) * 180 / .pi
        return min(1, max(0, (degrees - 18) / 24))
    }
}
