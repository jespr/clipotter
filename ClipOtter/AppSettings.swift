import Foundation
import Observation

/// Backend selection plus Claude credentials. Key lives in the Keychain; the rest in UserDefaults.
@MainActor
@Observable
final class AppSettings {
    var backend: LLMBackendKind {
        didSet { UserDefaults.standard.set(backend.rawValue, forKey: "backend") }
    }

    var claudeModel: String {
        didSet { UserDefaults.standard.set(claudeModel, forKey: "claudeModel") }
    }

    var claudeAPIKey: String {
        didSet { Keychain.set(claudeAPIKey, for: "claudeAPIKey") }
    }

    init() {
        backend = UserDefaults.standard.string(forKey: "backend")
            .flatMap(LLMBackendKind.init(rawValue:)) ?? .appleOnDevice
        claudeModel = UserDefaults.standard.string(forKey: "claudeModel") ?? "claude-sonnet-4-6"
        claudeAPIKey = Keychain.get("claudeAPIKey") ?? ""
    }

    /// Builds the processor for the current backend, throwing if it can't run yet.
    func makeProcessor() throws -> TextProcessor {
        switch backend {
        case .appleOnDevice:
            if let reason = AppleModel.unavailableReason { throw LLMError.appleUnavailable(reason) }
            return AppleProcessor()
        case .claude:
            guard !claudeAPIKey.isEmpty else { throw LLMError.missingAPIKey }
            return ClaudeProcessor(apiKey: claudeAPIKey, model: claudeModel)
        }
    }
}
