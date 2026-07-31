import Foundation

private actor VolcengineRealtimeState {
    struct Status {
        let ready: Bool
        let transcript: String
        let errorMessage: String?
    }

    private var latestTranscript = ""
    private var serverReady = false
    private var finalPacketReceived = false
    private var errorMessage: String?
    private var activeAppendOperations = 0
    private var stopping = false

    func reset() {
        latestTranscript = ""
        serverReady = false
        finalPacketReceived = false
        errorMessage = nil
        activeAppendOperations = 0
        stopping = false
    }

    func markServerReady() {
        serverReady = true
    }

    func startStatus() -> Status {
        Status(ready: serverReady, transcript: latestTranscript, errorMessage: errorMessage)
    }

    func beginAppend() throws {
        if let errorMessage {
            throw makeError(errorMessage)
        }
        guard serverReady, !stopping else {
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
            transcript: latestTranscript,
            errorMessage: errorMessage
        )
    }

    func updateTranscript(_ text: String) {
        latestTranscript = text
    }

    func markFinalPacketReceived() {
        finalPacketReceived = true
    }

    func stopStatus() -> Status {
        Status(
            ready: finalPacketReceived && activeAppendOperations == 0,
            transcript: latestTranscript,
            errorMessage: errorMessage
        )
    }

    func serverClosedAfterTerminalEvent() -> Bool {
        stopping && finalPacketReceived && activeAppendOperations == 0
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
                english: "Volcengine Realtime transcription was canceled.",
                simplifiedChinese: "火山语音实时转写已取消。"
            )
        }
    }

    private func makeError(_ message: String) -> NSError {
        NSError(
            domain: "VolcengineBigASRRealtimeTranscriber",
            code: 10,
            userInfo: [NSLocalizedDescriptionKey: message]
        )
    }
}

final class VolcengineBigASRRealtimeTranscriber: StreamingSpeechTranscribing {
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
    private let requestID = UUID().uuidString
    private let state = VolcengineRealtimeState()
    private let connection = LockedWebSocketConnection()
    private let senderSlot = LockedRealtimeSender()

    init(config: SpeechProviderConfig, apiKey: String) {
        self.config = config
        self.apiKey = apiKey
    }

    func start() async throws {
        try validateConfiguration()
        let url = try makeRealtimeURL()
        var request = URLRequest(url: url)
        request.setValue(apiKey, forHTTPHeaderField: "X-Api-Key")
        request.setValue(try resourceID(), forHTTPHeaderField: "X-Api-Resource-Id")
        request.setValue(requestID, forHTTPHeaderField: "X-Api-Request-Id")
        request.setValue(requestID, forHTTPHeaderField: "X-Api-Connect-Id")
        request.setValue("-1", forHTTPHeaderField: "X-Api-Sequence")

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
            try await sendFullClientRequest(using: sender)
            _ = try await waitForRealtimeCondition(
                timeout: 5,
                timeoutMessage: UIStrings.localized(
                    english: "Timed out waiting for Volcengine Realtime startup confirmation.",
                    simplifiedChinese: "火山语音实时转写启动确认超时。"
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
                english: "The Volcengine Realtime connection has not been established.",
                simplifiedChinese: "火山语音实时连接尚未建立。"
            ))
        }

