import AVFoundation
import Foundation

final class StreamingAudioCapture {
    private let handlerLock = NSLock()
    private var storedAudioChunkHandler: ((Data) -> Void)?
    private var storedErrorHandler: ((String) -> Void)?

    var audioChunkHandler: ((Data) -> Void)? {
        get {
            handlerLock.lock()
            defer { handlerLock.unlock() }
            return storedAudioChunkHandler
        }
        set {
            handlerLock.lock()
            storedAudioChunkHandler = newValue
            handlerLock.unlock()
        }
    }

    var errorHandler: ((String) -> Void)? {
        get {
            handlerLock.lock()
            defer { handlerLock.unlock() }
            return storedErrorHandler
        }
        set {
            handlerLock.lock()
            storedErrorHandler = newValue
            handlerLock.unlock()
        }
    }

    private let audioEngine = AVAudioEngine()
    private let stateLock = NSLock()
    private let lifecycleQueue = DispatchQueue(label: "com.flotis.streaming-audio-lifecycle")
    private let processingQueue = DispatchQueue(label: "com.flotis.streaming-audio-conversion")
    private let processingGroup = DispatchGroup()
    private var converter: AVAudioConverter?
    private var outputFormat: AVAudioFormat?
    private var converterGeneration: UUID?
    private var activeGeneration: UUID?
    private var tapInstalled = false
    private var acceptingTapBuffers = false
    private var isCapturing = false

    func start(sampleRate: Int, channels: Int = 1) async throws {
        try validateOutputConfiguration(sampleRate: sampleRate, channels: channels)

        let generation = UUID()
        let accepted = withStateLock { () -> Bool in
            guard activeGeneration == nil, !isCapturing else { return false }
            activeGeneration = generation
            return true
        }
        guard accepted else { return }

        let microphoneGranted = await requestMicrophoneAccess()
        guard microphoneGranted else {
            clearPendingGeneration(generation)
            throw makeError(
                code: 1,
                message: UIStrings.localized(
                    english: "Microphone access is required.",
                    simplifiedChinese: "需要开启麦克风权限。"
                )
            )
        }
        do {
            try Task.checkCancellation()
        } catch {
            clearPendingGeneration(generation)
            throw error
        }
        guard isGenerationActive(generation) else {
            throw CancellationError()
        }

        do {
            try lifecycleQueue.sync {
                try Task.checkCancellation()
                guard isGenerationActive(generation) else { throw CancellationError() }

                let inputNode = audioEngine.inputNode
                let inputFormat = inputNode.outputFormat(forBus: 0)
                guard inputFormat.sampleRate > 0, inputFormat.channelCount > 0 else {
                    throw makeError(
                        code: 2,
                        message: UIStrings.localized(
                            english: "No microphone input format is currently available.",
                            simplifiedChinese: "当前没有可用的麦克风输入格式。"
                        )
                    )
                }
                guard let outputFormat = AVAudioFormat(
                    commonFormat: .pcmFormatInt16,
                    sampleRate: Double(sampleRate),
                    channels: AVAudioChannelCount(channels),
                    interleaved: true
                ) else {
                    throw makeError(
                        code: 3,
                        message: UIStrings.localized(
                            english: "Could not create the PCM16 audio format.",
                            simplifiedChinese: "无法创建 PCM16 音频格式。"
                        )
                    )
                }
                guard let converter = AVAudioConverter(from: inputFormat, to: outputFormat) else {
                    throw makeError(
                        code: 4,
                        message: UIStrings.localized(
                            english: "Could not create the audio converter.",
                            simplifiedChinese: "无法创建音频转换器。"
                        )
                    )
                }

                withStateLock {
                    self.converter = converter
                    self.outputFormat = outputFormat
                    converterGeneration = generation
                    acceptingTapBuffers = true
                }

                inputNode.removeTap(onBus: 0)
                inputNode.installTap(onBus: 0, bufferSize: 2048, format: inputFormat) { [weak self] buffer, _ in
                    guard let self else { return }
                    let accepted = self.withStateLock { () -> Bool in
                        guard self.acceptingTapBuffers,
                              self.activeGeneration == generation else {
                            return false
                        }
                        // Enter while holding the same lock used by shutdown to close
                        // the gate. This prevents a callback from entering after wait()
                        // has observed a zero group count.
                        self.processingGroup.enter()
                        return true
                    }
                    guard accepted else { return }
                    guard let bufferCopy = Self.copyPCMBuffer(buffer) else {
                        self.processingGroup.leave()
                        self.reportError(
                            UIStrings.localized(
                                english: "Could not copy the microphone audio buffer.",
                                simplifiedChinese: "无法复制麦克风音频缓冲区。"
                            )
                        )
                        return
                    }
                    self.processingQueue.async {
                        defer { self.processingGroup.leave() }
                        self.handle(
                            buffer: bufferCopy,
                            inputFormat: inputFormat,
                            generation: generation
                        )
                    }
                }
                withStateLock { tapInstalled = true }

                do {
                    audioEngine.prepare()
                    try audioEngine.start()
                    withStateLock { isCapturing = true }
                } catch {
                    inputNode.removeTap(onBus: 0)
                    if audioEngine.isRunning { audioEngine.stop() }
                    withStateLock {
                        tapInstalled = false
                        acceptingTapBuffers = false
                        isCapturing = false
                    }
                    throw error
                }
            }
        } catch {
            lifecycleQueue.sync {
                withStateLock {
                    if activeGeneration == generation {
                        activeGeneration = nil
                        acceptingTapBuffers = false
                    }
                    if converterGeneration == generation {
                        converter = nil
                        outputFormat = nil
                        converterGeneration = nil
                    }
                }
            }
            throw error
        }
    }

