import XCTest
@testable import IslandCore

final class SpectrumBalanceTests: XCTestCase {
    private func tone(_ frequencies: [(Double, Float)], seconds: Double = 2, rate: Double = 48_000) -> [Float] {
        (0..<Int(seconds * rate)).map { n in
            frequencies.reduce(Float(0)) { $0 + $1.1 * Float(sin(2 * .pi * $1.0 * Double(n) / rate)) }
        }
    }

    func testBassHeavyAudioGetsBassCut() {
        let analyzer = SpectrumBalance(sampleRate: 48_000)
        analyzer.feed(tone([(100, 0.5), (1_000, 0.05), (8_000, 0.01)]))
        let gains = SpectrumBalance.gains(for: analyzer.result()!)
        XCTAssertLessThan(gains.bass, 0)
        XCTAssertEqual(gains.mid, 0)
    }

    func testDullAudioGetsTrebleBoost() {
        let analyzer = SpectrumBalance(sampleRate: 48_000)
        analyzer.feed(tone([(100, 0.1), (1_000, 0.3), (8_000, 0.0001)]))
        let gains = SpectrumBalance.gains(for: analyzer.result()!)
        XCTAssertGreaterThan(gains.treble, 0)
        XCTAssertLessThanOrEqual(gains.treble, SpectrumBalance.maxGain)
    }

    func testSilenceYieldsNoResult() {
        let analyzer = SpectrumBalance(sampleRate: 48_000)
        analyzer.feed([Float](repeating: 0, count: 48_000))
        XCTAssertNil(analyzer.result())
    }

    func testCurrentGainsAreRemovedFromMeasurement() {
        let result = SpectrumBalance.Result(bassDB: 10, midDB: 0, trebleDB: -9, seconds: 5)
        let flat = SpectrumBalance.gains(for: result)
        let boosted = SpectrumBalance.gains(for: result, currentGains: .init(bass: 6, mid: 0, treble: 0))
        XCTAssertLessThan(flat.bass, boosted.bass)
    }
}
