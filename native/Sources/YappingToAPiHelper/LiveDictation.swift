@preconcurrency import AVFoundation
import Foundation
import Speech

final class AudioCapture: @unchecked Sendable {
    private let engine = AVAudioEngine()
    private var continuation: AsyncStream<AVAudioPCMBuffer>.Continuation?

    func start() throws -> AsyncStream<AVAudioPCMBuffer> {
        let (stream, continuation) = AsyncStream<AVAudioPCMBuffer>.makeStream(
            bufferingPolicy: .bufferingNewest(12)
        )
        self.continuation = continuation

        let input = engine.inputNode
        input.removeTap(onBus: 0)
        let format = input.outputFormat(forBus: 0)
        input.installTap(onBus: 0, bufferSize: 4096, format: format) { buffer, _ in
            continuation.yield(buffer)
        }

        engine.prepare()
        try engine.start()
        return stream
    }

    func stop() {
        engine.stop()
        engine.inputNode.removeTap(onBus: 0)
        continuation?.finish()
        continuation = nil
    }
}

actor TranscriptAccumulator {
    private var finalized = ""
    private var volatile = ""

    func consume(_ text: String, isFinal: Bool) -> String {
        if isFinal {
            finalized.append(text)
            volatile = ""
        } else {
            volatile = text
        }
        return finalized + volatile
    }

    func finalText() -> String {
        finalized
    }
}

struct LiveDictation {
    let locale: Locale
    let localeIdentifier: String
    let emitter: ProtocolEmitter

    func run() async throws {
        let stopTask = Task.detached(priority: .userInitiated) { readLine() }
        await emitter.state("preparing", locale: localeIdentifier)

        guard await Self.isSupported(localeIdentifier) else {
            throw HelperFailure.localeUnsupported(localeIdentifier)
        }

        let transcriber = SpeechTranscriber(
            locale: locale,
            transcriptionOptions: [],
            reportingOptions: [.volatileResults],
            attributeOptions: []
        )

        if !(await Self.isInstalled(localeIdentifier)) {
            await emitter.state("installing-model", locale: localeIdentifier)
            if let request = try await AssetInventory.assetInstallationRequest(supporting: [transcriber]) {
                try await request.downloadAndInstall()
            }
        }

        try await authorizeMicrophone()

        guard let analyzerFormat = await SpeechAnalyzer.bestAvailableAudioFormat(compatibleWith: [transcriber]) else {
            throw HelperFailure.noCompatibleAudioFormat
        }

        let analyzer = SpeechAnalyzer(modules: [transcriber])
        let (inputSequence, inputBuilder) = AsyncStream<AnalyzerInput>.makeStream(
            bufferingPolicy: .bufferingNewest(12)
        )
        let accumulator = TranscriptAccumulator()
        let converter = BufferConverter()

        let resultTask = Task {
            for try await result in transcriber.results {
                let text = String(result.text.characters)
                let combined = await accumulator.consume(text, isFinal: result.isFinal)
                if !result.isFinal {
                    await emitter.partial(combined)
                }
            }
        }

        try await analyzer.start(inputSequence: inputSequence)

        let capture = AudioCapture()
        let buffers = try capture.start()
        let audioTask = Task {
            for await buffer in buffers {
                let converted = try converter.convert(buffer, to: analyzerFormat)
                inputBuilder.yield(AnalyzerInput(buffer: converted))
            }
        }

        await emitter.state("listening", locale: localeIdentifier)
        _ = await stopTask.value
        await emitter.state("finalizing", locale: localeIdentifier)

        capture.stop()
        try await audioTask.value
        inputBuilder.finish()
        try await analyzer.finalizeAndFinishThroughEndOfInput()
        resultTask.cancel()
        _ = try? await resultTask.value

        await emitter.final(await accumulator.finalText())
    }

    private func authorizeMicrophone() async throws {
        switch AVCaptureDevice.authorizationStatus(for: .audio) {
        case .authorized:
            return
        case .notDetermined:
            await emitter.state("requesting-permission", locale: localeIdentifier)
            guard await AVCaptureDevice.requestAccess(for: .audio) else {
                throw HelperFailure.microphoneDenied
            }
        case .denied:
            throw HelperFailure.microphoneDenied
        case .restricted:
            throw HelperFailure.microphoneRestricted
        @unknown default:
            throw HelperFailure.microphoneUnavailable
        }
    }

    static func isSupported(_ localeIdentifier: String) async -> Bool {
        let supported = await SpeechTranscriber.supportedLocales
        return supported.contains { $0.identifier(.bcp47) == localeIdentifier }
    }

    static func isInstalled(_ localeIdentifier: String) async -> Bool {
        let installed = await SpeechTranscriber.installedLocales
        return installed.contains { $0.identifier(.bcp47) == localeIdentifier }
    }
}

enum HelperFailure: LocalizedError {
    case invalidArguments(String)
    case localeUnsupported(String)
    case microphoneDenied
    case microphoneRestricted
    case microphoneUnavailable
    case noCompatibleAudioFormat

    var errorDescription: String? {
        switch self {
        case .invalidArguments(let message):
            message
        case .localeUnsupported(let locale):
            "The on-device speech model does not support \(locale)."
        case .microphoneDenied:
            "Microphone access was denied. Enable yapping to a pi in Privacy & Security → Microphone."
        case .microphoneRestricted:
            "Microphone access is restricted on this Mac."
        case .microphoneUnavailable:
            "Microphone authorization is unavailable."
        case .noCompatibleAudioFormat:
            "No microphone format is compatible with the on-device speech model."
        }
    }

    var code: String {
        switch self {
        case .invalidArguments: "invalid-arguments"
        case .localeUnsupported: "locale-unsupported"
        case .microphoneDenied: "microphone-denied"
        case .microphoneRestricted: "microphone-restricted"
        case .microphoneUnavailable: "microphone-unavailable"
        case .noCompatibleAudioFormat: "audio-format-unavailable"
        }
    }
}
