import AVFoundation
import Darwin
import Foundation
import Speech

private struct Options {
    var doctor = false
    var localeIdentifier = "en-AU"

    static func parse(_ arguments: [String]) throws -> Options {
        var options = Options()
        var index = 0

        while index < arguments.count {
            switch arguments[index] {
            case "--doctor":
                options.doctor = true
                index += 1
            case "--locale":
                guard index + 1 < arguments.count else {
                    throw HelperFailure.invalidArguments("--locale requires a BCP-47 locale.")
                }
                options.localeIdentifier = arguments[index + 1]
                index += 2
            case "--help", "-h":
                FileHandle.standardError.write(Data("Usage: yapping-to-a-pi-helper [--doctor] [--locale en-AU]\n".utf8))
                exit(0)
            default:
                throw HelperFailure.invalidArguments("Unknown argument: \(arguments[index])")
            }
        }

        return options
    }
}

@main
struct YappingToAPiHelper {
    static func main() async {
        let emitter = ProtocolEmitter()

        do {
            let options = try Options.parse(Array(CommandLine.arguments.dropFirst()))
            let locale = Locale(identifier: options.localeIdentifier)
            let identifier = locale.identifier(.bcp47)

            if options.doctor {
                await emitter.doctor(DoctorMessage(
                    locale: identifier,
                    supported: await LiveDictation.isSupported(identifier),
                    installed: await LiveDictation.isInstalled(identifier),
                    microphone: microphoneStatus(),
                    osVersion: ProcessInfo.processInfo.operatingSystemVersionString
                ))
                return
            }

            try await LiveDictation(locale: locale, localeIdentifier: identifier, emitter: emitter).run()
        } catch let failure as HelperFailure {
            await emitter.error(code: failure.code, message: failure.localizedDescription)
            FileHandle.standardError.write(Data("\(failure.localizedDescription)\n".utf8))
            exit(1)
        } catch {
            await emitter.error(code: "transcription-failed", message: error.localizedDescription)
            FileHandle.standardError.write(Data("\(error.localizedDescription)\n".utf8))
            exit(1)
        }
    }

    private static func microphoneStatus() -> String {
        switch AVCaptureDevice.authorizationStatus(for: .audio) {
        case .authorized: "authorized"
        case .denied: "denied"
        case .notDetermined: "not-determined"
        case .restricted: "restricted"
        @unknown default: "unknown"
        }
    }
}
