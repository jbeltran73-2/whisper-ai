import AVFoundation
import os.log
import Accelerate

/// Errors that can occur during audio capture
enum AudioCaptureError: Error, LocalizedError, Sendable {
    case permissionDenied
    case permissionNotDetermined
    case captureSessionFailed(underlying: Error)
    case noInputDevice
    case fileCreationFailed
    case encoderError

    var errorDescription: String? {
        switch self {
        case .permissionDenied:
            return "Microphone access was denied. Please enable it in System Settings > Privacy & Security > Microphone."
        case .permissionNotDetermined:
            return "Microphone permission has not been requested yet."
        case .captureSessionFailed(let error):
            return "Audio capture failed: \(error.localizedDescription)"
        case .noInputDevice:
            return "No microphone input device found."
        case .fileCreationFailed:
            return "Failed to create audio output file."
        case .encoderError:
            return "Audio encoding error occurred."
        }
    }
}

/// Protocol for audio capture delegate callbacks - all called on main thread
protocol AudioCaptureDelegate: AnyObject {
    func audioCaptureDidStart()
    func audioCaptureDidStop(audioFileURL: URL)
    func audioCaptureDidFail(error: AudioCaptureError)
    func audioCaptureDidUpdateLevel(_ level: Float)
}

/// Thread-safe audio buffer that accumulates samples
private final class AudioBuffer: @unchecked Sendable {
    private let lock = NSLock()
    private var samples: [Float] = []
    private var _currentLevel: Float = 0

    var currentLevel: Float {
        lock.lock()
        defer { lock.unlock() }
        return _currentLevel
    }

    func append(_ buffer: AVAudioPCMBuffer) {
        guard let channelData = buffer.floatChannelData?[0] else { return }
        let frameLength = Int(buffer.frameLength)

        // Calculate level
        var sum: Float = 0
        for i in 0..<frameLength {
            sum += abs(channelData[i])
        }
        let averageLevel = sum / Float(frameLength)
        let db = 20 * log10(max(averageLevel, 0.0001))
        let normalizedLevel = max(0, min(1, (db + 60) / 60))

        lock.lock()
        // Append samples
        samples.append(contentsOf: UnsafeBufferPointer(start: channelData, count: frameLength))
        _currentLevel = normalizedLevel
        lock.unlock()
    }

    func getSamplesAndClear() -> [Float] {
        lock.lock()
        defer { lock.unlock() }
        let result = samples
        samples = []
        _currentLevel = 0
        return result
    }

    func clear() {
        lock.lock()
        samples = []
        _currentLevel = 0
        lock.unlock()
    }
}

/// Service responsible for capturing audio from the microphone
/// Uses AVAudioEngine with in-memory buffer to avoid Swift 6 concurrency issues
final class AudioCaptureService: NSObject, @unchecked Sendable {
    private let logger = Logger(subsystem: "com.whisperai.app", category: "AudioCapture")

    private var audioEngine: AVAudioEngine?
    private var audioBuffer: AudioBuffer?
    private var levelTimer: Timer?
    private var isRecording = false
    private var inputSampleRate: Double = 44100

    weak var delegate: AudioCaptureDelegate?

    deinit {
        levelTimer?.invalidate()
        audioEngine?.stop()
    }

    /// Check current microphone permission status
    var permissionStatus: AVAuthorizationStatus {
        AVCaptureDevice.authorizationStatus(for: .audio)
    }

    /// Request microphone permission
    func requestPermission() async -> Bool {
        let status = permissionStatus

        switch status {
        case .authorized:
            return true
        case .notDetermined:
            return await AVCaptureDevice.requestAccess(for: .audio)
        case .denied, .restricted:
            return false
        @unknown default:
            return false
        }
    }

