import SwiftUI
import IslandCore

struct EQKnob: View {
    let title: String
    let gain: Double?
    let accent: Color
    let apply: (Double) -> Void

    @GestureState private var adjustment: Double?
    @FocusState private var focused: Bool

    private var displayedGain: Double? { adjustment ?? gain }

    var body: some View {
        HStack(spacing: 7) {
            ZStack {
                Circle().trim(from: 0, to: 0.75)
                    .stroke(.secondary.opacity(0.55), style: StrokeStyle(lineWidth: 2, lineCap: .round))
                    .rotationEffect(.degrees(135))
                Circle().fill(.linearGradient(colors: [Color(white: 0.30), Color(white: 0.08)],
                                              startPoint: .topLeading, endPoint: .bottomTrailing))
                    .strokeBorder(.white.opacity(0.28), style: StrokeStyle(lineWidth: 3, dash: [1, 1.8]))
                    .padding(4)
                    .shadow(color: .black.opacity(0.5), radius: 1, y: 2)
                Capsule().fill(accent)
                    .frame(width: 3, height: 12)
                    .offset(y: -17)
                    .rotationEffect(.degrees((displayedGain ?? 0) * 11.25))
                if focused, adjustment == nil {
                    Circle().strokeBorder(accent.opacity(0.65), lineWidth: 1.5)
                }
            }
            .frame(width: 54, height: 54)
            .frame(width: 60, height: 60)
            .contentShape(Rectangle())
            .gesture(DragGesture(minimumDistance: 3)
                .updating($adjustment) { drag, preview, _ in
                    // Snap the preview to whole dB so releasing never visually
                    // jumps from a fractional drag back to the committed value.
                    preview = min(12, max(-12, (gain ?? 0) + delta(drag.translation))).rounded()
                }
                .onEnded { drag in
                    let target = min(12, max(-12, (gain ?? 0) + delta(drag.translation))).rounded()
                    if target != gain { apply(target) }
                })
            .onTapGesture(count: 2) { apply(0) }
            .focusable()
            .focusEffectDisabled()
            .focused($focused)
            .onMoveCommand { direction in
                switch direction {
                case .up, .right: apply(min(12, (gain ?? 0).rounded() + 1))
                case .down, .left: apply(max(-12, (gain ?? 0).rounded() - 1))
                @unknown default: break
                }
            }
            VStack(alignment: .leading, spacing: 1) {
                Text(title).font(.callout.weight(.medium))
                Text(Self.label(displayedGain))
                    .font(.caption2.monospacedDigit())
                    .foregroundStyle(adjustment == nil ? .secondary : accent)
            }
            .frame(width: 48, alignment: .leading)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(title)
        .accessibilityValue(displayedGain.map { "\(Int($0)) decibelios" } ?? "No disponible")
        .accessibilityAdjustableAction { direction in
            switch direction {
            case .increment: apply(min(12, (gain ?? 0) + 1))
            case .decrement: apply(max(-12, (gain ?? 0) - 1))
            @unknown default: break
            }
        }
    }

    static func label(_ gain: Double?) -> String {
        guard let gain else { return "—" }
        let whole = Int(gain.rounded())
        return whole > 0 ? "+\(whole) dB" : "\(whole) dB"
    }

    private func delta(_ translation: CGSize) -> Double {
        (translation.width - translation.height) / 6
    }
}
