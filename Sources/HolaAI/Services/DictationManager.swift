import AppKit
import AVFoundation
import Foundation
import os.log

/// Manages the overall dictation workflow
@MainActor
final class DictationManager: AudioCaptureDelegate {
    static let shared = DictationManager()

    private let logger = Logger(subsystem: "com.holaai.app", category: "DictationManager")
    private let audioCapture = AudioCaptureService()
    private let transcriptionService = TranscriptionService()
    private let textProcessingService = TextProcessingService()
    private let textInsertionService = TextInsertionService()
    private let voiceCommandService = VoiceCommandService.shared

    /// Current dictation state
    private(set) var isRecording = false

    /// Whether transcription is in progress
    private(set) var isTranscribing = false

    /// Current intent for this dictation session
    private var currentIntent: DictationIntent = .transcription
    private var translateToEnglish: Bool = false

    /// Selected language for transcription (nil = auto-detect)
    var transcriptionLanguage: String? {
        get { UserDefaults.standard.string(forKey: "transcriptionLanguage") }
        set { UserDefaults.standard.set(newValue, forKey: "transcriptionLanguage") }
    }

    /// Callback for state changes (isRecording)
    var onStateChange: ((Bool) -> Void)?

    /// Callback for transcription state changes
    var onTranscribingChange: ((Bool) -> Void)?

    /// Callback for audio level updates
    var onAudioLevelUpdate: ((Float) -> Void)?

    /// Callback for errors
    var onError: ((Error) -> Void)?

    /// Callback when transcription is ready
    var onTranscriptionReady: ((String) -> Void)?

    /// Callback when command mode changes
    var onCommandModeChange: ((DictationMode) -> Void)?

    /// Current command mode
    var currentMode: DictationMode {
        voiceCommandService.mode
    }

    /// Whether to automatically insert text after transcription
    var autoInsertText: Bool {
        get { UserDefaults.standard.bool(forKey: "autoInsertText") }
        set { UserDefaults.standard.set(newValue, forKey: "autoInsertText") }
    }

    private init() {
        audioCapture.delegate = self
        // Default to auto-insert enabled
        if UserDefaults.standard.object(forKey: "autoInsertText") == nil {
            autoInsertText = true
        }

        // Wire up voice command service callbacks
        voiceCommandService.onModeChange = { [weak self] mode in
            self?.onCommandModeChange?(mode)
        }
    }

    /// Toggle command mode
    func toggleCommandMode() {
        voiceCommandService.toggleMode()
    }

    /// Toggle dictation on/off
    func toggleDictation(intent: DictationIntent = .transcription, translateToEnglish: Bool = false) async {
        if isRecording {
            await stopDictation()
        } else {
            await startDictation(intent: intent, translateToEnglish: translateToEnglish)
        }
    }

    /// Start dictation (request permission and begin recording)
    func startDictation(intent: DictationIntent = .transcription, translateToEnglish: Bool = false) async {
        guard !isRecording else {
            print("⚠️ [DictationManager] Already recording, ignoring start request")
            return
        }

        // Check for API key first
        guard KeychainService.shared.hasAPIKey else {
            print("❌ [DictationManager] No API key configured!")
            onError?(TranscriptionError.noAPIKey)
            return
        }

        currentIntent = intent
        self.translateToEnglish = translateToEnglish
        print("✅ [DictationManager] API key found")

        do {
            print("🎙️ [DictationManager] Starting audio capture...")
            try await audioCapture.startRecording()
            isRecording = true
            onStateChange?(true)
            print("🎙️ [DictationManager] Recording started successfully")
            logger.info("Dictation started")
        } catch {
            print("❌ [DictationManager] Failed to start: \(error.localizedDescription)")
            logger.error("Failed to start dictation: \(error.localizedDescription)")
            onError?(error)
        }
    }

    /// Stop dictation and process audio
    func stopDictation() async {
        guard isRecording else {
            print("⚠️ [DictationManager] Not recording, ignoring stop request")
            return
        }

        print("🛑 [DictationManager] Stopping recording...")
        guard let audioURL = audioCapture.stopRecording() else {
            print("❌ [DictationManager] No audio file returned!")
            isRecording = false
            onStateChange?(false)
            return
        }

        isRecording = false
        onStateChange?(false)
        print("✅ [DictationManager] Audio saved to: \(audioURL.path)")

        // Check file size
        if let attrs = try? FileManager.default.attributesOfItem(atPath: audioURL.path),
           let size = attrs[.size] as? Int64 {
            print("📁 [DictationManager] Audio file size: \(size) bytes")
        }

        logger.info("Dictation stopped, audio saved to: \(audioURL.path)")

        // Start transcription
        await transcribeAudio(at: audioURL)
    }

