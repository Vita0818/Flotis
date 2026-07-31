import Darwin
import Dispatch
import Foundation

protocol SecretStoring: AnyObject {
    @discardableResult
    func save(secret: String, for reference: String) -> Bool
    func load(for reference: String) -> String?
    @discardableResult
    func delete(for reference: String) -> Bool
}

final class LocalSecretStore: SecretStoring {
    static let shared = LocalSecretStore()

    static let defaultFileURL: URL = {
        let applicationSupport = FileManager.default.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        ).first ?? FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support", isDirectory: true)
        return applicationSupport
            .appendingPathComponent("Flotis", isDirectory: true)
            .appendingPathComponent("secrets.json", isDirectory: false)
    }()

    private static let schemaVersion = 1
    private static let maximumFileSize = 1_048_576
    private static let maximumSecretCount = 256
    private static let maximumReferenceLength = 1_024
    private static let maximumSecretLength = 262_144
    private static let maximumLockWaitNanoseconds: UInt64 = 500_000_000
    private static let lockRetryMicroseconds: UInt64 = 10_000
    private static let processLock = NSLock()

    private let fileURL: URL
    private let fileManager: FileManager
    private let encoder: JSONEncoder
    private let decoder = JSONDecoder()
    private let lockFileName = ".secrets.lock"

    init(
        fileURL: URL = LocalSecretStore.defaultFileURL,
        fileManager: FileManager = .default
    ) {
        self.fileURL = fileURL.standardizedFileURL
        self.fileManager = fileManager
        encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
    }

    @discardableResult
    func save(secret: String, for reference: String) -> Bool {
        guard let normalizedReference = normalizedReference(reference),
              let normalizedSecret = normalizedSecret(secret) else {
            return false
        }

        return withLockedDirectory { directoryDescriptor in
            guard var secrets = readSecrets(from: directoryDescriptor),
                  secrets.count < Self.maximumSecretCount
                    || secrets[normalizedReference] != nil else {
                return false
            }
            secrets[normalizedReference] = normalizedSecret
            return writeSecrets(secrets, to: directoryDescriptor)
        } ?? false
    }

    func load(for reference: String) -> String? {
        guard let normalizedReference = normalizedReference(reference) else {
            return nil
        }

        guard let result: String? = withLockedDirectory({ directoryDescriptor in
            readSecrets(from: directoryDescriptor)?[normalizedReference]
        }) else {
            return nil
        }
        return result
    }

    @discardableResult
    func delete(for reference: String) -> Bool {
        guard let normalizedReference = normalizedReference(reference) else {
            return false
        }

        return withLockedDirectory { directoryDescriptor in
            guard var secrets = readSecrets(from: directoryDescriptor) else {
                return false
            }
            guard secrets.removeValue(forKey: normalizedReference) != nil else {
                return true
            }
            if secrets.isEmpty {
                return removeSecretFile(from: directoryDescriptor)
            }
            return writeSecrets(secrets, to: directoryDescriptor)
        } ?? false
    }

    private func normalizedReference(_ reference: String) -> String? {
        let normalized = reference.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalized.isEmpty,
              normalized.count <= Self.maximumReferenceLength else {
            return nil
        }
        return normalized
    }

    private func normalizedSecret(_ secret: String) -> String? {
        let normalized = secret.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalized.isEmpty,
              normalized.count <= Self.maximumSecretLength else {
            return nil
        }
        return normalized
    }

    private func withLockedDirectory<Result>(
        _ body: (Int32) -> Result
    ) -> Result? {
        Self.processLock.lock()
        defer { Self.processLock.unlock() }

        guard let directoryDescriptor = openStorageDirectory() else {
            return nil
        }
        defer { Darwin.close(directoryDescriptor) }

        guard let lockDescriptor = openLockFile(in: directoryDescriptor) else {
            return nil
        }
        defer { Darwin.close(lockDescriptor) }

        guard acquireFileLock(on: lockDescriptor) else {
            return nil
        }
        defer {
            _ = applyFileLock(
                on: lockDescriptor,
                type: Int16(F_UNLCK)
            )
        }

        return body(directoryDescriptor)
    }

    private func openStorageDirectory() -> Int32? {
        let directoryURL = fileURL.deletingLastPathComponent()
        if let descriptor = openDirectory(at: directoryURL) {
            return descriptor
        }
        guard errno == ENOENT else {
            return nil
        }

        do {
            try fileManager.createDirectory(
                at: directoryURL,
                withIntermediateDirectories: true,
                attributes: [.posixPermissions: NSNumber(value: 0o700)]
            )
        } catch {
            return nil
        }
        return openDirectory(at: directoryURL)
    }

    private func openDirectory(at url: URL) -> Int32? {
        let descriptor = url.withUnsafeFileSystemRepresentation { path in
            guard let path else { return Int32(-1) }
            return Darwin.open(
                path,
                O_RDONLY | O_DIRECTORY | O_NOFOLLOW | O_CLOEXEC
            )
        }
        guard descriptor >= 0 else {
            return nil
        }

        var fileStatus = stat()
        guard Darwin.fstat(descriptor, &fileStatus) == 0,
              fileStatus.st_mode & S_IFMT == S_IFDIR,
              fileStatus.st_uid == geteuid(),
              Darwin.fchmod(descriptor, mode_t(0o700)) == 0,
              Darwin.fstat(descriptor, &fileStatus) == 0,
              fileStatus.st_mode & mode_t(0o777) == mode_t(0o700) else {
            Darwin.close(descriptor)
            return nil
        }
        return descriptor
    }

    private func openLockFile(in directoryDescriptor: Int32) -> Int32? {
        let descriptor = lockFileName.withCString { fileName in
            Darwin.openat(
                directoryDescriptor,
                fileName,
                O_RDWR | O_CREAT | O_NOFOLLOW | O_CLOEXEC,
                mode_t(0o600)
            )
        }
        guard descriptor >= 0,
              validateAndRestrictRegularFile(descriptor) else {
            if descriptor >= 0 {
                Darwin.close(descriptor)
            }
            return nil
        }
        return descriptor
    }

    private func readSecrets(from directoryDescriptor: Int32) -> [String: String]? {
        let descriptor = openSecretFile(
            in: directoryDescriptor,
            flags: O_RDONLY | O_NOFOLLOW | O_CLOEXEC
        )
        if descriptor < 0 {
            return errno == ENOENT ? [:] : nil
        }
        defer { Darwin.close(descriptor) }

        guard validateAndRestrictRegularFile(descriptor) else {
            return nil
        }

        var fileStatus = stat()
        guard Darwin.fstat(descriptor, &fileStatus) == 0,
              fileStatus.st_size >= 0,
              fileStatus.st_size <= off_t(Self.maximumFileSize),
              let data = readData(from: descriptor),
              data.count <= Self.maximumFileSize,
              let payload = try? decoder.decode(SecretPayload.self, from: data),
              payload.schemaVersion == Self.schemaVersion,
              payload.secrets.count <= Self.maximumSecretCount else {
            return nil
        }

        for (reference, secret) in payload.secrets {
            guard normalizedReference(reference) == reference,
                  normalizedSecret(secret) == secret else {
                return nil
            }
        }
        return payload.secrets
    }

    private func writeSecrets(
        _ secrets: [String: String],
        to directoryDescriptor: Int32
    ) -> Bool {
        guard existingSecretFileIsValidOrMissing(in: directoryDescriptor),
              let data = try? encoder.encode(
                SecretPayload(
                    schemaVersion: Self.schemaVersion,
                    secrets: secrets
                )
              ),
              data.count <= Self.maximumFileSize else {
            return false
        }

        let temporaryFileName = ".secrets-\(UUID().uuidString).tmp"
        let temporaryDescriptor = temporaryFileName.withCString { fileName in
            Darwin.openat(
                directoryDescriptor,
                fileName,
                O_WRONLY | O_CREAT | O_EXCL | O_NOFOLLOW | O_CLOEXEC,
                mode_t(0o600)
            )
        }
        guard temporaryDescriptor >= 0 else {
            return false
        }

        var shouldRemoveTemporaryFile = true
        defer {
            Darwin.close(temporaryDescriptor)
            if shouldRemoveTemporaryFile {
                _ = temporaryFileName.withCString { fileName in
                    Darwin.unlinkat(directoryDescriptor, fileName, 0)
                }
            }
        }

        guard validateAndRestrictRegularFile(temporaryDescriptor),
              writeData(data, to: temporaryDescriptor),
              Darwin.fsync(temporaryDescriptor) == 0,
              atomicReplace(
                sourceName: temporaryFileName,
                destinationName: fileURL.lastPathComponent,
                in: directoryDescriptor
              ) else {
            return false
        }
        shouldRemoveTemporaryFile = false
        _ = Darwin.fsync(directoryDescriptor)
        return true
    }

    private func existingSecretFileIsValidOrMissing(
        in directoryDescriptor: Int32
    ) -> Bool {
        let descriptor = openSecretFile(
            in: directoryDescriptor,
            flags: O_RDONLY | O_NOFOLLOW | O_CLOEXEC
        )
        if descriptor < 0 {
            return errno == ENOENT
        }
        defer { Darwin.close(descriptor) }
        return validateAndRestrictRegularFile(descriptor)
    }

    private func removeSecretFile(from directoryDescriptor: Int32) -> Bool {
        let descriptor = openSecretFile(
            in: directoryDescriptor,
            flags: O_RDONLY | O_NOFOLLOW | O_CLOEXEC
        )
        if descriptor < 0 {
            return errno == ENOENT
        }
        guard validateAndRestrictRegularFile(descriptor) else {
            Darwin.close(descriptor)
            return false
        }
        Darwin.close(descriptor)

        let result = fileURL.lastPathComponent.withCString { fileName in
            Darwin.unlinkat(directoryDescriptor, fileName, 0)
        }
        guard result == 0 else {
            return errno == ENOENT
        }
        _ = Darwin.fsync(directoryDescriptor)
        return true
    }

    private func openSecretFile(in directoryDescriptor: Int32, flags: Int32) -> Int32 {
        fileURL.lastPathComponent.withCString { fileName in
            Darwin.openat(directoryDescriptor, fileName, flags)
        }
    }

    private func validateAndRestrictRegularFile(_ descriptor: Int32) -> Bool {
        var fileStatus = stat()
        guard Darwin.fstat(descriptor, &fileStatus) == 0,
              fileStatus.st_mode & S_IFMT == S_IFREG,
              fileStatus.st_uid == geteuid(),
              Darwin.fchmod(descriptor, mode_t(0o600)) == 0,
              Darwin.fstat(descriptor, &fileStatus) == 0,
              fileStatus.st_mode & mode_t(0o777) == mode_t(0o600) else {
            return false
        }
        return true
    }

    private func readData(from descriptor: Int32) -> Data? {
        var data = Data()
        var buffer = [UInt8](repeating: 0, count: 16_384)

        while true {
            let byteCount = buffer.withUnsafeMutableBytes { bytes in
                Darwin.read(descriptor, bytes.baseAddress, bytes.count)
            }
            if byteCount < 0 {
                if errno == EINTR {
                    continue
                }
                return nil
            }
            if byteCount == 0 {
                return data
            }
            guard data.count + byteCount <= Self.maximumFileSize else {
                return nil
            }
            buffer.withUnsafeBytes { bytes in
                guard let baseAddress = bytes.bindMemory(to: UInt8.self).baseAddress else {
                    return
                }
                data.append(baseAddress, count: byteCount)
            }
        }
    }

    private func writeData(_ data: Data, to descriptor: Int32) -> Bool {
        data.withUnsafeBytes { bytes in
            guard let baseAddress = bytes.baseAddress else {
                return false
            }

            var offset = 0
            while offset < bytes.count {
                let written = Darwin.write(
                    descriptor,
                    baseAddress.advanced(by: offset),
                    bytes.count - offset
                )
                if written < 0 {
                    if errno == EINTR {
                        continue
                    }
                    return false
                }
                guard written > 0 else {
                    return false
                }
                offset += written
            }
            return true
        }
    }

    private func atomicReplace(
        sourceName: String,
        destinationName: String,
        in directoryDescriptor: Int32
    ) -> Bool {
        sourceName.withCString { sourcePath in
            destinationName.withCString { destinationPath in
                Darwin.renameat(
                    directoryDescriptor,
                    sourcePath,
                    directoryDescriptor,
                    destinationPath
                ) == 0
            }
        }
    }

    private func acquireFileLock(on descriptor: Int32) -> Bool {
        let start = DispatchTime.now().uptimeNanoseconds
        let (deadline, overflow) = start.addingReportingOverflow(
            Self.maximumLockWaitNanoseconds
        )
        guard !overflow else {
            return false
        }

        while true {
            guard let lockError = applyFileLock(
                on: descriptor,
                type: Int16(F_WRLCK)
            ) else {
                return true
            }
            guard lockError == EACCES || lockError == EAGAIN else {
                return false
            }

            let now = DispatchTime.now().uptimeNanoseconds
            guard now < deadline else {
                return false
            }
            let remainingMicroseconds = max(
                UInt64(1),
                min(
                    Self.lockRetryMicroseconds,
                    (deadline - now) / 1_000
                )
            )
            _ = Darwin.usleep(useconds_t(remainingMicroseconds))
        }
    }

    private func applyFileLock(
        on descriptor: Int32,
        type: Int16
    ) -> Int32? {
        var fileLock = Darwin.flock()
        fileLock.l_type = type
        fileLock.l_whence = Int16(SEEK_SET)
        fileLock.l_start = 0
        fileLock.l_len = 0

        while Darwin.fcntl(descriptor, F_SETLK, &fileLock) != 0 {
            let lockError = errno
            guard lockError == EINTR else {
                return lockError
            }
        }
        return nil
    }

    private struct SecretPayload: Codable {
        var schemaVersion: Int
        var secrets: [String: String]
    }
}
