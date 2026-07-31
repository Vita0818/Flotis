import Dispatch
import Foundation

protocol RealtimeWebSocket: AnyObject {
    func resume()
    func send(_ message: URLSessionWebSocketTask.Message) async throws
    func receive() async throws -> URLSessionWebSocketTask.Message
    func cancel(
        with closeCode: URLSessionWebSocketTask.CloseCode,
        reason: Data?
    )
}

extension URLSessionWebSocketTask: RealtimeWebSocket {}

typealias RealtimeWebSocketFactory = (URLRequest) -> RealtimeWebSocket

let noRedirectRealtimeURLSession: URLSession = {
    let configuration = URLSessionConfiguration.ephemeral
    configuration.timeoutIntervalForRequest = 30
    configuration.timeoutIntervalForResource = 180
    configuration.waitsForConnectivity = false
    return URLSession(
        configuration: configuration,
        delegate: NoRedirectSessionDelegate.shared,
        delegateQueue: nil
    )
}()

let liveRealtimeWebSocketFactory: RealtimeWebSocketFactory = { request in
    noRedirectRealtimeURLSession.webSocketTask(with: request)
}

// URLSessionWebSocketTask accepts concurrent sends, but does not provide the ordering
// and drain semantics needed by streaming audio protocols. Chain sends explicitly so
// stop can wait until every accepted audio chunk has reached the socket before commit.
actor SerializedWebSocketSender {
    private let socket: RealtimeWebSocket
    private var tail: (id: UUID, task: Task<Void, Error>)?

    init(socket: RealtimeWebSocket) {
        self.socket = socket
    }

    func send(_ message: URLSessionWebSocketTask.Message) async throws {
        let previous = tail?.task
        let id = UUID()
        let socket = self.socket
        let task = Task {
            if let previous {
                try await previous.value
            }
            try Task.checkCancellation()
            try await socket.send(message)
        }
        tail = (id, task)

        do {
            try await task.value
            if tail?.id == id {
                tail = nil
            }
        } catch {
            if tail?.id == id {
                tail = nil
            }
            throw error
        }
    }

    func drain() async throws {
        try await tail?.task.value
    }
}

final class LockedWebSocketConnection: @unchecked Sendable {
    private let lock = NSLock()
    private var socket: RealtimeWebSocket?
    private var receiveTask: Task<Void, Never>?

    func install(socket: RealtimeWebSocket) {
        let previous: (RealtimeWebSocket?, Task<Void, Never>?) = lock.withLock {
            let value = (self.socket, receiveTask)
            self.socket = socket
            receiveTask = nil
            return value
        }
        previous.1?.cancel()
        previous.0?.cancel(with: .goingAway, reason: nil)
    }

    func attach(receiveTask: Task<Void, Never>, to socket: RealtimeWebSocket) {
        let shouldKeep = lock.withLock { () -> Bool in
            guard self.socket === socket else { return false }
            self.receiveTask = receiveTask
            return true
        }
        if !shouldKeep {
            receiveTask.cancel()
        }
    }

    func isActive(_ socket: RealtimeWebSocket) -> Bool {
        lock.withLock { self.socket === socket }
    }

    func disconnect() {
        let current: (RealtimeWebSocket?, Task<Void, Never>?) = lock.withLock {
            let value = (socket, receiveTask)
            socket = nil
            receiveTask = nil
            return value
        }
        current.1?.cancel()
        current.0?.cancel(with: .normalClosure, reason: nil)
    }
}

final class LockedTranscriptionHandlers: @unchecked Sendable {
    private let lock = NSLock()
    private var partial: ((String) -> Void)?
    private var final: ((String) -> Void)?
    private var error: ((String) -> Void)?

    var partialHandler: ((String) -> Void)? {
        get { lock.withLock { partial } }
        set { lock.withLock { partial = newValue } }
    }

    var finalHandler: ((String) -> Void)? {
        get { lock.withLock { final } }
        set { lock.withLock { final = newValue } }
    }

