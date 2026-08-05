import Foundation

@MainActor
protocol FlotisInputMethodClientEndpoint: AnyObject {
    /// Commits text to the currently focused InputMethodKit client.
    func insertCommittedText(_ text: String) -> Bool
}

/// In-process boundary for the InputMethodKit controller.
///
/// This deliberately owns no provider, microphone, clipboard, Accessibility, logging,
/// or persistence behavior. A later transport can decode a versioned request and call
/// `submit(_:)` on the main actor without changing the client insertion policy here.
@MainActor
final class FlotisInputMethodService {
    static let shared = FlotisInputMethodService()

    private weak var activeEndpoint: (any FlotisInputMethodClientEndpoint)?
    private var sessionGate = FlotisInputMethodSessionGate()

    init() {}

    var currentSessionID: UUID? {
        sessionGate.activeSessionID
    }

    @discardableResult
    func activate(endpoint: any FlotisInputMethodClientEndpoint) -> UUID {
        activeEndpoint = endpoint
        return sessionGate.activate()
    }

    func deactivate(
        endpoint: any FlotisInputMethodClientEndpoint,
        sessionID: UUID
    ) {
        guard activeEndpoint === endpoint else {
            return
        }

        guard sessionGate.deactivate(sessionID: sessionID) else {
            return
        }

        activeEndpoint = nil
    }

    func submit(_ request: FlotisInputMethodCommitRequest) -> FlotisInputMethodCommitResult {
        if let failure = sessionGate.validate(request) {
            return .rejected(failure)
        }

        guard let activeEndpoint else {
            return .rejected(.endpointUnavailable)
        }

        guard activeEndpoint.insertCommittedText(request.text) else {
            return .rejected(.clientUnavailable)
        }

        return .deliveredToClient
    }
}
