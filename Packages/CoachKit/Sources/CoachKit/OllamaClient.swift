import Foundation

/// Errors surfaced by `OllamaClient`. `notReachable` covers `URLError`
/// connection-refused (fact 1's whole install/running detection story);
/// everything else is a real HTTP/stream failure.
public enum OllamaClientError: Error, Sendable, Equatable {
    case notReachable
    case http(status: Int, body: String)
    case streamError(String)
    case decoding(String)
}

/// Native `/api/*` client for a local Ollama server. Never uses the
/// OpenAI-compat layer - the native API is the only one carrying
/// `thinking`, `capabilities`, `options.num_ctx`, and `keep_alive`, all of
/// which the coach depends on (see `NEXT-SESSION-M6.md`'s OllamaClient
/// decisions).
public final class OllamaClient: Sendable {
    public static let defaultBaseURL = URL(string: "http://127.0.0.1:11434")!

    private let baseURL: URL
    private let session: URLSession

    public init(baseURL: URL = OllamaClient.defaultBaseURL, sessionConfiguration: URLSessionConfiguration? = nil) {
        self.baseURL = baseURL
        let config = sessionConfiguration ?? URLSessionConfiguration.default
        // First-token latency includes model load, which can exceed 60s for
        // large models on modest hardware (fact 7's load_duration is real).
        config.timeoutIntervalForRequest = 300
        self.session = URLSession(configuration: config)
    }

    public func version() async throws -> String {
        let (data, response) = try await request(path: "api/version")
        try Self.checkHTTP(response, data: data)
        return try JSONDecoder().decode(OllamaVersionResponse.self, from: data).version
    }

    public func installedModels() async throws -> [OllamaTagsModel] {
        let (data, response) = try await request(path: "api/tags")
        try Self.checkHTTP(response, data: data)
        return try JSONDecoder().decode(OllamaTagsResponse.self, from: data).models
    }

    public func loadedModels() async throws -> [OllamaPsModel] {
        let (data, response) = try await request(path: "api/ps")
        try Self.checkHTTP(response, data: data)
        return try JSONDecoder().decode(OllamaPsResponse.self, from: data).models
    }

    public func capabilities(of model: String) async throws -> [String] {
        var urlRequest = URLRequest(url: baseURL.appendingPathComponent("api/show"))
        urlRequest.httpMethod = "POST"
        urlRequest.setValue("application/json", forHTTPHeaderField: "Content-Type")
        urlRequest.httpBody = try JSONEncoder().encode(["model": model])
        let (data, response) = try await perform(urlRequest)
        try Self.checkHTTP(response, data: data)
        return try JSONDecoder().decode(OllamaShowResponse.self, from: data).capabilities ?? []
    }

    /// Streams one chat completion as NDJSON lines (fact 7). Every chat
    /// request sends `think:false` (narration explains a fixed payload
    /// rather than reasoning openly - latency wins, fact 8) and an explicit
    /// `num_ctx` (fact 4's 4096-default-context trap).
    public func chat(
        model: String,
        messages: [OllamaChatMessage],
        tools: [OllamaTool]? = nil,
        numCtx: Int = 8192,
        temperature: Double = 0.2
    ) -> AsyncThrowingStream<OllamaChatChunk, Error> {
        let body = OllamaChatRequest(
            model: model,
            messages: messages,
            stream: true,
            think: false,
            options: OllamaChatOptions(numCtx: numCtx, temperature: temperature),
            tools: tools
        )
        return AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    var urlRequest = URLRequest(url: self.baseURL.appendingPathComponent("api/chat"))
                    urlRequest.httpMethod = "POST"
                    urlRequest.setValue("application/json", forHTTPHeaderField: "Content-Type")
                    urlRequest.httpBody = try JSONEncoder().encode(body)
                    try await self.streamNDJSON(urlRequest) { lineData in
                        if let errorLine = try? JSONDecoder().decode(OllamaErrorLine.self, from: lineData) {
                            throw OllamaClientError.streamError(errorLine.error)
                        }
                        let chunk = try JSONDecoder().decode(OllamaChatChunk.self, from: lineData)
                        continuation.yield(chunk)
                        if chunk.done {
                            continuation.finish()
                        }
                    }
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    /// Streams pull progress (fact 5): per-line `error` keys are the only
    /// failure signal, HTTP status stays 200 throughout.
    public func pull(model: String) -> AsyncThrowingStream<OllamaPullEvent, Error> {
        AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    var urlRequest = URLRequest(url: self.baseURL.appendingPathComponent("api/pull"))
                    urlRequest.httpMethod = "POST"
                    urlRequest.setValue("application/json", forHTTPHeaderField: "Content-Type")
                    urlRequest.httpBody = try JSONEncoder().encode(["model": model])
                    try await self.streamNDJSON(urlRequest) { lineData in
                        let event = try JSONDecoder().decode(OllamaPullEvent.self, from: lineData)
                        if let error = event.error {
                            throw OllamaClientError.streamError(error)
                        }
                        continuation.yield(event)
                        if event.status == "success" {
                            continuation.finish()
                        }
                    }
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    // MARK: - Internals

    private func request(path: String) async throws -> (Data, URLResponse) {
        try await perform(URLRequest(url: baseURL.appendingPathComponent(path)))
    }

    private func perform(_ urlRequest: URLRequest) async throws -> (Data, URLResponse) {
        do {
            return try await session.data(for: urlRequest)
        } catch let error as URLError where error.code == .cannotConnectToHost || error.code == .networkConnectionLost {
            throw OllamaClientError.notReachable
        }
    }

    /// Line-buffered NDJSON decode over `URLSession.bytes(for:)`, one decode
    /// callback per non-empty line.
    private func streamNDJSON(_ urlRequest: URLRequest, onLine: (Data) throws -> Void) async throws {
        let (bytes, response): (URLSession.AsyncBytes, URLResponse)
        do {
            (bytes, response) = try await session.bytes(for: urlRequest)
        } catch let error as URLError where error.code == .cannotConnectToHost || error.code == .networkConnectionLost {
            throw OllamaClientError.notReachable
        }
        guard let http = response as? HTTPURLResponse else {
            throw OllamaClientError.decoding("no HTTP response")
        }
        guard http.statusCode == 200 else {
            var body = ""
            for try await line in bytes.lines { body += line }
            throw OllamaClientError.http(status: http.statusCode, body: body)
        }
        for try await line in bytes.lines {
            guard !line.isEmpty else { continue }
            try onLine(Data(line.utf8))
        }
    }

    private static func checkHTTP(_ response: URLResponse, data: Data) throws {
        guard let http = response as? HTTPURLResponse else { return }
        guard http.statusCode == 200 else {
            throw OllamaClientError.http(status: http.statusCode, body: String(data: data, encoding: .utf8) ?? "")
        }
    }
}
