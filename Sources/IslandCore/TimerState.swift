import Foundation
public struct Countdown: Sendable {
 public private(set) var deadline: Date?
 private var pausedRemaining: TimeInterval
 public let duration: TimeInterval
 public var isRunning: Bool { deadline != nil }
 public init(seconds: TimeInterval) { duration = seconds.isFinite ? max(0,seconds) : 0; pausedRemaining = duration }
 public mutating func start(at date: Date) { guard deadline == nil, pausedRemaining > 0 else { return }; deadline = date.addingTimeInterval(pausedRemaining) }
 public func remaining(at date: Date) -> TimeInterval { max(0,deadline.map { $0.timeIntervalSince(date) } ?? pausedRemaining) }
 public mutating func pause(at date: Date) { pausedRemaining = remaining(at: date); deadline = nil }
 public mutating func reset() { deadline = nil; pausedRemaining = duration }
}
public struct Stopwatch: Sendable {
 private var startedAt: Date?
 private var accumulated: TimeInterval = 0
 public var isRunning: Bool { startedAt != nil }
 public init() {}
 public mutating func start(at date: Date) { if startedAt == nil { startedAt = date } }
 public mutating func pause(at date: Date) { accumulated = elapsed(at: date); startedAt = nil }
 public func elapsed(at date: Date) -> TimeInterval { accumulated + max(0,startedAt.map { date.timeIntervalSince($0) } ?? 0) }
 public mutating func reset() { startedAt = nil; accumulated = 0 }
}
