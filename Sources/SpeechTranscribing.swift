import Foundation

protocol SpeechTranscribing {
    var partialTranscriptHandler: ((String) -> Void)? { get set }
    func start() async throws
    func stop() async throws -> String
    func cancel()
}
