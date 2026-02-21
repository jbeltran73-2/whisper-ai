import Foundation

/// Speech-to-text provider
enum STTProvider: String, CaseIterable, Identifiable {
    case groq = "Groq"
    case openrouter = "OpenRouter"

    var id: String { rawValue }

    var baseURL: String {
        switch self {
        case .groq:
            return "https://api.groq.com/openai/v1/audio/transcriptions"
        case .openrouter:
            return "https://openrouter.ai/api/v1/chat/completions"
        }
    }

    var defaultModel: String {
        switch self {
        case .groq:
            return "whisper-large-v3-turbo"
        case .openrouter:
            return "openai/whisper-1"
        }
    }

    var keychainAccount: String {
        switch self {
        case .groq: return "groq-api-key"
        case .openrouter: return "openrouter-api-key"
        }
    }
}

/// LLM provider for text processing
enum LLMProvider: String, CaseIterable, Identifiable {
    case cerebras = "Cerebras"
    case groq = "Groq"
    case openrouter = "OpenRouter"

    var id: String { rawValue }

    var baseURL: String {
        switch self {
        case .cerebras:
            return "https://api.cerebras.ai/v1/chat/completions"
        case .groq:
            return "https://api.groq.com/openai/v1/chat/completions"
        case .openrouter:
            return "https://openrouter.ai/api/v1/chat/completions"
        }
    }

    var defaultModel: String {
        switch self {
        case .cerebras:
            return "gpt-oss-120b"
        case .groq:
            return "llama-3.3-70b-versatile"
        case .openrouter:
            return "openai/gpt-4o-mini"
        }
    }

    var keychainAccount: String {
        switch self {
        case .cerebras: return "cerebras-api-key"
        case .groq: return "groq-api-key"
        case .openrouter: return "openrouter-api-key"
        }
    }
}
