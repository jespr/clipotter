import Foundation
import Observation

struct SavedPrompt: Identifiable, Codable, Hashable {
    var id = UUID()
    var name: String
    var text: String
}

/// Stores reusable prompts for different use cases, persisted in UserDefaults.
@MainActor
@Observable
final class PromptLibrary {
    var prompts: [SavedPrompt] = []

    private let storageKey = "savedPrompts.v1"

    init() {
        if let data = UserDefaults.standard.data(forKey: storageKey),
           let decoded = try? JSONDecoder().decode([SavedPrompt].self, from: data) {
            prompts = decoded
        } else {
            prompts = Self.starters
        }
    }

    /// Saves under `name`, overwriting an existing prompt with the same name.
    func save(name: String, text: String) {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        if let index = prompts.firstIndex(where: { $0.name.caseInsensitiveCompare(trimmed) == .orderedSame }) {
            prompts[index].text = text
        } else {
            prompts.append(SavedPrompt(name: trimmed, text: text))
        }
        persist()
    }

    func delete(_ prompt: SavedPrompt) {
        prompts.removeAll { $0.id == prompt.id }
        persist()
    }

    private func persist() {
        if let data = try? JSONEncoder().encode(prompts) {
            UserDefaults.standard.set(data, forKey: storageKey)
        }
    }

    static let starters: [SavedPrompt] = [
        SavedPrompt(name: "Summarize", text: "Summarize this transcript in a few concise paragraphs."),
        SavedPrompt(name: "Key takeaways", text: "Extract the key takeaways from this transcript as a bulleted list."),
        SavedPrompt(name: "Action items", text: "List every action item, decision, and owner mentioned in this transcript."),
        SavedPrompt(name: "Clean up", text: "Clean up this transcript: remove filler words and fix punctuation and capitalization, but preserve all content and meaning.")
    ]
}
