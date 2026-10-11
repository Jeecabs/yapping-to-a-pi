import AVFoundation
import Darwin
import Foundation
import Speech

private struct Options {
    var doctor = false
    var localeIdentifier = "en-AU"
    var inputUID: String?
    var meter = false

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
            case "--meter":
                options.meter = true
                index += 1
            case "--input-uid":
                guard index + 1 < arguments.count, !arguments[index + 1].isEmpty else {
                    throw HelperFailure.invalidArguments("--input-uid requires an audio device UID.")
                }
                options.inputUID = arguments[index + 1]
                index += 2
            case "--help", "-h":
                FileHandle.standardError.write(Data("Usage: yapping-to-a-pi-helper [--doctor] [--locale en-AU] [--input-uid UID] [--meter]\n".utf8))
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
            let selectedLocale = await LiveDictation.supportedLocale(equivalentTo: locale)
            let identifier = (selectedLocale ?? locale).identifier(.bcp47)

            if options.doctor {
                await emitter.doctor(DoctorMessage(
                    locale: identifier,
                    supported: selectedLocale != nil,
                    installed: await LiveDictation.isInstalled(locale),
                    microphone: microphoneStatus(),
                    inputDevice: LiveDictation.currentInputDeviceName(),
                    osVersion: ProcessInfo.processInfo.operatingSystemVersionString
                ))
                return
            }

            try await LiveDictation(locale: locale, emitter: emitter, inputUID: options.inputUID, emitMeter: options.meter).run()
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
