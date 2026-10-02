@preconcurrency import AVFoundation
import Foundation
import Speech

final class AudioCapture: @unchecked Sendable {
    typealias Buffers = AsyncThrowingStream<AVAudioPCMBuffer, any Error>

    private let engine = AVAudioEngine()
    private let lock = NSLock()
    private let restartQueue = DispatchQueue(label: "yapping-to-a-pi.audio-restart")
    private let onInputChange: @Sendable () -> Void
    private var continuation: Buffers.Continuation?
    private var configurationObserver: (any NSObjectProtocol)?
    private var running = false

    init(onInputChange: @escaping @Sendable () -> Void) {
        self.onInputChange = onInputChange
    }

    func start() throws -> Buffers {
        let (stream, continuation) = Buffers.makeStream(bufferingPolicy: .bufferingNewest(64))

        // A hardware change stops the engine without ending the tap, which would leave
        // dictation listening to nothing. Reopen the new default input instead.
        let observer = NotificationCenter.default.addObserver(
            forName: .AVAudioEngineConfigurationChange,
            object: engine,
            queue: nil
        ) { [weak self] _ in
            guard let self else { return }
            restartQueue.async { self.restartAfterConfigurationChange() }
        }

        lock.lock()
        self.continuation = continuation
        configurationObserver = observer
        running = true
        lock.unlock()

        do {
            try startEngine(yieldingTo: continuation)
        } catch {
            stop()
            throw error
        }
        return stream
    }

    func stop() {
        lock.lock()
        guard running else {
            lock.unlock()
            return
        }
        running = false
        let continuation = self.continuation
        self.continuation = nil
        let observer = configurationObserver
        configurationObserver = nil
        lock.unlock()

        if let observer { NotificationCenter.default.removeObserver(observer) }
        engine.stop()
        engine.inputNode.removeTap(onBus: 0)
        continuation?.finish()
    }

    private func startEngine(yieldingTo continuation: Buffers.Continuation) throws {
        let input = engine.inputNode
        input.removeTap(onBus: 0)
        let format = input.outputFormat(forBus: 0)
        guard format.sampleRate > 0, format.channelCount > 0 else {
            throw HelperFailure.microphoneUnavailable
        }

        input.installTap(onBus: 0, bufferSize: 4096, format: format) { buffer, _ in
            switch continuation.yield(buffer) {
            case .enqueued, .terminated:
                break
            case .dropped:
                continuation.finish(throwing: HelperFailure.audioQueueOverflow)
            @unknown default:
                continuation.finish(throwing: HelperFailure.audioQueueOverflow)
            }
        }

        engine.prepare()
        try engine.start()
    }

    private func restartAfterConfigurationChange() {
        lock.lock()
        defer { lock.unlock() }
        // A change that leaves the engine running needs no restart, which also avoids restart loops.
        guard running, let continuation, !engine.isRunning else { return }

        do {
            try startEngine(yieldingTo: continuation)
            onInputChange()
        } catch {
            continuation.finish(throwing: HelperFailure.microphoneChanged(error.localizedDescription))
        }
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
        finalized + volatile
    }
}

private enum PipelineEvent: Sendable {
    case stop
    case resultsEnded
    case audioEnded
    case failed(String)
}

struct LiveDictation {
    let locale: Locale
    let emitter: ProtocolEmitter

