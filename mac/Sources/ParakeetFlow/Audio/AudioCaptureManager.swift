@preconcurrency import AVFoundation
import AudioToolbox
import CoreAudio
import IOKit

/// Context shared with the real-time CoreAudio input callback via raw pointer.
private final class CaptureContext: @unchecked Sendable {
    let audioUnit: AudioComponentInstance
    let format: AVAudioFormat
    let targetFormat: AVAudioFormat?
    let converter: AVAudioConverter?
    let sampleRateRatio: Double
    let onBuffer: @Sendable (AVAudioPCMBuffer) -> Void

    init(audioUnit: AudioComponentInstance, format: AVAudioFormat,
         targetFormat: AVAudioFormat?, converter: AVAudioConverter?,
         onBuffer: @escaping @Sendable (AVAudioPCMBuffer) -> Void) {
        self.audioUnit = audioUnit
        self.format = format
        self.targetFormat = targetFormat
        self.converter = converter
        self.sampleRateRatio = if let t = targetFormat { t.sampleRate / format.sampleRate } else { 1.0 }
        self.onBuffer = onBuffer
    }
}

/// CoreAudio HAL input render callback — runs on the real-time I/O thread.
private let halInputCallback: AURenderCallback = {
    refCon, ioActionFlags, inTimeStamp, inBusNumber, inNumberFrames, _ in
    let ctx = Unmanaged<CaptureContext>.fromOpaque(refCon).takeUnretainedValue()

    guard let buffer = AVAudioPCMBuffer(pcmFormat: ctx.format, frameCapacity: inNumberFrames) else {
        return kAudioUnitErr_FailedInitialization
    }
    buffer.frameLength = inNumberFrames

    let status = AudioUnitRender(
        ctx.audioUnit, ioActionFlags, inTimeStamp,
        inBusNumber, inNumberFrames, buffer.mutableAudioBufferList)
    guard status == noErr else { return status }

    if let converter = ctx.converter, let target = ctx.targetFormat {
        let outFrames = AVAudioFrameCount(Double(inNumberFrames) * ctx.sampleRateRatio)
        guard let converted = AVAudioPCMBuffer(pcmFormat: target, frameCapacity: outFrames) else {
            return noErr
        }
        var error: NSError?
        converter.convert(to: converted, error: &error) { _, outStatus in
            outStatus.pointee = .haveData
            return buffer
        }
        if error == nil, converted.frameLength > 0 {
            ctx.onBuffer(converted)
        }
    } else {
        ctx.onBuffer(buffer)
    }

    return noErr
}

