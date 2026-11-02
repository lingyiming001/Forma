import Foundation
import Security

/// AI 模型服务商预设。统一走 OpenAI 兼容的 `/chat/completions` 接口。
public enum AIProvider: String, Codable, CaseIterable, Sendable {
    case openAI, anthropic, ollama, custom
    public var title: String {
        switch self {
        case .openAI: "OpenAI 兼容"
        case .anthropic: "Anthropic"
        case .ollama: "Ollama（本地）"
        case .custom: "自定义"
        }
    }
    public var defaultBaseURL: String {
        switch self {
        case .openAI: "https://api.openai.com/v1"
        case .anthropic: "https://api.anthropic.com/v1"
        case .ollama: "http://localhost:11434/v1"
        case .custom: ""
        }
    }
    public var defaultModel: String {
        switch self {
        case .openAI: "gpt-4o-mini"
        case .anthropic: "claude-3-5-sonnet-latest"
        case .ollama: "llama3.1"
        case .custom: ""
        }
    }
}

/// 大模型连接配置（不含密钥，密钥单独存放于钥匙串）。
public struct AIModelConfig: Codable, Equatable, Sendable {
    public var provider: AIProvider
    public var baseURL: String
    public var model: String
    public var temperature: Double
    public var systemPrompt: String
    public init(
        provider: AIProvider = .openAI, baseURL: String = AIProvider.openAI.defaultBaseURL,
        model: String = AIProvider.openAI.defaultModel, temperature: Double = 0.7,
        systemPrompt: String = "你是 Forma 的图表助手，帮助用户梳理与表达想法。"
    ) {
        self.provider = provider
        self.baseURL = baseURL
        self.model = model
        self.temperature = temperature
        self.systemPrompt = systemPrompt
    }
    public static let `default` = AIModelConfig()
    public var isReady: Bool {
        !baseURL.trimmingCharacters(in: .whitespaces).isEmpty && !model.trimmingCharacters(in: .whitespaces).isEmpty
    }
}

public enum MCPTransport: String, Codable, CaseIterable, Sendable {
    case stdio, http
    public var title: String { self == .stdio ? "标准输入输出 (stdio)" : "HTTP / SSE" }
}

/// 一条 MCP 服务器配置。当前仅做本地保存与展示，实际连接由后续版本实现。
public struct MCPServer: Identifiable, Codable, Equatable, Sendable {
    public var id: UUID
    public var name: String
    public var transport: MCPTransport
    public var command: String
    public var arguments: String
    public var url: String
    public var enabled: Bool
    public init(
        id: UUID = UUID(), name: String = "", transport: MCPTransport = .stdio, command: String = "",
        arguments: String = "", url: String = "", enabled: Bool = true
    ) {
        self.id = id
        self.name = name
        self.transport = transport
        self.command = command
        self.arguments = arguments
        self.url = url
        self.enabled = enabled
    }
}

public enum ChatRole: String, Codable, Sendable { case system, user, assistant }

public struct ChatMessage: Identifiable, Codable, Equatable, Sendable {
    public var id: UUID
    public var role: ChatRole
    public var text: String
    public init(id: UUID = UUID(), role: ChatRole, text: String) {
        self.id = id
        self.role = role
        self.text = text
    }
}

public enum AIChatError: LocalizedError, Equatable {
    case notConfigured, badURL, badResponse, server(String), transport(String)
    public var errorDescription: String? {
        switch self {
        case .notConfigured: "尚未配置模型服务，请在设置中填写接口地址与模型名称。"
        case .badURL: "接口地址无效，请检查设置中的 Base URL。"
        case .badResponse: "服务返回了无法解析的内容。"
        case .server(let message): message
        case .transport(let message): message
        }
    }
}

/// 轻量聊天客户端：请求体构造与响应解析为纯函数，便于离线单元测试；`send` 走真实网络。
public struct AIChatClient {
    private let session: URLSession
    public init(session: URLSession = .shared) { self.session = session }

    public static func normalizedBase(_ raw: String) -> String {
        var base = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        while base.hasSuffix("/") { base.removeLast() }
        return base
    }

    public static func requestBody(config: AIModelConfig, history: [ChatMessage]) -> Data {
        var messages: [[String: String]] = []
        if !config.systemPrompt.trimmingCharacters(in: .whitespaces).isEmpty {
            messages.append(["role": ChatRole.system.rawValue, "content": config.systemPrompt])
        }
        messages.append(contentsOf: history.map { ["role": $0.role.rawValue, "content": $0.text] })
        let body: [String: Any] = [
            "model": config.model, "messages": messages,
            "temperature": max(0, min(2, config.temperature)),
        ]
        return (try? JSONSerialization.data(withJSONObject: body)) ?? Data("{}".utf8)
    }

    public static func parseResponse(_ data: Data) throws -> String {
        guard let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw AIChatError.badResponse
        }
        if let error = obj["error"] as? [String: Any], let message = error["message"] as? String {
            throw AIChatError.server(message)
        }
        guard let choices = obj["choices"] as? [[String: Any]], let first = choices.first,
            let message = first["message"] as? [String: Any], let content = message["content"] as? String
        else { throw AIChatError.badResponse }
        return content
    }

    public func send(config: AIModelConfig, apiKey: String, history: [ChatMessage]) async throws -> String {
        guard config.isReady else { throw AIChatError.notConfigured }
        let endpoint = Self.normalizedBase(config.baseURL) + "/chat/completions"
        guard let url = URL(string: endpoint) else { throw AIChatError.badURL }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.timeoutInterval = 60
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        if !apiKey.isEmpty { request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization") }
        request.httpBody = Self.requestBody(config: config, history: history)
        do {
            let (data, response) = try await session.data(for: request)
            guard let http = response as? HTTPURLResponse else { throw AIChatError.badResponse }
            guard (200..<300).contains(http.statusCode) else {
                let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
                let message = (obj?["error"] as? [String: Any])?["message"] as? String ?? "HTTP \(http.statusCode)"
                throw AIChatError.server(message)
            }
            return try Self.parseResponse(data)
        } catch let error as AIChatError {
            throw error
        } catch {
            throw AIChatError.transport(error.localizedDescription)
        }
    }
}

/// 用 macOS 钥匙串保存 AI 接口密钥，避免写入 UserDefaults。
public enum AIKeychain {
    private static let service = "com.forma.ai"
    private static let account = "apiKey"
    private static var baseQuery: [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
    }
    public static func set(_ value: String) {
        SecItemDelete(baseQuery as CFDictionary)
        guard !value.isEmpty else { return }
        var add = baseQuery
        add[kSecValueData as String] = Data(value.utf8)
        SecItemAdd(add as CFDictionary, nil)
    }
    public static func get() -> String {
        var query = baseQuery
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        var result: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess,
            let data = result as? Data, let string = String(data: data, encoding: .utf8)
        else { return "" }
        return string
    }
}
