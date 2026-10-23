import Foundation
import Testing
import YappingCore
@testable import YappingToAPiApp

@MainActor
@Suite("Rewrite drafts without microphone or model access")
struct RewriteTests {
    @Test("Editing a draft while rewriting rejects the old result")
    func changedDraft() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let started = AsyncStream<Void>.makeStream()
        var finish: CheckedContinuation<String, Never>?
        let model = AppModel(store: DesktopStore(url: directory.appendingPathComponent("desktop.json"))) { _, _, _ in
            await withCheckedContinuation { continuation in
                finish = continuation
                started.continuation.yield(())
            }
        }
        model.scratchpad = "The first draft."
        let task = try #require(model.runTransform())
        var iterator = started.stream.makeAsyncIterator()
        await iterator.next()
        model.scratchpad = "A newer draft that must survive."
        finish?.resume(returning: "An outdated rewrite.")
        await task.value
        #expect(model.scratchpad == "A newer draft that must survive.")
        #expect(model.transformResult.isEmpty)
        #expect(model.transformOriginal == nil)
        #expect(!model.transforming)
    }

    @Test("A failed retry cannot leave the previous result looking current")
    func failedRetry() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        var attempts = 0
        let model = AppModel(store: DesktopStore(url: directory.appendingPathComponent("desktop.json"))) { _, _, _ in
            attempts += 1
            if attempts > 1 { throw AppFailure("The rewrite failed.") }
            return "A successful rewrite."
        }
        model.scratchpad = "The original draft."
        await model.runTransform()?.value
        #expect(model.transformResult == "A successful rewrite.")
        await model.runTransform()?.value
        #expect(model.scratchpad == "The original draft.")
        #expect(model.transformResult.isEmpty)
        #expect(model.transformOriginal == nil)
        #expect(model.transformError == "The rewrite failed.")
        #expect(!model.transforming)
    }

    @Test("An old cancelled request cannot finish a newer rewrite")
    func overlappingRequests() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let started = AsyncStream<Void>.makeStream()
        var pending: [CheckedContinuation<String, Never>] = []
        let model = AppModel(store: DesktopStore(url: directory.appendingPathComponent("desktop.json"))) { _, _, _ in
            await withCheckedContinuation { continuation in
                pending.append(continuation)
                started.continuation.yield(())
            }
        }
        var iterator = started.stream.makeAsyncIterator()
        model.scratchpad = "First draft."
        let first = try #require(model.runTransform())
        await iterator.next()
        model.scratchpad = "Second draft."
        let second = try #require(model.runTransform())
        await iterator.next()
        pending[0].resume(returning: "Old result.")
        await first.value
        #expect(model.transforming)
        #expect(model.transformResult.isEmpty)
        pending[1].resume(returning: "Current result.")
        await second.value
        #expect(!model.transforming)
        #expect(model.transformOriginal == "Second draft.")
        #expect(model.transformResult == "Current result.")
    }

    @Test("Apply and undo preserve the original; later typing clears undo")
    func applyAndUndo() async {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let model = AppModel(store: DesktopStore(url: directory.appendingPathComponent("desktop.json"))) { _, _, _ in
            "A clean draft."
        }
        let original = "  a rough draft\n"
        model.scratchpad = original
        await model.runTransform()?.value
        #expect(model.transformUndo == nil)
        model.applyTransform()
        #expect(model.scratchpad == "A clean draft.")
        #expect(model.transformResult.isEmpty)
        model.undoTransform()
        #expect(model.scratchpad == original)
        await model.runTransform()?.value
        model.applyTransform()
        model.scratchpad = "An edit after applying."
        model.undoTransform()
        #expect(model.scratchpad == "An edit after applying.")
    }

    @Test("Built-ins work without saved rewrites and custom names cannot duplicate choices")
    func rewriteChoices() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        var instructions: [String] = []
        let model = AppModel(store: DesktopStore(url: directory.appendingPathComponent("desktop.json"))) { text, instruction, _ in
            instructions.append(instruction)
            return text
        }
        #expect(model.data.transforms.isEmpty)
        model.scratchpad = "A draft."
        for preset in RewritePreset.allCases {
            model.selectedTransform = .preset(preset)
            await model.runTransform()?.value
            #expect(instructions.last == preset.instruction)
            #expect(model.transformResult == "A draft.")
        }
        #expect(model.saveTransform(name: " CLEAN UP ", instruction: "Make a list.") != nil)
        #expect(model.saveTransform(name: "my notes", instruction: "  Make a checklist.  ") == nil)
        let saved = try #require(model.data.transforms.first)
        #expect(saved.instruction == "Make a checklist.")
        #expect(model.selectedTransform == .custom(saved.id))
        #expect(model.saveTransform(name: "My Notes", instruction: "Different instructions.") != nil)
        await model.runTransform()?.value
        #expect(instructions.last == saved.instruction)
        #expect(model.saveTransform(name: "my notes", instruction: "Summarize.", replacing: saved.id) == nil)
        await model.runTransform()?.value
        #expect(instructions.last == "Summarize.")
        model.removeTransform(saved.id)
        #expect(model.selectedTransform == .preset(.cleanUp))
        #expect(model.transformResult.isEmpty)
        await model.runTransform()?.value
        #expect(instructions.last == RewritePreset.cleanUp.instruction)
    }

    @Test("Oversized drafts stay intact and the last saved dictation is available after launch")
    func inputReadiness() {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let model = AppModel(store: DesktopStore(url: directory.appendingPathComponent("desktop.json"))) { _, _, _ in
            Issue.record("Invalid input must not reach the writing model.")
            return ""
        }
        model.scratchpad = String(repeating: "x", count: LocalWriter.editInputLimit)
        #expect(model.runTransform() == nil)
        #expect(model.transformError != nil)
        #expect(model.scratchpad.count == LocalWriter.editInputLimit)
        #expect(!model.transforming)
        #expect(model.lastDictation == nil)
        model.data.history = [
            .init(original: "", text: "A voice edit.", appName: "Test", duration: 1, isCommand: true),
            .init(original: "", text: "The last dictation.", appName: "Test", duration: 1, isCommand: false)
        ]
        #expect(model.lastDictation == "The last dictation.")
        model.latestText = "A more recent dictation."
        #expect(model.lastDictation == "A more recent dictation.")
    }
}
