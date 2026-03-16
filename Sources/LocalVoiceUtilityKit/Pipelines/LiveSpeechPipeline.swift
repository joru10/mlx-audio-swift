import Foundation

public enum LiveSpeechPipeline {
    public static func start() throws {
        throw NSError(
            domain: "LiveSpeechPipeline",
            code: 1,
            userInfo: [NSLocalizedDescriptionKey: "Live mode is planned for Pro milestone and not yet implemented."]
        )
    }
}
