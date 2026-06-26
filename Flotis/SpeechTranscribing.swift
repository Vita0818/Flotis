import Foundation

protocol StreamingSpeechTranscribing: AnyObject {
    var partialTranscriptHandler: ((String) -> Void)? { get set }
    var finalTranscriptHandler: ((String) -> Void)? { get set }
    var errorHandler: ((String) -> Void)? { get set }

    func start() async throws
    func appendAudio(_ data: Data) async throws
    func stop() async throws -> String
    func cancel()
}

protocol FileSpeechTranscribing {
    func transcribeFile(_ fileURL: URL, config: SpeechProviderConfig) async throws -> String
}

typealias SpeechTranscribing = StreamingSpeechTranscribing
