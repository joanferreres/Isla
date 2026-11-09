import AppKit
import SwiftUI

/// Listens only to precise scrolling that starts over the record in its own window.
struct RecordTrackpadSurface: NSViewRepresentable {
    let update: (CGSize) -> Void
    let finish: (CGSize?) -> Void

    func makeNSView(context: Context) -> Surface { Surface() }

    func updateNSView(_ view: Surface, context: Context) {
        view.update = update
        view.finish = finish
    }

    static func dismantleNSView(_ view: Surface, coordinator: ()) {
        view.stop()
    }

    final class Surface: NSView {
        var update: ((CGSize) -> Void)?
        var finish: ((CGSize?) -> Void)?
        private var monitor: Any?
        private var distance: CGSize?

        override func hitTest(_ point: NSPoint) -> NSView? { nil }

        override func viewWillMove(toWindow newWindow: NSWindow?) {
            stop()
            super.viewWillMove(toWindow: newWindow)
        }

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            guard window != nil, monitor == nil else { return }
            monitor = NSEvent.addLocalMonitorForEvents(matching: .scrollWheel) { [weak self] event in
                self?.handle(event)
                return event
            }
        }

        func stop() {
            if let monitor { NSEvent.removeMonitor(monitor) }
            monitor = nil
            distance = nil
        }

        private func handle(_ event: NSEvent) {
            guard let window, event.window === window, window.isKeyWindow,
                  event.hasPreciseScrollingDeltas, event.momentumPhase.isEmpty else { return }
            if event.phase.contains(.began) {
                let point = convert(event.locationInWindow, from: nil)
                let inside = hypot(point.x - bounds.midX, point.y - bounds.midY) <= bounds.width / 2
                distance = inside ? .zero : nil
            }
            guard var distance else { return }
            if event.phase.contains(.cancelled) {
                self.distance = nil
                finish?(nil)
                return
            }
            let direction: CGFloat = event.isDirectionInvertedFromDevice ? 1 : -1
            distance.width += direction * event.scrollingDeltaX
            distance.height += direction * event.scrollingDeltaY
            if event.phase.contains(.ended) {
                self.distance = nil
                finish?(distance)
            } else {
                self.distance = distance
                update?(distance)
            }
        }
    }
}
