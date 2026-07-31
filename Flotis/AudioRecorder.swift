import Foundation
import AVFoundation

enum FlotisTemporaryFiles {
    static let audioPrefix = "Flotis-Audio-"
    static let multipartPrefix = "Flotis-Multipart-"
    private static let staleAge: TimeInterval = 24 * 60 * 60

    static func removeStaleFiles(withPrefix prefix: String) {
        let fileManager = FileManager.default
        let temporaryDirectory = fileManager.temporaryDirectory.standardizedFileURL
        guard let files = try? fileManager.contentsOfDirectory(
            at: temporaryDirectory,
            includingPropertiesForKeys: [.contentModificationDateKey, .creationDateKey, .isRegularFileKey],
            options: [.skipsHiddenFiles]
        ) else {
            return
        }

        let cutoff = Date().addingTimeInterval(-staleAge)
        for fileURL in files where fileURL.lastPathComponent.hasPrefix(prefix) {
            // Never follow a directory entry out of the system temporary directory,
            // and never touch another application's UUID-only temporary files.
            guard fileURL.deletingLastPathComponent().standardizedFileURL == temporaryDirectory,
                  let values = try? fileURL.resourceValues(forKeys: [
                    .contentModificationDateKey,
                    .creationDateKey,
                    .isRegularFileKey
                  ]),
                  values.isRegularFile == true,
                  let timestamp = values.contentModificationDate ?? values.creationDate,
                  timestamp < cutoff else {
                continue
            }
            try? fileManager.removeItem(at: fileURL)
        }
    }
}

enum RecordedAudioFormat {
    case m4a
    case wav

    var fileExtension: String {
        switch self {
        case .m4a:
            return "m4a"
        case .wav:
            return "wav"
        }
    }

    func settings(sampleRate: Int, channels: Int) -> [String: Any] {
        switch self {
        case .m4a:
            return [
                AVFormatIDKey: Int(kAudioFormatMPEG4AAC),
                AVSampleRateKey: sampleRate,
                AVNumberOfChannelsKey: channels,
                AVEncoderAudioQualityKey: AVAudioQuality.high.rawValue
            ]
        case .wav:
            return [
                AVFormatIDKey: Int(kAudioFormatLinearPCM),
                AVSampleRateKey: sampleRate,
                AVNumberOfChannelsKey: channels,
                AVLinearPCMBitDepthKey: 16,
                AVLinearPCMIsFloatKey: false,
                AVLinearPCMIsBigEndianKey: false
            ]
        }
    }
}

final class AudioRecorder: NSObject {
    private let stateLock = NSLock()
    private var audioRecorder: AVAudioRecorder?
    private var recordingURL: URL?
    private var activeGeneration: UUID?
    
    func startRecording(
        format: RecordedAudioFormat = .m4a,
        sampleRate: Int = 16000,
        channels: Int = 1
    ) async throws {
        try validateConfiguration(sampleRate: sampleRate, channels: channels)

        let generation = UUID()
        let accepted = withStateLock { () -> Bool in
            guard activeGeneration == nil, audioRecorder == nil else { return false }
            activeGeneration = generation
            return true
        }
        guard accepted else {
            throw makeError(
                code: 5,
                message: UIStrings.localized(
                    english: "Recording is already in progress.",
                    simplifiedChinese: "录音已经在进行中。"
                )
            )
        }

        let microphoneGranted = await requestMicrophoneAccess()
        guard microphoneGranted else {
            clearGeneration(generation)
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
            clearGeneration(generation)
            throw error
        }
        guard isGenerationActive(generation) else { throw CancellationError() }

        #if os(iOS)
        do {
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(.record, mode: .measurement, options: .duckOthers)
            try session.setActive(true, options: .notifyOthersOnDeactivation)
        } catch {
            clearGeneration(generation)
            throw error
        }
        #endif
        
        let tempDir = FileManager.default.temporaryDirectory
        FlotisTemporaryFiles.removeStaleFiles(withPrefix: FlotisTemporaryFiles.audioPrefix)
        let fileName = FlotisTemporaryFiles.audioPrefix + UUID().uuidString + ".\(format.fileExtension)"
        let url = tempDir.appendingPathComponent(fileName)

        let settings = format.settings(sampleRate: sampleRate, channels: channels)
        let recorder: AVAudioRecorder
        do {
            recorder = try AVAudioRecorder(url: url, settings: settings)
        } catch {
            clearGeneration(generation)
            try? FileManager.default.removeItem(at: url)
            throw error
        }

        guard recorder.prepareToRecord(), recorder.record() else {
            recorder.stop()
            clearGeneration(generation)
            try? FileManager.default.removeItem(at: url)
            throw makeError(
                code: 2,
                message: UIStrings.localized(
                    english: "Could not start microphone recording.",
                    simplifiedChinese: "麦克风录音启动失败。"
                )
            )
        }

        let stillActive = withStateLock { () -> Bool in
            let active = activeGeneration == generation
            if active {
                audioRecorder = recorder
                recordingURL = url
            }
            return active
        }

        if !stillActive {
            recorder.stop()
            try? FileManager.default.removeItem(at: url)
            throw CancellationError()
        }
    }
    
    func stopRecording() -> URL? {
        stateLock.lock()
        let recorder = audioRecorder
        let url = recordingURL
        audioRecorder = nil
        recordingURL = nil
        activeGeneration = nil
        stateLock.unlock()

        recorder?.stop()
        guard let url else { return nil }
        let fileSize = (try? url.resourceValues(forKeys: [.fileSizeKey]))?.fileSize ?? 0
        guard FileManager.default.fileExists(atPath: url.path),
              fileSize > 0 else {
            try? FileManager.default.removeItem(at: url)
            return nil
        }
        return url
    }
    
    func cancelRecording() {
        stateLock.lock()
        let recorder = audioRecorder
        let url = recordingURL
        audioRecorder = nil
        recordingURL = nil
        activeGeneration = nil
        stateLock.unlock()

        recorder?.stop()
        if let url {
            try? FileManager.default.removeItem(at: url)
        }
    }

    private func validateConfiguration(sampleRate: Int, channels: Int) throws {
        guard (8000...48000).contains(sampleRate) else {
            throw makeError(
                code: 3,
                message: UIStrings.localized(
                    english: "The recording sample rate must be between 8000 and 48000 Hz.",
                    simplifiedChinese: "录音采样率必须在 8000 到 48000 Hz 之间。"
                )
            )
        }
        guard channels == 1 || channels == 2 else {
            throw makeError(
                code: 4,
                message: UIStrings.localized(
                    english: "Recording supports only mono or stereo audio.",
                    simplifiedChinese: "录音仅支持单声道或双声道。"
                )
            )
        }
    }

    private func isGenerationActive(_ generation: UUID) -> Bool {
        withStateLock { activeGeneration == generation }
    }

    private func clearGeneration(_ generation: UUID) {
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

    private func makeError(code: Int, message: String) -> NSError {
        NSError(
            domain: "AudioRecorder",
            code: code,
            userInfo: [NSLocalizedDescriptionKey: message]
        )
    }

    private func requestMicrophoneAccess() async -> Bool {
        await withCheckedContinuation { continuation in
            AVCaptureDevice.requestAccess(for: .audio) { granted in
                continuation.resume(returning: granted)
            }
        }
    }
}
