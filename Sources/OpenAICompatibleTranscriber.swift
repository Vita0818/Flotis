import Foundation

final class OpenAIHTTPTranscriber: FileSpeechTranscribing {
    private let apiKey: String

    init(apiKey: String) {
        self.apiKey = apiKey
    }

    func transcribeFile(_ fileURL: URL, config: SpeechProviderConfig) async throws -> String {
        guard let endpointURL = URL(string: config.baseURL + config.endpointPath) else {
            throw NSError(
                domain: "OpenAIHTTPTranscriber",
                code: 1,
                userInfo: [NSLocalizedDescriptionKey: "Base URL 或 Endpoint Path 非法。"]
            )
        }

        var request = URLRequest(url: endpointURL)
        request.httpMethod = "POST"
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")

        let boundary = "Boundary-\(UUID().uuidString)"
        request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")

        var body = Data()
        appendFormField(name: "model", value: config.model, boundary: boundary, body: &body)

        if let language = config.language, !language.isEmpty {
            appendFormField(name: "language", value: language, boundary: boundary, body: &body)
        }

        if let prompt = config.prompt, !prompt.isEmpty {
            appendFormField(name: "prompt", value: prompt, boundary: boundary, body: &body)
        }

        if let temperature = config.temperature {
            appendFormField(name: "temperature", value: "\(temperature)", boundary: boundary, body: &body)
        }

        appendFormField(name: "response_format", value: "json", boundary: boundary, body: &body)
        try appendFileField(fileURL: fileURL, boundary: boundary, body: &body)
        body.append("--\(boundary)--\r\n".utf8Data)

        let (data, response) = try await URLSession.shared.upload(for: request, from: body)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw NSError(
                domain: "OpenAIHTTPTranscriber",
                code: 2,
                userInfo: [NSLocalizedDescriptionKey: "网络响应无效。"]
            )
        }

        guard (200...299).contains(httpResponse.statusCode) else {
            let errorText = String(data: data, encoding: .utf8) ?? "HTTP \(httpResponse.statusCode)"
            throw NSError(
                domain: "OpenAIHTTPTranscriber",
                code: httpResponse.statusCode,
                userInfo: [NSLocalizedDescriptionKey: errorText]
            )
        }

        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw NSError(
                domain: "OpenAIHTTPTranscriber",
                code: 3,
                userInfo: [NSLocalizedDescriptionKey: "转写响应 JSON 解析失败。"]
            )
        }

        if let text = json["text"] as? String {
            return text
        }
        if let transcript = json["transcript"] as? String {
            return transcript
        }
        if let dataObject = json["data"] as? [String: Any],
           let text = dataObject["text"] as? String {
            return text
        }

        throw NSError(
            domain: "OpenAIHTTPTranscriber",
            code: 4,
            userInfo: [NSLocalizedDescriptionKey: "转写响应中没有找到 text 字段。"]
        )
    }

    private func appendFormField(name: String, value: String, boundary: String, body: inout Data) {
        body.append("--\(boundary)\r\n".utf8Data)
        body.append("Content-Disposition: form-data; name=\"\(name)\"\r\n\r\n".utf8Data)
        body.append("\(value)\r\n".utf8Data)
    }

    private func appendFileField(fileURL: URL, boundary: String, body: inout Data) throws {
        let filename = fileURL.lastPathComponent
        let fileData = try Data(contentsOf: fileURL)

        body.append("--\(boundary)\r\n".utf8Data)
        body.append("Content-Disposition: form-data; name=\"file\"; filename=\"\(filename)\"\r\n".utf8Data)
        body.append("Content-Type: audio/m4a\r\n\r\n".utf8Data)
        body.append(fileData)
        body.append("\r\n".utf8Data)
    }
}

typealias OpenAICompatibleTranscriber = OpenAIHTTPTranscriber

private extension String {
    var utf8Data: Data {
        Data(utf8)
    }
}
