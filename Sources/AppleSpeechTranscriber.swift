import Foundation
import Speech
import AVFoundation

final class AppleSpeechTranscriber: NSObject, SpeechTranscribing {
    var partialTranscriptHandler: ((String) -> Void)?
    
    private let speechRecognizer: SFSpeechRecognizer?
    private let audioEngine = AVAudioEngine()
    private var recognitionRequest: SFSpeechAudioBufferRecognitionRequest?
    private var recognitionTask: SFSpeechRecognitionTask?
    
    private var finalTranscript: String = ""
    private var isStopping = false
    
    init(localeIdentifier: String) {
        self.speechRecognizer = SFSpeechRecognizer(locale: Locale(identifier: localeIdentifier))
        super.init()
    }
    
    func start() async throws {
        // Request permissions
        let authStatus = await withCheckedContinuation { continuation in
            SFSpeechRecognizer.requestAuthorization { status in
                continuation.resume(returning: status)
            }
        }
        
        guard authStatus == .authorized else {
            throw NSError(domain: "AppleSpeechTranscriber", code: 1, userInfo: [NSLocalizedDescriptionKey: "需要开启麦克风和语音识别权限。"])
        }
        
        #if os(iOS)
        // AVAudioSession configuration is mostly for iOS, on macOS we just use the engine
        #endif
        
        if audioEngine.isRunning {
            audioEngine.stop()
            recognitionRequest?.endAudio()
        }
        
        recognitionTask?.cancel()
        recognitionTask = nil
        finalTranscript = ""
        isStopping = false
        
        let inputNode = audioEngine.inputNode
        
        recognitionRequest = SFSpeechAudioBufferRecognitionRequest()
        guard let recognitionRequest = recognitionRequest else {
            throw NSError(domain: "AppleSpeechTranscriber", code: 2, userInfo: [NSLocalizedDescriptionKey: "无法创建语音识别请求。"])
        }
        
        recognitionRequest.shouldReportPartialResults = true
        
        recognitionTask = speechRecognizer?.recognitionTask(with: recognitionRequest) { [weak self] result, error in
            guard let self = self else { return }
            var isFinal = false
            
            if let result = result {
                self.finalTranscript = result.bestTranscription.formattedString
                self.partialTranscriptHandler?(self.finalTranscript)
                isFinal = result.isFinal
            }
            
            if error != nil || isFinal || self.isStopping {
                self.audioEngine.stop()
                inputNode.removeTap(onBus: 0)
                self.recognitionRequest = nil
                self.recognitionTask = nil
            }
        }
        
        let recordingFormat = inputNode.outputFormat(forBus: 0)
        inputNode.installTap(onBus: 0, bufferSize: 1024, format: recordingFormat) { buffer, _ in
            self.recognitionRequest?.append(buffer)
        }
        
        audioEngine.prepare()
        try audioEngine.start()
    }
    
    func stop() async throws -> String {
        isStopping = true
        audioEngine.stop()
        audioEngine.inputNode.removeTap(onBus: 0)
        recognitionRequest?.endAudio()
        
        // Let the task finish processing the final buffer
        try await Task.sleep(nanoseconds: 500_000_000)
        
        return finalTranscript
    }
    
    func cancel() {
        isStopping = true
        audioEngine.stop()
        audioEngine.inputNode.removeTap(onBus: 0)
        recognitionRequest?.endAudio()
        recognitionTask?.cancel()
    }
}
