import Foundation
import Network
import DictidyKit

/// Exercises the actual URLSession policy against a disposable loopback HTTP server.
@main
struct CompatibleServerPlatformTests {
    private final class Server {
        let listener: NWListener
        let queue = DispatchQueue(label: "DictidyCompatibleServerTests")
        private var captured: [String] = []

        init() throws {
            let parameters = NWParameters.tcp
            parameters.requiredLocalEndpoint = .hostPort(host: "127.0.0.1", port: .any)
            listener = try NWListener(using: parameters)
        }

        func start() async throws -> UInt16 {
            listener.newConnectionHandler = { connection in
                connection.start(queue: self.queue)
                self.receive(connection, buffer: Data())
            }
            return try await withCheckedThrowingContinuation { continuation in
                listener.stateUpdateHandler = { state in
                    switch state {
                    case .ready: continuation.resume(returning: self.listener.port!.rawValue)
                    case .failed(let error): continuation.resume(throwing: error)
                    default: break
                    }
                }
                listener.start(queue: queue)
            }
        }

        var requests: [String] { queue.sync { captured } }

        private func receive(_ connection: NWConnection, buffer: Data) {
            connection.receive(minimumIncompleteLength: 1, maximumLength: 65_536) { bytes, _, complete, error in
                let buffer = buffer + (bytes ?? Data())
                guard error == nil else { connection.cancel(); return }
                let raw = String(decoding: buffer, as: UTF8.self)
                if let end = raw.range(of: "\r\n\r\n") {
                    let header = String(raw[..<end.lowerBound])
                    let length = header.components(separatedBy: "\r\n").first {
                        $0.lowercased().hasPrefix("content-length:")
                    }.flatMap { Int($0.split(separator: ":", maxSplits: 1)[1].trimmingCharacters(in: .whitespaces)) } ?? 0
                    if raw[end.upperBound...].utf8.count >= length {
                        self.captured.append(raw)
                        let redirect = raw.hasPrefix("POST /redirect/")
                        let status = redirect ? "307 Temporary Redirect" : "200 OK"
                        let body = raw.hasPrefix("GET ") ? #"{"data":[{"id":"test-rewriter"}]}"#
                            : #"{"choices":[{"message":{"role":"assistant","content":"Rewritten text."},"finish_reason":"stop"}]}"#
                        let location = redirect ? "Location: http://127.0.0.1:\(self.listener.port!.rawValue)/leak\r\n" : ""
                        let response = "HTTP/1.1 \(status)\r\n\(location)Content-Type: application/json\r\nContent-Length: \(body.utf8.count)\r\nSet-Cookie: unwanted=cookie\r\nConnection: close\r\n\r\n\(body)"
                        connection.send(content: Data(response.utf8), completion: .contentProcessed { _ in connection.cancel() })
                        return
                    }
                }
                if complete { connection.cancel() }
                else { self.receive(connection, buffer: buffer) }
            }
        }
    }

    static func main() async throws {
        let server = try Server()
        let port = try await server.start()
        defer { server.listener.cancel() }
        let configuration = try CompatibleServerConfiguration(address: "http://127.0.0.1:\(port)/v1")
        let transport: CompatibleServerClient.Transport = { try await CompatibleServerHTTP.session.data(for: $0) }
        let client = CompatibleServerClient(configuration: configuration, token: "test-server-token", transport: transport)
        let models = try await client.listModelIDs()
        precondition(models == ["test-rewriter"], "Discover models over real loopback HTTP")
        let text = try await client.rewrite(text: "Original text.", systemPrompt: "Keep my voice.", model: models[0])
        precondition(text == "Rewritten text.", "Generate through the real URLSession")
        print("  ✓ loopback discovery and rewrite work through the production HTTP session")

        let redirect = try CompatibleServerConfiguration(address: "http://127.0.0.1:\(port)/redirect/v1")
        do {
            _ = try await CompatibleServerClient(configuration: redirect, token: "test-server-token", transport: transport)
                .rewrite(text: "Original text.", systemPrompt: "Keep my voice.", model: models[0])
            preconditionFailure("Redirect must not be followed")
        } catch CompatibleServerError.http(let status, _) {
            precondition(status == 307, "Return the original redirect as an error")
        }
        let requests = server.requests
        precondition(requests.count == 3 && !requests.contains { $0.contains(" /leak ") }, "Never forward source text or tokens to redirect targets")
        precondition(requests.allSatisfy { $0.lowercased().contains("authorization: bearer test-server-token") }, "Use the dedicated server token")
        precondition(!requests.contains { $0.lowercased().contains("\r\ncookie:") }, "Do not send server cookies")
        print("  ✓ redirects cannot forward text or tokens; cookies stay disabled")
        print("OK")
    }
}
