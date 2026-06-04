import Foundation
import FoundationModels

enum LLMBackendKind: String, CaseIterable, Identifiable, Codable {
    case appleOnDevice
    case claude

    var id: String { rawValue }

    var label: String {
        switch self {
        case .appleOnDevice: return "On-device"
        case .claude: return "Claude API"
        }
    }
}

enum LLMError: LocalizedError {
    case missingAPIKey
    case appleUnavailable(String)
    case http(Int, String)
    case badResponse

    var errorDescription: String? {
        switch self {
        case .missingAPIKey:
            return "Add your Claude API key in Settings to use the Claude backend."
        case .appleUnavailable(let reason):
            return reason
        case .http(let code, let body):
            return "Claude API error (\(code)): \(body)"
        case .badResponse:
            return "Couldn't read the response from Claude."
        }
    }
}

/// Runs a user prompt against a transcript, producing transformed text.
protocol TextProcessor: Sendable {
    func process(systemPrompt: String, transcript: String) async throws -> String
}

// MARK: - Apple on-device (Foundation Models)

struct AppleProcessor: TextProcessor {
    func process(systemPrompt: String, transcript: String) async throws -> String {
        if let reason = AppleModel.unavailableReason {
            throw LLMError.appleUnavailable(reason)
        }
        let session = LanguageModelSession(instructions: systemPrompt)
        let response = try await session.respond(to: transcript)
        return response.content
    }
}

enum AppleModel {
    /// `nil` when the on-device model is ready; otherwise a human-readable reason.
    static var unavailableReason: String? {
        switch SystemLanguageModel.default.availability {
        case .available:
            return nil
        case .unavailable(let reason):
            switch reason {
            case .deviceNotEligible:
                return "This Mac doesn't support Apple Intelligence."
            case .appleIntelligenceNotEnabled:
                return "Turn on Apple Intelligence in System Settings to use the on-device model."
            case .modelNotReady:
                return "The on-device model is still downloading. Try again shortly."
            @unknown default:
                return "The on-device model is currently unavailable."
            }
        @unknown default:
            return "The on-device model is currently unavailable."
        }
    }

    static var isAvailable: Bool { unavailableReason == nil }
}

// MARK: - Claude API

struct ClaudeProcessor: TextProcessor {
    let apiKey: String
    let model: String

    func process(systemPrompt: String, transcript: String) async throws -> String {
        guard !apiKey.isEmpty else { throw LLMError.missingAPIKey }

        var request = URLRequest(url: URL(string: "https://api.anthropic.com/v1/messages")!)
        request.httpMethod = "POST"
        request.setValue(apiKey, forHTTPHeaderField: "x-api-key")
        request.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")
        request.setValue("application/json", forHTTPHeaderField: "content-type")

        let payload = Request(
            model: model,
            max_tokens: 4096,
            system: systemPrompt,
            messages: [.init(role: "user", content: transcript)]
        )
        request.httpBody = try JSONEncoder().encode(payload)

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw LLMError.badResponse }
        guard (200..<300).contains(http.statusCode) else {
            throw LLMError.http(http.statusCode, String(data: data, encoding: .utf8) ?? "")
        }

        let decoded = try JSONDecoder().decode(Response.self, from: data)
        let text = decoded.content.compactMap(\.text).joined()
        guard !text.isEmpty else { throw LLMError.badResponse }
        return text
    }

    private struct Request: Encodable {
        let model: String
        let max_tokens: Int
        let system: String
        let messages: [Message]
        struct Message: Encodable { let role: String; let content: String }
    }

    private struct Response: Decodable {
        let content: [Block]
        struct Block: Decodable { let type: String; let text: String? }
    }
}