    func stop() {
        shutdown(flushPendingAudio: true)
    }

    func cancel() {
        shutdown(flushPendingAudio: false)
    }

    private func shutdown(flushPendingAudio: Bool) {
        lifecycleQueue.sync {
            let (generation, shouldRemoveTap) = withStateLock { () -> (UUID?, Bool) in
                let generation = activeGeneration
                let value = tapInstalled
                tapInstalled = false
                acceptingTapBuffers = false
                isCapturing = false
                if !flushPendingAudio {
                    activeGeneration = nil
                }
                return (generation, value)
            }
            if shouldRemoveTap {
                audioEngine.inputNode.removeTap(onBus: 0)
            }
            if audioEngine.isRunning {
                audioEngine.stop()
            }

            // Every tap callback enters the group before copying/enqueuing. Once the
            // tap is removed, waiting here drains callbacks that were already in flight.
            // Graceful stop keeps the generation valid so those chunks are delivered;
            // cancel invalidates it first so the same work is safely discarded.
            processingGroup.wait()
            if flushPendingAudio, let generation {
                processingQueue.sync {
                    flushConverter(generation: generation)
                }
            } else {
                processingQueue.sync {}
            }

            withStateLock {
                if activeGeneration == generation {
                    activeGeneration = nil
                }
                if converterGeneration == generation || generation == nil {
                    converter = nil
                    outputFormat = nil
                    converterGeneration = nil
                }
            }
        }
    }

    private func handle(
        buffer: AVAudioPCMBuffer,
        inputFormat: AVAudioFormat,
        generation: UUID
    ) {
        stateLock.lock()
        guard activeGeneration == generation,
              converterGeneration == generation,
              let converter,
              let outputFormat else {
            stateLock.unlock()
            return
        }
        stateLock.unlock()

        let ratio = outputFormat.sampleRate / inputFormat.sampleRate
        let outputCapacity = max(1, AVAudioFrameCount(ceil(Double(buffer.frameLength) * ratio)) + 32)
        guard let outputBuffer = AVAudioPCMBuffer(
            pcmFormat: outputFormat,
            frameCapacity: outputCapacity
        ) else {
            reportError(
                UIStrings.localized(
                    english: "Could not create the audio output buffer.",
                    simplifiedChinese: "无法创建音频输出缓冲区。"
                )
            )
            return
        }

        var didProvideInput = false
        var conversionError: NSError?
        let status = converter.convert(to: outputBuffer, error: &conversionError) { _, outStatus in
            if didProvideInput {
                outStatus.pointee = .noDataNow
                return nil
            }
            didProvideInput = true
            outStatus.pointee = .haveData
            return buffer
        }

        guard status != .error else {
            reportError(
                conversionError?.localizedDescription
                    ?? UIStrings.localized(
                        english: "Audio conversion failed.",
                        simplifiedChinese: "音频转换失败。"
                    )
            )
            return
        }

        deliver(outputBuffer: outputBuffer, generation: generation)
    }

