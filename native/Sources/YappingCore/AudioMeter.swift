import AVFoundation

/// Converts a captured audio buffer into a display level. Does not retain audio.
public enum AudioMeter {
    public static func level(in buffer: AVAudioPCMBuffer) -> Double {
        guard buffer.frameLength > 0 else { return 0 }
        // Read the PCM layout, not floatChannelData: SpeechAnalyzer can request Int16.
        let frameCount = Int(buffer.frameLength)
        var loudestRMS = 0.0
        for audioBuffer in UnsafeMutableAudioBufferListPointer(buffer.mutableAudioBufferList) {
            guard let data = audioBuffer.mData else { continue }
            let channels = Int(audioBuffer.mNumberChannels)
            guard channels > 0 else { continue }
            func measure<T: BinaryFloatingPoint>(_ samples: UnsafePointer<T>, scale: Double = 1) -> Double {
                var maximum = 0.0
                for channel in 0..<channels {
                    var energy = 0.0
                    for frame in 0..<frameCount {
                        let sample = Double(samples[frame * channels + channel]) * scale
                        if sample.isFinite { energy += sample * sample }
                    }
                    maximum = max(maximum, sqrt(energy / Double(frameCount)))
                }
                return maximum
            }
            func measureInteger<T: BinaryInteger>(_ samples: UnsafePointer<T>, scale: Double) -> Double {
                var maximum = 0.0
                for channel in 0..<channels {
                    var energy = 0.0
                    for frame in 0..<frameCount {
                        let sample = Double(samples[frame * channels + channel]) * scale
                        energy += sample * sample
                    }
                    maximum = max(maximum, sqrt(energy / Double(frameCount)))
                }
                return maximum
            }
            let rms: Double
            switch buffer.format.commonFormat {
            case .pcmFormatFloat32: rms = measure(UnsafePointer(data.assumingMemoryBound(to: Float.self)))
            case .pcmFormatFloat64: rms = measure(UnsafePointer(data.assumingMemoryBound(to: Double.self)))
            case .pcmFormatInt16: rms = measureInteger(UnsafePointer(data.assumingMemoryBound(to: Int16.self)), scale: 1 / 32_768)
            case .pcmFormatInt32: rms = measureInteger(UnsafePointer(data.assumingMemoryBound(to: Int32.self)), scale: 1 / 2_147_483_648)
            default: rms = 0
            }
            loudestRMS = max(loudestRMS, rms)
        }
        // Speech occupies only part of the digital range. Keep silence flat while
        // giving quiet syllables room to move without changing recording gain.
        let decibels = 20 * log10(max(loudestRMS, 0.000_001))
        return pow(min(1, max(0, (decibels + 60) / 42)), 0.7)
    }
}

/// A small history of actual microphone levels. No synthetic idle animation.
public struct WaveformHistory: Equatable, Sendable {
    public static let barCount = 13
    public private(set) var samples = Array(repeating: 0.0, count: barCount)
    public init() {}
    public mutating func append(_ value: Double) {
        samples.removeFirst()
        samples.append(value.isFinite ? min(1, max(0, value)) : 0)
    }
    public static func height(for level: Double, sensitivity: Double = 1) -> Double {
        let gain = sensitivity.isFinite ? min(2, max(0.5, sensitivity)) : 1
        return 2 + 18 * min(1, max(0, level.isFinite ? level * gain : 0))
    }
}
