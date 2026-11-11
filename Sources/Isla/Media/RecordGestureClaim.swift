import Foundation

/// Coordinates overlapping two-finger monitors so the half-disc selector
/// can claim trackpad input without also scrubbing the main turntable.
@MainActor enum RecordGestureClaim {
    static var selectorActive = false
}
