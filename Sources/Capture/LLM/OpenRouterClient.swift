import Foundation

enum OpenRouterError: LocalizedError {
    case missingAPIKey
    case httpStatus(Int, String?)
    case network(Error)
    case stream(String)
    case invalidResponse

    var errorDescription: String? {
        switch self {
        case .missingAPIKey: return "Add your OpenRouter API key in Settings."
        case .httpStatus(let status, let message): return "OpenRouter HTTP \(status)\(message.map { ": \($0)" } ?? "")"
        case .network(let error): return "Network failure: \(error.localizedDescription)"
        case .stream(let message): return "OpenRouter stream error: \(message)"
        case .invalidResponse: return "OpenRouter returned an invalid response."
        }
    }
}

final class OpenRouterClient {
    static let baseURL = URL(string: "https://openrouter.ai/api/v1")!
    private let session: URLSession
    private let readAPIKey: () throws -> String?
    init(session: URLSession = .shared, readAPIKey: @escaping () throws -> String? = Keychain.read) {
        self.session = session
        self.readAPIKey = readAPIKey
    }

    func stream(_ request: ChatRequest) -> AsyncThrowingStream<StreamEvent, Error> {
        AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    var request = request
                    var retried = false
                    while true {
                        var urlRequest = try await authorizedRequest(path: "chat/completions", method: "POST")
                        urlRequest.setValue("application/json", forHTTPHeaderField: "Content-Type")
                        urlRequest.httpBody = try JSONEncoder().encode(request)
                        let (bytes, response) = try await session.bytes(for: urlRequest)
                        guard let response = response as? HTTPURLResponse else { throw OpenRouterError.invalidResponse }
                        if response.statusCode == 400 && request.reasoning != nil && !retried {
                            request.reasoning = nil
                            retried = true
                            continue
                        }
                        guard (200..<300).contains(response.statusCode) else {
                            var body = Data()
                            for try await byte in bytes { body.append(byte) }
                            throw OpenRouterError.httpStatus(response.statusCode, Self.errorMessage(body))
                        }
                        var toolCalls: [Int: ToolCallDelta] = [:]
                        for try await line in bytes.lines {
                            try Task.checkCancellation()
                            guard line.hasPrefix("data:") else { continue }
                            let payload = line.dropFirst(5).trimmingCharacters(in: .whitespaces)
                            if payload == "[DONE]" { break }
                            if payload.isEmpty { continue }
                            let data = Data(payload.utf8)
                            let chunk: Chunk
                            do { chunk = try JSONDecoder().decode(Chunk.self, from: data) }
                            catch { throw OpenRouterError.stream("Invalid response data: \(error.localizedDescription)") }
                            if let error = chunk.error { throw OpenRouterError.stream(error.message) }
                            for choice in chunk.choices ?? [] {
                                if let text = choice.delta?.content, !text.isEmpty { continuation.yield(.text(text)) }
                                for fragment in choice.delta?.toolCalls ?? [] {
                                    var call = toolCalls[fragment.index] ?? ToolCallDelta(index: fragment.index)
                                    if let id = fragment.id { call.id += id }
                                    if let name = fragment.function?.name { call.name += name }
                                    if let arguments = fragment.function?.arguments { call.arguments += arguments }
                                    toolCalls[fragment.index] = call
                                    continuation.yield(.toolCall(call))
                                }
                                if let reason = choice.finishReason { continuation.yield(.finishReason(reason)) }
                            }
                            if let usage = chunk.usage { continuation.yield(.usage(usage)) }
                        }
                        continuation.finish()
                        return
                    }
                } catch is CancellationError {
                    continuation.finish(throwing: CancellationError())
                } catch let error as OpenRouterError {
                    continuation.finish(throwing: error)
                } catch let error as Keychain.KeychainError {
                    continuation.finish(throwing: error)
                } catch {
                    continuation.finish(throwing: OpenRouterError.network(error))
                }
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    func testKey() async throws -> String {
        do {
            let request = try await authorizedRequest(path: "key", method: "GET")
            let (data, response) = try await session.data(for: request)
            guard let response = response as? HTTPURLResponse else { throw OpenRouterError.invalidResponse }
            guard (200..<300).contains(response.statusCode) else {
                throw OpenRouterError.httpStatus(response.statusCode, Self.errorMessage(data))
            }
            let result = try JSONDecoder().decode(KeyResponse.self, from: data)
            let label = result.data.label ?? "Key"
            let usage = result.data.usage.map { String(format: "$%.2f", $0) } ?? "usage unavailable"
            return "OK — \(label) / \(usage)"
        } catch let error as OpenRouterError { throw error }
        catch let error as Keychain.KeychainError { throw error }
        catch { throw OpenRouterError.network(error) }
    }

    private func authorizedRequest(path: String, method: String) async throws -> URLRequest {
        guard let key = try readAPIKey(), !key.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            await MainActor.run { AppSettings.shared.apiKeyRequired = true }
            throw OpenRouterError.missingAPIKey
        }
        var request = URLRequest(url: Self.baseURL.appendingPathComponent(path))
        request.httpMethod = method
        request.setValue("Bearer \(key)", forHTTPHeaderField: "Authorization")
        request.setValue("Capture", forHTTPHeaderField: "X-Title")
        return request
    }

    private static func errorMessage(_ data: Data) -> String? {
        (try? JSONDecoder().decode(ErrorEnvelope.self, from: data))?.error.message
    }
    private struct ErrorEnvelope: Decodable { struct Detail: Decodable { let message: String }; let error: Detail }
    private struct KeyResponse: Decodable {
        struct Details: Decodable { let label: String?; let usage: Double? }
        let data: Details
    }
    private struct Chunk: Decodable {
        struct Choice: Decodable {
            struct Delta: Decodable {
                struct Tool: Decodable {
                    struct Function: Decodable { let name: String?; let arguments: String? }
                    let index: Int; let id: String?; let function: Function?
                }
                let content: String?; let toolCalls: [Tool]?
                enum CodingKeys: String, CodingKey { case content; case toolCalls = "tool_calls" }
            }
            let delta: Delta?; let finishReason: String?
            enum CodingKeys: String, CodingKey { case delta; case finishReason = "finish_reason" }
        }
        let choices: [Choice]?; let usage: ChatUsage?; let error: ErrorEnvelope.Detail?
    }
}
