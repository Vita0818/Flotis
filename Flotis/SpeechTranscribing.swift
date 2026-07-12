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

protocol FileSpeechTranscribing: AnyObject {
    var partialTranscriptHandler: ((String) -> Void)? { get set }

    func transcribeFile(_ fileURL: URL) async throws -> String
    func cancel()
}

typealias SpeechTranscribing = StreamingSpeechTranscribing
