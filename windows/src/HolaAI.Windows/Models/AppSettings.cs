namespace HolaAI.Windows.Models;

public sealed class AppSettings
{
    // Provider selections
    public STTProvider SttProvider { get; set; } = STTProvider.Groq;
    public LLMProvider DictationLLMProvider { get; set; } = LLMProvider.Cerebras;
    public LLMProvider PromptLLMProvider { get; set; } = LLMProvider.OpenRouter;

    // Models
    public string SttModel { get; set; } = "whisper-large-v3-turbo";
    public string DictationLLMModel { get; set; } = "gpt-oss-120b";
    public string PromptModel { get; set; } = "openai/gpt-4o-mini";

    // API Keys
    public string? GroqApiKey { get; set; }
    public string? CerebrasApiKey { get; set; }
    public string? OpenRouterApiKey { get; set; }

    // Language
    public string Language { get; set; } = "auto";
    public bool EnableCodeSwitching { get; set; }
    public bool EnableLLMEnhancement { get; set; } = true;

    // UI
    public bool ShowOverlayOnStartup { get; set; } = true;

    /// <summary>Get the API key for the current STT provider.</summary>
    public string? GetSttApiKey() => SttProvider switch
    {
        STTProvider.Groq => GroqApiKey,
        STTProvider.OpenRouter => OpenRouterApiKey,
        _ => null
    };

    /// <summary>Get the API key for a given LLM provider.</summary>
    public string? GetLLMApiKey(LLMProvider provider) => provider switch
    {
        LLMProvider.Cerebras => CerebrasApiKey,
        LLMProvider.Groq => GroqApiKey,
        LLMProvider.OpenRouter => OpenRouterApiKey,
        _ => null
    };

    /// <summary>Get effective language (null for auto-detect).</summary>
    public string? EffectiveLanguage => Language == "auto" ? null : Language;
}
