import Foundation

public enum MLXRuntimePreflight {
    public static func ensureReady() throws {
        if !hasMetalCompiler() {
            throw NSError(
                domain: "MLXRuntimePreflight",
                code: 1,
                userInfo: [
                    NSLocalizedDescriptionKey: "MLX runtime is not ready: missing Metal toolchain. Install full Xcode and run: sudo xcode-select -s /Applications/Xcode.app/Contents/Developer"
                ]
            )
        }
    }

    private static func hasMetalCompiler() -> Bool {
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
