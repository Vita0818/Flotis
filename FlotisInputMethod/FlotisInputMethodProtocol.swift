import Foundation

/// The versioned request passed from a future Flotis voice process to the input method.
///
/// The active session identifier is deliberately part of every request. A transcript
/// captured for one focused client must never be inserted after focus has moved to a
/// different client.
struct FlotisInputMethodCommitRequest: Codable, Equatable, Sendable {
    static let currentProtocolVersion = 1

    let protocolVersion: Int
    let sessionID: UUID
    let text: String

    init(
        protocolVersion: Int = Self.currentProtocolVersion,
        sessionID: UUID,
        text: String
    ) {
        self.protocolVersion = protocolVersion
        self.sessionID = sessionID
        self.text = text
    }
}

enum FlotisInputMethodCommitFailure: String, Codable, Equatable, Error, Sendable {
    case unsupportedProtocol
    case emptyText
    case textTooLarge
    case staleSession
    case endpointUnavailable
    case clientUnavailable
}

enum FlotisInputMethodCommitResult: Codable, Equatable, Sendable {
    case deliveredToClient
    case rejected(FlotisInputMethodCommitFailure)
}

struct FlotisInputMethodSessionGate {
    static let maximumTextByteCount = 1_048_576

    private(set) var activeSessionID: UUID?

    @discardableResult
    mutating func activate(sessionID: UUID = UUID()) -> UUID {
        activeSessionID = sessionID
        return sessionID
    }

    @discardableResult
    mutating func deactivate(sessionID: UUID) -> Bool {
        guard activeSessionID == sessionID else {
            return false
        }

        activeSessionID = nil
        return true
    }

    func validate(_ request: FlotisInputMethodCommitRequest) -> FlotisInputMethodCommitFailure? {
        guard request.protocolVersion == FlotisInputMethodCommitRequest.currentProtocolVersion else {
            return .unsupportedProtocol
        }

        guard request.text.utf8.count <= Self.maximumTextByteCount else {
            return .textTooLarge
        }

        guard request.text.contains(where: { !$0.isWhitespace }) else {
            return .emptyText
        }

        guard activeSessionID == request.sessionID else {
            return .staleSession
        }

        return nil
    }
}