    var errorHandler: ((String) -> Void)? {
        get { lock.withLock { error } }
        set { lock.withLock { error = newValue } }
    }
}

final class LockedRealtimeSender: @unchecked Sendable {
    private let lock = NSLock()
    private var sender: SerializedWebSocketSender?

    func install(_ sender: SerializedWebSocketSender) {
        lock.withLock { self.sender = sender }
    }

    func current() -> SerializedWebSocketSender? {
        lock.withLock { sender }
    }

    func clear() {
        lock.withLock { sender = nil }
    }
}

func waitForRealtimeCondition<T>(
    timeout: TimeInterval,
    timeoutMessage: String,
    pollIntervalNanoseconds: UInt64 = 20_000_000,
    condition: () async throws -> T?
) async throws -> T {
    let timeoutNanoseconds = UInt64(max(0, timeout) * 1_000_000_000)
    let start = DispatchTime.now().uptimeNanoseconds
    let deadline = start.addingReportingOverflow(timeoutNanoseconds).overflow
        ? UInt64.max
        : start + timeoutNanoseconds
    while DispatchTime.now().uptimeNanoseconds < deadline {
        try Task.checkCancellation()
        if let value = try await condition() {
            return value
        }
        try await Task.sleep(nanoseconds: pollIntervalNanoseconds)
    }

    if let value = try await condition() {
        return value
    }
    throw NSError(
        domain: "RealtimeTranscriber",
        code: 408,
        userInfo: [NSLocalizedDescriptionKey: timeoutMessage]
    )
}

private extension NSLock {
    func withLock<T>(_ operation: () throws -> T) rethrows -> T {
        lock()
        defer { unlock() }
        return try operation()
    }
}

// Pure value-type assembler: tests can feed interleaved delta/completed events and
// assert ordering without opening a socket or crossing an actor boundary.
struct OpenAITranscriptAssembler {
    struct ItemKey: Hashable {
        let itemID: String
        let contentIndex: Int
    }

    private var partialByKey: [ItemKey: String] = [:]
    private var finalByKey: [ItemKey: String] = [:]
    private var contentIndexesByItem: [String: Set<Int>] = [:]
    private var firstSeenItems: [String] = []
    private var orderedItems: [String] = []
    private var previousItemByItem: [String: String] = [:]
    private(set) var completedItemIDs: Set<String> = []

    init() {}

    mutating func recordItem(_ itemID: String, previousItemID: String?) {
        guard !itemID.isEmpty else { return }
        if !firstSeenItems.contains(itemID) {
            firstSeenItems.append(itemID)
        }
        if let previousItemID, !previousItemID.isEmpty {
            previousItemByItem[itemID] = previousItemID
        }
        rebuildOrder()
    }

    mutating func applyDelta(itemID: String, contentIndex: Int, delta: String) -> String {
        let resolvedID = itemID.isEmpty ? "legacy-item" : itemID
        recordItem(resolvedID, previousItemID: nil)
        let key = ItemKey(itemID: resolvedID, contentIndex: contentIndex)
        contentIndexesByItem[resolvedID, default: []].insert(contentIndex)
        partialByKey[key, default: ""] += delta
        return transcript
    }

    mutating func applyCompletion(itemID: String, contentIndex: Int, transcript: String) -> String {
        let resolvedID = itemID.isEmpty ? "legacy-item" : itemID
        recordItem(resolvedID, previousItemID: nil)
        let key = ItemKey(itemID: resolvedID, contentIndex: contentIndex)
        contentIndexesByItem[resolvedID, default: []].insert(contentIndex)
        finalByKey[key] = transcript.isEmpty ? (partialByKey[key] ?? "") : transcript
        completedItemIDs.insert(resolvedID)
        return self.transcript
    }

