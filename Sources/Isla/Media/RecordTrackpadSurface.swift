import AppKit
import SwiftUI
import IslandCore

/// Precise trackpad input over the platter: pan for disc changes, torque/rotate for spinning.
struct RecordTrackpadSurface: NSViewRepresentable {
    var enabled: Bool
    var onScroll: (_ dx: CGFloat, _ dy: CGFloat, _ locationInView: CGPoint) -> Void
    var onRotate: (_ degrees: Double) -> Void
    var onFinish: (_ cancelled: Bool) -> Void

    func makeNSView(context: Context) -> Surface { Surface() }

    func updateNSView(_ view: Surface, context: Context) {
        view.enabled = enabled
        view.onScroll = onScroll
        view.onRotate = onRotate
        view.onFinish = onFinish
    }

    static func dismantleNSView(_ view: Surface, coordinator: ()) {
        view.stop()
    }

    final class Surface: NSView {
        var enabled = true
        var onScroll: ((CGFloat, CGFloat, CGPoint) -> Void)?
        var onRotate: ((Double) -> Void)?
        var onFinish: ((Bool) -> Void)?
        private var monitor: Any?
        private var active = false

        override func hitTest(_ point: NSPoint) -> NSView? { nil }

        override func viewWillMove(toWindow newWindow: NSWindow?) {
            stop()
            super.viewWillMove(toWindow: newWindow)
        }

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            guard window != nil, monitor == nil else { return }
            monitor = NSEvent.addLocalMonitorForEvents(matching: [.scrollWheel, .rotate]) { [weak self] event in
                self?.handle(event)
                return event
            }
        }

        func stop() {
            if active {
                active = false
                onFinish?(true)
            }
            if let monitor { NSEvent.removeMonitor(monitor) }
            monitor = nil
        }

        private func handle(_ event: NSEvent) {
            guard enabled, let window, event.window === window else { return }
            if event.type == .rotate {
                handleRotate(event)
                return
            }
            handleScroll(event)
        }

        private func handleRotate(_ event: NSEvent) {
            let point = convert(event.locationInWindow, from: nil)
            let inside = hypot(point.x - bounds.midX, point.y - bounds.midY) <= bounds.width / 2
            if event.phase.contains(.began) || event.phase.contains(.mayBegin) {
                active = inside
            }
            guard active else { return }
            if event.phase.contains(.cancelled) {
                active = false
                onFinish?(true)
                return
            }
            let degrees = Double(event.rotation)
            if degrees != 0 { onRotate?(degrees) }
            if event.phase.contains(.ended) {
                active = false
                onFinish?(false)
            }
        }

        private func handleScroll(_ event: NSEvent) {
            guard event.hasPreciseScrollingDeltas, event.momentumPhase.isEmpty else { return }
            if event.phase.contains(.began) || event.phase.contains(.mayBegin) || !active {
                let point = convert(event.locationInWindow, from: nil)
                let inside = hypot(point.x - bounds.midX, point.y - bounds.midY) <= bounds.width / 2
                if !active { active = inside }
                if event.phase.contains(.began) || event.phase.contains(.mayBegin) {
                    active = inside
                }
            }
            guard active else { return }
            if event.phase.contains(.cancelled) {
                active = false
                onFinish?(true)
                return
            }
            let direction: CGFloat = event.isDirectionInvertedFromDevice ? 1 : -1
            let dx = direction * event.scrollingDeltaX
            let dy = direction * event.scrollingDeltaY
            let point = convert(event.locationInWindow, from: nil)
            if dx != 0 || dy != 0 { onScroll?(dx, dy, point) }
            if event.phase.contains(.ended) {
                active = false
                onFinish?(false)
            }
        }
    }
}
