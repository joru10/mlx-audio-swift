# Local Voice Utility for macOS (MLXAudio-based)

This repository now contains a baseline app built on top of `mlx-audio-swift`:

- SwiftUI executable target: `LocalVoiceUtility`
- Optional CLI target: `local-voice-utility-cli`
- Shared core target: `LocalVoiceUtilityKit`

## What is implemented

- Milestone 1 foundation
  - App shell with sidebar navigation and screens
  - Job model, JSON persistence, and library/history list
  - Application Support path layout in `AppPaths`
  - Per-job log file writing
- Milestone 2 baseline pipelines
  - PDF -> Audio pipeline with PDFKit text extraction and chunked TTS generation
  - Audio/Video -> Transcript pipeline with video audio extraction and STT
  - TXT export and optional JSON export for transcript metadata
- Milestone 3 scaffolds
  - URL extraction + URL -> Audio pipeline skeleton
  - VAD option plumbed through STT options (behavior can be refined)
- Milestone 4 scaffold
  - Live pipeline placeholder with explicit not-implemented error

## Build commands

```bash
swift build --product LocalVoiceUtility
swift build --product local-voice-utility-cli
```

## Run commands

```bash
swift run LocalVoiceUtility
swift run local-voice-utility-cli list-jobs
```

## Notes

- The app is intended for Apple Silicon macOS 14+.
- Model download/cache UI is scaffolded; operational model inventory and lifecycle can be expanded next.
- Live mode and action routing are intentionally deferred to Pro milestone.