    func run() async throws {
        let stopSignal = StopSignal()
        // The blocking stdin read gets its own thread instead of occupying Swift's cooperative pool.
        // End of input also stops dictation, so a crashed parent cannot leave the microphone open.
        let stopReader = Thread {
            _ = readLine()
            stopSignal.stop()
        }
        stopReader.name = "yapping-to-a-pi.stop-reader"
        stopReader.start()

        let requestedIdentifier = locale.identifier(.bcp47)
        await emitter.state("preparing", locale: requestedIdentifier)

        do {
            guard let selectedLocale = await Self.supportedLocale(equivalentTo: locale) else {
                throw HelperFailure.localeUnsupported(requestedIdentifier)
            }
            let localeIdentifier = selectedLocale.identifier(.bcp47)

            try preflightKnownMicrophoneFailure()
            try throwIfStopped(stopSignal)

            let transcriber = SpeechTranscriber(
                locale: selectedLocale,
                transcriptionOptions: [],
                reportingOptions: [.volatileResults],
                attributeOptions: []
            )

            if !(await Self.isInstalled(selectedLocale)) {
                await emitter.state("installing-model", locale: localeIdentifier)
                try throwIfStopped(stopSignal)
                if let request = try await AssetInventory.assetInstallationRequest(supporting: [transcriber]) {
                    try await runUntilStopped(stopSignal) {
                        try await request.downloadAndInstall()
                    }
                }
                try throwIfStopped(stopSignal)
            }

            try await runUntilStopped(stopSignal) {
                try await authorizeMicrophone(localeIdentifier: localeIdentifier)
            }
            try throwIfStopped(stopSignal)

            guard let analyzerFormat = await SpeechAnalyzer.bestAvailableAudioFormat(compatibleWith: [transcriber]) else {
                throw HelperFailure.noCompatibleAudioFormat
            }
            try throwIfStopped(stopSignal)

            let analyzer = SpeechAnalyzer(modules: [transcriber])
            let (inputSequence, inputBuilder) = AsyncStream<AnalyzerInput>.makeStream(
                bufferingPolicy: .bufferingNewest(64)
            )
            let accumulator = TranscriptAccumulator()
            let converter = BufferConverter()

            let resultTask = Task {
                for try await result in transcriber.results {
                    try Task.checkCancellation()
                    let text = String(result.text.characters)
                    let combined = await accumulator.consume(text, isFinal: result.isFinal)
                    // Final results update the preview too, so pauses show the settled words.
                    await emitter.partial(combined)
                }
            }

            do {
                try await runUntilStopped(stopSignal) {
                    try await analyzer.start(inputSequence: inputSequence)
                }
                try throwIfStopped(stopSignal)

                let capture = AudioCapture(onInputChange: { [emitter] in
                    Task {
                        await emitter.state(
                            "listening",
                            locale: localeIdentifier,
                            inputDevice: Self.currentInputDeviceName()
                        )
                    }
                })
                guard let buffers = try stopSignal.performUnlessStopped({ try capture.start() }) else {
                    resultTask.cancel()
                    inputBuilder.finish()
                    await emitCancelled(localeIdentifier: localeIdentifier)
                    return
                }

                let audioTask = Task {
                    for try await buffer in buffers {
                        try Task.checkCancellation()
                        let converted = try converter.convert(buffer, to: analyzerFormat)
                        switch inputBuilder.yield(AnalyzerInput(buffer: converted)) {
                        case .enqueued:
                            break
                        case .dropped:
                            throw HelperFailure.analyzerInputOverflow
                        case .terminated:
                            return
                        @unknown default:
                            throw HelperFailure.analyzerInputOverflow
                        }
                    }
                }

                let (events, eventContinuation) = AsyncStream<PipelineEvent>.makeStream()
                let stopWatcher = Task {
                    if await stopSignal.wait() {
                        eventContinuation.yield(.stop)
                    }
                }
                let resultWatcher = Task {
                    do {
                        try await resultTask.value
                        eventContinuation.yield(.resultsEnded)
                    } catch is CancellationError {
                        // Cleanup cancellation is not a pipeline failure.
                    } catch {
                        eventContinuation.yield(.failed(error.localizedDescription))
                    }
                }
                let audioWatcher = Task {
                    do {
                        try await audioTask.value
                        eventContinuation.yield(.audioEnded)
                    } catch is CancellationError {
                        // Cleanup cancellation is not a pipeline failure.
                    } catch {
                        eventContinuation.yield(.failed(error.localizedDescription))
                    }
                }

                defer {
                    capture.stop()
                    inputBuilder.finish()
                    resultTask.cancel()
                    audioTask.cancel()
                    stopWatcher.cancel()
                    resultWatcher.cancel()
                    audioWatcher.cancel()
                    eventContinuation.finish()
                }

                await emitter.state(
                    "listening",
                    locale: localeIdentifier,
                    inputDevice: Self.currentInputDeviceName()
                )
                guard let event = await events.first(where: { _ in true }) else {
                    throw HelperFailure.pipelineFailed("The dictation pipeline stopped without a result.")
                }

                switch event {
                case .stop:
                    await emitter.state("finalizing", locale: localeIdentifier)
                    capture.stop()
                    try await audioTask.value
                    inputBuilder.finish()
                    try await analyzer.finalizeAndFinishThroughEndOfInput()
                    try await resultTask.value
                    await emitter.final(await accumulator.finalText())
                case .resultsEnded:
                    throw HelperFailure.pipelineFailed("Speech recognition stopped unexpectedly.")
                case .audioEnded:
                    throw HelperFailure.pipelineFailed("Microphone audio stopped unexpectedly.")
                case .failed(let message):
                    throw HelperFailure.pipelineFailed(message)
                }
            } catch {
                resultTask.cancel()
                inputBuilder.finish()
                throw error
            }
        } catch is CancellationError where stopSignal.isStopped() {
            await emitCancelled(localeIdentifier: requestedIdentifier)
        }
    }

