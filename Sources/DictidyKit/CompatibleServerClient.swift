import Foundation

public enum CompatibleServerError: LocalizedError, Equatable {
    case invalidAddress
    case network(String)
    case http(Int, String)
    case invalidResponse
    case incompleteResponse(String)
    case refused
    case emptyResponse

    public var errorDescription: String? {
        switch self {
        case .invalidAddress:
            return "Enter an HTTP or HTTPS API base URL, such as https://server.example.ts.net/v1, without credentials, a query, or a fragment."
        case .network(let message):
            return "Couldn't reach the custom server: \(message). Check that the server is running and your network or Tailscale connection is available."
        case .http(let code, let message): return "Custom server error (\(code)): \(message)"
        case .invalidResponse: return "Couldn't read the custom server response. Check that it supports OpenAI-compatible Chat Completions."
        case .incompleteResponse(let reason):
            return "The custom server did not finish the rewrite (\(reason)). Try a shorter text or increase the server's context size."
        case .refused: return "The custom server declined the rewrite."
        case .emptyResponse: return "The custom server returned no rewritten text."
        }
    }
}

/// A stateless Chat Completions request. Only this connection's optional token is accepted.
public struct CompatibleServerClient {
    public typealias Transport = @Sendable (URLRequest) async throws -> (Data, URLResponse)
    private let configuration: CompatibleServerConfiguration
    private let token: String
    private let transport: Transport

    public init(configuration: CompatibleServerConfiguration, token: String? = nil,
                transport: @escaping Transport) {
        self.configuration = configuration
        self.token = token?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        self.transport = transport
    }

    public func listModelIDs() async throws -> [String] {
        let data = try await send(path: "models")
        struct Catalog: Decodable {
            struct Model: Decodable { let id: String }
            let data: [Model]
        }
        guard let catalog = try? JSONDecoder().decode(Catalog.self, from: data) else {
            throw CompatibleServerError.invalidResponse
        }
        // Local model IDs are arbitrary; OpenAI's family-name filter must not be applied here.
        return Array(Set(catalog.data.map(\.id).filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty })).sorted()
    }

    public func rewrite(text: String, systemPrompt: String, model: String) async throws -> String {
        let body = try JSONSerialization.data(withJSONObject: [
            "model": model,
            "messages": [["role": "system", "content": systemPrompt], ["role": "user", "content": text]],
            "stream": false, "max_tokens": 2048
        ])
        let data = try await send(path: "chat/completions", body: body)
        guard let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let choices = object["choices"] as? [[String: Any]], choices.count == 1,
              let choice = choices.first,
              let message = choice["message"] as? [String: Any], message["role"] as? String == "assistant" else {
            throw CompatibleServerError.invalidResponse
        }
        if let refusal = message["refusal"] as? String, !refusal.isEmpty { throw CompatibleServerError.refused }
        guard choice["finish_reason"] as? String == "stop" else {
            throw CompatibleServerError.incompleteResponse(choice["finish_reason"] as? String ?? "missing finish reason")
        }
        guard let text = message["content"] as? String else { throw CompatibleServerError.invalidResponse }
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { throw CompatibleServerError.emptyResponse }
        return text
    }

    private func send(path: String, body: Data? = nil) async throws -> Data {
        try Task.checkCancellation()
        var request = URLRequest(url: configuration.baseURL.appendingPathComponent(path))
        request.httpMethod = body == nil ? "GET" : "POST"
        request.httpBody = body
        request.timeoutInterval = body == nil ? 20 : 180
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        if !token.isEmpty { request.setValue("Bearer " + token, forHTTPHeaderField: "Authorization") }
        let data: Data
        let response: URLResponse
        do { (data, response) = try await transport(request) }
        catch is CancellationError { throw CancellationError() }
        catch {
            try Task.checkCancellation()
            throw CompatibleServerError.network(error.localizedDescription)
        }
        try Task.checkCancellation()
        guard let http = response as? HTTPURLResponse else { throw CompatibleServerError.invalidResponse }
        guard (200..<300).contains(http.statusCode) else {
            // Avoid reflecting arbitrary HTML or request text from a proxy into alerts.
            throw CompatibleServerError.http(http.statusCode, OpenAIClient.extractErrorMessage(data) ?? "Check the server address, token, and model configuration.")
        }
        return data
    }
}