    /// Start recording audio to memory buffer
    func startRecording() async throws {
        guard !isRecording else {
            logger.warning("Already recording")
            return
        }

        // Check permission first
        let hasPermission = await requestPermission()
        guard hasPermission else {
            let error = AudioCaptureError.permissionDenied
            DispatchQueue.main.async { [weak self] in
                self?.delegate?.audioCaptureDidFail(error: error)
            }
            throw error
        }

        // Clean up any previous state
        cleanup()

        do {
            try setupAudioEngine()
            try audioEngine?.start()
            isRecording = true

            // Start level monitoring on main thread
            DispatchQueue.main.async { [weak self] in
                self?.startLevelMonitoring()
                self?.delegate?.audioCaptureDidStart()
            }

            logger.info("Audio capture started")
        } catch {
            cleanup()
            let captureError = AudioCaptureError.captureSessionFailed(underlying: error)
            DispatchQueue.main.async { [weak self] in
                self?.delegate?.audioCaptureDidFail(error: captureError)
            }
            throw captureError
        }
    }

    /// Stop recording and return the audio file URL
    func stopRecording() -> URL? {
        guard isRecording else {
            logger.warning("Not currently recording")
            return nil
        }

        isRecording = false

        // Stop level monitoring
        DispatchQueue.main.async { [weak self] in
            self?.levelTimer?.invalidate()
            self?.levelTimer = nil
        }

        // Stop engine and remove tap
        audioEngine?.stop()
        audioEngine?.inputNode.removeTap(onBus: 0)

        // Get samples and write to file
        guard let buffer = audioBuffer else {
            cleanup()
            return nil
        }

        let samples = buffer.getSamplesAndClear()
        guard !samples.isEmpty else {
            cleanup()
            return nil
        }

        // Write samples to WAV file
        let outputURL = createOutputFileURL()

        do {
            try writeWAVFile(samples: samples, sampleRate: inputSampleRate, to: outputURL)
            logger.info("Audio capture stopped, file saved to: \(outputURL.path)")

            DispatchQueue.main.async { [weak self] in
                self?.delegate?.audioCaptureDidStop(audioFileURL: outputURL)
            }

            cleanup()
            return outputURL
        } catch {
            logger.error("Failed to write audio file: \(error.localizedDescription)")
            cleanup()
            return nil
        }
    }

    // MARK: - Private Methods

    private func cleanup() {
        levelTimer?.invalidate()
        levelTimer = nil

        // Important: Remove tap BEFORE stopping the engine
        if let engine = audioEngine {
            // Remove tap first
            engine.inputNode.removeTap(onBus: 0)

            // Stop engine if running
            if engine.isRunning {
                engine.stop()
            }

            // Reset the engine to clear internal state
            engine.reset()
        }

        // Clear buffer before releasing engine
        audioBuffer?.clear()
        audioBuffer = nil

        // Finally release the engine
        audioEngine = nil
    }

    private func setupAudioEngine() throws {
        let engine = AVAudioEngine()
        let inputNode = engine.inputNode
        let inputFormat = inputNode.outputFormat(forBus: 0)

        guard inputFormat.sampleRate > 0 else {
            throw AudioCaptureError.noInputDevice
        }

        inputSampleRate = inputFormat.sampleRate

        // Create buffer to accumulate samples
        let buffer = AudioBuffer()
        audioBuffer = buffer

        // Recording format - mono float for processing
        let recordingFormat = AVAudioFormat(
            commonFormat: .pcmFormatFloat32,
            sampleRate: inputFormat.sampleRate,
            channels: 1,
            interleaved: false
        )!

        // Install tap - the closure captures only the buffer, not self
        inputNode.installTap(onBus: 0, bufferSize: 4096, format: recordingFormat) { [buffer] pcmBuffer, _ in
            buffer.append(pcmBuffer)
        }

        audioEngine = engine
    }

    private func startLevelMonitoring() {
        levelTimer = Timer.scheduledTimer(withTimeInterval: 1.0 / 30.0, repeats: true) { [weak self] _ in
            guard let self = self, self.isRecording else { return }
            let level = self.audioBuffer?.currentLevel ?? 0
            self.delegate?.audioCaptureDidUpdateLevel(level)
        }
    }