    static func supportedLocale(equivalentTo locale: Locale) async -> Locale? {
        await SpeechTranscriber.supportedLocale(equivalentTo: locale)
    }

    static func isSupported(_ locale: Locale) async -> Bool {
        await supportedLocale(equivalentTo: locale) != nil
    }

    static func isInstalled(_ locale: Locale) async -> Bool {
        guard let selected = await supportedLocale(equivalentTo: locale) else { return false }
        let identifier = selected.identifier(.bcp47)
        let installed = await SpeechTranscriber.installedLocales
        return installed.contains { $0.identifier(.bcp47) == identifier }
    }

    static func currentInputDeviceName() -> String {
        AVCaptureDevice.default(for: .audio)?.localizedName ?? "Unknown input"
    }

    private func runUntilStopped<T: Sendable>(
        _ stopSignal: StopSignal,
        operation: @escaping @Sendable () async throws -> T
    ) async throws -> T {
        try throwIfStopped(stopSignal)
        return try await withThrowingTaskGroup(of: T.self) { group in
            group.addTask(operation: operation)
            group.addTask {
                // Returns on stop, or when cancelled because the operation finished first.
                _ = await stopSignal.wait()
                throw CancellationError()
            }
            defer { group.cancelAll() }
            guard let result = try await group.next() else { throw CancellationError() }
            return result
        }
    }

    private func throwIfStopped(_ stopSignal: StopSignal) throws {
        if stopSignal.isStopped() { throw CancellationError() }
    }

    private func emitCancelled(localeIdentifier: String) async {
        await emitter.state("finalizing", locale: localeIdentifier)
        await emitter.final("")
    }

    private func preflightKnownMicrophoneFailure() throws {
        switch AVCaptureDevice.authorizationStatus(for: .audio) {
        case .denied:
            throw HelperFailure.microphoneDenied
        case .restricted:
            throw HelperFailure.microphoneRestricted
        case .authorized, .notDetermined:
            return
        @unknown default:
            throw HelperFailure.microphoneUnavailable
        }
    }

    private func authorizeMicrophone(localeIdentifier: String) async throws {
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
}

enum HelperFailure: LocalizedError {
    case invalidArguments(String)
    case localeUnsupported(String)
    case microphoneDenied
    case microphoneRestricted
    case microphoneUnavailable
    case noCompatibleAudioFormat
    case audioQueueOverflow
    case analyzerInputOverflow
    case microphoneChanged(String)
    case pipelineFailed(String)

    var errorDescription: String? {
        switch self {
        case .invalidArguments(let message):
            message
        case .localeUnsupported(let locale):
            "The on-device speech model does not support \(locale)."
        case .microphoneDenied:
            "Microphone access was denied. macOS grants it to the terminal app that runs Pi; enable that app in System Settings → Privacy & Security → Microphone."
        case .microphoneRestricted:
            "Microphone access is restricted on this Mac."
        case .microphoneUnavailable:
            "No usable microphone input is available."
        case .noCompatibleAudioFormat:
            "No microphone format is compatible with the on-device speech model."
        case .audioQueueOverflow:
            "Microphone audio fell behind; no transcript was inserted. Try again."
        case .analyzerInputOverflow:
            "Speech analysis fell behind; no transcript was inserted. Try again."
        case .microphoneChanged(let message):
            "The microphone changed and could not be reopened; no transcript was inserted. \(message)"
        case .pipelineFailed(let message):
            "Dictation failed: \(message)"
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
        case .audioQueueOverflow, .analyzerInputOverflow: "audio-backpressure"
        case .microphoneChanged: "microphone-changed"
        case .pipelineFailed: "pipeline-failed"
        }
    }
}
