import Foundation
import Testing
import YappingCore
@testable import YappingToAPiApp

@MainActor
@Suite("Desktop process transport", .serialized)
struct HelperSessionTests {
    @Test("Listening reaches the UI before the helper exits or fills a pipe buffer")
    func deliversLiveState() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let executable = directory.appendingPathComponent("fake-helper")
        try """
        #!/bin/sh
        printf '%s\\n' '{"type":"state","state":"listening","locale":"en-AU","inputDevice":"Fixture"}'
        printf '%s\\n' '{"type":"level","level":0.8}'
        read -r request
        printf '%s\\n' '{"type":"final","text":"Finished."}'
        """.write(to: executable, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: executable.path)
        let session = try HelperSession(executableURL: executable, arguments: [])
        defer { session.terminate() }
        var messages: [HelperMessage] = []
        let listener = Task {
            for await event in session.events {
                if case .message(let message) = event { messages.append(message) }
            }
        }
        defer { listener.cancel() }
        // Wait for delivery, not an exact process-launch duration on a loaded Mac.
        // The original buffered-read bug still times out because stdin stays open.
        let deadline = ContinuousClock.now.advanced(by: .seconds(2))
        while !messages.contains(.level(0.8)), ContinuousClock.now < deadline {
            try await Task.sleep(for: .milliseconds(20))
        }
        #expect(messages.contains(.state("listening", inputDevice: "Fixture")), "The app must leave Starting while the helper is still alive.")
        #expect(messages.contains(.level(0.8)), "The live meter must update before stop.")
        session.stop()
        await listener.value
        #expect(messages.last == .final("Finished."))
    }
}
