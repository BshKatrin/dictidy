import Foundation
import DictidyKit

@MainActor
private func expectServerError(_ name: String, _ expected: CompatibleServerError,
                               _ body: () async throws -> Void) async {
    await checkAsync(name) {
        do { try await body(); return false }
        catch let error as CompatibleServerError { return error == expected }
    }
}

@MainActor
func runCompatibleServerTests() async {
    print("Compatible server configuration")
    do {
        let server = try CompatibleServerConfiguration(address: " HTTPS://Server.Example.ts.net/ ")
        let restored = try JSONDecoder().decode(CompatibleServerConfiguration.self, from: JSONEncoder().encode(server))
        check("canonical base URL adds v1 and preserves identity across persistence",
              server.baseURL.absoluteString == "https://server.example.ts.net/v1"
              && restored == server)
        check("loopback ports and proxy prefixes are supported",
              try CompatibleServerConfiguration(address: "http://127.0.0.1:8080/proxy/v1///").baseURL.absoluteString
              == "http://127.0.0.1:8080/proxy/v1")
        check("IPv6 loopback is supported",
              try CompatibleServerConfiguration(address: "http://[::1]:8080/v1").baseURL.absoluteString == "http://[::1]:8080/v1")
    } catch { check("server configuration", false) }
    for address in ["", "server:8080", "file:///tmp/model", "https:///", "https://user:password@host/v1",
                    "https://host/v1?token=secret", "https://host/v1#fragment", "http://host:0/v1",
                    "http://host:65536/v1", "https://bad host/v1"] {
        checkThrows("reject unsafe or invalid server address: \(address)") {
            _ = try CompatibleServerConfiguration(address: address)
        }
    }
    checkThrows("persisted configuration is validated on load") {
        _ = try JSONDecoder().decode(CompatibleServerConfiguration.self, from:
            data(#"{"id":"00000000-0000-0000-0000-000000000001","baseURL":"file:///tmp/model"}"#))
    }

    guard let server = try? CompatibleServerConfiguration(address: "https://server.example.ts.net/proxy/v1") else {
        check("test server configuration", false); return
    }
    let complete = #"{"choices":[{"message":{"role":"assistant","content":"First paragraph.\n\nSecond paragraph.","reasoning_content":"private reasoning"},"finish_reason":"stop"}]}"#
    await checkAsync("server rewrite preserves roles and paragraphs, ignores reasoning, and uses only its own token") {
        let client = CompatibleServerClient(configuration: server, token: " server-token ", transport: { request in
            let payload = try JSONSerialization.jsonObject(with: request.httpBody!) as! [String: Any]
            guard request.url?.absoluteString == "https://server.example.ts.net/proxy/v1/chat/completions",
                  request.httpMethod == "POST", request.timeoutInterval == 180,
                  request.value(forHTTPHeaderField: "Authorization") == "Bearer server-token",
                  request.value(forHTTPHeaderField: "x-api-key") == nil,
                  request.value(forHTTPHeaderField: "Content-Type") == "application/json",
                  payload["model"] as? String == "my-rewriter.gguf",
                  payload["messages"] as? [[String: String]] == [
                    ["role": "system", "content": "Keep my voice."], ["role": "user", "content": "Original text."]],
                  payload["stream"] as? Bool == false, payload["max_tokens"] as? Int == 2048,
                  payload["tools"] == nil else { throw URLError(.badServerResponse) }
            return (data(complete), httpResponse(200))
        })
        return try await client.rewrite(text: "Original text.", systemPrompt: "Keep my voice.", model: "my-rewriter.gguf")
            == "First paragraph.\n\nSecond paragraph."
    }
    await checkAsync("discovery accepts arbitrary GGUF aliases without an API token and deduplicates IDs") {
        let client = CompatibleServerClient(configuration: server, transport: { request in
            guard request.url?.absoluteString == "https://server.example.ts.net/proxy/v1/models",
                  request.httpMethod == "GET", request.httpBody == nil, request.timeoutInterval == 20,
                  request.value(forHTTPHeaderField: "Authorization") == nil else { throw URLError(.badServerResponse) }
            return (data(#"{"data":[{"id":"qwen-rewriter"},{"id":"my/model.gguf"},{"id":"qwen-rewriter"},{"id":" "}]}"#), httpResponse(200))
        })
        return try await client.listModelIDs() == ["my/model.gguf", "qwen-rewriter"]
    }
    await checkAsync("empty catalog is valid") {
        try await CompatibleServerClient(configuration: server, token: " ", transport: stubTransport(200, #"{"data":[]}"#))
            .listModelIDs().isEmpty
    }
    for catalog in ["not json", #"{"data":[{}]}"#] {
        await expectServerError("malformed catalog fails", .invalidResponse) {
            _ = try await CompatibleServerClient(configuration: server, transport: stubTransport(200, catalog)).listModelIDs()
        }
    }
    for (code, body, message) in [
        (401, #"{"error":{"message":"Invalid token"}}"#, "Invalid token"),
        (503, "<html>Private request text</html>", "Check the server address, token, and model configuration."),
        (307, "", "Check the server address, token, and model configuration.")
    ] {
        await expectServerError("HTTP \(code) errors never become rewrite output", .http(code, message)) {
            _ = try await CompatibleServerClient(configuration: server, transport: stubTransport(code, body))
                .rewrite(text: "Original", systemPrompt: "Rewrite", model: "m")
        }
    }
    await checkAsync("unreachable server has a useful connection error") {
        do {
            _ = try await CompatibleServerClient(configuration: server, transport: { _ in throw URLError(.timedOut) }).listModelIDs()
            return false
        } catch let error as CompatibleServerError {
            if case .network = error { return error.localizedDescription.contains("Tailscale") }
            return false
        }
    }
    await expectServerError("non-HTTP responses fail", .invalidResponse) {
        _ = try await CompatibleServerClient(configuration: server, transport: { request in
            (data(complete), URLResponse(url: request.url!, mimeType: nil, expectedContentLength: 0, textEncodingName: nil))
        }).listModelIDs()
    }
    let invalid: [(String, CompatibleServerError)] = [
        ("bad json", .invalidResponse),
        (#"{"choices":[]}"#, .invalidResponse),
        (#"{"choices":[{"message":{"role":"user","content":"text"},"finish_reason":"stop"}]}"#, .invalidResponse),
        (#"{"choices":[{"message":{"role":"assistant","content":"partial"},"finish_reason":"length"}]}"#, .incompleteResponse("length")),
        (#"{"choices":[{"message":{"role":"assistant","content":"partial"},"finish_reason":"tool_calls"}]}"#, .incompleteResponse("tool_calls")),
        (#"{"choices":[{"message":{"role":"assistant","content":"partial"}}]}"#, .incompleteResponse("missing finish reason")),
        (#"{"choices":[{"message":{"role":"assistant","refusal":"declined","content":null},"finish_reason":"stop"}]}"#, .refused),
        (#"{"choices":[{"message":{"role":"assistant","content":null},"finish_reason":"stop"}]}"#, .invalidResponse),
        (#"{"choices":[{"message":{"role":"assistant","content":" \n "},"finish_reason":"stop"}]}"#, .emptyResponse)
    ]
    for (body, error) in invalid {
        await expectServerError("reject unusable rewrite: \(error)", error) {
            _ = try await CompatibleServerClient(configuration: server, transport: stubTransport(200, body))
                .rewrite(text: "Original", systemPrompt: "Rewrite", model: "m")
        }
    }
    await checkAsync("transport cancellation propagates without a connection alert") {
        do {
            _ = try await CompatibleServerClient(configuration: server, transport: { _ in throw CancellationError() }).listModelIDs()
            return false
        } catch is CancellationError { return true }
    }
    await checkAsync("a cancelled operation never starts a request") {
        let task = Task {
            withUnsafeCurrentTask { $0?.cancel() }
            return try await CompatibleServerClient(configuration: server, transport: { _ in
                fatalError("Cancelled request must not be sent")
            }).listModelIDs()
        }
        do { _ = try await task.value; return false }
        catch is CancellationError { return true }
    }
    let errors: [CompatibleServerError] = [.invalidAddress, .invalidResponse, .network("offline"), .http(401, "token"),
                                         .incompleteResponse("length"), .refused, .emptyResponse]
    check("server errors explain failures", errors.allSatisfy { !$0.localizedDescription.isEmpty })
}
