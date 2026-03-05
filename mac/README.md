# ParakeetFlow

A macOS menu bar app for voice dictation with on-device LLM post-processing.

Hold a hotkey to record, release to transcribe and insert cleaned-up text at the cursor. All processing happens locally on your Mac.

## Features

- **Streaming transcription** via Apple SpeechAnalyzer (macOS 26+)
- **LLM cleanup** via Apple FoundationModels (on-device Apple Intelligence)
- **Push-to-talk and hands-free** hotkey modes
- **Context-aware** prompts using the active app and selected text
- **Filler word removal** (um, uh, like, etc.)
- **Recording overlay** with animated waveform indicator

## Requirements

- macOS 26 (Tahoe) or later
- Apple Intelligence enabled (for LLM cleanup)
- Accessibility, Input Monitoring, and Microphone permissions

## Build

```
swift build
```

Or open `ParakeetFlow.xcodeproj` in Xcode.

## Usage

1. Launch the app (runs in the menu bar)
2. Grant the requested permissions
3. Hold the hotkey (Option by default) to record
4. Release to transcribe and insert text

Quick-tap the hotkey for hands-free mode (tap again to stop). Press Escape to cancel.

## License

MIT
