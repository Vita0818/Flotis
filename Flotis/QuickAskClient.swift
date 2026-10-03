import Foundation

protocol QuickAskServicing: AnyObject {
    func complete(
        messages: [QuickAskMessage],
        configuration: QuickAskConfiguration
    ) async throws -> String
}

enum QuickAskError: Error, Equatable {
    case configuration(String)
    case missingModel
    case requestTimeout
    case connectionFailed(String)
    case server(status: Int, message: String)
    case emptyResponse
    case responseTooLarge
    case cancelled
    case unexpectedResponse
}

extension QuickAskError: LocalizedError {
    var errorDescription: String? {
        switch self {
        case .configuration(let message):
            return message
        case .missingModel:
            return UIStrings.quickAskMissingModelDetail
        case .requestTimeout:
            return UIStrings.quickAskRequestTimedOutDetail
        case .connectionFailed(let reason):
            return UIStrings.quickAskConnectionFailedDetail(reason)
        case .server(let status, let message):
            return UIStrings.quickAskServerError(status: status, message: message)
        case .emptyResponse:
            return UIStrings.quickAskEmptyResponse
        case .responseTooLarge:
            return UIStrings.quickAskResponseTooLarge
        case .cancelled:
            return UIStrings.quickAskRequestCancelled
        case .unexpectedResponse:
            return UIStrings.quickAskUnexpectedResponse
        }
    }
}

final class QuickAskClient: QuickAskServicing {
    static let maximumResponseBytes = 4_194_304

    private let session: URLSession

    init(session: URLSession? = nil) {
        if let session {
            self.session = session
        } else {
            let configuration = URLSessionConfiguration.ephemeral
            configuration.urlCache = nil
            configuration.requestCachePolicy = .reloadIgnoringLocalCacheData
            configuration.waitsForConnectivity = false
            self.session = URLSession(
                configuration: configuration,
                delegate: NoRedirectSessionDelegate.shared,
                delegateQueue: nil
            )
        }
    }

