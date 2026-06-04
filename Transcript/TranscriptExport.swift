import SwiftUI
import AppKit

/// Bundles the work artifacts — the original transcript, the processed Markdown,
/// and (if any lines are starred) a contact-sheet image of those frames — and
/// writes them side by side into a folder the user picks.
@MainActor
enum TranscriptExport {
    struct Bundle {
        var transcript: String
        var processed: String
        var image: NSImage?
    }

    /// Writes whatever the bundle has into `directory`, returning the filenames
    /// actually written. Skips empty pieces so an export never drops blank files.
    @discardableResult
    static func write(_ bundle: Bundle, to directory: URL) throws -> [String] {
        var written: [String] = []

        if !bundle.transcript.isEmpty {
            let url = directory.appending(path: "transcript.txt")
            try bundle.transcript.write(to: url, atomically: true, encoding: .utf8)
            written.append("transcript.txt")
        }

        if !bundle.processed.isEmpty {
            let url = directory.appending(path: "processed.md")
            try bundle.processed.write(to: url, atomically: true, encoding: .utf8)
            written.append("processed.md")
        }

        if let image = bundle.image, let data = png(from: image) {
            let url = directory.appending(path: "frames.png")
            try data.write(to: url)
            written.append("frames.png")
        }

        return written
    }

    private static func png(from image: NSImage) -> Data? {
        guard let tiff = image.tiffRepresentation,
              let rep = NSBitmapImageRep(data: tiff) else { return nil }
        return rep.representation(using: .png, properties: [:])
    }
}
