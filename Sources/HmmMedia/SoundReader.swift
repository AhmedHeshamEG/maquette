#if canImport(AVFoundation)
    import AVFoundation

    /// Reads a sound file (anything AVFoundation opens: WAV, AIFF, M4A, MP3, CAF) as mono samples at a rate of at most
    /// 24 kHz, and measures it. Meant for a background task: a three-minute song reads and measures in about a second.
    public enum SoundReader {
        public enum Failure: Error, Equatable {
            case unreadable
        }

        /// The file's levels (`SoundAnalysis`).
        public static func levels(of url: URL) throws(Failure) -> SoundLevels {
            let (samples, rate) = try monoSamples(of: url)
            return SoundAnalysis.levels(samples: samples, sampleRate: rate)
        }

        /// The channels averaged, kept every `step`-th averaged block so the rate stays at or under 24 kHz.
        public static func monoSamples(of url: URL) throws(Failure) -> (samples: [Float], rate: Double) {
            guard let file = try? AVAudioFile(forReading: url) else { throw .unreadable }
            let format = file.processingFormat
            let step = max(Int((format.sampleRate / 24000).rounded(.up)), 1)
            let channels = Int(format.channelCount)
            let chunk: AVAudioFrameCount = 65536
            guard channels > 0, let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: chunk) else { throw .unreadable }
            var samples: [Float] = []
            samples.reserveCapacity(Int(file.length) / step + 1)
            var carry: (sum: Float, count: Int) = (0, 0)
            while file.framePosition < file.length {
                guard (try? file.read(into: buffer, frameCount: chunk)) != nil, buffer.frameLength > 0,
                      let data = buffer.floatChannelData else { break }
                for frame in 0 ..< Int(buffer.frameLength) {
                    var mixed: Float = 0
                    for channel in 0 ..< channels {
                        mixed += data[channel][frame]
                    }
                    carry.sum += mixed / Float(channels)
                    carry.count += 1
                    if carry.count == step {
                        samples.append(carry.sum / Float(step))
                        carry = (0, 0)
                    }
                }
            }
            guard !samples.isEmpty else { throw .unreadable }
            return (samples, format.sampleRate / Double(step))
        }
    }
#endif