    private func flushConverter(generation: UUID) {
        stateLock.lock()
        guard activeGeneration == generation,
              converterGeneration == generation,
              let converter,
              let outputFormat else {
            stateLock.unlock()
            return
        }
        stateLock.unlock()

        for _ in 0..<16 {
            guard let outputBuffer = AVAudioPCMBuffer(
                pcmFormat: outputFormat,
                frameCapacity: 4096
            ) else {
                reportError(
                    UIStrings.localized(
                        english: "Could not create the audio tail buffer.",
                        simplifiedChinese: "无法创建音频尾帧缓冲区。"
                    )
                )
                return
            }

            var conversionError: NSError?
            let status = converter.convert(to: outputBuffer, error: &conversionError) { _, outStatus in
                outStatus.pointee = .endOfStream
                return nil
            }
            if status == .error {
                reportError(
                    conversionError?.localizedDescription
                        ?? UIStrings.localized(
                            english: "Audio tail conversion failed.",
                            simplifiedChinese: "音频尾帧转换失败。"
                        )
                )
                return
            }

            let deliveredData = deliver(outputBuffer: outputBuffer, generation: generation)
            if status == .endOfStream || !deliveredData {
                return
            }
        }

        reportError(
            UIStrings.localized(
                english: "The audio converter could not finish flushing tail frames within the limit.",
                simplifiedChinese: "音频转换器未能在限制内完成尾帧刷新。"
            )
        )
    }

    @discardableResult
    private func deliver(outputBuffer: AVAudioPCMBuffer, generation: UUID) -> Bool {
        let buffers = UnsafeMutableAudioBufferListPointer(outputBuffer.mutableAudioBufferList)
        guard buffers.count == 1,
              let pointer = buffers[0].mData,
              buffers[0].mDataByteSize > 0 else {
            return false
        }

        stateLock.lock()
        let shouldDeliver = activeGeneration == generation
        stateLock.unlock()
        guard shouldDeliver else { return false }

        let data = Data(bytes: pointer, count: Int(buffers[0].mDataByteSize))
        currentAudioChunkHandler()?(data)
        return true
    }

    private func validateOutputConfiguration(sampleRate: Int, channels: Int) throws {
        guard sampleRate == 16000 || sampleRate == 24000 else {
            throw makeError(
                code: 5,
                message: UIStrings.localized(
                    english: "Realtime PCM16 capture supports only 16000 or 24000 Hz.",
                    simplifiedChinese: "实时 PCM16 捕获仅支持 16000 或 24000 Hz。"
                )
            )
        }
        guard channels == 1 else {
            throw makeError(
                code: 6,
                message: UIStrings.localized(
                    english: "Realtime PCM16 capture supports mono audio only.",
                    simplifiedChinese: "实时 PCM16 捕获仅支持单声道。"
                )
            )
        }
    }

    private func isGenerationActive(_ generation: UUID) -> Bool {
        withStateLock { activeGeneration == generation }
    }

    private func clearPendingGeneration(_ generation: UUID) {
        withStateLock {
            if activeGeneration == generation {
                activeGeneration = nil
            }
        }
    }

    private func withStateLock<T>(_ operation: () throws -> T) rethrows -> T {
        stateLock.lock()
        defer { stateLock.unlock() }
        return try operation()
    }

    private func currentAudioChunkHandler() -> ((Data) -> Void)? {
        handlerLock.lock()
        defer { handlerLock.unlock() }
        return storedAudioChunkHandler
    }

    private func reportError(_ message: String) {
        handlerLock.lock()
        let handler = storedErrorHandler
        handlerLock.unlock()
        handler?(message)
    }

    private func makeError(code: Int, message: String) -> NSError {
        NSError(
            domain: "StreamingAudioCapture",
            code: code,
            userInfo: [NSLocalizedDescriptionKey: message]
        )
    }

    private static func copyPCMBuffer(_ source: AVAudioPCMBuffer) -> AVAudioPCMBuffer? {
        guard let copy = AVAudioPCMBuffer(
            pcmFormat: source.format,
            frameCapacity: source.frameLength
        ) else {
            return nil
        }
        copy.frameLength = source.frameLength

        let sourceBuffers = UnsafeMutableAudioBufferListPointer(source.mutableAudioBufferList)
        let destinationBuffers = UnsafeMutableAudioBufferListPointer(copy.mutableAudioBufferList)
        guard sourceBuffers.count == destinationBuffers.count else { return nil }

        for index in 0..<sourceBuffers.count {
            let byteCount = Int(sourceBuffers[index].mDataByteSize)
            guard byteCount == 0 || (
                sourceBuffers[index].mData != nil && destinationBuffers[index].mData != nil
            ) else {
                return nil
            }
            if byteCount > 0,
               let sourceData = sourceBuffers[index].mData,
               let destinationData = destinationBuffers[index].mData {
                memcpy(destinationData, sourceData, byteCount)
            }
            destinationBuffers[index].mDataByteSize = sourceBuffers[index].mDataByteSize
        }
        return copy
    }

    private func requestMicrophoneAccess() async -> Bool {
        await withCheckedContinuation { continuation in
            AVCaptureDevice.requestAccess(for: .audio) { granted in
                continuation.resume(returning: granted)
            }
        }
    }
}
