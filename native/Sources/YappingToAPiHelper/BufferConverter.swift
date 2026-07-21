@preconcurrency import AVFoundation
import Foundation

// Adapted from Apple's WWDC25 SpeechAnalyzer sample. See native/APPLE-SAMPLE-LICENSE.txt.
final class BufferConverter: @unchecked Sendable {
    enum ConversionError: Error {
        case failedToCreateConverter
        case failedToCreateBuffer
        case conversionFailed(NSError?)
    }

    private var converter: AVAudioConverter?

    func convert(_ buffer: AVAudioPCMBuffer, to format: AVAudioFormat) throws -> AVAudioPCMBuffer {
        let inputFormat = buffer.format
        guard inputFormat != format else { return buffer }

        if converter == nil || converter?.inputFormat != inputFormat || converter?.outputFormat != format {
            converter = AVAudioConverter(from: inputFormat, to: format)
            converter?.primeMethod = .none
        }

        guard let converter else { throw ConversionError.failedToCreateConverter }

        let ratio = converter.outputFormat.sampleRate / converter.inputFormat.sampleRate
        let capacity = AVAudioFrameCount((Double(buffer.frameLength) * ratio).rounded(.up))
        guard let output = AVAudioPCMBuffer(pcmFormat: converter.outputFormat, frameCapacity: capacity) else {
            throw ConversionError.failedToCreateBuffer
        }

        var conversionError: NSError?
        let input = SingleBufferInput(buffer)
        let status = converter.convert(to: output, error: &conversionError) { _, inputStatus in
            input.take(status: inputStatus)
        }

        guard status != .error else { throw ConversionError.conversionFailed(conversionError) }
        return output
    }
}

private final class SingleBufferInput: @unchecked Sendable {
    private let lock = NSLock()
    private var buffer: AVAudioPCMBuffer?

    init(_ buffer: AVAudioPCMBuffer) {
        self.buffer = buffer
    }

    func take(status: UnsafeMutablePointer<AVAudioConverterInputStatus>) -> AVAudioBuffer? {
        lock.lock()
        defer { lock.unlock() }

        guard let buffer else {
            status.pointee = .noDataNow
            return nil
        }

        self.buffer = nil
        status.pointee = .haveData
        return buffer
    }
}
