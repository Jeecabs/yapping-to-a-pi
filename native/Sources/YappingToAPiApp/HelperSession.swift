import Foundation
import Darwin
import YappingCore

enum SessionEvent: Sendable {
    case message(HelperMessage)
    case ended(Int32)
    case failed(String)
}

/// The app uses the same bundled helper as Pi. All wire validation stays here.
@MainActor
final class HelperSession {
    private let process = Process()
    private let input = Pipe()
    private let output = Pipe()
    private var stopped = false
    let events: AsyncStream<SessionEvent>
    private let continuation: AsyncStream<SessionEvent>.Continuation

    convenience init(locale: String, inputUID: String) throws {
        guard let helper = Bundle.main.url(forResource: "YappingToAPiHelper", withExtension: "app")?
            .appendingPathComponent("Contents/MacOS/yapping-to-a-pi-helper"),
              FileManager.default.isExecutableFile(atPath: helper.path) else {
            throw AppFailure("The speech helper is missing. Rebuild with pnpm run build:app.")
        }
        try self.init(executableURL: helper, arguments: ["--locale", locale, "--meter"] + (inputUID.isEmpty ? [] : ["--input-uid", inputUID]))
    }

    init(executableURL: URL, arguments: [String]) throws {
        (events, continuation) = AsyncStream.makeStream()
        process.executableURL = executableURL
        process.arguments = arguments
        process.standardInput = input
        process.standardOutput = output
        process.standardError = FileHandle.standardError
        try process.run()
        try? input.fileHandleForReading.close()
        try? output.fileHandleForWriting.close()

        let reader = output.fileHandleForReading
        let process = process
        let continuation = continuation
        let thread = Thread {
            defer { try? reader.close(); continuation.finish() }
            var framer = MessageFramer()
            do {
                var buffer = [UInt8](repeating: 0, count: 16_384)
                while true {
                    // FileHandle.read(upToCount:) fills its buffer on macOS pipes. POSIX read
                    // returns currently available bytes, so state and previews reach the UI live.
                    let count = buffer.withUnsafeMutableBytes { bytes in
                        Darwin.read(reader.fileDescriptor, bytes.baseAddress, bytes.count)
                    }
                    if count == 0 { break }
                    if count < 0 {
                        if errno == EINTR { continue }
                        throw AppFailure("Could not read the speech helper: \(String(cString: strerror(errno)))")
                    }
                    for message in try framer.append(Data(buffer.prefix(count))) { continuation.yield(.message(message)) }
                }
                try framer.finish()
                process.waitUntilExit()
                continuation.yield(.ended(process.terminationStatus))
            } catch {
                continuation.yield(.failed(error.localizedDescription))
            }
        }
        thread.name = "yapping.desktop-helper-reader"
        thread.start()
    }

    func stop() {
        guard !stopped else { return }
        stopped = true
        // EOF is the existing helper's graceful stop request. No SIGPIPE risk.
        try? input.fileHandleForWriting.close()
    }

    func terminate() {
        stop()
        guard process.isRunning else { return }
        process.terminate()
        let process = process
        DispatchQueue.global().asyncAfter(deadline: .now() + 1) {
            if process.isRunning { kill(process.processIdentifier, SIGKILL) }
        }
    }

    deinit {
        try? input.fileHandleForWriting.close()
        if process.isRunning { process.terminate() }
    }
}

struct AppFailure: LocalizedError {
    let message: String
    init(_ message: String) { self.message = message }
    var errorDescription: String? { message }
}
