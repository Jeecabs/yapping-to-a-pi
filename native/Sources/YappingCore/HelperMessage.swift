import Foundation

public enum HelperMessage: Equatable, Sendable {
    case state(String, inputDevice: String?)
    case partial(String)
    case final(String)
    case failure(String)
    case level(Double)

    public static func decode(_ data: Data) throws -> Self {
        let message = try JSONDecoder().decode(WireMessage.self, from: data)
        switch message.type {
        case "state":
            guard let state = message.state,
                  ["preparing", "installing-model", "requesting-permission", "listening", "finalizing"].contains(state),
                  message.locale?.isEmpty == false else { throw ProtocolFailure.invalidMessage }
            return .state(state, inputDevice: message.inputDevice)
        case "partial", "final":
            guard let text = message.text else { throw ProtocolFailure.invalidMessage }
            return message.type == "partial" ? .partial(text) : .final(text)
        case "error":
            guard let code = message.code, !code.isEmpty, let text = message.message, !text.isEmpty else { throw ProtocolFailure.invalidMessage }
            return .failure(text)
        case "level":
            guard let level = message.level, level.isFinite, (0...1).contains(level) else { throw ProtocolFailure.invalidMessage }
            return .level(level)
        default: throw ProtocolFailure.invalidMessage
        }
    }

    private struct WireMessage: Decodable {
        let type: String
        let state: String?
        let locale: String?
        let inputDevice: String?
        let text: String?
        let code: String?
        let message: String?
        let level: Double?
    }

    public enum ProtocolFailure: LocalizedError {
        case invalidMessage, oversizedMessage
        public var errorDescription: String? { "The speech helper returned an invalid response. Your last preview is available in Yapping." }
    }
}

public struct MessageFramer: Sendable {
    private var pending = Data()
    public init() {}
    public mutating func append(_ bytes: Data) throws -> [HelperMessage] {
        pending.append(bytes)
        var messages: [HelperMessage] = []
        while let newline = pending.firstIndex(of: 10) {
            let line = pending[..<newline]
            guard line.count <= 1_048_576 else { throw HelperMessage.ProtocolFailure.oversizedMessage }
            if !line.isEmpty { messages.append(try HelperMessage.decode(Data(line))) }
            pending.removeSubrange(...newline)
        }
        guard pending.count <= 1_048_576 else { throw HelperMessage.ProtocolFailure.oversizedMessage }
        return messages
    }
    public func finish() throws {
        guard pending.isEmpty else { throw HelperMessage.ProtocolFailure.invalidMessage }
    }
}
