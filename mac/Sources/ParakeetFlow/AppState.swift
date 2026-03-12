import SwiftUI
import CoreGraphics

enum HotkeyChoice: String, CaseIterable {
    case option
    case rightCommand
    case control
    case fn

    var eventFlag: CGEventFlags {
        switch self {
        case .option: return .maskAlternate
        case .rightCommand: return .maskCommand
        case .control: return .maskControl
        case .fn: return .maskSecondaryFn
        }
    }

    var symbol: String {
        switch self {
        case .option: return "⌥"
        case .rightCommand: return "⌘"
        case .control: return "⌃"
        case .fn: return "fn"
        }
    }

    var label: String {
        switch self {
        case .option: return "⌥ Option"
        case .rightCommand: return "⌘ Command"
        case .control: return "⌃ Control"
        case .fn: return "fn"
        }
    }
}

enum WaveformColor: String, CaseIterable {
    case parakeet
    case white
    case green
    case bluePurple
    case red

    var label: String {
        switch self {
        case .parakeet: return "Parakeet"
        case .white: return "White"
        case .green: return "Green"
        case .bluePurple: return "Blue / Purple"
        case .red: return "Red"
        }
    }

    var colors: [Color] {
        switch self {
        case .parakeet:
            return [
                Color(red: 0.0, green: 0.7, blue: 0.65),    // teal
                Color(red: 0.0, green: 0.8, blue: 0.5),     // green-teal
                Color(red: 0.0, green: 0.85, blue: 0.45),   // green
                Color(red: 0.0, green: 0.8, blue: 0.5),     // green-teal
                Color(red: 0.9, green: 0.78, blue: 0.2),    // yellow
            ]
        case .white:
            return Array(repeating: .white, count: 5)
        case .green:
            return [
                Color(red: 0.2, green: 0.9, blue: 0.4),
                Color(red: 0.1, green: 1.0, blue: 0.5),
                Color(red: 0.0, green: 1.0, blue: 0.6),
                Color(red: 0.1, green: 1.0, blue: 0.5),
                Color(red: 0.2, green: 0.9, blue: 0.4),
            ]
        case .bluePurple:
            return [
                Color(red: 0.3, green: 0.6, blue: 1.0),
                Color(red: 0.5, green: 0.4, blue: 1.0),
                Color(red: 0.8, green: 0.3, blue: 0.9),
                Color(red: 0.5, green: 0.4, blue: 1.0),
                Color(red: 0.3, green: 0.6, blue: 1.0),
            ]
        case .red:
            return [
                Color(red: 1.0, green: 0.4, blue: 0.2),
                Color(red: 1.0, green: 0.25, blue: 0.2),
                Color(red: 1.0, green: 0.15, blue: 0.15),
                Color(red: 1.0, green: 0.25, blue: 0.2),
                Color(red: 1.0, green: 0.4, blue: 0.2),
            ]
        }
    }
}

enum AsrBackend: String, CaseIterable {
    case apple
    case parakeetV2
    case parakeet
    case qwen3Asr
    case qwen3AsrInt8

    var label: String {
        switch self {
        case .apple: return "Apple Speech"
        case .parakeetV2: return "Parakeet TDT v2 (EN)"
        case .parakeet: return "Parakeet TDT v3 (Multilingual)"
        case .qwen3Asr: return "Qwen3 ASR"
        case .qwen3AsrInt8: return "Qwen3 ASR Int8"
        }
    }

    var needsDownload: Bool {
        switch self {
        case .apple: return false
        case .parakeetV2, .parakeet, .qwen3Asr, .qwen3AsrInt8: return true
        }
    }
}

enum LlmBackend: String, CaseIterable {
    case apple
    case mlx

    var label: String {
        switch self {
        case .apple: return "Apple Intelligence"
        case .mlx: return "MLX"
        }
    }

    var needsDownload: Bool {
        self == .mlx
    }
}

