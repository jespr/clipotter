import SwiftUI
import AVFoundation
import AppKit

@MainActor
enum StarredExport {
    /// Builds the text for starred lines, each tagged with a matching `[Frame N · mm:ss]`
    /// reference so it lines up with the exported image.
    static func text(for segments: [TranscriptSegment]) -> String {
        segments.enumerated()
            .map { index, segment in "[Frame \(index + 1) · \(segment.timecode)] \(segment.text)" }
            .joined(separator: "\n")
    }

    /// Renders a "contact sheet" image of the starred moments: a video still +
    /// `Frame N · mm:ss` label + the line's text per card. Returns nil if there's
    /// nothing to render.
    static func image(mediaURL: URL?, segments: [TranscriptSegment]) async -> NSImage? {
        guard !segments.isEmpty else { return nil }

        var stills: [Int: NSImage] = [:]
        if let url = mediaURL {
            let generator = AVAssetImageGenerator(asset: AVURLAsset(url: url))
            generator.appliesPreferredTrackTransform = true
            generator.requestedTimeToleranceBefore = .zero
            generator.requestedTimeToleranceAfter = .zero
            generator.maximumSize = CGSize(width: 960, height: 960)
            for (index, segment) in segments.enumerated() {
                let time = CMTime(seconds: segment.start, preferredTimescale: 600)
                if let cg = try? await generator.image(at: time).image {
                    stills[index] = NSImage(cgImage: cg, size: .zero)
                }
            }
        }

        let sheet = ContactSheet(segments: segments, stills: stills)
        let renderer = ImageRenderer(content: sheet)
        renderer.scale = 2
        return renderer.nsImage
    }
}

private struct ContactSheet: View {
    let segments: [TranscriptSegment]
    let stills: [Int: NSImage]

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            ForEach(Array(segments.enumerated()), id: \.offset) { index, segment in
                VStack(alignment: .leading, spacing: 8) {
                    Text("Frame \(index + 1) · \(segment.timecode)")
                        .font(.system(.headline, design: .rounded))
                        .foregroundStyle(.white)
                    if let still = stills[index] {
                        Image(nsImage: still)
                            .resizable()
                            .aspectRatio(contentMode: .fit)
                            .frame(maxWidth: .infinity)
                            .clipShape(RoundedRectangle(cornerRadius: 10))
                    }
                    Text(segment.text)
                        .font(.body)
                        .foregroundStyle(.white.opacity(0.85))
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
        }
        .padding(24)
        .frame(width: 600)
        .background(Color(red: 0.06, green: 0.06, blue: 0.07))
        .environment(\.colorScheme, .dark)
    }
}
