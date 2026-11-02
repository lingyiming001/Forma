import Foundation
import FormaApplication
import Testing

struct AITests {
    @Test func modelConfigRoundTripsAndReportsReadiness() throws {
        var config = AIModelConfig.default
        config.provider = .ollama
        config.baseURL = "http://localhost:11434/v1/"
        config.model = "llama3.1"
        config.temperature = 0.3
        let data = try JSONEncoder().encode(config)
        let decoded = try JSONDecoder().decode(AIModelConfig.self, from: data)
        #expect(decoded == config)
        #expect(decoded.isReady)
        #expect(AIModelConfig(baseURL: "https://x", model: "  ").isReady == false)
        #expect(AIChatClient.normalizedBase("https://api.openai.com/v1///") == "https://api.openai.com/v1")
    }
    @Test func requestBodyIncludesSystemPromptAndClampsTemperature() throws {
        var config = AIModelConfig.default
        config.temperature = 5  // 越界应被夹到 2
        let body = AIChatClient.requestBody(
            config: config, history: [ChatMessage(role: .user, text: "你好"), ChatMessage(role: .assistant, text: "hi")])
        let obj = try #require(try JSONSerialization.jsonObject(with: body) as? [String: Any])
        #expect(obj["model"] as? String == config.model)
        #expect(obj["temperature"] as? Double == 2.0)
        let messages = try #require(obj["messages"] as? [[String: String]])
        #expect(messages.count == 3)  // system + user + assistant
        #expect(messages.first?["role"] == "system")
        #expect(messages.last?["content"] == "hi")
    }
    @Test func parseResponseExtractsContentOrThrows() throws {
        let ok = Data(
            #"{"choices":[{"message":{"role":"assistant","content":"结果"}}]}"#.utf8)
        #expect(try AIChatClient.parseResponse(ok) == "结果")
        let err = Data(#"{"error":{"message":"invalid api key"}}"#.utf8)
        #expect(throws: AIChatError.server("invalid api key")) { try AIChatClient.parseResponse(err) }
        let bad = Data("not json".utf8)
        #expect(throws: AIChatError.badResponse) { try AIChatClient.parseResponse(bad) }
    }
    @Test func mcpServersRoundTrip() throws {
        let servers = [
            MCPServer(name: "fs", transport: .stdio, command: "npx", arguments: "-y server"),
            MCPServer(name: "web", transport: .http, url: "http://localhost:3000/sse", enabled: false),
        ]
        let data = try JSONEncoder().encode(servers)
        #expect(try JSONDecoder().decode([MCPServer].self, from: data) == servers)
    }
}
