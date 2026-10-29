import Foundation
public struct CaptureHealth:Sendable {
 public private(set) var error:String?
 private var started:TimeInterval?
 private var lastFrame:TimeInterval?
 public var canStart:Bool { error == nil && started == nil }
 public var canRender:Bool { error == nil && lastFrame != nil }
 public init() {}
 public mutating func begin(at time:TimeInterval) { guard canStart else { return };started=time }
 public mutating func receivedFrame(at time:TimeInterval) { guard error == nil else { return };lastFrame=time }
 public mutating func observePrewarm(hasFrame:Bool,at time:TimeInterval) {
 if hasFrame { receivedFrame(at:time) }
 check(at:time)
 }
 public mutating func check(at time:TimeInterval) { if let started,lastFrame == nil,time-started>2 { fail("No se recibió una imagen de pantalla para el efecto.") } }
 public mutating func fail(_ message:String) { error=message;lastFrame=nil }
 public mutating func stop() { started=nil;lastFrame=nil }
 public mutating func reset() { self=Self() }
}
