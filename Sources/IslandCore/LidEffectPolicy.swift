import Foundation
public enum LidEffectState:Equatable,Sendable { case inactive,prewarming,active(progress:Double) }
public struct LidEffectPolicy {
 private var lastAngle:Double?
 private var motionAnchor:Double?
 private var openAngle:Double?
 private var lowest=360.0
 private var lastMotion = -Double.greatestFiniteMagnitude
 private var active=false
 public private(set) var startAngle=100.0
 public private(set) var state=LidEffectState.inactive
 public var pollInterval:TimeInterval { state == .inactive ? 0.25 : 0.1 }
 public init() {}
 public mutating func update(angle:Double,timestamp:TimeInterval) -> LidEffectState {
 guard angle.isFinite,(0...180).contains(angle),timestamp.isFinite else { self=Self();return .inactive }
 defer { lastAngle=angle }
 guard let previous=lastAngle else { motionAnchor=angle;if angle>=75 { openAngle=angle };return .inactive }
 let delta=angle-previous
 // Compare against the last meaningful position, not adjacent samples.
 // M4 readings jitter by hundredths of a degree even with a still hinge.
 // Accumulation preserves slow movement without letting noise renew the wait.
 if let anchor=motionAnchor,abs(angle-anchor)>=0.5 {
 if angle<anchor || active { lastMotion=timestamp }
 motionAnchor=angle
 }
 if (!active && (delta>0.3 || (state != .inactive && angle-lowest>=1.5))) || (active && angle>=startAngle) {
 active=false;motionAnchor=angle;lowest=360;openAngle=angle>=75 ? angle : nil;state = .inactive;return state
 }
 if state != .inactive && timestamp-lastMotion>=3 {
 active=false;motionAnchor=angle;lowest=360;openAngle=angle>=75 ? angle : nil;state = .inactive;return state
 }
 guard let opened=openAngle else { if angle>=75 { openAngle=angle };state = .inactive;return state }
 if active {
 lowest=min(lowest,angle)
 state = .active(progress:max(0,min(1,(startAngle-angle)/60)));return state
 }
 let travel=opened-angle
 guard travel>=3 else { state = .inactive;return state }
 startAngle=opened-8
 lowest=min(lowest,angle)
 if travel>=8 { active=true;lowest=angle;state = .active(progress:max(0,min(1,(startAngle-angle)/60))) }
 else { state = .prewarming }
 return state
 }
}
public enum LidReportDecoder {
 public static func decode(_ bytes:[UInt8]) -> Double? {
 let result:Double
 if bytes.first == 7,bytes.count >= 5 { result=Double(UInt32(bytes[1]) | UInt32(bytes[2]) << 8 | UInt32(bytes[3]) << 16 | UInt32(bytes[4]) << 24)/100 }
 else if bytes.first == 1,bytes.count >= 3 { result=Double(UInt16(bytes[1]) | UInt16(bytes[2]) << 8) }
 else { return nil }
 return (0...360).contains(result) ? result : nil
 }
}
