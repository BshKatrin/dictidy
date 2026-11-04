import Foundation

/// A new identity on address changes prevents saved model choices from targeting another server.
public struct CompatibleServerConfiguration: Codable, Equatable, Sendable, Identifiable {
    public let id: UUID
    public let baseURL: URL

    public init(address: String, id: UUID = UUID()) throws {
        let address = address.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !address.contains(where: { $0.isWhitespace }),
              var parts = URLComponents(string: address),
              let scheme = parts.scheme?.lowercased(), ["http", "https"].contains(scheme),
              let host = parts.host, !host.isEmpty,
              parts.user == nil, parts.password == nil, parts.query == nil, parts.fragment == nil,
              parts.port.map({ (1...65535).contains($0) }) ?? true else {
            throw CompatibleServerError.invalidAddress
        }
        parts.scheme = scheme
        parts.host = host.lowercased()
        while parts.path.hasSuffix("/") { parts.path.removeLast() }
        if parts.path.isEmpty { parts.path = "/v1" }
        guard let url = parts.url else { throw CompatibleServerError.invalidAddress }
        self.id = id
        baseURL = url
    }

    public init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        try self.init(address: values.decode(String.self, forKey: .baseURL),
                      id: values.decode(UUID.self, forKey: .id))
    }
}
