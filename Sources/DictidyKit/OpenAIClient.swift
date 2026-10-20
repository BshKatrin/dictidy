import Foundation

public enum OpenAIError: LocalizedError, Equatable {
    case missingAPIKey
    case http(Int, String)
    case network(String)
    case decoding(String)
    case incompleteResponse(String)
    case response(String)
    case emptyResponse

    public var errorDescription: String? {
        switch self {
        case .missingAPIKey: return "No OpenAI API key set. Open Settings → Rewrite and add your key."
        case .http(let code, let message): return "OpenAI API error (\(code)): \(message)"
        case .network(let message): return "Network error: \(message)"
        case .decoding(let message): return "Couldn't read the OpenAI response: \(message)"
        case .incompleteResponse(let reason): return "OpenAI did not finish the rewrite (\(reason)). Try a shorter text or another model."
        case .response(let message): return "OpenAI could not complete the rewrite: \(message)"
        case .emptyResponse: return "OpenAI returned no rewritten text."
        }
    }
}

/// Stateless Responses API integration: no conversation, tools, or stored response requested.
/// https://developers.openai.com/api/docs/guides/text
public struct OpenAIClient {
    public typealias Transport = @Sendable (URLRequest) async throws -> (Data, URLResponse)
    public let apiKey: String
    private let transport: Transport

    public init(apiKey: String, transport: @escaping Transport = { try await URLSession.shared.data(for: $0) }) {
        self.apiKey = apiKey
        self.transport = transport
    }

    private func request(_ path: String, body: Data? = nil) throws -> URLRequest {
        guard !apiKey.isEmpty else { throw OpenAIError.missingAPIKey }
        var request = URLRequest(url: URL(string: "https://api.openai.com" + path)!)
        request.httpMethod = body == nil ? "GET" : "POST"
        request.httpBody = body
        request.timeoutInterval = 120
        request.setValue("Bearer " + apiKey, forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        return request
    }

    public func listModels() async throws -> [RewriteModel] {
        let (data, response) = try await send(request("/v1/models"))
        try Self.validate(response, data)
        return try Self.parseModels(data)
    }

    public func rewrite(text: String, systemPrompt: String, model: String,
                        maxTokens: Int? = nil) async throws -> String {
        // The budget includes reasoning tokens; incomplete results must never replace source text.
        let payload: [String: Any] = [
            "model": model, "instructions": systemPrompt,
            "input": [["role": "user", "content": text]],
            "max_output_tokens": maxTokens ?? Self.outputBudget(for: model), "store": false
        ]
        let body = try JSONSerialization.data(withJSONObject: payload)
        let (data, response) = try await send(request("/v1/responses", body: body))
        try Self.validate(response, data)
        return try Self.parseRewriteText(data)
    }

    private func send(_ request: URLRequest) async throws -> (Data, URLResponse) {
        do { return try await transport(request) }
        catch { throw OpenAIError.network(error.localizedDescription) }
    }

    public static func outputBudget(for model: String) -> Int {
        let base = model.hasPrefix("ft:") ? String(model.split(separator: ":", omittingEmptySubsequences: false).dropFirst().first ?? "") : model
        if base.hasPrefix("gpt-4o-2024-05-13") { return 4096 }
        if base.hasPrefix("gpt-4") { return 8192 }
        return 32768
    }

    /// /models has no endpoint/modality capability field. Include modern Responses text families and
    /// their fine-tunes while excluding dedicated audio, image, search, and specialist model IDs.
    public static func supportsRewriting(_ id: String) -> Bool {
        let base = id.hasPrefix("ft:") ? String(id.split(separator: ":", omittingEmptySubsequences: false).dropFirst().first ?? "") : id
        let excluded = ["audio", "realtime", "transcribe", "tts", "image", "search", "embedding",
                        "moderation", "instruct", "codex", "computer-use", "cyber", "rosalind", "research"]
        guard !excluded.contains(where: { base.contains($0) }) else { return false }
        if base.hasPrefix("gpt-4.1") || base.hasPrefix("gpt-4o") { return true }
        if base.hasPrefix("gpt-"), let major = Int(base.dropFirst(4).prefix(while: { $0.isNumber })) {
            return major >= 5
        }
        return base == "o1" || base.hasPrefix("o1-20") || base.hasPrefix("o1-pro")
            || base == "o3" || base.hasPrefix("o3-20") || base.hasPrefix("o3-mini") || base.hasPrefix("o3-pro")
            || base.hasPrefix("o4-mini")
    }

    private struct ModelRecord: Decodable { let id: String }
    private struct ModelsResponse: Decodable { let data: [ModelRecord] }

    public static func parseModels(_ data: Data) throws -> [RewriteModel] {
        do {
            return try JSONDecoder().decode(ModelsResponse.self, from: data).data
                .filter { supportsRewriting($0.id) }
                .map { RewriteModel(provider: .openai, modelID: $0.id, displayName: $0.id) }
        } catch { throw OpenAIError.decoding(error.localizedDescription) }
    }

    public static func parseRewriteText(_ data: Data) throws -> String {
        guard let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let status = object["status"] as? String else {
            throw OpenAIError.decoding("unexpected response shape")
        }
        if status == "incomplete" {
            let details = object["incomplete_details"] as? [String: Any]
            throw OpenAIError.incompleteResponse(details?["reason"] as? String ?? "incomplete response")
        }
        guard status == "completed" else {
            throw OpenAIError.response(extractErrorMessage(data) ?? status)
        }
        guard let output = object["output"] as? [[String: Any]] else {
            throw OpenAIError.decoding("missing output")
        }
        var text = ""
        for item in output where item["type"] as? String == "message" {
            guard let content = item["content"] as? [[String: Any]] else { continue }
            for block in content {
                if block["type"] as? String == "refusal" {
                    throw OpenAIError.response(block["refusal"] as? String ?? "the model declined the rewrite")
                }
                if block["type"] as? String == "output_text", let part = block["text"] as? String {
                    text += part
                }
            }
        }
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { throw OpenAIError.emptyResponse }
        return text
    }

    public static func extractErrorMessage(_ data: Data) -> String? {
        guard let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let error = object["error"] as? [String: Any] else { return nil }
        return error["message"] as? String
    }

    private static func validate(_ response: URLResponse, _ data: Data) throws {
        guard let http = response as? HTTPURLResponse else { return }
        guard (200..<300).contains(http.statusCode) else {
            throw OpenAIError.http(http.statusCode, extractErrorMessage(data)
                                  ?? String(data: data, encoding: .utf8) ?? "unknown error")
        }
    }
}