    /// Transcribe audio file
    private func transcribeAudio(at url: URL) async {
        isTranscribing = true
        onTranscribingChange?(true)
        print("🔄 [DictationManager] Starting transcription...")

        do {
            print("📡 [DictationManager] Sending audio to Whisper API...")
            let text = try await transcriptionService.transcribe(
                audioURL: url,
                language: transcriptionLanguage
            )

            print("✅ [DictationManager] Transcription received: \"\(text)\"")
            logger.info("Transcription complete: \(text.prefix(50))...")

            // Check if in command mode - process as command instead of dictation
            if voiceCommandService.mode == .command {
                print("🎯 [DictationManager] Command mode - processing as command")
                let wasCommand = voiceCommandService.processInput(text)
                if wasCommand {
                    logger.info("Processed as voice command")
                }
                // Clean up audio file
                try? FileManager.default.removeItem(at: url)
                isTranscribing = false
                onTranscribingChange?(false)
                return
            }

            let processedText: String
            switch currentIntent {
            case .prompt:
                print("✨ [DictationManager] Enhancing prompt with LLM...")
                if textProcessingService.promptEnhancementModel == nil {
                    throw TextProcessingError.missingModel
                }
                processedText = await textProcessingService.processPromptAsync(text, language: transcriptionLanguage)
                print("✅ [DictationManager] Enhanced prompt: \"\(processedText)\"")
                logger.info("Prompt enhanced: \(processedText.prefix(50))...")
            case .transcription:
                print("✨ [DictationManager] Cleaning transcription with semantic correction...")
                let cleaned = await textProcessingService.processTextAsync(text, language: transcriptionLanguage)
                if translateToEnglish {
                    print("🌐 [DictationManager] Translating to English...")
                    processedText = await textProcessingService.translateTextToEnglish(cleaned, language: transcriptionLanguage)
                } else {
                    processedText = cleaned
                }
                print("✅ [DictationManager] Processed text: \"\(processedText)\"")
                logger.info("Text processed: \(processedText.prefix(50))...")
            }

            // Track last inserted text for "delete that" command
            _ = voiceCommandService.processInput(processedText)

            // Insert text if enabled
            if autoInsertText {
                print("📝 [DictationManager] Inserting text into active app...")
                do {
                    try textInsertionService.insertText(processedText)
                    print("✅ [DictationManager] Text inserted successfully!")
                    logger.info("Text inserted successfully")
                } catch {
                    print("❌ [DictationManager] Text insertion FAILED: \(error.localizedDescription)")
                    logger.error("Text insertion failed: \(error.localizedDescription)")
                    onError?(error)
                }
            } else {
                print("⏭️ [DictationManager] Auto-insert disabled, skipping insertion")
            }

            onTranscriptionReady?(processedText)

            // Clean up audio file
            try? FileManager.default.removeItem(at: url)

        } catch {
            print("❌ [DictationManager] Transcription FAILED: \(error)")
            print("❌ [DictationManager] Error details: \(error.localizedDescription)")
            logger.error("Transcription failed: \(error.localizedDescription)")
            onError?(error)

            // Clean up audio file even on error
            try? FileManager.default.removeItem(at: url)
        }

        isTranscribing = false
        onTranscribingChange?(false)
        print("🏁 [DictationManager] Transcription process complete")
    }

    /// Check if microphone permission is granted
    var hasMicrophonePermission: Bool {
        audioCapture.permissionStatus == .authorized
    }

    /// Check if accessibility permission is granted
    var hasAccessibilityPermission: Bool {
        textInsertionService.hasAccessibilityPermission
    }

    /// Request microphone permission
    func requestMicrophonePermission() async -> Bool {
        let granted = await audioCapture.requestPermission()
        if !granted {
            let status = audioCapture.permissionStatus
            if status == .denied || status == .restricted,
               let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Microphone") {
                NSWorkspace.shared.open(url)
            }
        }
        return granted
    }

    /// Request accessibility permission (opens System Settings)
    func requestAccessibilityPermission() {
        textInsertionService.requestAccessibilityPermission()
    }

    // MARK: - AudioCaptureDelegate

    nonisolated func audioCaptureDidStart() {
        Task { @MainActor in
            logger.info("Audio capture started")
        }
    }

    nonisolated func audioCaptureDidStop(audioFileURL: URL) {
        Task { @MainActor in
            logger.info("Audio capture stopped: \(audioFileURL.path)")
        }
    }

    nonisolated func audioCaptureDidFail(error: AudioCaptureError) {
        Task { @MainActor in
            logger.error("Audio capture failed: \(error.localizedDescription)")
            onError?(error)
        }
    }

    nonisolated func audioCaptureDidUpdateLevel(_ level: Float) {
        Task { @MainActor in
            onAudioLevelUpdate?(level)
        }
    }
}
