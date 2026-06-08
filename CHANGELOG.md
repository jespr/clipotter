# Changelog

All notable changes to ClipOtter are documented here. The release script reads
this file: each `## [x.y.z] - YYYY-MM-DD` section becomes the Sparkle release
notes and a card on the website changelog.

## [Unreleased]

## [0.7.1] - 2026-06-07

- Saving a session now overrides the existing one for that video instead of leaving duplicate copies
- Moved backend & API-key settings into the Prompt box, next to the model selector

## [0.7.0] - 2026-06-07

- Renamed the app to ClipOtter 🦦
- Search your transcript — find any line and jump straight to that moment in the video
- Save and restore sessions — come back to a transcript with its stars and processed output intact
- Added website and X links to the About window

## [0.6.0] - 2026-06-04

- Save your work to a folder — the original transcript as `transcript.txt`, the processed result as `processed.md`, and any starred moments as a `frames.png` contact sheet

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