actor AudioCaptureManager {
    private var audioUnit: AudioComponentInstance?
    private var isCapturing = false
    private var contextRef: Unmanaged<CaptureContext>?
    private var deviceListenerBlock: AudioObjectPropertyListenerBlock?

    private var activeTargetFormat: AVAudioFormat?
    private var activeCallback: (@Sendable (AVAudioPCMBuffer) -> Void)?

    /// Start capturing mic audio via CoreAudio HAL (AUHAL).
    /// Uses the HAL audio unit directly — no AVAudioEngine, no aggregate device creation.
    func startCapture(
        targetFormat: AVAudioFormat? = nil,
        onBuffer: @escaping @Sendable (AVAudioPCMBuffer) -> Void
    ) throws {
        guard !isCapturing else { return }
        guard Self.hasUsableAudioInput() else { throw AudioCaptureError.noInputDevice }

        activeTargetFormat = targetFormat
        activeCallback = onBuffer

        try openAndStart(targetFormat: targetFormat, onBuffer: onBuffer)
        installDeviceChangeListener()
        isCapturing = true
    }

    func stopCapture() {
        guard isCapturing else { return }
        removeDeviceChangeListener()
        closeAudioUnit()
        activeTargetFormat = nil
        activeCallback = nil
        isCapturing = false
    }

    // MARK: - Audio Unit lifecycle

    private func openAndStart(
        targetFormat: AVAudioFormat?,
        onBuffer: @escaping @Sendable (AVAudioPCMBuffer) -> Void
    ) throws {
        var desc = AudioComponentDescription(
            componentType: kAudioUnitType_Output,
            componentSubType: kAudioUnitSubType_HALOutput,
            componentManufacturer: kAudioUnitManufacturer_Apple,
            componentFlags: 0, componentFlagsMask: 0)
        guard let comp = AudioComponentFindNext(nil, &desc) else {
            throw AudioCaptureError.componentNotFound
        }
        var optAU: AudioComponentInstance?
        guard AudioComponentInstanceNew(comp, &optAU) == noErr, let au = optAU else {
            throw AudioCaptureError.componentNotFound
        }

        do {
            try configureAndStart(au, targetFormat: targetFormat, onBuffer: onBuffer)
            self.audioUnit = au
        } catch {
            AudioComponentInstanceDispose(au)
            throw error
        }
    }

    private func configureAndStart(
        _ au: AudioComponentInstance,
        targetFormat: AVAudioFormat?,
        onBuffer: @escaping @Sendable (AVAudioPCMBuffer) -> Void
    ) throws {
        // Enable input (element 1), disable output (element 0).
        // Input-only prevents AUHAL from creating an aggregate device.
        var one: UInt32 = 1, zero: UInt32 = 0
        try osCheck(AudioUnitSetProperty(au, kAudioOutputUnitProperty_EnableIO,
            kAudioUnitScope_Input, 1, &one, size(of: UInt32.self)))
        try osCheck(AudioUnitSetProperty(au, kAudioOutputUnitProperty_EnableIO,
            kAudioUnitScope_Output, 0, &zero, size(of: UInt32.self)))

        // Set the default input device.
        var deviceID = try Self.defaultInputDeviceID()
        try osCheck(AudioUnitSetProperty(au, kAudioOutputUnitProperty_CurrentDevice,
            kAudioUnitScope_Global, 0, &deviceID, size(of: AudioDeviceID.self)))

        // Query the device's native stream format (input scope, element 1).
        var nativeASBD = AudioStreamBasicDescription()
        var asbdSize = UInt32(MemoryLayout<AudioStreamBasicDescription>.size)
        try osCheck(AudioUnitGetProperty(au, kAudioUnitProperty_StreamFormat,
            kAudioUnitScope_Input, 1, &nativeASBD, &asbdSize))

        // Request mono Float32 at the device's sample rate on the output scope.
        // AUHAL handles channel mixing and int-to-float; sample rate conversion
        // is done separately via AVAudioConverter when needed.
        var outputASBD = AudioStreamBasicDescription(
            mSampleRate: nativeASBD.mSampleRate,
            mFormatID: kAudioFormatLinearPCM,
            mFormatFlags: kAudioFormatFlagIsFloat | kAudioFormatFlagIsPacked | kAudioFormatFlagIsNonInterleaved,
            mBytesPerPacket: 4, mFramesPerPacket: 1, mBytesPerFrame: 4,
            mChannelsPerFrame: 1, mBitsPerChannel: 32, mReserved: 0)
        try osCheck(AudioUnitSetProperty(au, kAudioUnitProperty_StreamFormat,
            kAudioUnitScope_Output, 1, &outputASBD, size(of: AudioStreamBasicDescription.self)))

        // Build AVAudioFormat matching the AUHAL output.
        guard let hwFormat = AVAudioFormat(commonFormat: .pcmFormatFloat32,
            sampleRate: nativeASBD.mSampleRate, channels: 1, interleaved: false) else {
            throw AudioCaptureError.formatConversionFailed
        }

        // AVAudioConverter for sample rate / format conversion when the consumer
        // needs something different from the device's native rate.
        let converter: AVAudioConverter?
        if let t = targetFormat,
           t.sampleRate != hwFormat.sampleRate || t.commonFormat != hwFormat.commonFormat {
            guard let c = AVAudioConverter(from: hwFormat, to: t) else {
                throw AudioCaptureError.formatConversionFailed
            }
            converter = c
        } else {
            converter = nil
        }

        // Create callback context and set the input callback.
        let ctx = CaptureContext(audioUnit: au, format: hwFormat,
            targetFormat: targetFormat, converter: converter, onBuffer: onBuffer)
        let ref = Unmanaged.passRetained(ctx)

        do {
            var cb = AURenderCallbackStruct(inputProc: halInputCallback, inputProcRefCon: ref.toOpaque())
            try osCheck(AudioUnitSetProperty(au, kAudioOutputUnitProperty_SetInputCallback,
                kAudioUnitScope_Global, 0, &cb, size(of: AURenderCallbackStruct.self)))
            try osCheck(AudioUnitInitialize(au))
            let startStatus = AudioOutputUnitStart(au)
            guard startStatus == noErr else {
                AudioUnitUninitialize(au)
                throw AudioCaptureError.audioUnitError(startStatus)
            }
        } catch {
            ref.release()
            throw error
        }

        self.contextRef = ref
    }

    private func closeAudioUnit() {
        if let au = audioUnit {
            AudioOutputUnitStop(au)
            AudioUnitUninitialize(au)
            AudioComponentInstanceDispose(au)
            audioUnit = nil
        }
        if let ref = contextRef {
            ref.release()
            contextRef = nil
        }
    }

    // MARK: - Default device change

    private func installDeviceChangeListener() {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDefaultInputDevice,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain)
        let block: AudioObjectPropertyListenerBlock = { [weak self] _, _ in
            Task { [weak self] in await self?.handleDeviceChange() }
        }
        AudioObjectAddPropertyListenerBlock(
            AudioObjectID(kAudioObjectSystemObject), &address, nil, block)
        deviceListenerBlock = block
    }

    private func removeDeviceChangeListener() {
        guard let block = deviceListenerBlock else { return }
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDefaultInputDevice,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain)
        AudioObjectRemovePropertyListenerBlock(
            AudioObjectID(kAudioObjectSystemObject), &address, nil, block)
        deviceListenerBlock = nil
    }

    private func handleDeviceChange() {
        guard isCapturing, let callback = activeCallback else { return }
        closeAudioUnit()
        do {
            try openAndStart(targetFormat: activeTargetFormat, onBuffer: callback)
        } catch {
            stopCapture()
        }
    }

    // MARK: - Helpers

    private static func defaultInputDeviceID() throws -> AudioDeviceID {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDefaultInputDevice,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain)
        var deviceID: AudioDeviceID = kAudioObjectUnknown
        var size = UInt32(MemoryLayout<AudioDeviceID>.size)
        guard AudioObjectGetPropertyData(
            AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, &size, &deviceID
        ) == noErr, deviceID != kAudioObjectUnknown else {
            throw AudioCaptureError.noInputDevice
        }
        return deviceID
    }

    /// Check whether the default input device can actually capture audio.
    /// Returns false when in clamshell mode with only the built-in mic available.
    nonisolated static func hasUsableAudioInput() -> Bool {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDefaultInputDevice,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain)
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
            mElement: kAudioObjectPropertyElementMain)
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
            kIOMainPortDefault, IOServiceMatching("IOPMrootDomain"))
        guard service != IO_OBJECT_NULL else { return false }
        defer { IOObjectRelease(service) }

        guard let prop = IORegistryEntryCreateCFProperty(
            service, "AppleClamshellState" as CFString, kCFAllocatorDefault, 0
        )?.takeRetainedValue() else {
            return false
        }
        return (prop as? Bool) ?? false
    }

    private func osCheck(_ status: OSStatus) throws {
        if status != noErr { throw AudioCaptureError.audioUnitError(status) }
    }

    private func size<T>(of _: T.Type) -> UInt32 {
        UInt32(MemoryLayout<T>.size)
    }
}

enum AudioCaptureError: LocalizedError {
    case formatConversionFailed
    case noInputDevice
    case componentNotFound
    case audioUnitError(OSStatus)

    var errorDescription: String? {
        switch self {
        case .formatConversionFailed:
            return "Failed to create audio format converter"
        case .noInputDevice:
            return "No microphone available. In clamshell mode, connect an external microphone or headset."
        case .componentNotFound:
            return "Audio input component not found"
        case .audioUnitError(let status):
            return "Audio unit error (OSStatus \(status))"
        }
    }
}
