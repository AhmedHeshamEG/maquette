@testable import HmmMedia
import XCTest

/// Loudness, bass and beats measured from samples: a click track's tempo and beats, a fade's rising loudness, speech-like
/// bursts with no pulse, and the levels' small encoding.
final class SoundAnalysisTests: XCTestCase {
    private let rate = 22050.0

    /// `seconds` of silence with a 30 ms kick (a 60 Hz tone, decaying) every `60 / bpm` seconds from `start`.
    private func clicks(bpm: Double, seconds: Double, start: Double = 0.2) -> [Float] {
        var samples = [Float](repeating: 0, count: Int(seconds * rate))
        var beat = start
        while beat < seconds - 0.05 {
            let first = Int(beat * rate)
            for index in 0 ..< Int(0.03 * rate) where first + index < samples.count {
                let t = Double(index) / rate
                samples[first + index] = Float(sin(2 * .pi * 60 * t) * exp(-t * 60) * 0.8)
            }
            beat += 60 / bpm
        }
        return samples
    }

    func testAClickTracksTempoAndBeats() throws {
        for bpm in [96.0, 120, 140] {
            let levels = SoundAnalysis.levels(samples: clicks(bpm: bpm, seconds: 12), sampleRate: rate)
            let tempo = try XCTUnwrap(levels.tempo, "\(bpm)")
            XCTAssertEqual(tempo, bpm, accuracy: bpm * 0.03, "\(bpm)")
            // Every beat lands within 25 ms of a click.
            let period = 60 / bpm
            for beat in levels.beats {
                let fromClick = (beat - 0.2).truncatingRemainder(dividingBy: period)
                XCTAssertLessThan(min(fromClick, period - fromClick), 0.025, "\(bpm): \(beat)")
            }
            XCTAssertGreaterThan(levels.beats.count, Int(11 / period) - 2)
        }
    }

    func testLoudnessRisesWithAFadeAndTheBassFollowsTheKick() {
        // Two seconds of a 440 Hz tone fading in from silence.
        let samples = (0 ..< Int(2 * rate)).map { index -> Float in
            let t = Double(index) / rate
            return Float(sin(2 * .pi * 440 * t) * t / 2 * 0.5)
        }
        let levels = SoundAnalysis.levels(samples: samples, sampleRate: rate)
        XCTAssertEqual(levels.loudness.count, 120)
        XCTAssertLessThan(levels.loudness(at: 0.1), levels.loudness(at: 1))
        XCTAssertLessThan(levels.loudness(at: 1), levels.loudness(at: 1.9))
        XCTAssertGreaterThan(levels.loudness(at: 1.9), 0.9)
        // A 440 Hz tone has little bass: the bass stays under the loudness.
        XCTAssertLessThan(levels.bass(at: 1.9) - 0.05, levels.loudness(at: 1.9))
        let kicks = SoundAnalysis.levels(samples: clicks(bpm: 120, seconds: 4), sampleRate: rate)
        XCTAssertGreaterThan(kicks.bass(at: 0.21), 0.6)
        XCTAssertLessThan(kicks.bass(at: 0.6), kicks.bass(at: 0.21))
    }

    func testBurstsWithoutAPulseGiveOnsetsAndNoTempo() {
        // Irregular bursts (speech-like): onsets at their starts, no steady tempo.
        let starts = [0.3, 1.1, 1.45, 2.9, 3.2, 4.75, 5.05, 6.6]
        var samples = [Float](repeating: 0, count: Int(7.5 * rate))
        for start in starts {
            for index in 0 ..< Int(0.2 * rate) {
                let t = Double(index) / rate
                samples[Int(start * rate) + index] = Float(sin(2 * .pi * 200 * t) * 0.5)
            }
        }
        let levels = SoundAnalysis.levels(samples: samples, sampleRate: rate)
        XCTAssertNil(levels.tempo)
        for start in starts {
            XCTAssertTrue(levels.beats.contains { abs($0 - start) < 0.04 }, "\(start): \(levels.beats)")
        }
    }

    func testThePulseRisesIntoABeatAndFallsAway() {
        let levels = SoundLevels(loudness: [], bass: [], beats: [1, 2], tempo: 60)
        XCTAssertEqual(levels.pulse(at: 1), 1, accuracy: 1e-9)
        XCTAssertEqual(levels.pulse(at: 1.25), exp(-1), accuracy: 1e-9)
        XCTAssertEqual(levels.pulse(at: 1.985), 0.5, accuracy: 0.01)
        XCTAssertEqual(levels.pulse(at: 0.5), 0, accuracy: 1e-9)
        XCTAssertEqual(SoundLevels.silent.pulse(at: 1), 0)
    }

    func testLevelsTravelAsBase64() throws {
        let levels = SoundLevels(loudness: [0, 128, 255], bass: [1, 2, 3], beats: [0.1234567], tempo: 120.04)
        let data = try JSONEncoder().encode(levels)
        let text = String(decoding: data, as: UTF8.self)
        XCTAssertTrue(text.contains("\"AQID\""), text)
        let back = try JSONDecoder().decode(SoundLevels.self, from: data)
        XCTAssertEqual(back.loudness, levels.loudness)
        XCTAssertEqual(back.bass, levels.bass)
        XCTAssertEqual(back.beats, [0.123])
        XCTAssertEqual(back.tempo, 120)
        XCTAssertEqual(back.loudness(at: 1 / 120), 64.0 / 255, accuracy: 1e-9)
    }

    func testSilenceAndTooShort() {
        XCTAssertEqual(SoundAnalysis.levels(samples: [], sampleRate: rate), .silent)
        let quiet = SoundAnalysis.levels(samples: [Float](repeating: 0, count: Int(rate)), sampleRate: rate)
        XCTAssertTrue(quiet.beats.isEmpty)
        XCTAssertNil(quiet.tempo)
    }
}
