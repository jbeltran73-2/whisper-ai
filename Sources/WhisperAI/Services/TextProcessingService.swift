import Foundation
import os.log

/// Errors that can occur during text processing
enum TextProcessingError: Error, LocalizedError {
    case enhancementFailed(underlying: Error)
    case noAPIKey
    case missingModel

    var errorDescription: String? {
        switch self {
        case .enhancementFailed(let error):
            return "Text enhancement failed: \(error.localizedDescription)"
        case .noAPIKey:
            return "No OpenRouter API key configured."
        case .missingModel:
            return "No prompt enhancement model configured."
        }
    }
}

/// GPT API response structure
private struct GPTResponse: Decodable {
    struct Choice: Decodable {
        struct Message: Decodable {
            let content: String
        }
        let message: Message
    }
    let choices: [Choice]
}

/// Service responsible for post-processing transcribed text
/// Removes filler words, adds punctuation, and applies capitalization
@MainActor
final class TextProcessingService {
    private let logger = Logger(subsystem: "com.whisperai.app", category: "TextProcessing")
    private let gptEndpoint = "https://openrouter.ai/api/v1/chat/completions"

    /// Whether to use LLM enhancement (punctuation + capitalization)
    var enableLLMEnhancement: Bool {
        get { UserDefaults.standard.bool(forKey: "enableLLMEnhancement") }
        set { UserDefaults.standard.set(newValue, forKey: "enableLLMEnhancement") }
    }

    /// Whether code-switching (mixed languages) mode is enabled
    var enableCodeSwitching: Bool {
        get { UserDefaults.standard.bool(forKey: "enableCodeSwitching") }
        set { UserDefaults.standard.set(newValue, forKey: "enableCodeSwitching") }
    }

    init() {
        // Default to enabled
        if UserDefaults.standard.object(forKey: "enableLLMEnhancement") == nil {
            enableLLMEnhancement = true
        }
        // Default code-switching to disabled
        if UserDefaults.standard.object(forKey: "enableCodeSwitching") == nil {
            enableCodeSwitching = false
        }
    }

    /// Model used for prompt enhancement and text cleanup
    var promptEnhancementModel: String? {
        let value = UserDefaults.standard.string(forKey: "promptEnhancementModel")?.trimmingCharacters(in: .whitespacesAndNewlines)
        return (value?.isEmpty == false) ? value : nil
    }

    // MARK: - Filler Words

    /// English filler words/phrases to remove
    private let englishFillers: [String] = [
        "um", "uh", "ah", "er", "eh",
        "like", "you know", "basically", "actually", "literally",
        "i mean", "sort of", "kind of", "right", "okay so",
        "well", "so yeah", "yeah", "you see", "anyway"
    ]

    /// Spanish filler words/phrases to remove
    private let spanishFillers: [String] = [
        "este", "eh", "o sea", "como que", "bueno",
        "pues", "entonces", "es que", "a ver", "digamos",
        "osea", "tipo", "sabes", "mira", "oye"
    ]

    /// Patterns for elongated fillers like "uuummmm", "aaaahhh", "eeehhh"
    private let elongatedFillerPatterns: [String] = [
        "(?i)\\b(u+m+|u+h+)\\b[,\\s]*",
        "(?i)\\b(a+h+|e+h+|o+h+)\\b[,\\s]*",
        "(?i)\\b(e+m+|m{2,})\\b[,\\s]*"
    ]

