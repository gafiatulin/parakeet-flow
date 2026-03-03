@preconcurrency import AVFoundation

actor AudioCaptureManager {
    private var engine: AVAudioEngine?
    private var converter: AVAudioConverter?
    private var isCapturing = false

    /// Start capturing mic audio. Each buffer is delivered to `onBuffer`.
    /// If `targetFormat` differs from the hardware format, buffers are converted automatically.
    func startCapture(
        targetFormat: AVAudioFormat? = nil,
        onBuffer: @escaping @Sendable (AVAudioPCMBuffer) -> Void
    ) throws {
        guard !isCapturing else { return }

        let engine = AVAudioEngine()
        let inputNode = engine.inputNode
        let hardwareFormat = inputNode.outputFormat(forBus: 0)

        // Always tap in hardware-native format to avoid AVAudioEngine format mismatch
        if let target = targetFormat,
           target.sampleRate != hardwareFormat.sampleRate || target.commonFormat != hardwareFormat.commonFormat {
            // Set up converter: hardware format → target format
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
            // No conversion needed — tap in native format
            inputNode.installTap(onBus: 0, bufferSize: 4096, format: hardwareFormat) { buffer, _ in
                onBuffer(buffer)
            }
        }

        engine.prepare()
        try engine.start()

        self.engine = engine
        self.isCapturing = true
    }

    func stopCapture() {
        guard isCapturing else { return }

        engine?.inputNode.removeTap(onBus: 0)
        engine?.stop()
        engine = nil
        converter = nil
        isCapturing = false
    }
}

enum AudioCaptureError: LocalizedError {
    case formatConversionFailed

    var errorDescription: String? {
        "Failed to create audio format converter"
    }
}
