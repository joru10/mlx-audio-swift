# Local Voice Utility - Quick User Guide

## 1) Build

```bash
cd /Users/joru2/Applications/MLXAudio
swift build --product LocalVoiceUtility
swift build --product local-voice-utility-cli
```

## 2) Launch the macOS app

```bash
swift run LocalVoiceUtility
```

In the sidebar, use these flows:

- `PDF -> Audio`
  - Click `Select PDF`
  - Pick a PDF with embedded text
  - Optionally adjust model/chunk settings
  - Click `Run PDF to Audio`
  - Open `Library` to see progress and output file path

- `Transcribe`
  - Click `Select Audio/Video`
  - Choose `m4a/mp3/wav/aiff/mov/mp4`
  - Choose STT model and options
  - Click `Run Transcription`
  - Open `Library` for transcript output path

- `Library`
  - Shows job status (`queued/running/completed/failed`)
  - Shows produced output paths (audio/transcript/json)

- `Settings`
  - Configure defaults (output folder, logging level, default model IDs)

## 3) Use the CLI (optional)

```bash
# List jobs
swift run local-voice-utility-cli list-jobs

# Queue PDF -> Audio
swift run local-voice-utility-cli pdf2audio /absolute/path/to/file.pdf

# Queue transcription
swift run local-voice-utility-cli transcribe /absolute/path/to/file.mp4
```

## 4) Where files are stored

Application data is persisted at:

```text
~/Library/Application Support/LocalVoiceUtility/
```

Key folders:
- `jobs/` job metadata
- `outputs/` generated audio/transcript artifacts
- `logs/` per-job logs
- `models/` model metadata/cache bookkeeping

## 5) Current status and limits

Implemented now:
- PDF -> Audio (MVP baseline)
- Audio/Video -> Transcript (MVP baseline)
- Job persistence + history UI + logs
- Live realtime transcript from audio input devices (Live tab)
- Live routing actions: clipboard, type into front app, shell, webhook

Scaffolded but not fully wired in UI yet:
- URL -> Audio full UX
- Advanced model management UI actions

## 6) Live transcript + app connection

- Open app: `/Users/joru2/Applications/LocalVoiceUtility.app`
- Go to `Live`
- Choose `Input` device:
  - microphone for normal dictation
  - loopback device (for example BlackHole) for Mac speaker/system-audio transcript
- Click `Start Live Transcript`
- Choose `Action` to connect transcript to apps:
  - `Copy to Clipboard`
  - `Type into Front App` (sends keystrokes to active app)
  - `Run Shell Command` (template supports `{{text}}`)
  - `POST Webhook` (JSON payload: `{ \"text\": \"...\" }`)