enum MlxModelChoice: String, CaseIterable {
    case qwen35_2b = "mlx-community/Qwen3.5-2B-6bit"
    case phi4mini = "mlx-community/Phi-4-mini-instruct-4bit"
    case llama32_3b = "mlx-community/Llama-3.2-3B-Instruct-4bit"

    var label: String {
        switch self {
        case .qwen35_2b: return "Qwen 3.5 2B (6-bit)"
        case .phi4mini: return "Phi-4 Mini (4-bit)"
        case .llama32_3b: return "Llama 3.2 3B (4-bit)"
        }
    }

    var modelID: String { rawValue }
}

enum ModelStatus: Equatable {
    case notNeeded
    case ready
    case notDownloaded
    case downloading(progress: Double)
    case error(String)
}

enum PasteMethod: String, CaseIterable {
    case paste
    case accessibility
    case keyByKey
    case clipboardOnly

    var label: String {
        switch self {
        case .paste: return "Paste (⌘V)"
        case .accessibility: return "Accessibility API"
        case .keyByKey: return "Key-by-Key Typing"
        case .clipboardOnly: return "Clipboard Only"
        }
    }

    var description: String {
        switch self {
        case .paste: return "Simulates ⌘V. Works everywhere, preserves clipboard."
        case .accessibility: return "Sets text directly via Accessibility. No clipboard use."
        case .keyByKey: return "Types each character. Slowest but most compatible."
        case .clipboardOnly: return "Copies text to clipboard without pasting. ⌘V manually."
        }
    }
}

enum AppPhase: String {
    case idle
    case recording
    case processing
    case inserting
    case error
}

@MainActor
@Observable
final class AppState {
    var phase: AppPhase = .idle
    var modelStatusByBackend: [AsrBackend: ModelStatus] = [:]
    var partialTranscription: String?
    var errorMessage: String?

    var isLLMEnabled: Bool {
        didSet { UserDefaults.standard.set(isLLMEnabled, forKey: "isLLMEnabled") }
    }
    var isFillerRemovalEnabled: Bool {
        didSet { UserDefaults.standard.set(isFillerRemovalEnabled, forKey: "isFillerRemovalEnabled") }
    }
    var fillerWords: [String] {
        didSet {
            UserDefaults.standard.set(fillerWords, forKey: "fillerWords")
            FillerWordFilter.updatePatterns(fillerWords)
        }
    }
    var isDictionaryEnabled: Bool {
        didSet { UserDefaults.standard.set(isDictionaryEnabled, forKey: "isDictionaryEnabled") }
    }
    var dictionaryThreshold: Double {
        didSet { UserDefaults.standard.set(dictionaryThreshold, forKey: "dictionaryThreshold") }
    }
    /// Minutes of inactivity before unloading models from memory. 0 = never unload.
    var modelUnloadMinutes: Int {
        didSet { UserDefaults.standard.set(modelUnloadMinutes, forKey: "modelUnloadMinutes") }
    }
    var isAudioFeedbackEnabled: Bool {
        didSet { UserDefaults.standard.set(isAudioFeedbackEnabled, forKey: "isAudioFeedbackEnabled") }
    }
    var isRecordingOverlayEnabled: Bool {
        didSet { UserDefaults.standard.set(isRecordingOverlayEnabled, forKey: "isRecordingOverlayEnabled") }
    }
    var waveformColor: WaveformColor {
        didSet { UserDefaults.standard.set(waveformColor.rawValue, forKey: "waveformColor") }
    }
    var pasteMethod: PasteMethod {
        didSet { UserDefaults.standard.set(pasteMethod.rawValue, forKey: "pasteMethod") }
    }
    var hotkeyChoice: HotkeyChoice {
        didSet { UserDefaults.standard.set(hotkeyChoice.rawValue, forKey: "hotkeyChoice") }
    }
    var asrBackend: AsrBackend {
        didSet { UserDefaults.standard.set(asrBackend.rawValue, forKey: "asrBackend") }
    }
    var llmBackend: LlmBackend {
        didSet { UserDefaults.standard.set(llmBackend.rawValue, forKey: "llmBackend") }
    }
    var mlxModel: MlxModelChoice {
        didSet { UserDefaults.standard.set(mlxModel.rawValue, forKey: "mlxModel") }
    }
    var mlxModelStatus: [MlxModelChoice: ModelStatus] = [:]
    var hasCompletedOnboarding: Bool {
        didSet { UserDefaults.standard.set(hasCompletedOnboarding, forKey: "hasCompletedOnboarding") }
    }

