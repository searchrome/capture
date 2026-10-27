import Foundation

enum JSONValue: Codable, Equatable {
    case null, bool(Bool), number(Double), string(String), array([JSONValue]), object([String: JSONValue])

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if container.decodeNil() { self = .null }
        else if let value = try? container.decode(Bool.self) { self = .bool(value) }
        else if let value = try? container.decode(Double.self) { self = .number(value) }
        else if let value = try? container.decode(String.self) { self = .string(value) }
        else if let value = try? container.decode([JSONValue].self) { self = .array(value) }
        else { self = .object(try container.decode([String: JSONValue].self)) }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case .null: try container.encodeNil()
        case .bool(let value): try container.encode(value)
        case .number(let value): try container.encode(value)
        case .string(let value): try container.encode(value)
        case .array(let value): try container.encode(value)
        case .object(let value): try container.encode(value)
        }
    }
}

struct ChatRequest: Codable {
    var model: String
    var messages: [ChatMessage]
    var stream: Bool = true
    var temperature: Double? = nil
    var tools: [ChatTool]? = nil
    var reasoning: [String: JSONValue]? = nil
}

struct ChatMessage: Codable {
    enum Role: String, Codable { case system, user, assistant, tool }
    var role: Role
    var content: ChatContent?
    var toolCalls: [ChatToolCall]? = nil
    var toolCallID: String? = nil

    enum CodingKeys: String, CodingKey {
        case role, content
        case toolCalls = "tool_calls", toolCallID = "tool_call_id"
    }
}

enum ChatContent: Codable {
    case text(String)
    case parts([ChatContentPart])

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if let text = try? container.decode(String.self) { self = .text(text) }
        else { self = .parts(try container.decode([ChatContentPart].self)) }
    }
    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case .text(let text): try container.encode(text)
        case .parts(let parts): try container.encode(parts)
        }
    }
}

struct ChatContentPart: Codable {
    struct ImageURL: Codable { var url: String }
    var type: String
    var text: String? = nil
    var imageURL: ImageURL? = nil
    enum CodingKeys: String, CodingKey { case type, text; case imageURL = "image_url" }

    static func text(_ text: String) -> Self { Self(type: "text", text: text) }
    static func imageURL(_ url: String) -> Self { Self(type: "image_url", imageURL: ImageURL(url: url)) }
}

struct ChatToolCall: Codable {
    struct Function: Codable { var name: String; var arguments: String }
    var id: String
    var type: String = "function"
    var function: Function
}

struct ChatTool: Codable {
    struct Function: Codable {
        var name: String
        var description: String
        var parameters: [String: JSONValue]
    }
    var type: String = "function"
    var function: Function
}

struct ToolCallDelta: Equatable {
    var index: Int
    var id: String = ""
    var name: String = ""
    var arguments: String = ""
}

struct ChatUsage: Codable {
    var promptTokens: Int?
    var completionTokens: Int?
    var totalTokens: Int?
    enum CodingKeys: String, CodingKey {
        case promptTokens = "prompt_tokens", completionTokens = "completion_tokens", totalTokens = "total_tokens"
    }
}

enum StreamEvent {
    case text(String)
    // Each update is the accumulated state for this index.
    case toolCall(ToolCallDelta)
    case finishReason(String)
    case usage(ChatUsage)
}
