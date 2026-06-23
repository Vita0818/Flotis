import AVFoundation
import Foundation

final class StreamingAudioCapture {
    var audioChunkHandler: ((Data) -> Void)?
    var errorHandler: ((String) -> Void)?

    private let audioEngine = AVAudioEngine()
    private var converter: AVAudioConverter?
    private var outputFormat: AVAudioFormat?
    private var isCapturing = false

    func start(sampleRate: Int, channels: Int = 1) async throws {
        guard !isCapturing else { return }

        let microphoneGranted = await requestMicrophoneAccess()
        guard microphoneGranted else {
            throw NSError(
                domain: "StreamingAudioCapture",
                code: 1,
                userInfo: [NSLocalizedDescriptionKey: "需要开启麦克风权限。"]
            )
        }

        let inputNode = audioEngine.inputNode
        let inputFormat = inputNode.outputFormat(forBus: 0)
        guard let outputFormat = AVAudioFormat(
            commonFormat: .pcmFormatInt16,
            sampleRate: Double(sampleRate),
            channels: AVAudioChannelCount(channels),
            interleaved: true
        ) else {
            throw NSError(
                domain: "StreamingAudioCapture",
                code: 2,
                userInfo: [NSLocalizedDescriptionKey: "无法创建 PCM16 音频格式。"]
            )
        }

        guard let converter = AVAudioConverter(from: inputFormat, to: outputFormat) else {
            throw NSError(
                domain: "StreamingAudioCapture",
                code: 3,
                userInfo: [NSLocalizedDescriptionKey: "无法创建音频转换器。"]
            )
        }

        self.converter = converter
        self.outputFormat = outputFormat

        inputNode.removeTap(onBus: 0)
        inputNode.installTap(onBus: 0, bufferSize: 2048, format: inputFormat) { [weak self] buffer, _ in
            self?.handle(buffer: buffer, inputFormat: inputFormat)
        }

        audioEngine.prepare()
        try audioEngine.start()
        isCapturing = true
    }

    func stop() {
        guard isCapturing || audioEngine.isRunning else { return }
        audioEngine.inputNode.removeTap(onBus: 0)
        audioEngine.stop()
        converter = nil
        outputFormat = nil
        isCapturing = false
    }

    func cancel() {
        stop()
    }

    private func handle(buffer: AVAudioPCMBuffer, inputFormat: AVAudioFormat) {
        guard let converter, let outputFormat else { return }

        let ratio = outputFormat.sampleRate / inputFormat.sampleRate
        let outputCapacity = max(1, AVAudioFrameCount(Double(buffer.frameLength) * ratio) + 16)
        guard let outputBuffer = AVAudioPCMBuffer(pcmFormat: outputFormat, frameCapacity: outputCapacity) else {
            errorHandler?("无法创建音频输出缓冲区。")
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

        if status == .error {
            errorHandler?(conversionError?.localizedDescription ?? "音频转换失败。")
            return
        }

        let audioBuffer = outputBuffer.audioBufferList.pointee.mBuffers
        guard let dataPointer = audioBuffer.mData, audioBuffer.mDataByteSize > 0 else { return }
        let data = Data(bytes: dataPointer, count: Int(audioBuffer.mDataByteSize))
        audioChunkHandler?(data)
    }

    private func requestMicrophoneAccess() async -> Bool {
        await withCheckedContinuation { continuation in
            AVCaptureDevice.requestAccess(for: .audio) { granted in
                continuation.resume(returning: granted)
            }
        }
    }
}
