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
            return "No API key configured for the selected STT provider. Please add your API key in Preferences."
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
            return "Invalid response from API."
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

/// Service responsible for transcribing audio using configurable STT providers
@MainActor
final class TranscriptionService {
    private let logger = Logger(subsystem: "com.holaai.app", category: "Transcription")

    /// Current STT provider
    var currentSTTProvider: STTProvider {
        if let raw = UserDefaults.standard.string(forKey: "sttProvider"),
           let provider = STTProvider(rawValue: raw) {
            return provider
        }
        return .groq
    }

    /// Whether code-switching mode is enabled
    var isCodeSwitchingEnabled: Bool {
        UserDefaults.standard.bool(forKey: "enableCodeSwitching")
    }

    /// Model used for STT
    var sttModel: String? {
        let value = UserDefaults.standard.string(forKey: "sttModel")?.trimmingCharacters(in: .whitespacesAndNewlines)
        return (value?.isEmpty == false) ? value : nil
    }

    init() {}

    /// Transcribe audio file using the configured STT provider
    func transcribe(audioURL: URL, language: String? = nil) async throws -> String {
        let provider = currentSTTProvider

        guard let apiKey = KeychainService.shared.getKey(for: provider.keychainAccount), !apiKey.isEmpty else {
            throw TranscriptionError.noAPIKey
        }

        let model = sttModel ?? provider.defaultModel

        switch provider {
        case .groq:
            return try await transcribeWithGroq(audioURL: audioURL, language: language, apiKey: apiKey, model: model)
        case .openrouter:
            return try await transcribeWithOpenRouter(audioURL: audioURL, language: language, apiKey: apiKey, model: model)
        }
    }

    // MARK: - Groq Whisper (multipart/form-data)

    private func transcribeWithGroq(audioURL: URL, language: String?, apiKey: String, model: String) async throws -> String {
        let audioData: Data
        do {
            audioData = try Data(contentsOf: audioURL)
        } catch {
            logger.error("Failed to read audio file: \(error.localizedDescription)")
            throw TranscriptionError.invalidAudioFile
        }

        let boundary = "Boundary-\(UUID().uuidString)"
        var body = Data()

        // file field
        let filename = audioURL.lastPathComponent
        let mimeType = "audio/wav"
        body.append("--\(boundary)\r\n".data(using: .utf8)!)
        body.append("Content-Disposition: form-data; name=\"file\"; filename=\"\(filename)\"\r\n".data(using: .utf8)!)
        body.append("Content-Type: \(mimeType)\r\n\r\n".data(using: .utf8)!)
        body.append(audioData)
        body.append("\r\n".data(using: .utf8)!)

        // model field
        body.append("--\(boundary)\r\n".data(using: .utf8)!)
        body.append("Content-Disposition: form-data; name=\"model\"\r\n\r\n".data(using: .utf8)!)
        body.append("\(model)\r\n".data(using: .utf8)!)

        // language field (if set and not code-switching)
        if let lang = language, !isCodeSwitchingEnabled {
            body.append("--\(boundary)\r\n".data(using: .utf8)!)
            body.append("Content-Disposition: form-data; name=\"language\"\r\n\r\n".data(using: .utf8)!)
            body.append("\(lang)\r\n".data(using: .utf8)!)
        }

        // response_format
        body.append("--\(boundary)\r\n".data(using: .utf8)!)
        body.append("Content-Disposition: form-data; name=\"response_format\"\r\n\r\n".data(using: .utf8)!)
        body.append("json\r\n".data(using: .utf8)!)

        body.append("--\(boundary)--\r\n".data(using: .utf8)!)

        var request = URLRequest(url: URL(string: STTProvider.groq.baseURL)!)
        request.httpMethod = "POST"
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
        request.httpBody = body

        let (data, response): (Data, URLResponse)
        do {
            (data, response) = try await URLSession.shared.data(for: request)
        } catch {
            logger.error("Network error: \(error.localizedDescription)")
            throw TranscriptionError.networkError(underlying: error)
        }

        guard let httpResponse = response as? HTTPURLResponse else {
            throw TranscriptionError.invalidResponse
        }

        if httpResponse.statusCode != 200 {
            if let errorResponse = try? JSONDecoder().decode(OpenAIErrorResponse.self, from: data) {
                if httpResponse.statusCode == 429 { throw TranscriptionError.rateLimited }
                throw TranscriptionError.apiError(statusCode: httpResponse.statusCode, message: errorResponse.error.message)
            }
            throw TranscriptionError.apiError(statusCode: httpResponse.statusCode, message: "Unknown error")
        }

        // Groq returns {"text": "..."}
        let groqResponse = try JSONDecoder().decode(GroqTranscriptionResponse.self, from: data)
        let text = groqResponse.text.trimmingCharacters(in: .whitespacesAndNewlines)

        logger.info("Groq transcription successful: \(text.prefix(50))...")
        return text
    }

    // MARK: - OpenRouter (base64 chat completions)

    private func transcribeWithOpenRouter(audioURL: URL, language: String?, apiKey: String, model: String) async throws -> String {
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
        2. Remove filler words, elongated fillers (e.g., "uuummmm", "aaaahhh"), stutters, and repeated phrases.
        3. Resolve self-corrections: if the speaker corrects themselves (e.g., "2+2, no mejor 3+2"), output ONLY the corrected version.
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

        var request = URLRequest(url: URL(string: STTProvider.openrouter.baseURL)!)
        request.httpMethod = "POST"
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("Hola-AI", forHTTPHeaderField: "X-Title")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: requestBody)

        let (data, response): (Data, URLResponse)
        do {
            (data, response) = try await URLSession.shared.data(for: request)
        } catch {
            logger.error("Network error: \(error.localizedDescription)")
            throw TranscriptionError.networkError(underlying: error)
        }

        guard let httpResponse = response as? HTTPURLResponse else {
            throw TranscriptionError.invalidResponse
        }

        if httpResponse.statusCode != 200 {
            if let errorResponse = try? JSONDecoder().decode(OpenAIErrorResponse.self, from: data) {
                if httpResponse.statusCode == 429 { throw TranscriptionError.rateLimited }
                throw TranscriptionError.apiError(statusCode: httpResponse.statusCode, message: errorResponse.error.message)
            }
            throw TranscriptionError.apiError(statusCode: httpResponse.statusCode, message: "Unknown error")
        }

        let responseBody = try JSONDecoder().decode(ChatCompletionResponse.self, from: data)

        guard let text = responseBody.choices.first?.message.content else {
            throw TranscriptionError.invalidResponse
        }

        logger.info("OpenRouter transcription successful: \(text.prefix(50))...")
        return text
    }
}

// MARK: - Response Models

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

    struct GroqTranscriptionResponse: Decodable {
        let text: String
    }

    func normalizedAudioFormat(from url: URL) -> String {
        let ext = url.pathExtension.lowercased()
        let allowed = ["wav", "mp3", "m4a", "flac", "ogg", "webm", "aac"]
        return allowed.contains(ext) ? ext : "wav"
    }
}
