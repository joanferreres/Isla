import Foundation
import Combine
import AppKit
import IslandCore
@MainActor final class TimerStore: ObservableObject {
 @Published private(set) var countdown = Countdown(seconds: 300)
 @Published private(set) var stopwatch = Stopwatch()
 @Published private(set) var now = Date()
 @Published private(set) var finished = false
 private var ticker: AnyCancellable?
 init() {
  ticker = Timer.publish(every: 1, on: .main, in: .common).autoconnect().sink { [weak self] date in self?.tick(date) }
 }
 var remaining: TimeInterval { countdown.remaining(at: now) }
 var elapsed: TimeInterval { stopwatch.elapsed(at: now) }
 var compactText: String? { countdown.isRunning || finished ? (finished ? "Listo" : Self.format(remaining, roundUp: true)) : nil }
 func tick(_ date: Date) {
  now = date
  if countdown.isRunning && remaining <= 0 && !finished {
   countdown.pause(at: date); finished = true; NSSound(named: "Glass")?.play()
  }
 }
 func configure(minutes: Double) { guard !countdown.isRunning else { return }; countdown = Countdown(seconds: max(1,minutes)*60); finished = false; now = Date() }
 func toggleCountdown() {
  now = Date()
  if countdown.isRunning { countdown.pause(at: now) }
  else { if finished { countdown.reset(); finished = false }; countdown.start(at: now) }
 }
 func resetCountdown() { countdown.reset(); finished = false; now = Date() }
 func toggleStopwatch() { now = Date(); if stopwatch.isRunning { stopwatch.pause(at: now) } else { stopwatch.start(at: now) } }
 func resetStopwatch() { stopwatch.reset(); now = Date() }
 static func format(_ interval: TimeInterval, roundUp: Bool = false) -> String {
  let seconds = Int(roundUp ? ceil(interval) : floor(interval))
  let hours = seconds / 3600
  return hours > 0 ? String(format: "%d:%02d:%02d",hours,(seconds/60)%60,seconds%60) : String(format:"%02d:%02d",seconds/60,seconds%60)
 }
}
