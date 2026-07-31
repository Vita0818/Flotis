import Foundation

private actor DashScopeRealtimeState {
    struct Status {
        let ready: Bool
        let transcript: String
        let errorMessage: String?
    }

    private var committedTranscript = ""
    private var currentPartial = ""
    private var taskStarted = false
    private var taskFinished = false
    private var errorMessage: String?
    private var activeAppendOperations = 0
    private var stopping = false

    func reset() {
        committedTranscript = ""
        currentPartial = ""
        taskStarted = false
        taskFinished = false
        errorMessage = nil
        activeAppendOperations = 0
        stopping = false
    }

    func markTaskStarted() {
        taskStarted = true
    }

    func markTaskFinished() {
        taskFinished = true
    }

    func startStatus() -> Status {
        Status(ready: taskStarted, transcript: displayTranscript(), errorMessage: errorMessage)
    }

    func beginAppend() throws {
        if let errorMessage {
            throw makeError(errorMessage)
        }
        guard taskStarted, !stopping else {
            throw CancellationError()
        }
        activeAppendOperations += 1
    }

    func finishAppend() {
        activeAppendOperations = max(0, activeAppendOperations - 1)
    }

    func beginStopping() {
        stopping = true
    }

    func appendDrainStatus() -> Status {
        Status(
            ready: activeAppendOperations == 0,
            transcript: displayTranscript(),
            errorMessage: errorMessage
        )
    }

    func stopStatus() -> Status {
        Status(
            ready: taskFinished && activeAppendOperations == 0,
            transcript: displayTranscript(),
            errorMessage: errorMessage
        )
    }

    func serverClosedAfterTerminalEvent() -> Bool {
        taskFinished && activeAppendOperations == 0
    }

    func applyResult(text: String, sentenceEnded: Bool) -> String {
        if sentenceEnded {
            // Each sentence_end result is a distinct spoken segment. Never suppress a
            // segment merely because it equals the suffix of the previous sentence.
            committedTranscript = appendDashScopeSegment(text, to: committedTranscript)
            currentPartial = ""
        } else {
            currentPartial = text
        }
        return displayTranscript()
    }

    func recordError(_ message: String) {
        if errorMessage == nil {
            errorMessage = message
        }
    }

    func cancel() {
        stopping = true
        if errorMessage == nil {
            errorMessage = UIStrings.localized(
                english: "Qwen/DashScope Realtime transcription was canceled.",
                simplifiedChinese: "Qwen/百炼实时转写已取消。"
            )
        }
    }

    private func displayTranscript() -> String {
        appendDashScopeSegment(currentPartial, to: committedTranscript)
    }

    private func makeError(_ message: String) -> NSError {
        NSError(
            domain: "DashScopeParaformerRealtimeTranscriber",
            code: 10,
            userInfo: [NSLocalizedDescriptionKey: message]
        )
    }
}

// Pure merge helper kept internal so segment-repeat and CJK-spacing behavior can be
// covered by a future XCTest without constructing a WebSocket transcriber.
func appendDashScopeSegment(_ segment: String, to base: String) -> String {
    appendTranscriptSegment(segment, to: base)
}

final class DashScopeParaformerRealtimeTranscriber: StreamingSpeechTranscribing {
    private let handlers = LockedTranscriptionHandlers()
    var partialTranscriptHandler: ((String) -> Void)? {
        get { handlers.partialHandler }
        set { handlers.partialHandler = newValue }
    }
    var finalTranscriptHandler: ((String) -> Void)? {
        get { handlers.finalHandler }
        set { handlers.finalHandler = newValue }
    }
    var errorHandler: ((String) -> Void)? {
        get { handlers.errorHandler }
        set { handlers.errorHandler = newValue }
    }

    private let config: SpeechProviderConfig
    private let apiKey: String
    private let taskID = UUID().uuidString
    private let state = DashScopeRealtimeState()
    private let connection = LockedWebSocketConnection()
    private let senderSlot = LockedRealtimeSender()

    init(config: SpeechProviderConfig, apiKey: String) {
        self.config = config
        self.apiKey = apiKey
    }

    func start() async throws {
        try validateAudioConfiguration()
        let url = try makeRealtimeURL()
        var request = URLRequest(url: url)
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")

        await state.reset()
        let socket = noRedirectRealtimeURLSession.webSocketTask(with: request)
        let sender = SerializedWebSocketSender(socket: socket)
        senderSlot.install(sender)
        connection.install(socket: socket)
        socket.resume()

        let receiveTask = Task<Void, Never> { [weak self] in
            guard let self else { return }
            await self.receiveLoop(socket: socket)
        }
        connection.attach(receiveTask: receiveTask, to: socket)

        do {
            try await sendJSON(runTaskPayload(), using: sender)
            _ = try await waitForRealtimeCondition(
                timeout: 5,
                timeoutMessage: UIStrings.localized(
                    english: "Timed out starting Qwen/DashScope Realtime transcription.",
                    simplifiedChinese: "Qwen/百炼实时转写启动超时。"
                )
            ) {
                let status = await self.state.startStatus()
                if let errorMessage = status.errorMessage {
                    throw self.makeError(errorMessage)
                }
                return status.ready ? true : nil
            }
        } catch {
            disconnect()
            throw error
        }
    }

