import Foundation

final class OpenAIRealtimeTranscriber: StreamingSpeechTranscribing {
    var partialTranscriptHandler: ((String) -> Void)?
    var finalTranscriptHandler: ((String) -> Void)?
    var errorHandler: ((String) -> Void)?

    private let config: SpeechProviderConfig
    private let apiKey: String
    private var webSocketTask: URLSessionWebSocketTask?
    private var receiveTask: Task<Void, Never>?
    private var partialTranscript = ""
    private var finalTranscript = ""
    private var isConnected = false

    init(config: SpeechProviderConfig, apiKey: String) {
        self.config = config
        self.apiKey = apiKey
    }

    func start() async throws {
        let url = try makeRealtimeURL()
        var request = URLRequest(url: url)
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("realtime=v1", forHTTPHeaderField: "OpenAI-Beta")

        partialTranscript = ""
        finalTranscript = ""

        let task = URLSession.shared.webSocketTask(with: request)
        webSocketTask = task
        task.resume()
        isConnected = true

        try await sendJSON(sessionUpdatePayload())
        receiveTask = Task { [weak self] in
            await self?.receiveLoop()
        }
    }

    func appendAudio(_ data: Data) async throws {
        guard isConnected else { return }
        let payload: [String: Any] = [
            "type": "input_audio_buffer.append",
            "audio": data.base64EncodedString()
        ]
        try await sendJSON(payload)
    }

    func stop() async throws -> String {
        if isConnected {
            try? await sendJSON(["type": "input_audio_buffer.commit"])
            try? await Task.sleep(nanoseconds: 700_000_000)
        }

        disconnect()
        let text = finalTranscript.isEmpty ? partialTranscript : finalTranscript
        finalTranscriptHandler?(text)
        return text
    }

    func cancel() {
        disconnect()
    }

    private func receiveLoop() async {
        while !Task.isCancelled, let webSocketTask {
            do {
                let message = try await webSocketTask.receive()
                switch message {
                case .string(let text):
                    handleMessage(text)
                case .data(let data):
                    if let text = String(data: data, encoding: .utf8) {
                        handleMessage(text)
                    }
                @unknown default:
                    break
                }
            } catch {
                if isConnected {
                    errorHandler?(error.localizedDescription)
                }
                break
            }
        }
    }

    private func handleMessage(_ text: String) {
        guard let data = text.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return
        }

        let type = (json["type"] as? String) ?? (json["event"] as? String) ?? ""

        if type == "error" || json["error"] != nil {
            errorHandler?(extractError(from: json))
            return
        }

        if isDeltaEvent(type) {
            let delta = extractText(from: json, keys: ["delta", "text", "transcript"])
            guard !delta.isEmpty else { return }
            partialTranscript += delta
            partialTranscriptHandler?(partialTranscript)
            return
        }

        if isCompletedEvent(type) {
            let completed = extractText(from: json, keys: ["transcript", "text", "delta"])
            if !completed.isEmpty {
                finalTranscript = completed
            } else if finalTranscript.isEmpty {
                finalTranscript = partialTranscript
            }
            partialTranscriptHandler?(finalTranscript)
            finalTranscriptHandler?(finalTranscript)
            return
        }

        if type == "input_audio_buffer.speech_started" {
            return
        }

        if type == "input_audio_buffer.speech_stopped" {
            return
        }
    }

    private func isDeltaEvent(_ type: String) -> Bool {
        type == "conversation.item.input_audio_transcription.delta"
            || type == "transcript.delta"
            || type == "transcription.delta"
            || (type.contains("transcription") && type.contains("delta"))
            || (type.contains("transcript") && type.contains("delta"))
    }

    private func isCompletedEvent(_ type: String) -> Bool {
        type == "conversation.item.input_audio_transcription.completed"
            || type == "transcript.completed"
            || type == "transcription.completed"
            || (type.contains("transcription") && type.contains("completed"))
            || (type.contains("transcript") && type.contains("completed"))
    }

    private func extractText(from json: [String: Any], keys: [String]) -> String {
        for key in keys {
            if let value = json[key] as? String {
                return value
            }
        }

        if let item = json["item"] as? [String: Any] {
            for key in keys {
                if let value = item[key] as? String {
                    return value
                }
            }
        }

        if let transcript = json["transcription"] as? [String: Any] {
            for key in keys {
                if let value = transcript[key] as? String {
                    return value
                }
            }
        }

        return ""
    }

    private func extractError(from json: [String: Any]) -> String {
        if let error = json["error"] as? [String: Any] {
            if let message = error["message"] as? String {
                return message
            }
            if let code = error["code"] as? String {
                return code
            }
        }

        if let message = json["message"] as? String {
            return message
        }

        return "实时提供商返回错误。"
    }

    private func makeRealtimeURL() throws -> URL {
        guard let realtimeURL = config.realtimeURL, !realtimeURL.isEmpty,
              let realtimePath = config.realtimePath, !realtimePath.isEmpty else {
            throw NSError(
                domain: "OpenAIRealtimeTranscriber",
                code: 1,
                userInfo: [NSLocalizedDescriptionKey: "当前提供商不支持实时转写，请切换到 HTTP 转写模式。"]
            )
        }

        let base = realtimeURL.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        let path = realtimePath.hasPrefix("/") ? realtimePath : "/\(realtimePath)"
        guard var components = URLComponents(string: base + path) else {
            throw NSError(
                domain: "OpenAIRealtimeTranscriber",
                code: 2,
                userInfo: [NSLocalizedDescriptionKey: "实时地址非法。"]
            )
        }

        var queryItems = components.queryItems ?? []
        if !config.model.isEmpty,
           !queryItems.contains(where: { $0.name == "model" }) {
            queryItems.append(URLQueryItem(name: "model", value: config.model))
        }
        components.queryItems = queryItems

        guard let url = components.url else {
            throw NSError(
                domain: "OpenAIRealtimeTranscriber",
                code: 3,
                userInfo: [NSLocalizedDescriptionKey: "实时地址生成失败。"]
            )
        }
        return url
    }

    private func sessionUpdatePayload() -> [String: Any] {
        var transcription: [String: Any] = [
            "model": config.model
        ]

        if let language = config.language, !language.isEmpty {
            transcription["language"] = language
        }
        if let prompt = config.prompt, !prompt.isEmpty {
            transcription["prompt"] = prompt
        }

        var session: [String: Any] = [
            "input_audio_format": config.inputAudioFormat ?? "pcm16",
            "input_audio_transcription": transcription
        ]

        if config.enableServerVAD {
            session["turn_detection"] = [
                "type": "server_vad"
            ]
        } else {
            session["turn_detection"] = NSNull()
        }

        return [
            "type": "session.update",
            "session": session
        ]
    }

    private func sendJSON(_ payload: [String: Any]) async throws {
        guard let webSocketTask else { return }
        let data = try JSONSerialization.data(withJSONObject: payload)
        guard let text = String(data: data, encoding: .utf8) else { return }
        try await webSocketTask.send(.string(text))
    }

    private func disconnect() {
        isConnected = false
        receiveTask?.cancel()
        receiveTask = nil
        webSocketTask?.cancel(with: .normalClosure, reason: nil)
        webSocketTask = nil
    }
}