    /// Remove filler words from text
    /// - Parameters:
    ///   - text: The transcribed text
    ///   - language: Optional language code to use specific filler lists
    ///   - isCodeSwitching: If true, use fillers from all supported languages
    /// - Returns: Text with filler words removed
    func removeFillers(from text: String, language: String? = nil, isCodeSwitching: Bool = false) -> String {
        var result = text

        // Remove elongated fillers first
        for pattern in elongatedFillerPatterns {
            if let regex = try? NSRegularExpression(pattern: pattern, options: []) {
                let range = NSRange(result.startIndex..., in: result)
                result = regex.stringByReplacingMatches(in: result, options: [], range: range, withTemplate: "")
            }
        }

        // Get fillers based on language or use all
        let fillers: [String]
        if isCodeSwitching {
            // Code-switching mode: use all language fillers
            fillers = englishFillers + spanishFillers
        } else {
            switch language {
            case "es":
                fillers = spanishFillers
            case "en":
                fillers = englishFillers
            default:
                // Use both for auto-detect or other languages
                fillers = englishFillers + spanishFillers
            }
        }

        // Sort by length (longest first) to avoid partial matches
        let sortedFillers = fillers.sorted { $0.count > $1.count }

        for filler in sortedFillers {
            // Create pattern that matches filler as a whole word
            // Handle various positions: start of text, after punctuation, between words
            let pattern = "(?i)\\b\(NSRegularExpression.escapedPattern(for: filler))\\b[,]?\\s*"

            if let regex = try? NSRegularExpression(pattern: pattern, options: []) {
                let range = NSRange(result.startIndex..., in: result)
                result = regex.stringByReplacingMatches(in: result, options: [], range: range, withTemplate: "")
            }
        }

        // Clean up extra spaces
        result = result.replacingOccurrences(of: "  +", with: " ", options: .regularExpression)
        result = result.trimmingCharacters(in: .whitespaces)

        // Fix any double punctuation that might result
        result = result.replacingOccurrences(of: "\\s*,\\s*,", with: ",", options: .regularExpression)
        result = result.replacingOccurrences(of: "\\s*\\.\\s*\\.", with: ".", options: .regularExpression)

        // Capitalize first letter if needed
        if let first = result.first, first.isLowercase {
            result = result.prefix(1).uppercased() + result.dropFirst()
        }

        logger.info("Filler removal: '\(text.prefix(30))...' -> '\(result.prefix(30))...'")
        return result
    }

    // MARK: - LLM Enhancement (Punctuation + Capitalization)

