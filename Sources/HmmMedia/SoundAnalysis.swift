import Foundation

/// Measures a sound into `SoundLevels`: loudness and bass envelopes from the energy of each sixtieth of a second, and
/// beats from where the energy jumps (onsets). When the onsets keep a steady pulse between 60 and 180 beats a minute
/// (found by autocorrelation), the beats are that grid, each nudged onto the onset nearest it; otherwise they are the
/// strong onsets themselves. Pure Swift and deterministic: the same samples always give the same levels.
public enum SoundAnalysis {
    /// Levels of mono `samples` at `sampleRate`.
    public static func levels(samples: [Float], sampleRate: Double) -> SoundLevels {
        guard sampleRate > 0, samples.count > Int(sampleRate / SoundLevels.rate) else { return .silent }
        let hop = sampleRate / SoundLevels.rate
        let count = Int(Double(samples.count) / hop)
        let full = energies(samples, hop: hop, count: count)
        let low = energies(lowPassed(samples, sampleRate: sampleRate, cutoff: 150), hop: hop, count: count)
        let fullDB = follow(full.map(decibels))
        let lowDB = follow(low.map(decibels))
        let onsets = onsetStrength(fullDB, lowDB)
        let (beats, tempo) = BeatFinder.beats(onsets, loud: fullDB, rate: SoundLevels.rate)
        return SoundLevels(loudness: normalised(fullDB), bass: normalised(lowDB), beats: beats, tempo: tempo)
    }

    /// Mean square of each hop's window (two hops wide, centred).
    static func energies(_ samples: [Float], hop: Double, count: Int) -> [Double] {
        (0 ..< count).map { index in
            let centre = (Double(index) + 0.5) * hop
            let start = max(Int(centre - hop), 0)
            let end = min(Int(centre + hop), samples.count)
            guard end > start else { return 0 }
            var sum = 0.0
            for sample in samples[start ..< end] {
                sum += Double(sample) * Double(sample)
            }
            return sum / Double(end - start)
        }
    }

    static func decibels(_ meanSquare: Double) -> Double { 10 * log10(meanSquare + 1e-10) }

    /// Two one-pole low-passes in a row (12 dB an octave).
    static func lowPassed(_ samples: [Float], sampleRate: Double, cutoff: Double) -> [Float] {
        let alpha = Float(1 - exp(-2 * Double.pi * cutoff / sampleRate))
        var first: Float = 0
        var second: Float = 0
        return samples.map { sample in
            first += alpha * (sample - first)
            second += alpha * (first - second)
            return second
        }
    }

    /// An envelope follower in decibels: rises within 10 ms, falls over 150 ms.
    static func follow(_ values: [Double]) -> [Double] {
        let attack = exp(-1 / (SoundLevels.rate * 0.01))
        let release = exp(-1 / (SoundLevels.rate * 0.15))
        var current = values.first ?? -100
        return values.map { value in
            let coefficient = value > current ? attack : release
            current = value + (current - value) * coefficient
            return current
        }
    }

    /// 0…255 between the sound's quiet (its 10th percentile, at most 50 dB under the loud) and its loud (98th).
    static func normalised(_ values: [Double]) -> [UInt8] {
        guard !values.isEmpty else { return [] }
        let sorted = values.sorted()
        let ceiling = sorted[min(Int(Double(sorted.count - 1) * 0.98), sorted.count - 1)]
        let floor = max(sorted[Int(Double(sorted.count - 1) * 0.1)], ceiling - 50)
        let span = max(ceiling - floor, 6)
        return values.map { UInt8((min(max(($0 - floor) / span, 0), 1) * 255).rounded()) }
    }

    /// How much the energy jumps at each step, the bass counting double (kicks carry the beat).
    static func onsetStrength(_ full: [Double], _ low: [Double]) -> [Double] {
        guard full.count > 1 else { return Array(repeating: 0, count: full.count) }
        return full.indices.map { index in
            guard index > 0 else { return 0 }
            return max(full[index] - full[index - 1], 0) + 2 * max(low[index] - low[index - 1], 0)
        }
    }
}

