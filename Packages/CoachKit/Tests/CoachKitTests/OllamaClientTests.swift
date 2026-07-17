import Foundation
import Testing
@testable import CoachKit

/// Replays fixed NDJSON/JSON bodies for known paths, mirroring the real
/// transcripts captured live in `NEXT-SESSION-M6.md`'s verified facts.
final class StubURLProtocol: URLProtocol {
    struct Response {
        let status: Int
        let body: String
    }

    nonisolated(unsafe) static var responses: [String: Response] = [:]

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        guard let url = request.url, let path = url.path.split(separator: "/").last.map(String.init),
            let stub = Self.responses[path]
        else {
            client?.urlProtocol(self, didFailWithError: URLError(.fileDoesNotExist))
            return
        }
        let response = HTTPURLResponse(url: url, statusCode: stub.status, httpVersion: "HTTP/1.1", headerFields: nil)!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: Data(stub.body.utf8))
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}
}

func stubbedClient(_ responses: [String: StubURLProtocol.Response]) -> OllamaClient {
    StubURLProtocol.responses = responses
    let config = URLSessionConfiguration.ephemeral
    config.protocolClasses = [StubURLProtocol.self]
    return OllamaClient(sessionConfiguration: config)
}

@Suite(.serialized)
struct OllamaClientTests {
    @Test func versionDecodesRealShape() async throws {
        let client = stubbedClient(["version": .init(status: 200, body: #"{"version":"0.31.2"}"#)])
        #expect(try await client.version() == "0.31.2")
    }

    @Test func tagsDecodesRealShapeWithCapabilities() async throws {
        let body = """
            {"models": [{
              "name": "qwen2.5:0.5b-instruct",
              "model": "qwen2.5:0.5b-instruct",
              "modified_at": "2026-06-19T00:00:00+08:00",
              "size": 397821543,
              "digest": "a8b0c515",
              "details": {"format": "gguf", "family": "qwen2", "parameter_size": "494.03M",
                          "quantization_level": "Q4_K_M", "context_length": 32768, "embedding_length": 896},
              "capabilities": ["completion", "tools"]
            }]}
            """
        let client = stubbedClient(["tags": .init(status: 200, body: body)])
        let models = try await client.installedModels()
        #expect(models.count == 1)
        #expect(models[0].capabilities == ["completion", "tools"])
        #expect(models[0].details?.contextLength == 32768)
    }

    @Test func psDecodesRealShape() async throws {
        let body = #"{"models":[{"name":"qwen3:0.6b","size":1000000,"size_vram":2440000000,"expires_at":"2026-07-17T13:00:00Z","context_length":16384}]}"#
        let client = stubbedClient(["ps": .init(status: 200, body: body)])
        let models = try await client.loadedModels()
        #expect(models[0].contextLength == 16384)
        #expect(models[0].sizeVram == 2_440_000_000)
    }

    @Test func chatStreamAssemblesContentDeltas() async throws {
        let lines = [
            #"{"model":"qwen2.5:0.5b-instruct","created_at":"t","message":{"role":"assistant","content":"Hello"},"done":false}"#,
            #"{"model":"qwen2.5:0.5b-instruct","created_at":"t","message":{"role":"assistant","content":" Coach"},"done":false}"#,
            #"{"model":"qwen2.5:0.5b-instruct","created_at":"t","message":{"role":"assistant","content":""},"done":true,"done_reason":"stop","total_duration":331611625,"load_duration":154108625,"prompt_eval_count":33,"prompt_eval_duration":70693000,"eval_count":11,"eval_duration":105509000}"#,
        ]
        let client = stubbedClient(["chat": .init(status: 200, body: lines.joined(separator: "\n"))])
        var assembled = ""
        var sawDone = false
        for try await chunk in client.chat(model: "qwen2.5:0.5b-instruct", messages: [.init(role: "user", content: "hi")]) {
            assembled += chunk.message?.content ?? ""
            if chunk.done {
                sawDone = true
                #expect(chunk.doneReason == "stop")
                #expect(chunk.evalCount == 11)
            }
        }
        #expect(assembled == "Hello Coach")
        #expect(sawDone)
    }

    @Test func chatStreamSeparatesThinkingFromContent() async throws {
        let lines = [
            #"{"model":"qwen3:0.6b","created_at":"t","message":{"role":"assistant","content":"","thinking":"Okay"},"done":false}"#,
            #"{"model":"qwen3:0.6b","created_at":"t","message":{"role":"assistant","content":"e4 is fine"},"done":false}"#,
            #"{"model":"qwen3:0.6b","created_at":"t","message":{"role":"assistant","content":""},"done":true,"done_reason":"stop"}"#,
        ]
        let client = stubbedClient(["chat": .init(status: 200, body: lines.joined(separator: "\n"))])
        var thinking = ""
        var content = ""
        for try await chunk in client.chat(model: "qwen3:0.6b", messages: [.init(role: "user", content: "hi")]) {
            thinking += chunk.message?.thinking ?? ""
            content += chunk.message?.content ?? ""
        }
        #expect(thinking == "Okay")
        #expect(content == "e4 is fine")
    }

    @Test func chatStreamDecodesWholeToolCallChunk() async throws {
        let lines = [
            #"{"message": {"role": "assistant", "content": "", "tool_calls": [{"id": "call_lex8r2fo", "function": {"index": 0, "name": "evaluate", "arguments": {"fen": "rnbqkbnr/pppppppp/8/8/4P3/8/PPPP1PPP/RNBQKBNR b KQkq - 0 1"}}}]}, "model": "qwen3:0.6b", "done": false}"#,
            #"{"model":"qwen3:0.6b","message":{"role":"assistant","content":""},"done":true,"done_reason":"stop"}"#,
        ]
        let body = lines.joined(separator: "\n")
        let client = stubbedClient(["chat": .init(status: 200, body: body)])
        var sawCall = false
        for try await chunk in client.chat(model: "qwen3:0.6b", messages: [.init(role: "user", content: "go")]) {
            if let calls = chunk.message?.toolCalls, !calls.isEmpty {
                sawCall = true
                #expect(calls[0].function.name == "evaluate")
                #expect(calls[0].function.arguments["fen"]?.stringValue?.hasPrefix("rnbqkbnr") == true)
                #expect(chunk.doneReason == nil || chunk.doneReason == "stop")
            }
        }
        #expect(sawCall)
    }

    @Test func pullStreamsProgressThenSuccess() async throws {
        let lines = [
            #"{"status":"pulling manifest"}"#,
            #"{"status":"pulling 7f4030143c1c","digest":"sha256:7f40","total":522640096,"completed":16368992}"#,
            #"{"status":"verifying sha256 digest"}"#,
            #"{"status":"writing manifest"}"#,
            #"{"status":"success"}"#,
        ]
        let client = stubbedClient(["pull": .init(status: 200, body: lines.joined(separator: "\n"))])
        var statuses: [String] = []
        for try await event in client.pull(model: "qwen3:0.6b") {
            statuses.append(event.status ?? "")
        }
        #expect(statuses.last == "success")
    }

    @Test func pullMidStreamErrorLineIsTerminal() async throws {
        let lines = [
            #"{"status":"pulling manifest"}"#,
            #"{"error":"503: "}"#,
        ]
        let client = stubbedClient(["pull": .init(status: 200, body: lines.joined(separator: "\n"))])
        await #expect(throws: OllamaClientError.self) {
            for try await _ in client.pull(model: "qwen3:0.6b") {}
        }
    }

    @Test func chatAgainstMissingModelSurfaces404() async throws {
        let client = stubbedClient(["chat": .init(status: 404, body: #"{"error":"model 'nonexistent-model:1b' not found"}"#)])
        await #expect(throws: OllamaClientError.self) {
            for try await _ in client.chat(model: "nonexistent-model:1b", messages: [.init(role: "user", content: "hi")]) {}
        }
    }

    @Test func liveRoundTripWithRealQwen3IfRequested() async throws {
        guard ProcessInfo.processInfo.environment["LIVE"] == "1" else { return }
        let client = OllamaClient()
        var text = ""
        for try await chunk in client.chat(model: "qwen3:0.6b", messages: [.init(role: "user", content: "Say hello in one word.")]) {
            text += chunk.message?.content ?? ""
        }
        #expect(!text.isEmpty)
    }
}