    func complete(
        messages: [QuickAskMessage],
        configuration: QuickAskConfiguration
    ) async throws -> String {
        let normalized = configuration.normalized()
        if let error = normalized.validationError() {
            if error == .missingModel {
                throw QuickAskError.missingModel
            }
            throw QuickAskError.configuration(error.localizedDescription)
        }

        let url: URL
        do {
            url = try QuickAskEndpointResolver.endpointURL(for: normalized)
        } catch let error as QuickAskConfigurationError {
            throw QuickAskError.configuration(error.localizedDescription)
        } catch {
            throw QuickAskError.configuration(UIStrings.quickAskHTTPSRequired)
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        if let apiKey = normalized.apiKey {
            request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        }
        request.timeoutInterval = TimeInterval(normalized.timeoutSeconds)

        var payloadMessages: [QuickAskRequestBody.Message] = []
        let systemPrompt = normalized.systemPrompt.trimmingCharacters(in: .whitespacesAndNewlines)
        if !systemPrompt.isEmpty {
            payloadMessages.append(.init(role: "system", content: systemPrompt))
        }
        payloadMessages.append(contentsOf: messages.map {
            QuickAskRequestBody.Message(role: $0.role.rawValue, content: $0.content)
        })
        request.httpBody = try JSONEncoder().encode(
            QuickAskRequestBody(
                model: normalized.model,
                messages: payloadMessages,
                temperature: normalized.temperature,
                maxTokens: normalized.maxTokens
            )
        )

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await session.data(for: request)
        } catch let error as URLError {
            switch error.code {
            case .timedOut:
                throw QuickAskError.requestTimeout
            case .cancelled:
                throw QuickAskError.cancelled
            default:
                throw QuickAskError.connectionFailed(error.localizedDescription)
            }
        } catch is CancellationError {
            throw QuickAskError.cancelled
        } catch {
            throw QuickAskError.connectionFailed(error.localizedDescription)
        }

        guard data.count <= Self.maximumResponseBytes else {
            throw QuickAskError.responseTooLarge
        }
        guard let http = response as? HTTPURLResponse else {
            throw QuickAskError.unexpectedResponse
        }
        guard (200 ... 299).contains(http.statusCode) else {
            throw Self.error(
                for: http.statusCode,
                data: data,
                apiKey: normalized.apiKey
            )
        }
        guard Self.isJSONResponse(http) else {
            throw QuickAskError.unexpectedResponse
        }

        do {
            let decoded = try JSONDecoder().decode(QuickAskResponseBody.self, from: data)
            guard let content = decoded.choices?.first?.message?.content,
                  !content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                throw QuickAskError.emptyResponse
            }
            return content
        } catch let error as QuickAskError {
            throw error
        } catch {
            throw QuickAskError.unexpectedResponse
        }
    }

    func testConnection(
        configuration: QuickAskConfiguration
    ) async -> QuickAskConnectionTestResult {
        var probe = configuration.normalized()
        probe.maxTokens = 64
        probe.timeoutSeconds = min(probe.timeoutSeconds, 10)
        do {
            _ = try await complete(
                messages: [QuickAskMessage(role: .user, content: "ping")],
                configuration: probe
            )
            return QuickAskConnectionTestResult(
                status: .ready,
                detail: UIStrings.quickAskConnected(model: probe.model)
            )
        } catch let error as QuickAskError {
            switch error {
            case .missingModel:
                return QuickAskConnectionTestResult(
                    status: .missingModel,
                    detail: UIStrings.quickAskMissingModelDetail
                )
            case .requestTimeout:
                return QuickAskConnectionTestResult(
                    status: .requestTimeout,
                    detail: UIStrings.quickAskRequestTimedOutDetail
                )
            default:
                return QuickAskConnectionTestResult(
                    status: .connectionFailed,
                    detail: error.localizedDescription
                )
            }
        } catch {
            return QuickAskConnectionTestResult(
                status: .connectionFailed,
                detail: error.localizedDescription
            )
        }
    }

    static func error(for status: Int, data: Data, apiKey: String?) -> QuickAskError {
        let decodedMessage = (try? JSONDecoder().decode(
            QuickAskErrorResponseBody.self,
            from: data
        ))?.error?.message
        let safeMessage = sanitizedErrorMessage(
            decodedMessage ?? "HTTP \(status)",
            apiKey: apiKey
        )
        if status == 404 {
            return .missingModel
        }
        if status == 400, safeMessage.lowercased().contains("model") {
            return .missingModel
        }
        return .server(status: status, message: safeMessage)
    }

    static func sanitizedErrorMessage(_ message: String, apiKey: String?) -> String {
        var value = message
        if let apiKey, !apiKey.isEmpty {
            value = value.replacingOccurrences(of: apiKey, with: "[REDACTED]")
        }
        value = value.replacingOccurrences(of: "\u{0000}", with: "")
        return String(value.prefix(512))
    }

    private static func isJSONResponse(_ response: HTTPURLResponse) -> Bool {
        guard let contentType = response.value(forHTTPHeaderField: "Content-Type")?
            .lowercased()
            .split(separator: ";", maxSplits: 1)
            .first?
            .trimmingCharacters(in: .whitespacesAndNewlines) else {
            return false
        }
        return contentType == "application/json" || contentType.hasSuffix("+json")
    }
}

private struct QuickAskRequestBody: Encodable {
    struct Message: Encodable {
        let role: String
        let content: String
    }

    let model: String
    let messages: [Message]
    let temperature: Double
    let maxTokens: Int

    private enum CodingKeys: String, CodingKey {
        case model
        case messages
        case temperature
        case maxTokens = "max_tokens"
    }
}

private struct QuickAskResponseBody: Decodable {
    struct Choice: Decodable {
        struct Message: Decodable {
            let role: String?
            let content: String?
        }

        let message: Message?
    }

    let choices: [Choice]?
}

private struct QuickAskErrorResponseBody: Decodable {
    struct Payload: Decodable {
        let message: String?
    }

    let error: Payload?
}