    var transcript: String {
        var result = ""
        let itemIDs = orderedItems.isEmpty ? firstSeenItems : orderedItems
        for itemID in itemIDs {
            let indexes = (contentIndexesByItem[itemID] ?? []).sorted()
            for contentIndex in indexes {
                let key = ItemKey(itemID: itemID, contentIndex: contentIndex)
                let text = finalByKey[key] ?? partialByKey[key] ?? ""
                result = appendTranscriptSegment(text, to: result)
            }
        }
        return result
    }

    private mutating func rebuildOrder() {
        var result = firstSeenItems
        for _ in 0..<max(1, result.count) {
            var changed = false
            for itemID in result {
                guard let previous = previousItemByItem[itemID],
                      let itemIndex = result.firstIndex(of: itemID),
                      let previousIndex = result.firstIndex(of: previous),
                      itemIndex != previousIndex + 1 else {
                    continue
                }
                result.remove(at: itemIndex)
                let refreshedPreviousIndex = result.firstIndex(of: previous) ?? (result.count - 1)
                result.insert(itemID, at: min(result.count, refreshedPreviousIndex + 1))
                changed = true
            }
            if !changed { break }
        }
        orderedItems = result
    }
}

private actor OpenAIRealtimeState {

    struct Status {
        let ready: Bool
        let transcript: String
        let errorMessage: String?
    }

    private var assembler = OpenAITranscriptAssembler()
    private var committedItems: Set<String> = []

    private var sessionUpdated = false
    private var errorMessage: String?
    private var activeAppendOperations = 0
    private var hasUncommittedAudio = false
    private var isStopping = false
    private var stopCommitBaseline = 0
    private var stopCommittedItemID: String?
    private var commitCount = 0

    func reset() {
        assembler = OpenAITranscriptAssembler()
        committedItems.removeAll()
        sessionUpdated = false
        errorMessage = nil
        activeAppendOperations = 0
        hasUncommittedAudio = false
        isStopping = false
        stopCommitBaseline = 0
        stopCommittedItemID = nil
        commitCount = 0
    }

    func markSessionUpdated() {
        sessionUpdated = true
    }

    func startStatus() -> Status {
        Status(ready: sessionUpdated, transcript: assembler.transcript, errorMessage: errorMessage)
    }

    func beginAppend() throws {
        if let errorMessage {
            throw makeError(errorMessage)
        }
        guard !isStopping else {
            throw CancellationError()
        }
        activeAppendOperations += 1
    }

    func finishAppend(sent: Bool) {
        activeAppendOperations = max(0, activeAppendOperations - 1)
        if sent {
            hasUncommittedAudio = true
        }
    }

    func beginStopping() {
        isStopping = true
    }

    func appendDrainStatus() -> Status {
        Status(
            ready: activeAppendOperations == 0,
            transcript: assembler.transcript,
            errorMessage: errorMessage
        )
    }

    func prepareCommit() -> Bool {
        stopCommitBaseline = commitCount
        stopCommittedItemID = nil
        return hasUncommittedAudio
    }

    func recordItem(_ itemID: String, previousItemID: String?) {
        assembler.recordItem(itemID, previousItemID: previousItemID)
    }

    func markCommitted(itemID: String, previousItemID: String?) {
        recordItem(itemID, previousItemID: previousItemID)
        committedItems.insert(itemID)
        commitCount += 1
        hasUncommittedAudio = false
        if isStopping, commitCount > stopCommitBaseline {
            stopCommittedItemID = itemID
        }
    }

    func applyDelta(itemID: String, contentIndex: Int, delta: String) -> String {
        assembler.applyDelta(itemID: itemID, contentIndex: contentIndex, delta: delta)
    }

    func applyCompletion(itemID: String, contentIndex: Int, transcript: String) -> String {
        assembler.applyCompletion(itemID: itemID, contentIndex: contentIndex, transcript: transcript)
    }

    func recordError(_ message: String) {
        if errorMessage == nil {
            errorMessage = message
        }
    }

    func cancel() {
        isStopping = true
        if errorMessage == nil {
            errorMessage = UIStrings.localized(
                english: "OpenAI Realtime transcription was canceled.",
                simplifiedChinese: "实时转写已取消。"
            )
        }
    }

    func stopStatus(expectCommittedItem: Bool) -> Status {
        let completedItems = assembler.completedItemIDs
        let allKnownCommitsCompleted = committedItems.isSubset(of: completedItems)
        let stopCommitCompleted: Bool
        if expectCommittedItem {
            if let stopCommittedItemID {
                stopCommitCompleted = completedItems.contains(stopCommittedItemID)
            } else {
                stopCommitCompleted = false
            }
        } else {
            stopCommitCompleted = true
        }

        return Status(
            ready: activeAppendOperations == 0 && allKnownCommitsCompleted && stopCommitCompleted,
            transcript: assembler.transcript,
            errorMessage: errorMessage
        )
    }

    func serverClosedAfterTerminalEvent() -> Bool {
        guard isStopping, activeAppendOperations == 0 else { return false }
        let completedItems = assembler.completedItemIDs
        guard committedItems.isSubset(of: completedItems) else { return false }
        if let stopCommittedItemID {
            return completedItems.contains(stopCommittedItemID)
        }
        return !committedItems.isEmpty
    }

    private func makeError(_ message: String) -> NSError {
        NSError(
            domain: "OpenAIRealtimeTranscriber",
            code: 10,
            userInfo: [NSLocalizedDescriptionKey: message]
        )
    }
}