    init() {
        let defaults = UserDefaults.standard
        defaults.register(defaults: [
            "isLLMEnabled": true,
            "isFillerRemovalEnabled": true,
            "fillerWords": FillerWordFilter.defaultFillerWords,
            "isDictionaryEnabled": true,
            "dictionaryThreshold": DictionaryCorrector.defaultThreshold,
            "modelUnloadMinutes": 10,
            "isAudioFeedbackEnabled": true,
            "isRecordingOverlayEnabled": false,
            "waveformColor": WaveformColor.parakeet.rawValue,
            "pasteMethod": PasteMethod.paste.rawValue,
            "hotkeyChoice": HotkeyChoice.option.rawValue,
            "asrBackend": AsrBackend.apple.rawValue,
            "llmBackend": LlmBackend.apple.rawValue,
            "mlxModel": MlxModelChoice.qwen35_2b.rawValue,
        ])
        self.isLLMEnabled = defaults.bool(forKey: "isLLMEnabled")
        self.isFillerRemovalEnabled = defaults.bool(forKey: "isFillerRemovalEnabled")
        let loadedFillerWords = (defaults.array(forKey: "fillerWords") as? [String]) ?? FillerWordFilter.defaultFillerWords
        self.fillerWords = loadedFillerWords
        self.isDictionaryEnabled = defaults.bool(forKey: "isDictionaryEnabled")
        self.dictionaryThreshold = defaults.double(forKey: "dictionaryThreshold")
        self.modelUnloadMinutes = defaults.integer(forKey: "modelUnloadMinutes")
        self.isAudioFeedbackEnabled = defaults.bool(forKey: "isAudioFeedbackEnabled")
        self.isRecordingOverlayEnabled = defaults.bool(forKey: "isRecordingOverlayEnabled")
        self.waveformColor = WaveformColor(rawValue: defaults.string(forKey: "waveformColor") ?? "") ?? .bluePurple
        self.pasteMethod = PasteMethod(rawValue: defaults.string(forKey: "pasteMethod") ?? "") ?? .paste
        self.hotkeyChoice = HotkeyChoice(rawValue: defaults.string(forKey: "hotkeyChoice") ?? "") ?? .option
        self.asrBackend = AsrBackend(rawValue: defaults.string(forKey: "asrBackend") ?? "") ?? .apple
        self.llmBackend = LlmBackend(rawValue: defaults.string(forKey: "llmBackend") ?? "") ?? .apple
        self.mlxModel = MlxModelChoice(rawValue: defaults.string(forKey: "mlxModel") ?? "") ?? .qwen35_2b
        self.hasCompletedOnboarding = defaults.bool(forKey: "hasCompletedOnboarding")
        FillerWordFilter.updatePatterns(loadedFillerWords)
    }

    var isLaunchAtLoginEnabled: Bool {
        get { LaunchAtLoginManager.isEnabled }
        set { LaunchAtLoginManager.setEnabled(newValue) }
    }

    var statusText: String {
        switch phase {
        case .idle: return "Ready"
        case .recording: return "Recording..."
        case .processing: return "Cleaning up..."
        case .inserting: return "Inserting..."
        case .error: return errorMessage ?? "Error"
        }
    }

    var menuBarIcon: String {
        switch phase {
        case .idle: return "waveform"
        case .recording: return "waveform.circle.fill"
        case .processing: return "ellipsis.circle"
        case .inserting: return "doc.on.clipboard"
        case .error: return "exclamationmark.triangle"
        }
    }
}
