# Changelog

All notable changes to Transcript are documented here. The release script reads
this file: each `## [x.y.z] - YYYY-MM-DD` section becomes the Sparkle release
notes and a card on the website changelog.

## [Unreleased]

## [0.5.4] - 2026-06-04

- Star any transcript line (★) to bookmark a moment
- Copy starred lines as text, each tagged with a `[Frame N · mm:ss]` reference
- Export starred moments as an image — a card per moment with the video still, timecode, and text — straight to the clipboard
- The text tags and the image's "Frame N" labels match, so an LLM can tie each line to its still

## [0.5.3] - 2026-06-04

- Fresh app icon — the otter got headphones and shades
- A little more personality: playful status messages and empty states
- New side-by-side layout — video on the left, transcript on the right
- Click anywhere on a transcript line, not just the timestamp, to jump there
- The drop area now fills the whole window when it's empty

## [0.5.2] - 2026-06-04

- New app icon
- Fixed a crash that could happen when a video loaded into the player
- Focused on local files — drag a file in or click to browse (removed the URL field)
- Use the up and down arrow keys to step through transcript segments; the video jumps to each