    /// Enhance text with proper punctuation and capitalization using GPT
    /// - Parameters:
    ///   - text: Text after filler removal
    ///   - language: Language for context
    ///   - isCodeSwitching: If true, handle mixed-language text
    /// - Returns: Enhanced text with punctuation and capitalization
    func enhanceWithLLM(_ text: String, language: String? = nil, isCodeSwitching: Bool = false) async throws -> String {
        guard let apiKey = KeychainService.shared.getAPIKey(), !apiKey.isEmpty else {
            throw TextProcessingError.noAPIKey
        }
        guard let model = promptEnhancementModel else {
            throw TextProcessingError.missingModel
        }

        let systemPrompt: String

        if isCodeSwitching {
            // Code-switching prompt: handle mixed languages
            systemPrompt = """
            You are a multilingual speech-to-text post-processor specialized in code-switching (mixed-language speech). Your job is to clean up transcribed speech that may contain multiple languages within the same utterance.

            IMPORTANT: The text may switch between languages mid-sentence. This is intentional and common in multilingual speakers.

            Rules:
            1. **Self-corrections (CRITICAL)**: Detect when the speaker corrects themselves and REPLACE the wrong part with the correction. Look for these correction markers:
               - Spanish: "no", "digo", "quiero decir", "mejor dicho", "o sea", "bueno", "en realidad", "perdón"
               - English: "no", "I mean", "actually", "wait", "sorry", "rather", "well"
               - French: "non", "je veux dire", "en fait", "pardon"
               When you see "[wrong] [marker] [correct]", output ONLY the sentence with [correct], removing [wrong] and [marker] entirely.
            2. **Repetitions**: Remove stutters and repeated words/phrases in any language
            3. **False starts**: Remove abandoned sentence beginnings
            4. Detect and preserve language switches within the text - DO NOT translate or change languages
            5. Add periods at sentence boundaries
            6. Add commas for natural clause breaks
            7. Add question marks for questions (detect from context)
            8. Add exclamation marks for emphatic statements
            9. Capitalize the first word of each sentence
            10. Capitalize proper nouns (names, places, companies) according to each language's conventions
            11. Capitalize acronyms (API, URL, HTML, etc.)
            12. Always capitalize "I" in English and apply appropriate capitalization rules for each language
            13. Maintain grammatical coherence when languages switch - do not "fix" natural code-switching
            14. Resolve fragmented speech into coherent, natural phrasing while preserving original intent
            15. Return ONLY the cleaned text, no explanations

            Self-correction examples (VERY IMPORTANT):
            Input: "esto es una prueba de fuego no de arena"
            Output: "Esto es una prueba de arena."

            Input: "necesito cinco no seis archivos"
            Output: "Necesito seis archivos."

            Input: "la reunión es el lunes digo el martes"
            Output: "La reunión es el martes."

            Input: "vamos al cine no mejor al teatro"
            Output: "Vamos al teatro."

            Input: "I need the red one no the blue one"
            Output: "I need the blue one."

            Code-switching examples:
            Input: "hey can you send me el documento that we discussed yesterday porque lo necesito para la reunión"
            Output: "Hey, can you send me el documento that we discussed yesterday? Porque lo necesito para la reunión."

            Input: "i think c'est une bonne idée but we need to verify avec l'équipe"
            Output: "I think c'est une bonne idée, but we need to verify avec l'équipe."

            Input: "vamos a hacer una prueba qué tal qué tal modelo lo hace"
            Output: "Vamos a hacer una prueba para ver qué tal lo hace el modelo."
            """
        } else {
            let languageHint = language.map { "The text is in \($0)." } ?? "Detect the language automatically."

            systemPrompt = """
            You are a speech-to-text post-processor. Your job is to clean up transcribed speech and produce polished, final text. \(languageHint)

            Rules:
            1. **Self-corrections (CRITICAL)**: Detect when the speaker corrects themselves and REPLACE the wrong part with the correction. Look for these correction markers:
               - Spanish: "no", "digo", "quiero decir", "mejor dicho", "o sea", "bueno", "en realidad", "perdón"
               - English: "no", "I mean", "actually", "wait", "sorry", "rather", "well"
               When you see "[wrong] [marker] [correct]", output ONLY the sentence with [correct], removing [wrong] and [marker] entirely.
            2. **Repetitions**: Remove stutters and repeated words/phrases (e.g., "I I think" → "I think")
            3. **False starts**: Remove abandoned sentence beginnings (e.g., "I was going to— Actually, let's do this" → "Actually, let's do this")
            4. Add periods at sentence boundaries
            5. Add commas for natural clause breaks
            6. Add question marks for questions
            7. Add exclamation marks for emphatic statements
            8. Capitalize the first word of each sentence
            9. Capitalize proper nouns (names, places, companies)
            10. Capitalize acronyms (API, URL, HTML, etc.)
            11. Always capitalize "I" when referring to oneself
            12. Resolve fragmented speech into coherent, natural phrasing while preserving original intent
            13. Return ONLY the cleaned text, no explanations

            Self-correction examples (VERY IMPORTANT - apply the correction, remove the error):
            Input: "esto es una prueba de fuego no de arena"
            Output: "Esto es una prueba de arena."

            Input: "necesito cinco no seis archivos"
            Output: "Necesito seis archivos."

            Input: "la reunión es el lunes digo el martes"
            Output: "La reunión es el martes."

            Input: "vamos al cine no mejor al teatro"
            Output: "Vamos al teatro."

            Input: "I need the red one no the blue one"
            Output: "I need the blue one."

            Input: "the meeting is on monday no tuesday at three pm"
            Output: "The meeting is on Tuesday at 3 PM."

            Input: "I want to count to five no wait six"
            Output: "I want to count to six."

            Other examples:
            Input: "hey john can you send me the api documentation for the new feature i need it by tomorrow"
            Output: "Hey John, can you send me the API documentation for the new feature? I need it by tomorrow."

            Input: "I think I think we should we should go with option A"
            Output: "I think we should go with option A."

            Input: "vamos a hacer una prueba qué tal qué tal modelo lo hace"
            Output: "Vamos a hacer una prueba para ver qué tal lo hace el modelo."
            """
        }

        let requestBody: [String: Any] = [
            "model": model,
            "messages": [
                ["role": "system", "content": systemPrompt],
                ["role": "user", "content": text]
            ],
            "max_tokens": 1024,
            "temperature": 0.1
        ]

        var request = URLRequest(url: URL(string: gptEndpoint)!)
        request.httpMethod = "POST"
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("Whisper-AI", forHTTPHeaderField: "X-Title")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: requestBody)

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
            throw TextProcessingError.enhancementFailed(underlying: NSError(
                domain: "TextProcessing",
                code: -1,
                userInfo: [NSLocalizedDescriptionKey: "API request failed"]
            ))
        }

        let gptResponse = try JSONDecoder().decode(GPTResponse.self, from: data)

        guard let enhancedText = gptResponse.choices.first?.message.content else {
            throw TextProcessingError.enhancementFailed(underlying: NSError(
                domain: "TextProcessing",
                code: -2,
                userInfo: [NSLocalizedDescriptionKey: "No response from GPT"]
            ))
        }

        logger.info("LLM enhancement: '\(text.prefix(30))...' -> '\(enhancedText.prefix(30))...'")
        return enhancedText.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    // MARK: - Prompt Enhancement (Translate to English)

    /// Enhance spoken input into a clear English prompt
    /// - Parameters:
    ///   - text: Raw transcribed text
    ///   - language: Optional language hint
    /// - Returns: Enhanced English prompt
    func enhancePromptToEnglish(_ text: String, language: String? = nil) async throws -> String {
        guard let apiKey = KeychainService.shared.getAPIKey(), !apiKey.isEmpty else {
            throw TextProcessingError.noAPIKey
        }
        guard let model = promptEnhancementModel else {
            throw TextProcessingError.missingModel
        }

        let languageHint = language.map { "Original language hint: \($0)." } ?? "Detect the original language automatically."
        let systemPrompt = """
        You are a prompt engineer. Rewrite the user's spoken request into a clear, high-quality English prompt.

        Rules:
        1. Translate to English while preserving meaning.
        2. Remove filler words, stutters, and false starts.
        3. Improve clarity and structure without inventing new requirements.
        4. Keep proper nouns, product names, and code terms intact.
        5. If the request contains multiple requirements, format them as a concise list.
        6. Return ONLY the improved prompt, no explanations.

        \(languageHint)
        """

        let requestBody: [String: Any] = [
            "model": model,
            "messages": [
                ["role": "system", "content": systemPrompt],
                ["role": "user", "content": text]
            ],
            "max_tokens": 1024,
            "temperature": 0.2
        ]

        var request = URLRequest(url: URL(string: gptEndpoint)!)
        request.httpMethod = "POST"
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("Whisper-AI", forHTTPHeaderField: "X-Title")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: requestBody)

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
            throw TextProcessingError.enhancementFailed(underlying: NSError(
                domain: "TextProcessing",
                code: -3,
                userInfo: [NSLocalizedDescriptionKey: "API request failed"]
            ))
        }

        let gptResponse = try JSONDecoder().decode(GPTResponse.self, from: data)

        guard let enhancedText = gptResponse.choices.first?.message.content else {
            throw TextProcessingError.enhancementFailed(underlying: NSError(
                domain: "TextProcessing",
                code: -4,
                userInfo: [NSLocalizedDescriptionKey: "No response from LLM"]
            ))
        }

        logger.info("Prompt enhancement: '\(text.prefix(30))...' -> '\(enhancedText.prefix(30))...'")
        return enhancedText.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    // MARK: - Full Processing Pipeline

    /// Process text through the full pipeline
    /// - Parameters:
    ///   - text: Raw transcribed text
    ///   - language: Optional language code
    /// - Returns: Processed text
    func processText(_ text: String, language: String? = nil) -> String {
        // Step 1: Remove filler words (local, fast)
        let afterFillers = removeFillers(from: text, language: language, isCodeSwitching: enableCodeSwitching)

        // For sync version, just return after filler removal
        // Async version should be used for full processing
        return afterFillers
    }

    /// Process text through the full pipeline including LLM enhancement
    /// - Parameters:
    ///   - text: Raw transcribed text
    ///   - language: Optional language code
    /// - Returns: Fully processed text with punctuation and capitalization
    func processTextAsync(_ text: String, language: String? = nil) async -> String {
        let isCodeSwitching = enableCodeSwitching

        // Step 1: Remove filler words (local, fast)
        // In code-switching mode, use all language fillers
        let afterFillers = removeFillers(from: text, language: language, isCodeSwitching: isCodeSwitching)

        // Step 2 & 3: Add punctuation and capitalization via LLM
        if enableLLMEnhancement && !afterFillers.isEmpty {
            do {
                let enhanced = try await enhanceWithLLM(afterFillers, language: language, isCodeSwitching: isCodeSwitching)
                return enhanced
            } catch {
                logger.error("LLM enhancement failed, returning filler-removed text: \(error.localizedDescription)")
                // Fall back to filler-removed text
                return afterFillers
            }
        }

        return afterFillers
    }

    /// Process text for prompt mode (translate to English + enhance)
    /// - Parameters:
    ///   - text: Raw transcribed text
    ///   - language: Optional language code
    /// - Returns: Enhanced English prompt
    func processPromptAsync(_ text: String, language: String? = nil) async -> String {
        let afterFillers = removeFillers(from: text, language: language, isCodeSwitching: enableCodeSwitching)

        do {
            return try await enhancePromptToEnglish(afterFillers.isEmpty ? text : afterFillers, language: language)
        } catch {
            logger.error("Prompt enhancement failed, returning filler-removed text: \(error.localizedDescription)")
            return afterFillers.isEmpty ? text : afterFillers
        }
    }

    // MARK: - Translation (Dictation)

    /// Translate dictation output to English (no prompt formatting)
    /// - Parameters:
    ///   - text: Cleaned transcribed text
    ///   - language: Optional language hint
    /// - Returns: English translation
    func translateTextToEnglish(_ text: String, language: String? = nil) async -> String {
        guard let apiKey = KeychainService.shared.getAPIKey(), !apiKey.isEmpty else {
            return text
        }
        guard let model = promptEnhancementModel else {
            return text
        }

        let languageHint = language.map { "Original language hint: \($0)." } ?? "Detect the original language automatically."
        let systemPrompt = """
        You are a translator. Translate the user's text to clear, natural English.

        Rules:
        1. Preserve meaning exactly; do not add new content.
        2. Keep code, product names, and proper nouns intact.
        3. Keep numbers and expressions as spoken (e.g., "3+2").
        4. Preserve line breaks if they exist.
        5. Return ONLY the translated text, no explanations.

        \(languageHint)
        """

        let requestBody: [String: Any] = [
            "model": model,
            "messages": [
                ["role": "system", "content": systemPrompt],
                ["role": "user", "content": text]
            ],
            "max_tokens": 1024,
            "temperature": 0.1
        ]

        var request = URLRequest(url: URL(string: gptEndpoint)!)
        request.httpMethod = "POST"
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("Whisper-AI", forHTTPHeaderField: "X-Title")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try? JSONSerialization.data(withJSONObject: requestBody)

        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
                return text
            }
            let gptResponse = try JSONDecoder().decode(GPTResponse.self, from: data)
            guard let translated = gptResponse.choices.first?.message.content else {
                return text
            }
            return translated.trimmingCharacters(in: .whitespacesAndNewlines)
        } catch {
            logger.error("Translation failed, returning original text: \(error.localizedDescription)")
            return text
        }
    }
}
