import Foundation
import Observation

/// Drives running a prompt over the transcript and holds the result.
@MainActor
@Observable
final class ProcessingModel {
    var output = ""
    var isProcessing = false
    var errorMessage: String?

    private var task: Task<Void, Never>?

    var hasOutput: Bool { !output.isEmpty }

    func run(systemPrompt: String, transcript: String, processor: TextProcessor) {
        cancel()
        output = ""
        errorMessage = nil
        isProcessing = true
        task = Task {
            do {
                let result = try await processor.process(systemPrompt: systemPrompt, transcript: transcript)
                if !Task.isCancelled { output = result }
            } catch is CancellationError {
                // ignored
            } catch {
                errorMessage = error.localizedDescription
            }
            isProcessing = false
        }
    }

    func cancel() {
        task?.cancel()
        task = nil
        isProcessing = false
    }

    func reset() {
        cancel()
        output = ""
        errorMessage = nil
    }
}
