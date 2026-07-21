import Foundation

actor ProtocolEmitter {
    private let encoder = JSONEncoder()

    func state(_ state: String, locale: String) {
        emit(StateMessage(type: "state", state: state, locale: locale))
    }

    func partial(_ text: String) {
        emit(TextMessage(type: "partial", text: text))
    }

    func final(_ text: String) {
        emit(TextMessage(type: "final", text: text))
    }

    func error(code: String, message: String) {
        emit(ErrorMessage(type: "error", code: code, message: message))
    }

    func doctor(_ message: DoctorMessage) {
        emit(message)
    }

    private func emit<T: Encodable>(_ message: T) {
        do {
            let data = try encoder.encode(message)
            FileHandle.standardOutput.write(data)
            FileHandle.standardOutput.write(Data([0x0A]))
        } catch {
            FileHandle.standardError.write(Data("protocol encoding failed: \(error)\n".utf8))
        }
    }
}

private struct StateMessage: Encodable {
    let type: String
    let state: String
    let locale: String
}

private struct TextMessage: Encodable {
    let type: String
    let text: String
}

private struct ErrorMessage: Encodable {
    let type: String
    let code: String
    let message: String
}

struct DoctorMessage: Encodable {
    let type = "doctor"
    let locale: String
    let engine = "speech-transcriber"
    let supported: Bool
    let installed: Bool
    let microphone: String
    let osVersion: String
}
