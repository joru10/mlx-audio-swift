import Foundation
import Testing

enum MLXTestSupport {
    static var runtimeAvailable: Bool {
        if ProcessInfo.processInfo.environment["MLXAUDIO_FORCE_TESTS"] == "1" {
            return true
        }

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/xcrun")
        process.arguments = ["--sdk", "macosx", "--find", "metal"]
        process.standardOutput = Pipe()
        process.standardError = Pipe()

        do {
            try process.run()
            process.waitUntilExit()
            return process.terminationStatus == 0
        } catch {
            return false
        }
    }
}
