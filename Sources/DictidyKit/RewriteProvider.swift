import Foundation

/// The selected model determines which connection receives the source text.
public enum RewriteProvider: String, Codable, CaseIterable, Sendable {
    case anthropic
    case openai
    case chatgpt
    case compatible

    public static let apiKeyProviders: [Self] = [.anthropic, .openai]

    public var displayName: String {
        switch self {
        case .anthropic: return "Anthropic"
        case .openai: return "OpenAI"
        case .chatgpt: return "ChatGPT plan"
        case .compatible: return "Local / custom server"
        }
    }

    public var apiHost: String {
        switch self {
        case .anthropic: return "api.anthropic.com"
        case .openai, .chatgpt: return "api.openai.com"
        case .compatible: return "your configured server"
        }
    }

    public var keyURL: URL? {
        switch self {
        case .anthropic: return URL(string: "https://console.anthropic.com/settings/keys")!
        case .openai: return URL(string: "https://platform.openai.com/api-keys")!
        case .chatgpt, .compatible: return nil
        }
    }
}