/// Beats from onset strength.
enum BeatFinder {
    static func beats(_ onsets: [Double], loud: [Double], rate: Double) -> (beats: [Double], tempo: Double?) {
        let peaks = strongOnsets(onsets, rate: rate)
        guard let (period, phase) = pulse(blurred(onsets), rate: rate) else { return (peaks.map { Double($0) / rate }, nil) }
        // Strong enough to lock onto: a third of the typical strong onset.
        let strong = peaks.map { onsets[$0] }.sorted()
        let lock = strong.isEmpty ? .infinity : strong[strong.count / 2] / 3
        let quiet = (loud.max() ?? 0) - 40
        var beats: [Double] = []
        var position = Double(phase)
        while Int(position.rounded()) < onsets.count {
            // Each grid beat locks onto the strongest onset within a sixth of a beat of it, so the grid never drifts.
            let near = Int(position.rounded())
            let reach = max(Int(period / 6), 2)
            let window = max(near - reach, 0) ... min(near + reach, onsets.count - 1)
            let best = window.max { onsets[$0] < onsets[$1] } ?? near
            let anchor = onsets[best] >= lock ? refined(onsets, at: best) : position
            if loud[min(max(Int(anchor.rounded()), 0), loud.count - 1)] > quiet { beats.append(anchor / rate) }
            position = anchor + period
        }
        return (beats, 60 * rate / period)
    }

    /// Onsets softened over ±2 steps, so a beat that falls between steps still lines up with the next.
    static func blurred(_ onsets: [Double]) -> [Double] {
        let kernel = [1.0, 4, 6, 4, 1].map { $0 / 16 }
        return onsets.indices.map { index in
            kernel.indices.reduce(0) { sum, offset in
                let source = index + offset - 2
                return source >= 0 && source < onsets.count ? sum + onsets[source] * kernel[offset] : sum
            }
        }
    }

    /// The beat's period (in steps, between steps) and where the grid starts, when the onsets are periodic enough.
    static func pulse(_ onsets: [Double], rate: Double) -> (period: Double, phase: Int)? {
        let shortest = Int((rate * 60 / 180).rounded())
        let longest = Int((rate * 60 / 60).rounded())
        guard onsets.count > longest * 4 else { return nil }
        let mean = onsets.reduce(0, +) / Double(onsets.count)
        let centred = onsets.map { $0 - mean }
        let energy = centred.reduce(0) { $0 + $1 * $1 }
        guard energy > 1e-9 else { return nil }
        let scores = (shortest ... longest).map { lag -> Double in
            var sum = 0.0
            for index in lag ..< centred.count {
                sum += centred[index] * centred[index - lag]
            }
            // A gentle preference for tempos near 120, so a beat isn't read at half or double speed.
            let bpm = 60 * rate / Double(lag)
            return sum / energy * exp(-pow(log2(bpm / 120), 2) / 2)
        }
        guard let bestIndex = scores.indices.max(by: { scores[$0] < scores[$1] }), scores[bestIndex] > 0.1 else { return nil }
        let period = Double(shortest) + refined(scores, at: bestIndex)
        let phase = (0 ..< shortest + bestIndex).max { comb(onsets, start: $0, period: period) < comb(onsets, start: $1, period: period) } ?? 0
        return (period, phase)
    }

    /// The onsets on a grid of `period` steps from `start`.
    static func comb(_ onsets: [Double], start: Int, period: Double) -> Double {
        var sum = 0.0
        var position = Double(start)
        while Int(position.rounded()) < onsets.count {
            sum += onsets[Int(position.rounded())]
            position += period
        }
        return sum
    }

    /// The peak between steps (a parabola through the step and its neighbours).
    static func refined(_ values: [Double], at index: Int) -> Double {
        guard index > 0, index < values.count - 1 else { return Double(index) }
        let a = values[index - 1], b = values[index], c = values[index + 1]
        let denominator = a - 2 * b + c
        guard abs(denominator) > 1e-12 else { return Double(index) }
        return Double(index) + min(max(0.5 * (a - c) / denominator, -0.5), 0.5)
    }

    /// Onsets standing well above their second around them (mean + 1.5 deviations), at least 0.1 s apart.
    static func strongOnsets(_ onsets: [Double], rate: Double) -> [Int] {
        let half = Int(rate / 2)
        let gap = Int(rate / 10)
        var result: [Int] = []
        for index in onsets.indices {
            let window = onsets[max(index - half, 0) ..< min(index + half, onsets.count)]
            let mean = window.reduce(0, +) / Double(window.count)
            let deviation = (window.reduce(0) { $0 + ($1 - mean) * ($1 - mean) } / Double(window.count)).squareRoot()
            guard onsets[index] > mean + 1.5 * deviation, onsets[index] > 0.5 else { continue }
            if let last = result.last, index - last < gap {
                if onsets[index] > onsets[last] { result[result.count - 1] = index }
                continue
            }
            result.append(index)
        }
        return result
    }
}
