import Foundation
import os.log

/// Errors that can occur during transcription
enum TranscriptionError: Error, LocalizedError {
    case noAPIKey
    case missingModel
    case invalidAudioFile
    case networkError(underlying: Error)
    case apiError(statusCode: Int, message: String)
    case rateLimited
    case invalidResponse

    var errorDescription: String? {
        switch self {
        case .noAPIKey:
            return "No OpenRouter API key configured. Please add your API key in Preferences."
        case .missingModel:
            return "No STT model configured. Please select a model in Preferences."
        case .invalidAudioFile:
            return "The audio file could not be read."
        case .networkError(let error):
            return "Network error: \(error.localizedDescription)"
        case .apiError(let code, let message):
            return "API error (\(code)): \(message)"
        case .rateLimited:
            return "Rate limited. Please wait a moment and try again."
        case .invalidResponse:
            return "Invalid response from OpenRouter API."
        }
    }
}

/// Error response from OpenAI-compatible API
struct OpenAIErrorResponse: Decodable {
    struct ErrorDetail: Decodable {
        let message: String
        let type: String?
        let code: String?
    }
    let error: ErrorDetail
}

/// Service responsible for transcribing audio using an OpenAI-compatible API
@MainActor
final class TranscriptionService {
    private let logger = Logger(subsystem: "com.whisperai.app", category: "Transcription")
    private let whisperEndpoint = "https://openrouter.ai/api/v1/chat/completions"

    /// Whether code-switching mode is enabled (use auto-detect for better mixed-language support)
    var isCodeSwitchingEnabled: Bool {
        UserDefaults.standard.bool(forKey: "enableCodeSwitching")
    }

    /// Model used for STT
    var sttModel: String? {
        let value = UserDefaults.standard.string(forKey: "sttModel")?.trimmingCharacters(in: .whitespacesAndNewlines)
        return (value?.isEmpty == false) ? value : nil
    }

    init() {}

    /// Transcribe audio file using OpenRouter (audio input via chat completions)
    /// - Parameters:
    ///   - audioURL: URL to the audio file
    ///   - language: Optional language code (e.g., "en", "es"). If nil or code-switching enabled, auto-detect.
    /// - Returns: Transcribed text
    func transcribe(audioURL: URL, language: String? = nil) async throws -> String {
        // Get API key from keychain
        guard let apiKey = KeychainService.shared.getAPIKey(), !apiKey.isEmpty else {
            throw TranscriptionError.noAPIKey
        }
        guard let model = sttModel else {
            throw TranscriptionError.missingModel
        }

        // Read audio file
        let audioData: Data
        do {
            audioData = try Data(contentsOf: audioURL)
        } catch {
            logger.error("Failed to read audio file: \(error.localizedDescription)")
            throw TranscriptionError.invalidAudioFile
        }

        let audioFormat = normalizedAudioFormat(from: audioURL)
        let audioBase64 = audioData.base64EncodedString()

        let languageHint: String
        if let lang = language, !isCodeSwitchingEnabled {
            languageHint = "Language hint: \(lang)."
        } else {
            languageHint = "Detect language automatically (may include code-switching)."
        }

        let systemPrompt = """
        You are a speech-to-text transcriber. Transcribe the audio and return a clean, final text.

        Rules:
        1. Preserve the original language(s). Do NOT translate.
        2. Remove filler words, elongated fillers (e.g., \"uuummmm\", \"aaaahhh\"), stutters, and repeated phrases.
        3. Resolve self-corrections: if the speaker corrects themselves (e.g., \"2+2, no mejor 3+2\"), output ONLY the corrected version.
        4. Remove false starts and abandoned sentence beginnings.
        5. Add punctuation and capitalization for readability.
        6. Keep numbers and expressions as spoken; do not solve them.
        7. Return ONLY the cleaned transcript, no explanations.

        \(languageHint)
        """

        let userContent: [[String: Any]] = [
            ["type": "input_text", "text": "Transcribe the audio following the system rules."],
            ["type": "input_audio", "input_audio": ["data": audioBase64, "format": audioFormat]]
        ]

        let requestBody: [String: Any] = [
            "model": model,
            "messages": [
                ["role": "system", "content": systemPrompt],
                ["role": "user", "content": userContent]
            ],
            "temperature": 0.2,
            "max_tokens": 1024
        ]

        var request = URLRequest(url: URL(string: whisperEndpoint)!)
        request.httpMethod = "POST"
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("Whisper-AI", forHTTPHeaderField: "X-Title")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: requestBody)

        // Make request
        let (data, response): (Data, URLResponse)
        do {
            (data, response) = try await URLSession.shared.data(for: request)
        } catch {
            logger.error("Network error: \(error.localizedDescription)")
            throw TranscriptionError.networkError(underlying: error)
        }

        // Check HTTP response
        guard let httpResponse = response as? HTTPURLResponse else {
            throw TranscriptionError.invalidResponse
        }

        // Handle error responses
        if httpResponse.statusCode != 200 {
            // Try to parse error response
            if let errorResponse = try? JSONDecoder().decode(OpenAIErrorResponse.self, from: data) {
                if httpResponse.statusCode == 429 {
                    throw TranscriptionError.rateLimited
                }
                throw TranscriptionError.apiError(
                    statusCode: httpResponse.statusCode,
                    message: errorResponse.error.message
                )
            }
            throw TranscriptionError.apiError(
                statusCode: httpResponse.statusCode,
                message: "Unknown error"
            )
        }

        // Parse successful response
        let responseBody: ChatCompletionResponse
        do {
            responseBody = try JSONDecoder().decode(ChatCompletionResponse.self, from: data)
        } catch {
            logger.error("Failed to parse response: \(error.localizedDescription)")
            throw TranscriptionError.invalidResponse
        }

        guard let text = responseBody.choices.first?.message.content else {
            throw TranscriptionError.invalidResponse
        }

        logger.info("Transcription successful: \(text.prefix(50))...")
        return text
    }
}

private extension TranscriptionService {
    struct ChatCompletionResponse: Decodable {
        struct Choice: Decodable {
            struct Message: Decodable {
                let content: String
            }
            let message: Message
        }
        let choices: [Choice]
    }

    func normalizedAudioFormat(from url: URL) -> String {
        let ext = url.pathExtension.lowercased()
        let allowed = ["wav", "mp3", "m4a", "flac", "ogg", "webm", "aac"]
        return allowed.contains(ext) ? ext : "wav"
    }
}
