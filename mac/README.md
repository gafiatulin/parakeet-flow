# ParakeetFlow — macOS

A macOS menu bar app for voice dictation with on-device LLM post-processing.

Hold a hotkey to record, release to transcribe and insert cleaned-up text at the cursor. All processing happens locally on your Mac.

## Features

- **Streaming transcription** via Apple SpeechAnalyzer (macOS 26+)
- **LLM cleanup** via Apple FoundationModels (on-device Apple Intelligence) or MLX (Qwen, Phi, Llama)
- **Push-to-talk and hands-free** hotkey modes
- **Context-aware** prompts using the active app and selected text
- **Filler word removal** (um, uh, like, etc.)
- **Custom dictionary** with fuzzy + phonetic matching (Levenshtein + Soundex) for names, technical terms, and frequently misheard words
- **Recording overlay** with animated waveform indicator
- **Transcription history** stored in SwiftData with full pipeline visibility
- **Alternative ASR backends** via FluidAudio (Parakeet TDT v2/v3, Qwen3 ASR)

## Requirements

- macOS 26 (Tahoe) or later
- Xcode 26+ with macOS 26 SDK
- [XcodeGen](https://github.com/yonaskolb/XcodeGen) — generates the Xcode project from `project.yml`
- Apple Intelligence enabled (optional — required only for Apple Intelligence LLM cleanup backend)

### Installing XcodeGen

Via [Homebrew](https://brew.sh):

```bash
brew install xcodegen
```

Or see the [XcodeGen repo](https://github.com/yonaskolb/XcodeGen) for alternative installation methods (Mint, Make, etc.).

## Build

### Command line

```bash
# 1. Generate the Xcode project from project.yml
xcodegen generate

# 2. Build (debug)
xcodebuild build -scheme ParakeetFlow -configuration Debug

# Or build release
xcodebuild build -scheme ParakeetFlow -configuration Release
```

> **Tip:** If you get `xcode-select: error: tool 'xcodebuild' requires Xcode`, point `xcode-select` to your Xcode installation:
> ```bash
> sudo xcode-select -s /Applications/Xcode.app/Contents/Developer
> ```

The built app will be at:

```
# Debug
~/Library/Developer/Xcode/DerivedData/ParakeetFlow-*/Build/Products/Debug/ParakeetFlow.app

# Release
~/Library/Developer/Xcode/DerivedData/ParakeetFlow-*/Build/Products/Release/ParakeetFlow.app
```

### Xcode

1. Run `xcodegen generate` to create `ParakeetFlow.xcodeproj`
2. Open `ParakeetFlow.xcodeproj` in Xcode
3. Select the `ParakeetFlow` scheme and click Run

> **Note:** `swift build` does not work because SwiftData `@Model` macros require the Xcode build system.

### Why XcodeGen?

The Xcode project file (`ParakeetFlow.xcodeproj`) is generated from [`project.yml`](project.yml) and is not checked into version control. `project.yml` is the source of truth — you need to run `xcodegen generate` before building and re-run it after adding or removing source files.

## Permissions

The app requires:

- **Microphone** — for audio capture
- **Accessibility** — for reading context (active app, surrounding text) and inserting text via `CGEvent` posting

These are requested during the first-launch onboarding wizard.

> **Note:** The app is not sandboxed because `CGEvent` posting and `AXUIElement` access require it.

## Usage

1. Launch the app (runs in the menu bar)
2. Complete the onboarding wizard (permissions, engine selection, hotkey)
3. Hold the hotkey (Option by default) to record
4. Release to transcribe and insert text

Quick-tap the hotkey for hands-free mode (tap again to stop). Press Escape to cancel.

## Configuration

All settings are accessible from the menu bar icon → Settings:

- **ASR backend** — Apple Speech (built-in), Parakeet TDT v2/v3, Qwen3 ASR
- **LLM backend** — Apple Intelligence, MLX (Qwen 3.5, Phi-4 Mini, Llama 3.2)
- **Hotkey** — Option, Command, Control, or Fn
- **Paste method** — Cmd+V, Accessibility API, key-by-key typing, or clipboard only
- **Filler words** — customizable list of words to strip
- **Dictionary** — custom word corrections with configurable fuzzy match threshold
- **Recording overlay** — waveform color and visibility
- **Model memory management** — auto-unload models after inactivity

## License

MIT
