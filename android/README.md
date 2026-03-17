# ParakeetFlow Android

On-device voice dictation for Android. Tap or hold the floating bubble to transcribe speech and insert text into any app via AccessibilityService. Optional LLM post-processing cleans up grammar and punctuation.

## Architecture

```
Bubble (tap/hold) → AudioCaptureManager → Sherpa-ONNX ASR → FillerWordFilter → LLM PostProcessor → TextInserter
                                                                (optional)          (optional)
```

**ASR**: [NVIDIA Parakeet TDT 0.6B](https://huggingface.co/nvidia/parakeet-tdt-0.6b-v2) via [Sherpa-ONNX](https://github.com/k2-fsa/sherpa-onnx) (int8 quantized, offline transducer). Two model variants: v2 (English-only) and v3 (multilingual en/de/es/fr).

**LLM**: [Qwen3 0.6B](https://huggingface.co/litert-community/Qwen3-0.6B) via [LiteRT-LM](https://github.com/google-ai-edge/LiteRT-LM) (dynamic_int8, CPU/GPU). Cleans up punctuation, capitalization, stutters, and backtrack phrases.

**Text insertion**: AccessibilityService pastes via clipboard into the focused text field, with fallback to `ACTION_SET_TEXT`.

## Performance (Pixel 7, LLM off)

| Metric | Value |
|---|---|
| ASR RTF | ~0.21x (5x faster than real-time) |
| ASR model load | ~10s cold start |
| Memory (idle with bubble) | ~1.3 GB (ASR model dominates) |
| APK size | ~40 MB (native libs only, models downloaded separately) |

## Project Structure

```
app/src/main/java/com/github/gafiatulin/parakeetflow/
├── asr/                  # ASR engine interface + Sherpa-ONNX implementation
├── audio/                # AudioRecord capture (16kHz mono PCM float)
├── bubble/               # Floating overlay bubble (Compose, drag/tap/hold gestures)
├── context/              # Reads focused app/field via AccessibilityService
├── core/
│   ├── di/               # Hilt modules (App, ASR, LLM)
│   ├── model/            # Data classes (AsrModel, ModelStatus, UserSettings, etc.)
│   ├── preferences/      # DataStore-backed user preferences
│   └── util/             # Filler word filter, package name mapper
├── feedback/             # Haptic + audio feedback (SoundPool)
├── history/              # JSON-backed transcription history
├── insertion/            # Text insertion via AccessibilityService
├── llm/                  # LiteRT-LM post-processor + prompt builder
├── model/                # Model download manager (OkHttp, resume support)
├── orchestrator/         # Wires record → transcribe → process → insert pipeline
├── service/              # DictationService (foreground), AccessibilityService, ServiceBridge
├── ui/                   # Compose screens (Settings, Permissions, History, Onboarding)
├── viewmodel/            # ViewModels (App, Settings, History)
├── MainActivity.kt       # Single activity, Compose Navigation
└── ParakeetFlowApp.kt    # Hilt application class
```

### Native Libraries

Pre-built Sherpa-ONNX v1.12.28 (arm64-v8a only):
- `libonnxruntime.so` — 16 MB
- `libsherpa-onnx-jni.so` — 4.9 MB
- Kotlin API in `com.k2fsa.sherpa.onnx` (copied from upstream, not a Maven dependency)

## Build

Requires JDK 17+ and Android SDK with API 36.

```bash
./gradlew assembleRelease -x lintVitalRelease
```

Release APK: `app/build/outputs/apk/release/app-release.apk`

### Key Build Config

| Component | Version |
|---|---|
| AGP | 9.1.0 (built-in Kotlin) |
| Kotlin | 2.3.10 |
| Compose BOM | 2026.02.01 |
| Hilt | 2.59.2 (KSP) |
| minSdk / targetSdk / compileSdk | 26 / 35 / 36 |
| NDK | 29 (arm64-v8a only) |

## Install & Run

```bash
# Build and install
./gradlew assembleRelease -x lintVitalRelease
adb install -r app/build/outputs/apk/release/app-release.apk

# Launch — grant permissions via the in-app permissions screen:
#   1. Microphone (runtime)
#   2. Display over other apps (overlay)
#   3. Notifications (Android 13+)
#   4. Accessibility Service (for text insertion)
```

Models are downloaded in-app from HuggingFace. No authentication required.

## Permissions

| Permission | Purpose |
|---|---|
| `RECORD_AUDIO` | Microphone capture for ASR |
| `SYSTEM_ALERT_WINDOW` | Floating bubble overlay |
| `POST_NOTIFICATIONS` | Foreground service notification |
| `FOREGROUND_SERVICE` / `FOREGROUND_SERVICE_MICROPHONE` | Keep recording alive in background |
| `VIBRATE` | Haptic feedback on record start/stop |
| `INTERNET` | Model downloads |
| AccessibilityService | Read focused field, insert text, detect text fields |

## Tests

### Unit tests

```bash
./gradlew testDebugUnitTest
```

Tests cover `FillerWordFilter` and `PromptBuilder` — pure logic with no Android dependencies.

### Instrumentation tests

```bash
# Push ASR models to device first
adb push models/parakeet-tdt-v2/ /data/local/tmp/models/parakeet-tdt-v2/

# Run pipeline test
./gradlew connectedDebugAndroidTest -Pandroid.testInstrumentationRunnerArguments.class=com.github.gafiatulin.parakeetflow.SherpaOnnxPipelineTest
```