        try await state.beginAppend()
        do {
            try await sender.send(.data(makeMessage(
                type: .audioOnlyClientRequest,
                flags: .none,
                serialization: .none,
                compression: .none,
                payload: data
            )))
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
                english: "The Volcengine Realtime connection has not been established.",
                simplifiedChinese: "火山语音实时连接尚未建立。"
            ))
        }

        await state.beginStopping()
        do {
            _ = try await waitForRealtimeCondition(
                timeout: 3,
                timeoutMessage: UIStrings.localized(
                    english: "Timed out waiting for Volcengine audio delivery to finish.",
                    simplifiedChinese: "等待火山语音音频发送完成超时。"
                )
            ) {
                let status = await self.state.appendDrainStatus()
                if let errorMessage = status.errorMessage {
                    throw self.makeError(errorMessage)
                }
                return status.ready ? true : nil
            }
            try await sender.drain()
            try await sender.send(.data(makeMessage(
                type: .audioOnlyClientRequest,
                flags: .lastPacketNoSequence,
                serialization: .none,
                compression: .none,
                payload: Data()
            )))

            let text = try await waitForRealtimeCondition(
                timeout: 10,
                timeoutMessage: UIStrings.localized(
                    english: "Timed out waiting for the final Volcengine Realtime transcription.",
                    simplifiedChinese: "火山语音实时转写最终结果超时。"
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
                case .data(let data):
                    await handleServerMessage(data)
                case .string(let text):
                    await handleServerText(text, isFinalPacket: false)
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

    private func sendFullClientRequest(using sender: SerializedWebSocketSender) async throws {
        let payload = try JSONSerialization.data(withJSONObject: fullClientRequestPayload())
        try await sender.send(.data(makeMessage(
            type: .fullClientRequest,
            flags: .none,
            serialization: .json,
            compression: .none,
            payload: payload
        )))
    }

    private func fullClientRequestPayload() -> [String: Any] {
        [
            "user": ["uid": "flotis"],
            "audio": [
                "format": "pcm",
                "codec": "raw",
                "rate": 16000,
                "bits": 16,
                "channel": 1
            ],
            "request": [
                "model_name": "bigmodel",
                "enable_itn": true,
                "enable_punc": true,
                "enable_ddc": false,
                // The optimized bidirectional endpoint calls its second-pass option
                // enable_nonstream. This is not a server-VAD master switch.
                "enable_nonstream": config.enableServerVAD,
                "show_utterances": true,
                "result_type": "full"
            ]
        ]
    }

    private func handleServerMessage(_ data: Data) async {
        guard data.count >= 8 else {
            await reportProtocolError(UIStrings.localized(
                english: "Volcengine returned a data frame that is too short.",
                simplifiedChinese: "火山语音返回了过短的数据帧。"
            ))
            return
        }

        let headerSize = Int(data[0] & 0x0F) * 4
        guard headerSize >= 4, data.count >= headerSize + 4 else {
            await reportProtocolError(UIStrings.localized(
                english: "Volcengine returned an invalid protocol header.",
                simplifiedChinese: "火山语音返回了非法协议头。"
            ))
            return
        }

        let messageType = data[1] >> 4
        let flags = data[1] & 0x0F
        let serialization = data[2] >> 4
        let compression = data[2] & 0x0F
        let isFinalPacket = (flags & 0b0010) != 0
        var cursor = headerSize

        if messageType == VolcMessageType.errorResponse.rawValue {
            guard let code = readUInt32(data, at: cursor) else {
                await reportProtocolError(UIStrings.localized(
                    english: "The Volcengine error frame is missing an error code.",
                    simplifiedChinese: "火山语音错误帧缺少错误码。"
                ))
                return
            }
            cursor += 4
            guard let size = readUInt32(data, at: cursor) else {
                await reportProtocolError(UIStrings.localized(
                    english: "The Volcengine error frame is missing its content length.",
                    simplifiedChinese: "火山语音错误帧缺少内容长度。"
                ))
                return
            }
            cursor += 4
            let message = readPayloadString(data, at: cursor, size: Int(size))
                ?? UIStrings.localized(
                    english: "The Volcengine service returned an error.",
                    simplifiedChinese: "火山语音服务返回错误。"
                )
            await reportProtocolError(UIStrings.localized(
                english: "Volcengine service error \(code): \(message)",
                simplifiedChinese: "火山语音服务错误 \(code)：\(message)"
            ))
            return
        }

        guard messageType == VolcMessageType.fullServerResponse.rawValue else {
            return
        }

        if (flags & 0b0001) != 0 {
            guard cursor + 4 <= data.count else {
                await reportProtocolError(UIStrings.localized(
                    english: "The Volcengine response is missing a sequence number.",
                    simplifiedChinese: "火山语音响应缺少序列号。"
                ))
                return
            }
            cursor += 4
        }

        guard let size = readUInt32(data, at: cursor) else {
            await reportProtocolError(UIStrings.localized(
                english: "The Volcengine response is missing its content length.",
                simplifiedChinese: "火山语音响应缺少内容长度。"
            ))
            return
        }
        cursor += 4
        guard cursor + Int(size) <= data.count else {
            await reportProtocolError(UIStrings.localized(
                english: "The Volcengine response has an invalid content length.",
                simplifiedChinese: "火山语音响应内容长度非法。"
            ))
            return
        }
        guard compression == VolcCompression.none.rawValue else {
            await reportProtocolError(UIStrings.localized(
                english: "Volcengine returned a compressed response that this client did not negotiate.",
                simplifiedChinese: "火山语音返回了当前客户端未协商的压缩响应。"
            ))
            return
        }
        guard serialization == VolcSerialization.json.rawValue
                || (serialization == VolcSerialization.none.rawValue && size == 0 && isFinalPacket) else {
            await reportProtocolError(UIStrings.localized(
                english: "Volcengine returned a serialization format that this client does not support.",
                simplifiedChinese: "火山语音返回了当前客户端不支持的序列化格式。"
            ))
            return
        }

        if size > 0 {
            let payload = data.subdata(in: cursor..<(cursor + Int(size)))
            guard let text = String(data: payload, encoding: .utf8) else {
                await reportProtocolError(UIStrings.localized(
                    english: "The Volcengine response is not valid UTF-8.",
                    simplifiedChinese: "火山语音响应不是有效 UTF-8。"
                ))
                return
            }
            await handleServerText(text, isFinalPacket: isFinalPacket)
        } else if isFinalPacket {
            await state.markFinalPacketReceived()
        }
        await state.markServerReady()
    }

    private func handleServerText(_ text: String, isFinalPacket: Bool) async {
        guard let data = text.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            await reportProtocolError(UIStrings.localized(
                english: "Could not parse the Volcengine response JSON.",
                simplifiedChinese: "火山语音响应 JSON 解析失败。"
            ))
            return
        }

        if let error = extractError(from: json) {
            await reportProtocolError(error)
            return
        }

        if let transcript = extractTranscript(from: json), !transcript.isEmpty {
            await state.updateTranscript(transcript)
            handlers.partialHandler?(transcript)
            if containsDefiniteUtterance(json) || isFinalPacket {
                handlers.finalHandler?(transcript)
            }
        }
        if isFinalPacket {
            await state.markFinalPacketReceived()
        }
    }

    private func reportProtocolError(_ message: String) async {
        await state.recordError(message)
        handlers.errorHandler?(message)
    }

    private func extractTranscript(from json: [String: Any]) -> String? {
        if let text = json["text"] as? String { return text }
        if let result = json["result"] as? [String: Any],
           let text = result["text"] as? String {
            return text
        }
        if let resultList = json["result"] as? [[String: Any]] {
            let texts = resultList.compactMap { $0["text"] as? String }
            return texts.isEmpty ? nil : texts.joined()
        }
        return nil
    }

    private func containsDefiniteUtterance(_ json: [String: Any]) -> Bool {
        guard let result = json["result"] as? [String: Any],
              let utterances = result["utterances"] as? [[String: Any]] else {
            return false
        }
        return utterances.contains { $0["definite"] as? Bool == true }
    }

    private func extractError(from json: [String: Any]) -> String? {
        if let error = json["error"] as? [String: Any] {
            if let message = error["message"] as? String { return message }
            if let code = error["code"] as? String { return code }
        }
        return json["message"] as? String
    }

    private func makeRealtimeURL() throws -> URL {
        guard let realtimeURL = config.realtimeURL, !realtimeURL.isEmpty,
              let realtimePath = config.realtimePath, !realtimePath.isEmpty else {
            throw makeError(UIStrings.localized(
                english: "The Volcengine Realtime endpoint is not configured.",
                simplifiedChinese: "火山语音实时地址未配置。"
            ))
        }

        let base = realtimeURL.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        let path = realtimePath.hasPrefix("/") ? realtimePath : "/\(realtimePath)"
        guard let url = URL(string: base + path),
              url.scheme?.lowercased() == "wss",
              url.host?.isEmpty == false else {
            throw makeError(UIStrings.localized(
                english: "The Volcengine Realtime endpoint must be a valid wss:// address.",
                simplifiedChinese: "火山语音实时地址必须是有效的 wss:// 地址。"
            ))
        }
        return url
    }

    private func resourceID() throws -> String {
        let value = config.model.trimmingCharacters(in: .whitespacesAndNewlines)
        guard SpeechProviderConfig.isValidVolcengineResourceID(value) else {
            throw makeError(UIStrings.localized(
                english: "Enter the X-Api-Resource-Id in the Volcengine model field, for example volc.seedasr.sauc.duration.",
                simplifiedChinese: "火山语音模型字段应填写 X-Api-Resource-Id，例如 volc.seedasr.sauc.duration。"
            ))
        }
        return value
    }

    private func validateConfiguration() throws {
        let format = (config.inputAudioFormat ?? "pcm").lowercased()
        guard format == "pcm" || format == "pcm16" else {
            throw makeError(UIStrings.localized(
                english: "The current Volcengine Realtime capture pipeline only supports raw PCM16.",
                simplifiedChinese: "火山语音当前实时捕获管线仅支持裸 PCM16。"
            ))
        }
        guard (config.sampleRate ?? 16000) == 16000 else {
            throw makeError(UIStrings.localized(
                english: "Volcengine bigmodel_async requires 16000 Hz PCM audio.",
                simplifiedChinese: "火山语音 bigmodel_async 要求 16000 Hz PCM。"
            ))
        }
        guard (config.channels ?? 1) == 1 else {
            throw makeError(UIStrings.localized(
                english: "Volcengine bigmodel_async requires mono audio.",
                simplifiedChinese: "火山语音 bigmodel_async 要求单声道。"
            ))
        }
        _ = try resourceID()
    }

    private func disconnect() {
        senderSlot.clear()
        connection.disconnect()
    }

    private func makeMessage(
        type: VolcMessageType,
        flags: VolcMessageFlags,
        serialization: VolcSerialization,
        compression: VolcCompression,
        payload: Data
    ) -> Data {
        var data = Data()
        data.append((UInt8(1) << 4) | 1)
        data.append((type.rawValue << 4) | flags.rawValue)
        data.append((serialization.rawValue << 4) | compression.rawValue)
        data.append(0)
        data.appendUInt32(UInt32(payload.count))
        data.append(payload)
        return data
    }

    private func readUInt32(_ data: Data, at index: Int) -> UInt32? {
        guard index + 4 <= data.count else { return nil }
        return UInt32(data[index]) << 24
            | UInt32(data[index + 1]) << 16
            | UInt32(data[index + 2]) << 8
            | UInt32(data[index + 3])
    }

    private func readPayloadString(_ data: Data, at index: Int, size: Int) -> String? {
        guard index + size <= data.count else { return nil }
        return String(data: data.subdata(in: index..<(index + size)), encoding: .utf8)
    }

    private func makeError(_ message: String) -> NSError {
        NSError(
            domain: "VolcengineBigASRRealtimeTranscriber",
            code: 1,
            userInfo: [NSLocalizedDescriptionKey: message]
        )
    }
}

private enum VolcMessageType: UInt8 {
    case fullClientRequest = 0b0001
    case audioOnlyClientRequest = 0b0010
    case fullServerResponse = 0b1001
    case errorResponse = 0b1111
}

private enum VolcMessageFlags: UInt8 {
    case none = 0b0000
    case lastPacketNoSequence = 0b0010
}

private enum VolcSerialization: UInt8 {
    case none = 0b0000
    case json = 0b0001
}

private enum VolcCompression: UInt8 {
    case none = 0b0000
}

private extension Data {
    mutating func appendUInt32(_ value: UInt32) {
        append(UInt8((value >> 24) & 0xFF))
        append(UInt8((value >> 16) & 0xFF))
        append(UInt8((value >> 8) & 0xFF))
        append(UInt8(value & 0xFF))
    }
}
