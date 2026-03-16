import Foundation
import LocalVoiceUtilityKit

@main
enum LocalVoiceUtilityCLI {
    static func main() async {
        do {
            let args = Array(CommandLine.arguments.dropFirst())
            guard let command = args.first else {
                printUsage()
                return
            }

            let coordinator = LocalVoiceCoordinator()
            _ = try await coordinator.recoverInterruptedJobs()
            switch command {
            case "list-jobs":
                let jobs = try await coordinator.loadJobs()
                jobs.forEach { job in
                    print("\(job.id.uuidString)\t\(job.type.rawValue)\t\(job.status.rawValue)\t\(job.inputRef)")
                }
            case "pdf2audio":
                guard args.count >= 2 else { throw CLIError.missingArgument("pdf path") }
                let inputURL = URL(fileURLWithPath: args[1])
                guard FileManager.default.fileExists(atPath: inputURL.path) else {
                    throw CLIError.inputNotFound(inputURL.path)
                }
                let result = try await coordinator.runPDFToAudioNow(inputURL: inputURL, options: TTSOptions())
                print("PDF -> Audio job \(result.status.rawValue): \(result.id.uuidString)")
                if let audioPath = result.outputRefs.audioPath {
                    print("Output audio: \(audioPath)")
                }
                if let error = result.errorMessage {
                    print("Error: \(error)")
                }
            case "transcribe":
                guard args.count >= 2 else { throw CLIError.missingArgument("media path") }
                let inputURL = URL(fileURLWithPath: args[1])
                guard FileManager.default.fileExists(atPath: inputURL.path) else {
                    throw CLIError.inputNotFound(inputURL.path)
                }
                let result = try await coordinator.runTranscriptionNow(inputURL: inputURL, options: STTOptions())
                print("Transcription job \(result.status.rawValue): \(result.id.uuidString)")
                if let transcriptPath = result.outputRefs.transcriptPath {
                    print("Output transcript: \(transcriptPath)")
                }
                if let error = result.errorMessage {
                    print("Error: \(error)")
                }
            default:
                printUsage()
            }
        } catch {
            fputs("Error: \(error.localizedDescription)\n", stderr)
            exit(1)
        }
    }

    private static func printUsage() {
        print(
            """
            local-voice-utility-cli commands:
              list-jobs
              pdf2audio <pdf-path>
              transcribe <media-path>
            """
        )
    }
}

enum CLIError: LocalizedError {
    case missingArgument(String)
    case inputNotFound(String)

    var errorDescription: String? {
        switch self {
        case .missingArgument(let value):
            return "Missing required argument: \(value)"
        case .inputNotFound(let path):
            return "Input file not found: \(path)"
        }
    }
}