    func appendAudio(_ data: Data) async throws {
        guard !data.isEmpty else { return }
        guard let sender = senderSlot.current() else {
            throw makeError(UIStrings.localized(
                english: "The Qwen/DashScope Realtime connection has not been established.",
                simplifiedChinese: "Qwen/百炼实时连接尚未建立。"
            ))
        }

        try await state.beginAppend()
        do {
            try await sender.send(.data(data))
            await state.finishAppend()
        } catch {
            await state.finishAppend()
            await state.recordError(error.localizedDescription)
            throw error
        }
    }

    func stop() async throws -> String {
        guard let sender = senderSlot.current() else {
            throw makeError(UIStrings.localized(
                english: "The Qwen/DashScope Realtime connection has not been established.",
                simplifiedChinese: "Qwen/百炼实时连接尚未建立。"
            ))
        }

        await state.beginStopping()
        do {
            _ = try await waitForRealtimeCondition(
                timeout: 3,
                timeoutMessage: UIStrings.localized(
                    english: "Timed out waiting for Qwen/DashScope audio delivery to finish.",
                    simplifiedChinese: "等待 Qwen/百炼音频发送完成超时。"
                )
            ) {
                let status = await self.state.appendDrainStatus()
                if let errorMessage = status.errorMessage {
                    throw self.makeError(errorMessage)
                }
                return status.ready ? true : nil
            }
            try await sender.drain()
            try await sendJSON(finishTaskPayload(), using: sender)

            let text = try await waitForRealtimeCondition(
                timeout: 8,
                timeoutMessage: UIStrings.localized(
                    english: "Timed out waiting for the final Qwen/DashScope Realtime transcription.",
                    simplifiedChinese: "Qwen/百炼实时转写最终结果超时。"
                )
            ) {
                let status = await self.state.stopStatus()
                if let errorMessage = status.errorMessage {
                    throw self.makeError(errorMessage)
                }
                return status.ready ? status.transcript : nil
            }
            disconnect()
            handlers.finalHandler?(text)
            return text
        } catch {
            disconnect()
            throw error
        }
    }

    func cancel() {
        disconnect()
        Task { await state.cancel() }
    }

    private func receiveLoop(socket: URLSessionWebSocketTask) async {
        while !Task.isCancelled, connection.isActive(socket) {
            do {
                let message = try await socket.receive()
                guard connection.isActive(socket), !Task.isCancelled else { return }
                switch message {
                case .string(let text):
                    await handleMessage(text)
                case .data(let data):
                    if let text = String(data: data, encoding: .utf8) {
                        await handleMessage(text)
                    }
                @unknown default:
                    break
                }
            } catch {
                guard connection.isActive(socket), !Task.isCancelled else { return }
                if await state.serverClosedAfterTerminalEvent() { return }
                let message = error.localizedDescription
                await state.recordError(message)
                handlers.errorHandler?(message)
                return
            }
        }
    }

    private func handleMessage(_ text: String) async {
        guard let data = text.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return
        }
        if let header = json["header"] as? [String: Any],
           let responseTaskID = header["task_id"] as? String,
           responseTaskID != taskID {
            return
        }

