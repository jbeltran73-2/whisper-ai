namespace HolaAI.Windows.Models;

/// <summary>Speech-to-text provider.</summary>
public enum STTProvider
{
    Groq,
    OpenRouter
}

/// <summary>LLM provider for text processing.</summary>
public enum LLMProvider
{
    Cerebras,
    Groq,
    OpenRouter
}

public static class ProviderDefaults
{
    public static string BaseUrl(this STTProvider provider) => provider switch
    {
        STTProvider.Groq => "https://api.groq.com/openai/v1/audio/transcriptions",
        STTProvider.OpenRouter => "https://openrouter.ai/api/v1/chat/completions",
        _ => throw new ArgumentOutOfRangeException(nameof(provider))
    };

    public static string DefaultModel(this STTProvider provider) => provider switch
    {
        STTProvider.Groq => "whisper-large-v3-turbo",
        STTProvider.OpenRouter => "openai/whisper-1",
        _ => throw new ArgumentOutOfRangeException(nameof(provider))
    };

    public static string BaseUrl(this LLMProvider provider) => provider switch
    {
        LLMProvider.Cerebras => "https://api.cerebras.ai/v1/chat/completions",
        LLMProvider.Groq => "https://api.groq.com/openai/v1/chat/completions",
        LLMProvider.OpenRouter => "https://openrouter.ai/api/v1/chat/completions",
        _ => throw new ArgumentOutOfRangeException(nameof(provider))
    };

    public static string DefaultModel(this LLMProvider provider) => provider switch
    {
        LLMProvider.Cerebras => "gpt-oss-120b",
        LLMProvider.Groq => "llama-3.3-70b-versatile",
        LLMProvider.OpenRouter => "openai/gpt-4o-mini",
        _ => throw new ArgumentOutOfRangeException(nameof(provider))
    };

    public static string SettingsKeyName(this STTProvider provider) => provider switch
    {
        STTProvider.Groq => "groq",
        STTProvider.OpenRouter => "openrouter",
        _ => throw new ArgumentOutOfRangeException(nameof(provider))
    };

    public static string SettingsKeyName(this LLMProvider provider) => provider switch
    {
        LLMProvider.Cerebras => "cerebras",
        LLMProvider.Groq => "groq",
        LLMProvider.OpenRouter => "openrouter",
        _ => throw new ArgumentOutOfRangeException(nameof(provider))
    };

    public static readonly (string Code, string Name)[] SupportedLanguages =
    [
        ("auto", "Auto-detect"),
        ("en", "English"),
        ("es", "Spanish"),
        ("fr", "French"),
        ("de", "German"),
        ("it", "Italian"),
        ("pt", "Portuguese"),
        ("nl", "Dutch"),
        ("pl", "Polish"),
        ("ru", "Russian"),
        ("ja", "Japanese"),
        ("ko", "Korean"),
        ("zh", "Chinese"),
        ("ar", "Arabic"),
        ("hi", "Hindi"),
        ("tr", "Turkish"),
        ("vi", "Vietnamese"),
        ("th", "Thai"),
        ("id", "Indonesian"),
        ("sv", "Swedish"),
        ("da", "Danish"),
        ("no", "Norwegian"),
        ("fi", "Finnish")
    ];
}
