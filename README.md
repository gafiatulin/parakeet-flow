<p align="center">
  <img src="app-icon.png" width="128" alt="ParakeetFlow icon">
</p>

# ParakeetFlow

On-device voice dictation with LLM post-processing. Hold a hotkey (or tap a bubble) to record, release to transcribe and insert cleaned-up text at the cursor. All processing happens locally — no cloud APIs.

> **Note:** This project is an ongoing experiment with agentic coding flows — almost one-shotting entire apps and features. Expect rough edges.

## Features

- **Push-to-talk and hands-free** — hold a hotkey to record, or quick-tap for hands-free mode (macOS); tap or long-press the floating bubble (Android)
- **Backtrack correction** — say "actually", "scratch that", or "no wait" to revise what you just said ("coffee at 2 actually 3" → "coffee at 3")
- **Stutter and false start removal** — repeated words and immediate restarts are cleaned up ("I I think" → "I think")
- **Voice formatting commands** — "new line", "new paragraph", "comma", "period", etc. are converted to punctuation (macOS)
- **Numbered list formatting** — dictate items with numbers and they're formatted as a list (macOS)
- **Filler word removal** — strips um, uh, like, you know, basically, etc. via regex set-match before LLM, and again during LLM cleanup (toggleable)
- **Context-aware cleanup** — reads the active app, window title, and surrounding text; adapts tone (casual for Slack, formal for Mail, technical for Xcode) (macOS)
- **Recording overlay** — animated waveform indicator while recording (macOS)
- **Transcription history** — log of past dictations with full pipeline visibility (raw ASR → filtered → LLM output)

## Platforms

### [macOS](mac/)

Menu bar app for macOS 26+ (Tahoe). Uses Apple SpeechAnalyzer for streaming ASR and Apple FoundationModels for LLM cleanup. Alternative backends via FluidAudio (Parakeet TDT) and MLX (Qwen, Phi, Llama).

```
cd mac && swift build
```

### [Android](android/)

Floating bubble overlay for Android 8+. Uses Sherpa-ONNX with NVIDIA Parakeet TDT 0.6B (int8) for ASR and LiteRT-LM with Qwen3 0.6B (int4) for LLM cleanup.

```
cd android && ./gradlew assembleRelease -x lintVitalRelease
```

## Architecture

Both platforms share the same pipeline:

```
Audio capture -> ASR transcription -> Filler word filter -> LLM cleanup -> Text insertion
                                        (optional)          (optional)
```

| Component | macOS | Android |
|---|---|---|
| ASR | Apple SpeechAnalyzer (streaming) | Sherpa-ONNX Parakeet TDT (batch) |
| LLM | Apple FoundationModels / MLX | LiteRT-LM Qwen3 0.6B |
| Trigger | Hotkey (Option hold/release) | Floating bubble (tap/hold) |
| Text insertion | Clipboard + Cmd+V | AccessibilityService |
| Context | AXUIElement + NSWorkspace | AccessibilityService |

## License

MIT
