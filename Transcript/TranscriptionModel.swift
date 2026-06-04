import Foundation
import Observation

enum MediaSource {
    case local(URL)
    case remote(URL)
}

@MainActor
@Observable
final class TranscriptionModel {
    var status: String = ""
    var segments: [TranscriptSegment] = []
    var mediaURL: URL?
    var isRunning = false
    var errorMessage: String?

    private var task: Task<Void, Never>?
    /// A downloaded remote file we keep alive for playback; removed when a new media loads.
    private var retainedTemp: URL?

    var transcript: String {
        segments.map(\.text).joined(separator: " ")
    }

    var timestampedTranscript: String {
        segments.map { "[\($0.timecode)] \($0.text)" }.joined(separator: "\n")
    }

    var canCopy: Bool { !segments.isEmpty }

    func start(_ source: MediaSource) {
        cancel()
        segments = []
        mediaURL = nil
        errorMessage = nil
        status = ""
        if let old = retainedTemp {
            try? FileManager.default.removeItem(at: old)
            retainedTemp = nil
        }
        isRunning = true
        task = Task { await run(source) }
    }

    func cancel() {
        task?.cancel()
        task = nil
        isRunning = false
    }

    private func run(_ source: MediaSource) async {
        do {
            let url: URL
            switch source {
            case .local(let local):
                url = local
            case .remote(let remote):
                status = "Downloading video…"
                let downloaded = try await download(remote)
                retainedTemp = downloaded
                url = downloaded
            }
            // Expose for playback as soon as it's available, even while transcribing.
            mediaURL = url

            for try await event in TranscriptionEngine.transcribe(mediaURL: url) {
                if Task.isCancelled { break }
                switch event {
                case .status(let value):
                    status = value
                case .transcript(let newSegments):
                    segments = newSegments
                }
            }
            status = segments.isEmpty ? "No speech found in that file." : "Done"
        } catch is CancellationError {
            status = "Cancelled"
        } catch {
            errorMessage = error.localizedDescription
            status = ""
        }
        isRunning = false
    }

    private func download(_ url: URL) async throws -> URL {
        let (tempURL, _) = try await URLSession.shared.download(from: url)
        let ext = url.pathExtension.isEmpty ? "mp4" : url.pathExtension
        let destination = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathExtension(ext)
        try FileManager.default.moveItem(at: tempURL, to: destination)
        return destination
    }
}
