import SwiftUI
import IslandCore

/// Two-finger trackpad scrub across the platter. Mouse drags are left to `RecordSpinGesture`.
struct RecordSwipeGesture: ViewModifier {
    let diameter: CGFloat
    let trackID: String?
    let onPreview: (CGFloat) -> Void
    let onFinish: (RecordSwipe?, String) -> Void

    func body(content: Content) -> some View {
        content
            .background {
                if let trackID {
                    RecordTrackpadSurface(
                        update: { distance in
                            onPreview(preview(distance))
                        },
                        finish: { distance in
                            if let distance {
                                onFinish(RecordSwipe(translation: distance, diameter: diameter), trackID)
                            } else {
                                onFinish(nil, trackID)
                            }
                        }
                    )
                    .frame(width: diameter, height: diameter)
                    .allowsHitTesting(false)
                    .id(trackID)
                }
            }
            .onChange(of: trackID) { _, _ in onPreview(0) }
    }

    private func preview(_ distance: CGSize) -> CGFloat {
        guard abs(distance.width) > abs(distance.height) else { return 0 }
        // Long enough travel to reveal the incoming platter during the gesture.
        let limit = diameter * 0.62
        return max(-limit, min(limit, distance.width * 0.72))
    }
}
