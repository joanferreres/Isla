import SwiftUI
import IslandCore

struct RecordSwipeGesture: ViewModifier {
    let diameter: CGFloat
    let reduceMotion: Bool
    let trackID: String?
    let skip: (RecordSwipe, String) -> Void

    @GestureState(resetTransaction: Transaction(animation: .snappy(duration: 0.24)))
    private var translation: CGFloat = 0
    @State private var flick = 0
    @State private var direction: CGFloat = 1
    @State private var trackpadOffset: CGFloat = 0

    func body(content: Content) -> some View {
        content
            .keyframeAnimator(initialValue: CGFloat.zero, trigger: flick) { record, recoil in
                // Keep finger-following even with Reduce Motion; only the automatic recoil is optional.
                let offset = translation + trackpadOffset + (reduceMotion ? 0 : recoil * direction * diameter)
                record
                    .rotationEffect(.degrees(Double(offset / diameter) * 18))
                    .offset(x: offset)
            } keyframes: { _ in
                LinearKeyframe(0.11, duration: 0.10)
                SpringKeyframe(0, duration: 0.30, spring: .snappy)
            }
            .overlay {
                if let trackID {
                    Circle().fill(.clear)
                        .contentShape(Circle())
                        .gesture(swipeGesture(trackID: trackID))
                        .background {
                            RecordTrackpadSurface(update: { trackpadOffset = preview($0) }, finish: { distance in
                                withAnimation(reduceMotion ? nil : .snappy(duration: 0.24)) { trackpadOffset = 0 }
                                if let distance { complete(distance, trackID: trackID) }
                            })
                        }
                        .id(trackID)
                }
            }
            .onChange(of: trackID) { _, _ in trackpadOffset = 0 }
    }

    private func swipeGesture(trackID: String) -> some Gesture {
        DragGesture(minimumDistance: 10)
            .updating($translation) { value, offset, transaction in
                transaction.animation = nil
                offset = preview(value.translation)
            }
            .onEnded { value in
                complete(value.translation, trackID: trackID)
            }
    }

    private func preview(_ distance: CGSize) -> CGFloat {
        // Direct manipulation follows the fingers even with Reduce Motion enabled;
        // only the automatic recoil animation is suppressed in that mode.
        guard abs(distance.width) > abs(distance.height) else { return 0 }
        let limit = diameter * 0.12
        return max(-limit, min(limit, distance.width * 0.55))
    }

    private func complete(_ distance: CGSize, trackID: String) {
        guard let swipe = RecordSwipe(translation: distance, diameter: diameter) else { return }
        if !reduceMotion {
            direction = swipe == .next ? -1 : 1
            flick += 1
        }
        skip(swipe, trackID)
    }
}
