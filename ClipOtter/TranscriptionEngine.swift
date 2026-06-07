import Foundation
import AVFoundation
import Speech

/// One recognized chunk of speech with the audio time it starts at.
struct TranscriptSegment: Sendable, Identifiable, Hashable, Codable {
    let id: Int
    let start: TimeInterval
    let timecode: String
    let text: String
}

/// Events emitted while a media file is being transcribed.
enum TranscriptionEvent: Sendable {
    /// A human-readable status update ("Extracting audio…", "Transcribing…", …).
    case status(String)
    /// The full list of segments recognized so far. Sent repeatedly as more speech arrives.
    case transcript([TranscriptSegment])
}

enum TranscriptionError: LocalizedError {
    case localeNotSupported(String)
    case noAudioTrack
    case audioExportFailed
    case modelUnavailable

    var errorDescription: String? {
        switch self {
        case .localeNotSupported(let id):
            return "On-device speech recognition isn't available for \(id) on this Mac."
        case .noAudioTrack:
            return "That file doesn't contain an audio track to transcribe."
        case .audioExportFailed:
            return "Couldn't extract the audio from that file."
        case .modelUnavailable:
            return "The on-device speech model could not be installed."
        }
    }
}

/// Transcribes a local media file entirely on-device using `SpeechAnalyzer`.
enum TranscriptionEngine {
    static func transcribe(mediaURL: URL) -> AsyncThrowingStream<TranscriptionEvent, Error> {
        AsyncThrowingStream { continuation in
            let work = Task {
                do {
                    try await run(mediaURL: mediaURL, continuation: continuation)
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
            continuation.onTermination = { _ in work.cancel() }
        }
    }

    private static func run(
        mediaURL: URL,
        continuation: AsyncThrowingStream<TranscriptionEvent, Error>.Continuation
    ) async throws {
        continuation.yield(.status("Fishing out the audio…"))
        let audioURL = try await extractAudio(from: mediaURL)
        defer { try? FileManager.default.removeItem(at: audioURL) }

        let locale = Locale.current
        let transcriber = SpeechTranscriber(
            locale: locale,
            transcriptionOptions: [],
            reportingOptions: [],
            attributeOptions: [.audioTimeRange]
        )

        guard await isSupported(locale) else {
            throw TranscriptionError.localeNotSupported(locale.identifier)
        }

        if await !isInstalled(locale) {
            continuation.yield(.status("Grabbing the speech model (just this once)…"))
            if let request = try await AssetInventory.assetInstallationRequest(supporting: [transcriber]) {
                try await request.downloadAndInstall()
            }
        }

        let analyzer = SpeechAnalyzer(modules: [transcriber])

        continuation.yield(.status("Listening closely…"))

        let resultsTask = Task {
            var segments: [TranscriptSegment] = []
            for try await result in transcriber.results {
                let text = String(result.text.characters).trimmingCharacters(in: .whitespacesAndNewlines)
                guard !text.isEmpty else { continue }
                let startTime = result.text.runs.compactMap(\.audioTimeRange?.start).first ?? .zero
                let seconds = startTime.seconds.isFinite ? max(0, startTime.seconds) : 0
                segments.append(TranscriptSegment(
                    id: segments.count,
                    start: seconds,
                    timecode: timecode(startTime),
                    text: text
                ))
                continuation.yield(.transcript(segments))
            }
        }

        let audioFile = try AVAudioFile(forReading: audioURL)
        if let lastSample = try await analyzer.analyzeSequence(from: audioFile) {
            try await analyzer.finalizeAndFinish(through: lastSample)
        } else {
            try await analyzer.cancelAndFinishNow()
        }

        try await resultsTask.value
    }

    private static func timecode(_ time: CMTime) -> String {
        let seconds = time.seconds.isFinite ? max(0, Int(time.seconds)) : 0
        if seconds >= 3600 {
            return String(format: "%d:%02d:%02d", seconds / 3600, (seconds % 3600) / 60, seconds % 60)
        }
        return String(format: "%02d:%02d", seconds / 60, seconds % 60)
    }

    // MARK: - Audio extraction

    private static func extractAudio(from mediaURL: URL) async throws -> URL {
        let asset = AVURLAsset(url: mediaURL)
        let audioTracks = try await asset.loadTracks(withMediaType: .audio)
        guard !audioTracks.isEmpty else { throw TranscriptionError.noAudioTrack }

        guard let export = AVAssetExportSession(asset: asset, presetName: AVAssetExportPresetAppleM4A) else {
            throw TranscriptionError.audioExportFailed
        }

        let outputURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathExtension("m4a")

        try await export.export(to: outputURL, as: .m4a)
        return outputURL
    }

    // MARK: - Locale / model availability

    private static func isSupported(_ locale: Locale) async -> Bool {
        let target = locale.identifier(.bcp47)
        let supported = await SpeechTranscriber.supportedLocales
        return supported.contains { $0.identifier(.bcp47) == target }
    }

    private static func isInstalled(_ locale: Locale) async -> Bool {
        let target = locale.identifier(.bcp47)
        let installed = await SpeechTranscriber.installedLocales
        return installed.contains { $0.identifier(.bcp47) == target }
    }
}