func appendTranscriptSegment(_ segment: String, to base: String) -> String {
    let trimmed = segment.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !trimmed.isEmpty else { return base }
    guard !base.isEmpty else { return trimmed }

    if shouldInsertASCIISpace(between: base, and: trimmed) {
        return base + " " + trimmed
    }
    return base + trimmed
}

func shouldInsertASCIISpace(between left: String, and right: String) -> Bool {
    guard let leftScalar = left.unicodeScalars.last,
          let rightScalar = right.unicodeScalars.first else {
        return false
    }

    let asciiAlphaNumeric = CharacterSet(charactersIn: "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789")
    let asciiTrailingPunctuation = CharacterSet(charactersIn: ".,!?;:)]}\"'")
    return asciiAlphaNumeric.contains(rightScalar)
        && (asciiAlphaNumeric.contains(leftScalar) || asciiTrailingPunctuation.contains(leftScalar))
}

final class OpenAIRealtimeTranscriber: StreamingSpeechTranscribing {
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
    private let socketFactory: RealtimeWebSocketFactory
    private let state = OpenAIRealtimeState()
    private let connection = LockedWebSocketConnection()
    private let senderSlot = LockedRealtimeSender()

    init(
        config: SpeechProviderConfig,
        apiKey: String,
        socketFactory: @escaping RealtimeWebSocketFactory = liveRealtimeWebSocketFactory
    ) {
        self.config = config
        self.apiKey = apiKey
        self.socketFactory = socketFactory
    }

    func start() async throws {
        try validateAudioConfiguration()
        let url = try makeRealtimeURL()
        var request = URLRequest(url: url)
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")

        await state.reset()
        let socket = socketFactory(request)
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
            try await sendJSON(sessionUpdatePayload(), using: sender)
            _ = try await waitForRealtimeCondition(
                timeout: 5,
                timeoutMessage: UIStrings.localized(
                    english: "Timed out waiting for OpenAI Realtime session configuration confirmation.",
                    simplifiedChinese: "OpenAI 实时转写会话配置确认超时。"
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
                english: "The OpenAI Realtime connection has not been established.",
                simplifiedChinese: "OpenAI 实时连接尚未建立。"
            ))
        }

