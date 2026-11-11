import SwiftUI

// Mouse left-drag spin was removed: the platter turns with two fingers on the trackpad
// (see `RecordPlatterGestures`). This file stays so older call sites fail loudly at compile
// time if reintroduced without an explicit design review.
enum RecordSpinGestureUnavailable {
    static let reason = "Use RecordPlatterGestures for two-finger spin."
}
