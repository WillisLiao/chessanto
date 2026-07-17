import Foundation

/// Request/response Codable types for Ollama's native `/api/*` endpoints
/// (never the OpenAI-compat layer - see `NEXT-SESSION-M6.md`'s verified
/// facts 1-9, 12 for the exact JSON shapes these mirror). Every type uses
/// explicit `CodingKeys` rather than a decoder-wide snake_case strategy, so
/// mixing this file with `keyDecodingStrategy` elsewhere is safe.

/// A minimal JSON value used for tool-call arguments, which arrive as an
/// arbitrary JSON object (fact 9) that may be malformed by small models
/// (fact 10) - callers validate/extract fields defensively rather than
/// trusting a fixed schema at decode time.
public enum JSONValue: Codable, Sendable, Equatable {
    case string(String)
    case number(Double)
    case bool(Bool)
    case array([JSONValue])
    case object([String: JSONValue])
    case null

    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if container.decodeNil() {
            self = .null
        } else if let value = try? container.decode(Bool.self) {
            self = .bool(value)
        } else if let value = try? container.decode(Double.self) {
            self = .number(value)
        } else if let value = try? container.decode(String.self) {
            self = .string(value)
        } else if let value = try? container.decode([JSONValue].self) {
            self = .array(value)
        } else if let value = try? container.decode([String: JSONValue].self) {
            self = .object(value)
        } else {
            throw DecodingError.dataCorruptedError(in: container, debugDescription: "Unsupported JSON value")
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case .string(let value): try container.encode(value)
        case .number(let value): try container.encode(value)
        case .bool(let value): try container.encode(value)
        case .array(let value): try container.encode(value)
        case .object(let value): try container.encode(value)
        case .null: try container.encodeNil()
        }
    }

    public var stringValue: String? {
        if case .string(let value) = self { return value }
        return nil
    }

    public var arrayValue: [JSONValue]? {
        if case .array(let value) = self { return value }
        return nil
    }
}

// MARK: - /api/version

public struct OllamaVersionResponse: Decodable, Sendable {
    public let version: String
}

// MARK: - /api/tags

public struct OllamaModelDetails: Decodable, Sendable, Equatable {
    public let format: String?
    public let family: String?
    public let parameterSize: String?
    public let quantizationLevel: String?
    public let contextLength: Int?
    public let embeddingLength: Int?

    enum CodingKeys: String, CodingKey {
        case format, family
        case parameterSize = "parameter_size"
        case quantizationLevel = "quantization_level"
        case contextLength = "context_length"
        case embeddingLength = "embedding_length"
    }
}

public struct OllamaTagsModel: Decodable, Sendable, Equatable {
    public let name: String
    public let model: String
    public let modifiedAt: String?
    public let size: Int?
    public let digest: String?
    public let details: OllamaModelDetails?
    public let capabilities: [String]?

    enum CodingKeys: String, CodingKey {
        case name, model, size, digest, details, capabilities
        case modifiedAt = "modified_at"
    }
}

public struct OllamaTagsResponse: Decodable, Sendable {
    public let models: [OllamaTagsModel]
}

// MARK: - /api/ps

public struct OllamaPsModel: Decodable, Sendable, Equatable {
    public let name: String
    public let size: Int?
    public let sizeVram: Int?
    public let expiresAt: String?
    public let contextLength: Int?

    enum CodingKeys: String, CodingKey {
        case name, size
        case sizeVram = "size_vram"
        case expiresAt = "expires_at"
        case contextLength = "context_length"
    }
}

public struct OllamaPsResponse: Decodable, Sendable {
    public let models: [OllamaPsModel]
}

// MARK: - /api/show

public struct OllamaShowResponse: Decodable, Sendable {
    public let capabilities: [String]?
    public let details: OllamaModelDetails?
}

// MARK: - /api/pull

public struct OllamaPullEvent: Decodable, Sendable, Equatable {
    public let status: String?
    public let digest: String?
    public let total: Int?
    public let completed: Int?
    public let error: String?
}

// MARK: - /api/chat

public struct OllamaToolCall: Codable, Sendable, Equatable {
    public struct Function: Codable, Sendable, Equatable {
        public let index: Int?
        public let name: String
        public let arguments: [String: JSONValue]

        public init(index: Int? = nil, name: String, arguments: [String: JSONValue]) {
            self.index = index
            self.name = name
            self.arguments = arguments
        }
    }

    public let id: String?
    public let function: Function

    public init(id: String? = nil, function: Function) {
        self.id = id
        self.function = function
    }
}

public struct OllamaChatMessage: Codable, Sendable, Equatable {
    public let role: String
    public let content: String
    public let thinking: String?
    public let toolCalls: [OllamaToolCall]?
    public let toolName: String?

    enum CodingKeys: String, CodingKey {
        case role, content, thinking
        case toolCalls = "tool_calls"
        case toolName = "tool_name"
    }

    public init(role: String, content: String, thinking: String? = nil, toolCalls: [OllamaToolCall]? = nil, toolName: String? = nil) {
        self.role = role
        self.content = content
        self.thinking = thinking
        self.toolCalls = toolCalls
        self.toolName = toolName
    }
}

public struct OllamaChatOptions: Encodable, Sendable {
    public let numCtx: Int
    public let temperature: Double

    enum CodingKeys: String, CodingKey {
        case numCtx = "num_ctx"
        case temperature
    }

    public init(numCtx: Int, temperature: Double) {
        self.numCtx = numCtx
        self.temperature = temperature
    }
}

public struct OllamaTool: Encodable, Sendable {
    public struct FunctionSpec: Encodable, Sendable {
        public let name: String
        public let description: String
        public let parameters: JSONValue

        public init(name: String, description: String, parameters: JSONValue) {
            self.name = name
            self.description = description
            self.parameters = parameters
        }
    }

    public let type = "function"
    public let function: FunctionSpec

    public init(function: FunctionSpec) {
        self.function = function
    }
}

public struct OllamaChatRequest: Encodable, Sendable {
    public let model: String
    public let messages: [OllamaChatMessage]
    public let stream: Bool
    public let think: Bool
    public let options: OllamaChatOptions
    public let tools: [OllamaTool]?

    public init(model: String, messages: [OllamaChatMessage], stream: Bool, think: Bool, options: OllamaChatOptions, tools: [OllamaTool]?) {
        self.model = model
        self.messages = messages
        self.stream = stream
        self.think = think
        self.options = options
        self.tools = tools
    }
}

public struct OllamaChatChunk: Decodable, Sendable {
    public let model: String
    public let message: OllamaChatMessage?
    public let done: Bool
    public let doneReason: String?
    public let totalDuration: Int?
    public let loadDuration: Int?
    public let promptEvalCount: Int?
    public let evalCount: Int?

    enum CodingKeys: String, CodingKey {
        case model, message, done
        case doneReason = "done_reason"
        case totalDuration = "total_duration"
        case loadDuration = "load_duration"
        case promptEvalCount = "prompt_eval_count"
        case evalCount = "eval_count"
    }
}

/// Any NDJSON line with an `error` key (fact 5's mid-stream pull errors,
/// fact 12's chat error shapes) is terminal for that request.
public struct OllamaErrorLine: Decodable, Sendable {
    public let error: String
}