        try await state.beginAppend()
        do {
            let payload: [String: Any] = [
                "type": "input_audio_buffer.append",
                "audio": data.base64EncodedString()
            ]
            try await sendJSON(payload, using: sender)
            await state.finishAppend(sent: true)
        } catch {
            await state.finishAppend(sent: false)
            await state.recordError(error.localizedDescription)
            throw error
        }
    }

    func stop() async throws -> String {
        guard let sender = senderSlot.current() else {
            throw makeError(UIStrings.localized(
                english: "The OpenAI Realtime connection has not been established.",
                simplifiedChinese: "OpenAI 实时连接尚未建立。"
            ))
        }

        await state.beginStopping()
        do {
            _ = try await waitForRealtimeCondition(
                timeout: 3,
                timeoutMessage: UIStrings.localized(
                    english: "Timed out waiting for Realtime audio delivery to finish.",
                    simplifiedChinese: "等待实时音频发送完成超时。"
                )
            ) {
                let status = await self.state.appendDrainStatus()
                if let errorMessage = status.errorMessage {
                    throw self.makeError(errorMessage)
                }
                return status.ready ? true : nil
            }
            try await sender.drain()

            let shouldCommit = await state.prepareCommit()
            if shouldCommit {
                try await sendJSON(["type": "input_audio_buffer.commit"], using: sender)
            }

            let text = try await waitForRealtimeCondition(
                timeout: 8,
                timeoutMessage: UIStrings.localized(
                    english: "Timed out waiting for the final OpenAI Realtime transcription.",
                    simplifiedChinese: "OpenAI 实时转写最终结果超时。"
                )
            ) {
                let status = await self.state.stopStatus(expectCommittedItem: shouldCommit)
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

    private func receiveLoop(socket: RealtimeWebSocket) async {
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

        let type = (json["type"] as? String) ?? ""
        if type == "error" || type == "conversation.item.input_audio_transcription.failed" || json["error"] != nil {
            let message = extractError(from: json)
            await state.recordError(message)
            handlers.errorHandler?(message)
            return
        }

        switch type {
        case "session.updated":
            await state.markSessionUpdated()
            return
        case "conversation.item.created":
            if let item = json["item"] as? [String: Any],
               let itemID = item["id"] as? String {
                await state.recordItem(itemID, previousItemID: json["previous_item_id"] as? String)
            }
            return
        case "input_audio_buffer.committed":
            if let itemID = json["item_id"] as? String {
                await state.markCommitted(
                    itemID: itemID,
                    previousItemID: json["previous_item_id"] as? String
                )
            }
            return
        default:
            break
        }

        guard let itemID = json["item_id"] as? String, !itemID.isEmpty else {
            return
        }
        let contentIndex = json["content_index"] as? Int ?? 0
        if isDeltaEvent(type) {
            let delta = (json["delta"] as? String) ?? ""
            guard !delta.isEmpty else { return }
            let display = await state.applyDelta(
                itemID: itemID,
                contentIndex: contentIndex,
                delta: delta
            )
            handlers.partialHandler?(display)
            return
        }

        if isCompletedEvent(type) {
            let completed = (json["transcript"] as? String) ?? ""
            let display = await state.applyCompletion(
                itemID: itemID,
                contentIndex: contentIndex,
                transcript: completed
            )
            handlers.partialHandler?(display)
            handlers.finalHandler?(display)
        }
    }

    private func isDeltaEvent(_ type: String) -> Bool {
        type == "conversation.item.input_audio_transcription.delta"
    }

    private func isCompletedEvent(_ type: String) -> Bool {
        type == "conversation.item.input_audio_transcription.completed"
    }

    private func extractError(from json: [String: Any]) -> String {
        if let error = json["error"] as? [String: Any] {
            if let message = error["message"] as? String { return message }
            if let code = error["code"] as? String { return code }
        }
        if let message = json["message"] as? String { return message }
        return UIStrings.localized(
            english: "OpenAI Realtime transcription returned an error.",
            simplifiedChinese: "OpenAI 实时转写返回错误。"
        )
    }

    private func makeRealtimeURL() throws -> URL {
        guard let realtimeURL = config.realtimeURL, !realtimeURL.isEmpty,
              let realtimePath = config.realtimePath, !realtimePath.isEmpty else {
            throw makeError(UIStrings.localized(
                english: "The Realtime endpoint is not configured.",
                simplifiedChinese: "实时地址未配置。"
            ))
        }

        let base = realtimeURL.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        let path = realtimePath.hasPrefix("/") ? realtimePath : "/\(realtimePath)"
        guard var components = URLComponents(string: base + path),
              components.scheme?.lowercased() == "wss",
              components.host?.isEmpty == false else {
            throw makeError(UIStrings.localized(
                english: "The OpenAI Realtime endpoint must be a valid wss:// address.",
                simplifiedChinese: "OpenAI 实时地址必须是有效的 wss:// 地址。"
            ))
        }

        var queryItems = components.queryItems ?? []
        if !config.model.isEmpty, !queryItems.contains(where: { $0.name == "model" }) {
            queryItems.append(URLQueryItem(name: "model", value: config.model))
        }
        components.queryItems = queryItems
        guard let url = components.url else {
            throw makeError(UIStrings.localized(
                english: "Could not create the Realtime endpoint URL.",
                simplifiedChinese: "实时地址生成失败。"
            ))
        }
        return url
    }

    private func sessionUpdatePayload() -> [String: Any] {
        var transcription: [String: Any] = ["model": config.model]
        if let language = config.language, !language.isEmpty {
            transcription["language"] = language
        }

        let input: [String: Any] = [
            "format": [
                "type": "audio/pcm",
                "rate": config.sampleRate ?? 24000
            ],
            "transcription": transcription,
            // GA transcription uses explicit client commit for deterministic finalization.
            "turn_detection": NSNull()
        ]
        return [
            "type": "session.update",
            "session": [
                "type": "transcription",
                "audio": ["input": input]
            ]
        ]
    }

    private func validateAudioConfiguration() throws {
        let format = (config.inputAudioFormat ?? "pcm16").lowercased()
        guard ["pcm", "pcm16", "audio/pcm"].contains(format) else {
            throw makeError(UIStrings.localized(
                english: "OpenAI GA Realtime transcription only supports PCM16 from the current capture pipeline.",
                simplifiedChinese: "OpenAI GA 实时转写仅支持当前捕获管线提供的 PCM16。"
            ))
        }
        guard (config.sampleRate ?? 24000) == 24000 else {
            throw makeError(UIStrings.localized(
                english: "OpenAI PCM Realtime transcription requires 24000 Hz audio.",
                simplifiedChinese: "OpenAI PCM 实时转写要求 24000 Hz。"
            ))
        }
        guard (config.channels ?? 1) == 1 else {
            throw makeError(UIStrings.localized(
                english: "OpenAI PCM Realtime transcription requires mono audio.",
                simplifiedChinese: "OpenAI PCM 实时转写要求单声道。"
            ))
        }
        guard !config.model.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw makeError(UIStrings.localized(
                english: "The OpenAI Realtime transcription model cannot be empty.",
                simplifiedChinese: "OpenAI 实时转写模型不能为空。"
            ))
        }
    }

    private func sendJSON(
        _ payload: [String: Any],
        using sender: SerializedWebSocketSender
    ) async throws {
        let data = try JSONSerialization.data(withJSONObject: payload)
        guard let text = String(data: data, encoding: .utf8) else {
            throw makeError(UIStrings.localized(
                english: "Could not encode the OpenAI Realtime request.",
                simplifiedChinese: "OpenAI 实时请求编码失败。"
            ))
        }
        try await sender.send(.string(text))
    }

    private func disconnect() {
        senderSlot.clear()
        connection.disconnect()
    }

    private func makeError(_ message: String) -> NSError {
        NSError(
            domain: "OpenAIRealtimeTranscriber",
            code: 1,
            userInfo: [NSLocalizedDescriptionKey: message]
        )
    }
}
