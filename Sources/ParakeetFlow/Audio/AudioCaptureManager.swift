@preconcurrency import AVFoundation
import CoreAudio
import IOKit

actor AudioCaptureManager {
    private var engine: AVAudioEngine?
    private var converter: AVAudioConverter?
    private var isCapturing = false
    private var configObserver: (any NSObjectProtocol)?

    // Stored so we can re-install after configuration change
    private var activeTargetFormat: AVAudioFormat?
    private var activeCallback: (@Sendable (AVAudioPCMBuffer) -> Void)?

    /// Start capturing mic audio. Each buffer is delivered to `onBuffer`.
    /// If `targetFormat` differs from the hardware format, buffers are converted automatically.
    func startCapture(
        targetFormat: AVAudioFormat? = nil,
        onBuffer: @escaping @Sendable (AVAudioPCMBuffer) -> Void
    ) throws {
        guard !isCapturing else { return }

        activeTargetFormat = targetFormat
        activeCallback = onBuffer

        let engine = AVAudioEngine()
        self.engine = engine

        try installTapAndStart(engine: engine, targetFormat: targetFormat, onBuffer: onBuffer)

        // Re-start engine when audio configuration changes (e.g. lid close, device switch)
        configObserver = NotificationCenter.default.addObserver(
            forName: .AVAudioEngineConfigurationChange,
            object: engine,
            queue: nil
        ) { [weak self] _ in
            Task { await self?.handleConfigurationChange() }
        }

        self.isCapturing = true
    }

    func stopCapture() {
        guard isCapturing else { return }

        if let obs = configObserver {
            NotificationCenter.default.removeObserver(obs)
            configObserver = nil
        }

        engine?.inputNode.removeTap(onBus: 0)
        engine?.stop()
        engine = nil
        converter = nil
        activeTargetFormat = nil
        activeCallback = nil
        isCapturing = false
    }

    // MARK: - Private

    private func handleConfigurationChange() {
        guard isCapturing, let engine, let callback = activeCallback else { return }

        // Engine is reset — remove old tap and re-install
        engine.inputNode.removeTap(onBus: 0)
        converter = nil

        do {
            try installTapAndStart(engine: engine, targetFormat: activeTargetFormat, onBuffer: callback)
        } catch {
            // Can't recover — stop capturing
            stopCapture()
        }
    }

    /// Check whether the default input device can actually capture audio.
    /// Returns false when in clamshell mode with only the built-in mic available.
    nonisolated static func hasUsableAudioInput() -> Bool {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDefaultInputDevice,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var deviceID: AudioDeviceID = kAudioObjectUnknown
        var size = UInt32(MemoryLayout<AudioDeviceID>.size)
        guard AudioObjectGetPropertyData(
            AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, &size, &deviceID
        ) == noErr, deviceID != kAudioObjectUnknown else {
            return false
        }

        guard isClamshellClosed() else { return true }

        var transportAddress = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyTransportType,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var transportType: UInt32 = 0
        var transportSize = UInt32(MemoryLayout<UInt32>.size)
        guard AudioObjectGetPropertyData(
            deviceID, &transportAddress, 0, nil, &transportSize, &transportType
        ) == noErr else {
            return true
        }

        return transportType != kAudioDeviceTransportTypeBuiltIn
    }

    private nonisolated static func isClamshellClosed() -> Bool {
        let service = IOServiceGetMatchingService(
            kIOMainPortDefault,
            IOServiceMatching("IOPMrootDomain")
        )
        guard service != IO_OBJECT_NULL else { return false }
        defer { IOObjectRelease(service) }

        guard let prop = IORegistryEntryCreateCFProperty(
            service, "AppleClamshellState" as CFString, kCFAllocatorDefault, 0
        )?.takeRetainedValue() else {
            return false
        }
        return (prop as? Bool) ?? false
    }

    private func installTapAndStart(
        engine: AVAudioEngine,
        targetFormat: AVAudioFormat?,
        onBuffer: @escaping @Sendable (AVAudioPCMBuffer) -> Void
    ) throws {
        guard Self.hasUsableAudioInput() else {
            throw AudioCaptureError.noInputDevice
        }

        let inputNode = engine.inputNode
        let hardwareFormat = inputNode.outputFormat(forBus: 0)

        if let target = targetFormat,
           target.sampleRate != hardwareFormat.sampleRate || target.commonFormat != hardwareFormat.commonFormat {
            guard let conv = AVAudioConverter(from: hardwareFormat, to: target) else {
                throw AudioCaptureError.formatConversionFailed
            }
            self.converter = conv

            let sampleRateRatio = target.sampleRate / hardwareFormat.sampleRate

            inputNode.installTap(onBus: 0, bufferSize: 4096, format: hardwareFormat) { [conv] buffer, _ in
                let frameCount = AVAudioFrameCount(Double(buffer.frameLength) * sampleRateRatio)
                guard let converted = AVAudioPCMBuffer(pcmFormat: target, frameCapacity: frameCount) else { return }

                var error: NSError?
                conv.convert(to: converted, error: &error) { _, outStatus in
                    outStatus.pointee = .haveData
                    return buffer
                }

                if error == nil, converted.frameLength > 0 {
                    onBuffer(converted)
                }
            }
        } else {
            inputNode.installTap(onBus: 0, bufferSize: 4096, format: hardwareFormat) { buffer, _ in
                onBuffer(buffer)
            }
        }

        engine.prepare()
        try engine.start()
    }
}

enum AudioCaptureError: LocalizedError {
    case formatConversionFailed
    case noInputDevice

    var errorDescription: String? {
        switch self {
        case .formatConversionFailed:
            return "Failed to create audio format converter"
        case .noInputDevice:
            return "No microphone available. In clamshell mode, connect an external microphone or headset."
        }
    }
}