        switch extractEvent(from: json) {
        case "task-started":
            await state.markTaskStarted()
        case "result-generated":
            await handleResultGenerated(json)
        case "task-finished":
            await state.markTaskFinished()
        case "task-failed":
            let message = extractError(from: json)
            await state.recordError(message)
            handlers.errorHandler?(message)
        default:
            if json["error"] != nil {
                let message = extractError(from: json)
                await state.recordError(message)
                handlers.errorHandler?(message)
            }
        }
    }

    private func handleResultGenerated(_ json: [String: Any]) async {
        guard let sentence = (((json["payload"] as? [String: Any])?["output"] as? [String: Any])?["sentence"] as? [String: Any]),
              let text = sentence["text"] as? String,
              !text.isEmpty,
              sentence["heartbeat"] as? Bool != true else {
            return
        }

        let sentenceEnded = sentence["sentence_end"] as? Bool ?? false
        let display = await state.applyResult(text: text, sentenceEnded: sentenceEnded)
        handlers.partialHandler?(display)
        if sentenceEnded {
            handlers.finalHandler?(display)
        }
    }

    private func makeRealtimeURL() throws -> URL {
        guard let realtimeURL = config.realtimeURL, !realtimeURL.isEmpty,
              let realtimePath = config.realtimePath, !realtimePath.isEmpty else {
            throw makeError(UIStrings.localized(
                english: "The Qwen/DashScope Realtime endpoint is not configured.",
                simplifiedChinese: "Qwen/百炼实时地址未配置。"
            ))
        }

        let base = realtimeURL.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        let path = realtimePath.hasPrefix("/") ? realtimePath : "/\(realtimePath)"
        guard let url = URL(string: base + path),
              url.scheme?.lowercased() == "wss",
              url.host?.isEmpty == false else {
            throw makeError(UIStrings.localized(
                english: "The Qwen/DashScope Realtime endpoint must be a valid wss:// address.",
                simplifiedChinese: "Qwen/百炼实时地址必须是有效的 wss:// 地址。"
            ))
        }
        return url
    }

    private func runTaskPayload() -> [String: Any] {
        var parameters: [String: Any] = [
            "format": "pcm",
            "sample_rate": config.sampleRate ?? 16000,
            "punctuation_prediction_enabled": true,
            "inverse_text_normalization_enabled": true,
            "disfluency_removal_enabled": false,
            // Prevent the documented 60-second silent-audio timeout.
            "heartbeat": true
        ]
        if let language = normalizedLanguageHint(config.language) {
            parameters["language_hints"] = [language]
        }

        return [
            "header": [
                "action": "run-task",
                "task_id": taskID,
                "streaming": "duplex"
            ],
            "payload": [
                "task_group": "audio",
                "task": "asr",
                "function": "recognition",
                "model": config.model.isEmpty ? "paraformer-realtime-v2" : config.model,
                "parameters": parameters,
                "input": [:] as [String: Any]
            ]
        ]
    }

    private func finishTaskPayload() -> [String: Any] {
        [
            "header": [
                "action": "finish-task",
                "task_id": taskID,
                "streaming": "duplex"
            ],
            "payload": ["input": [:] as [String: Any]]
        ]
    }

    private func sendJSON(
        _ payload: [String: Any],
        using sender: SerializedWebSocketSender
    ) async throws {
        let data = try JSONSerialization.data(withJSONObject: payload)
        guard let text = String(data: data, encoding: .utf8) else {
            throw makeError(UIStrings.localized(
                english: "Could not encode the Qwen/DashScope request.",
                simplifiedChinese: "Qwen/百炼请求编码失败。"
            ))
        }
        try await sender.send(.string(text))
    }

    private func disconnect() {
        senderSlot.clear()
        connection.disconnect()
    }

    private func extractEvent(from json: [String: Any]) -> String {
        if let header = json["header"] as? [String: Any],
           let event = header["event"] as? String {
            return event
        }
        return (json["event"] as? String) ?? (json["type"] as? String) ?? ""
    }

    private func extractError(from json: [String: Any]) -> String {
        if let error = json["error"] as? [String: Any] {
            if let message = error["message"] as? String { return message }
            if let code = error["code"] as? String { return code }
        }
        if let header = json["header"] as? [String: Any],
           let message = header["error_message"] as? String {
            return message
        }
        if let message = json["message"] as? String { return message }
        return UIStrings.localized(
            english: "Qwen/DashScope Realtime transcription returned an error.",
            simplifiedChinese: "Qwen/百炼实时转写返回错误。"
        )
    }

    private func normalizedLanguageHint(_ language: String?) -> String? {
        guard let language, !language.isEmpty else { return nil }
        let lowercased = language.lowercased()
        if lowercased.hasPrefix("zh") { return "zh" }
        if lowercased.hasPrefix("en") { return "en" }
        if lowercased.hasPrefix("ja") { return "ja" }
        if lowercased.hasPrefix("ko") { return "ko" }
        if lowercased.hasPrefix("yue") { return "yue" }
        return language
    }

    private func validateAudioConfiguration() throws {
        let format = (config.inputAudioFormat ?? "pcm").lowercased()
        guard format == "pcm" || format == "pcm16" else {
            throw makeError(UIStrings.localized(
                english: "The current Qwen/DashScope Realtime capture pipeline only supports raw PCM16.",
                simplifiedChinese: "Qwen/百炼当前实时捕获管线仅支持裸 PCM16。"
            ))
        }
        let sampleRate = config.sampleRate ?? 16000
        guard sampleRate == 8000 || sampleRate == 16000 else {
            throw makeError(UIStrings.localized(
                english: "Qwen/DashScope PCM supports only 8000 or 16000 Hz sample rates.",
                simplifiedChinese: "Qwen/百炼 PCM 采样率仅支持 8000 或 16000 Hz。"
            ))
        }
        guard (config.channels ?? 1) == 1 else {
            throw makeError(UIStrings.localized(
                english: "Qwen/DashScope Realtime transcription requires mono audio.",
                simplifiedChinese: "Qwen/百炼实时转写要求单声道。"
            ))
        }
    }

    private func makeError(_ message: String) -> NSError {
        NSError(
            domain: "DashScopeParaformerRealtimeTranscriber",
            code: 1,
            userInfo: [NSLocalizedDescriptionKey: message]
        )
    }
}
