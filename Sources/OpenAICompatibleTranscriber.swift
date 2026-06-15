import Foundation

final class OpenAICompatibleTranscriber: SpeechTranscribing {
    var partialTranscriptHandler: ((String) -> Void)?
    
    private let config: TranscriptionProviderConfig
    private let apiKey: String
    private let audioRecorder = AudioRecorder()
    private var isRecording = false
    
    init(config: TranscriptionProviderConfig, apiKey: String) {
        self.config = config
        self.apiKey = apiKey
    }
    
    func start() async throws {
        // Request Microphone permission manually since AVAudioRecorder might just record silence
        // or fail if permission is not granted.
        // In macOS, if we haven't requested it, we should.
        // But AVAudioRecorder start usually handles the prompt on macOS.
        
        try audioRecorder.startRecording()
        isRecording = true
    }
    
    func stop() async throws -> String {
        guard isRecording else { return "" }
        isRecording = false
        
        guard let url = audioRecorder.stopRecording() else {
            throw NSError(domain: "OpenAICompatibleTranscriber", code: 1, userInfo: [NSLocalizedDescriptionKey: "录音文件创建失败"])
        }
        
        defer {
            try? FileManager.default.removeItem(at: url)
        }
        
        partialTranscriptHandler?("上传中...")
        
        return try await uploadAudio(at: url)
    }
    
    func cancel() {
        if isRecording {
            audioRecorder.cancelRecording()
            isRecording = false
        }
    }
    
    private func uploadAudio(at fileURL: URL) async throws -> String {
        guard let endpointURL = URL(string: config.baseURL + config.endpointPath) else {
            throw NSError(domain: "OpenAICompatibleTranscriber", code: 2, userInfo: [NSLocalizedDescriptionKey: "Base URL 非法"])
        }
        
        var request = URLRequest(url: endpointURL)
        request.httpMethod = "POST"
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        
        let boundary = "Boundary-\(UUID().uuidString)"
        request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
        
        var body = Data()
        
        // Model
        body.append("--\(boundary)\r\n".data(using: .utf8)!)
        body.append("Content-Disposition: form-data; name=\"model\"\r\n\r\n".data(using: .utf8)!)
        body.append("\(config.model)\r\n".data(using: .utf8)!)
        
        // Language
        if let language = config.language, !language.isEmpty {
            body.append("--\(boundary)\r\n".data(using: .utf8)!)
            body.append("Content-Disposition: form-data; name=\"language\"\r\n\r\n".data(using: .utf8)!)
            body.append("\(language)\r\n".data(using: .utf8)!)
        }
        
        // Temperature
        if let temp = config.temperature {
            body.append("--\(boundary)\r\n".data(using: .utf8)!)
            body.append("Content-Disposition: form-data; name=\"temperature\"\r\n\r\n".data(using: .utf8)!)
            body.append("\(temp)\r\n".data(using: .utf8)!)
        }
        
        // response_format
        body.append("--\(boundary)\r\n".data(using: .utf8)!)
        body.append("Content-Disposition: form-data; name=\"response_format\"\r\n\r\n".data(using: .utf8)!)
        body.append("json\r\n".data(using: .utf8)!)
        
        // File
        let filename = fileURL.lastPathComponent
        let fileData = try Data(contentsOf: fileURL)
        body.append("--\(boundary)\r\n".data(using: .utf8)!)
        body.append("Content-Disposition: form-data; name=\"file\"; filename=\"\(filename)\"\r\n".data(using: .utf8)!)
        body.append("Content-Type: audio/m4a\r\n\r\n".data(using: .utf8)!)
        body.append(fileData)
        body.append("\r\n".data(using: .utf8)!)
        
        body.append("--\(boundary)--\r\n".data(using: .utf8)!)
        
        let (data, response) = try await URLSession.shared.upload(for: request, from: body)
        
        guard let httpResponse = response as? HTTPURLResponse else {
            throw NSError(domain: "OpenAICompatibleTranscriber", code: 3, userInfo: [NSLocalizedDescriptionKey: "网络失败"])
        }
        
        guard (200...299).contains(httpResponse.statusCode) else {
            let errorText = String(data: data, encoding: .utf8) ?? "HTTP 非 2xx"
            throw NSError(domain: "OpenAICompatibleTranscriber", code: httpResponse.statusCode, userInfo: [NSLocalizedDescriptionKey: errorText])
        }
        
        guard let json = try JSONSerialization.jsonObject(with: data, options: []) as? [String: Any] else {
            throw NSError(domain: "OpenAICompatibleTranscriber", code: 4, userInfo: [NSLocalizedDescriptionKey: "JSON 解析失败"])
        }
        
        if let text = json["text"] as? String {
            return text
        } else if let transcript = json["transcript"] as? String {
            return transcript
        } else if let dataObj = json["data"] as? [String: Any], let text = dataObj["text"] as? String {
            return text
        }
        
        throw NSError(domain: "OpenAICompatibleTranscriber", code: 5, userInfo: [NSLocalizedDescriptionKey: "转写响应中没有找到 text 字段。"])
    }
}