    private func createOutputFileURL() -> URL {
        let tempDir = FileManager.default.temporaryDirectory
        let fileName = "whisperai_recording_\(Date().timeIntervalSince1970).wav"
        return tempDir.appendingPathComponent(fileName)
    }

    /// Write float samples to a 16-bit WAV file
    private func writeWAVFile(samples: [Float], sampleRate: Double, to url: URL) throws {
        // Resample to 16kHz if needed (Whisper prefers 16kHz)
        let targetSampleRate: Double = 16000
        let finalSamples: [Float]

        if abs(sampleRate - targetSampleRate) > 1 {
            finalSamples = resample(samples, from: sampleRate, to: targetSampleRate)
        } else {
            finalSamples = samples
        }

        // Convert to 16-bit PCM
        var int16Samples = [Int16](repeating: 0, count: finalSamples.count)
        for i in 0..<finalSamples.count {
            let sample = max(-1.0, min(1.0, finalSamples[i]))
            int16Samples[i] = Int16(sample * 32767)
        }

        // Build WAV header
        let numChannels: UInt16 = 1
        let bitsPerSample: UInt16 = 16
        let byteRate = UInt32(targetSampleRate) * UInt32(numChannels) * UInt32(bitsPerSample / 8)
        let blockAlign = numChannels * (bitsPerSample / 8)
        let dataSize = UInt32(int16Samples.count * 2)
        let fileSize = 36 + dataSize

        var header = Data()

        // RIFF header
        header.append(contentsOf: "RIFF".utf8)
        header.append(contentsOf: withUnsafeBytes(of: fileSize.littleEndian) { Array($0) })
        header.append(contentsOf: "WAVE".utf8)

        // fmt chunk
        header.append(contentsOf: "fmt ".utf8)
        header.append(contentsOf: withUnsafeBytes(of: UInt32(16).littleEndian) { Array($0) })
        header.append(contentsOf: withUnsafeBytes(of: UInt16(1).littleEndian) { Array($0) }) // PCM
        header.append(contentsOf: withUnsafeBytes(of: numChannels.littleEndian) { Array($0) })
        header.append(contentsOf: withUnsafeBytes(of: UInt32(targetSampleRate).littleEndian) { Array($0) })
        header.append(contentsOf: withUnsafeBytes(of: byteRate.littleEndian) { Array($0) })
        header.append(contentsOf: withUnsafeBytes(of: blockAlign.littleEndian) { Array($0) })
        header.append(contentsOf: withUnsafeBytes(of: bitsPerSample.littleEndian) { Array($0) })

        // data chunk
        header.append(contentsOf: "data".utf8)
        header.append(contentsOf: withUnsafeBytes(of: dataSize.littleEndian) { Array($0) })

        // Write file
        var fileData = header
        int16Samples.withUnsafeBufferPointer { buffer in
            fileData.append(UnsafeBufferPointer(start: UnsafeRawPointer(buffer.baseAddress)?.assumingMemoryBound(to: UInt8.self), count: buffer.count * 2))
        }

        try fileData.write(to: url)
    }

    /// Simple linear resampling
    private func resample(_ samples: [Float], from sourceSampleRate: Double, to targetSampleRate: Double) -> [Float] {
        let ratio = sourceSampleRate / targetSampleRate
        let newCount = Int(Double(samples.count) / ratio)
        var result = [Float](repeating: 0, count: newCount)

        for i in 0..<newCount {
            let srcIndex = Double(i) * ratio
            let index0 = Int(srcIndex)
            let index1 = min(index0 + 1, samples.count - 1)
            let fraction = Float(srcIndex - Double(index0))
            result[i] = samples[index0] * (1 - fraction) + samples[index1] * fraction
        }

        return result
    }
}
