using System.Text.RegularExpressions;
using HolaAI.Windows.Models;

namespace HolaAI.Windows.Services;

/// <summary>
/// Post-processes transcribed text: filler removal, LLM enhancement, prompt rewriting, translation.
/// Mirrors the macOS TextProcessingService for full parity.
/// </summary>
public sealed class TextProcessingService
{
    private readonly ApiClient _apiClient;

    private static readonly string[] EnglishFillers =
    [
        "um", "uh", "ah", "er", "eh",
        "like", "you know", "basically", "actually", "literally",
        "i mean", "sort of", "kind of", "right", "okay so",
        "well", "so yeah", "yeah", "you see", "anyway"
    ];

    private static readonly string[] SpanishFillers =
    [
        "este", "eh", "o sea", "como que", "bueno",
        "pues", "entonces", "es que", "a ver", "digamos",
        "osea", "tipo", "sabes", "mira", "oye"
    ];

    private static readonly string[] ElongatedFillerPatterns =
    [
        @"(?i)\b(u+m+|u+h+)\b[,\s]*",
        @"(?i)\b(a+h+|e+h+|o+h+)\b[,\s]*",
        @"(?i)\b(e+m+|m{2,})\b[,\s]*"
    ];

    public TextProcessingService(ApiClient apiClient)
    {
        _apiClient = apiClient;
    }

    /// <summary>Remove filler words from text.</summary>
    public string RemoveFillers(string text, string? language, bool isCodeSwitching)
    {
        var result = text;

        // Remove elongated fillers first
        foreach (var pattern in ElongatedFillerPatterns)
        {
            result = Regex.Replace(result, pattern, "", RegexOptions.None, TimeSpan.FromSeconds(1));
        }

        // Pick fillers based on language
        var fillers = isCodeSwitching
            ? EnglishFillers.Concat(SpanishFillers)
            : language switch
            {
                "es" => SpanishFillers.AsEnumerable(),
                "en" => EnglishFillers.AsEnumerable(),
                _ => EnglishFillers.Concat(SpanishFillers)
            };

        // Sort by length descending to avoid partial matches
        foreach (var filler in fillers.OrderByDescending(f => f.Length))
        {
            var escaped = Regex.Escape(filler);
            result = Regex.Replace(result, $@"(?i)\b{escaped}\b[,]?\s*", "",
                RegexOptions.None, TimeSpan.FromSeconds(1));
        }

        // Clean up extra spaces and double punctuation
        result = Regex.Replace(result, @"  +", " ").Trim();
        result = Regex.Replace(result, @"\s*,\s*,", ",");
        result = Regex.Replace(result, @"\s*\.\s*\.", ".");

        // Capitalize first letter
        if (result.Length > 0 && char.IsLower(result[0]))
        {
            result = char.ToUpper(result[0]) + result[1..];
        }

        return result;
    }

    /// <summary>Enhance text with LLM for punctuation, capitalization, self-correction.</summary>
    public async Task<string> EnhanceWithLLMAsync(
        string text, AppSettings settings, CancellationToken ct = default)
    {
        var provider = settings.DictationLLMProvider;
        var apiKey = settings.GetLLMApiKey(provider)
            ?? throw new InvalidOperationException($"No API key configured for {provider}.");
        var model = string.IsNullOrWhiteSpace(settings.DictationLLMModel)
            ? provider.DefaultModel()
            : settings.DictationLLMModel;

        var systemPrompt = settings.EnableCodeSwitching
            ? BuildCodeSwitchingPrompt()
            : BuildStandardPrompt(settings.EffectiveLanguage);

        return await _apiClient.ChatCompletionAsync(provider, apiKey, model, systemPrompt, text, 0.1, ct);
    }

    /// <summary>Enhance spoken input into a clear English prompt.</summary>
    public async Task<string> EnhancePromptAsync(
        string text, AppSettings settings, CancellationToken ct = default)
    {
        var provider = settings.PromptLLMProvider;
        var apiKey = settings.GetLLMApiKey(provider)
            ?? throw new InvalidOperationException($"No API key configured for {provider}.");
        var model = string.IsNullOrWhiteSpace(settings.PromptModel)
            ? provider.DefaultModel()
            : settings.PromptModel;

        var languageHint = settings.EffectiveLanguage is { } lang
            ? $"Original language hint: {lang}."
            : "Detect the original language automatically.";

        var systemPrompt = $"""
            You are a prompt engineer. Rewrite the user's spoken request into a clear, high-quality English prompt.

            Rules:
            1. Translate to English while preserving meaning.
            2. Remove filler words, stutters, and false starts.
            3. Improve clarity and structure without inventing new requirements.
            4. Keep proper nouns, product names, and code terms intact.
            5. If the request contains multiple requirements, format them as a concise list.
            6. Return ONLY the improved prompt, no explanations.

            {languageHint}
            """;

        return await _apiClient.ChatCompletionAsync(provider, apiKey, model, systemPrompt, text, 0.2, ct);
    }

    /// <summary>Translate text to English using the dictation LLM.</summary>
    public async Task<string> TranslateToEnglishAsync(
        string text, AppSettings settings, CancellationToken ct = default)
    {
        var provider = settings.DictationLLMProvider;
        var apiKey = settings.GetLLMApiKey(provider);
        if (string.IsNullOrWhiteSpace(apiKey)) return text;

        var model = string.IsNullOrWhiteSpace(settings.DictationLLMModel)
            ? provider.DefaultModel()
            : settings.DictationLLMModel;

        var languageHint = settings.EffectiveLanguage is { } lang
            ? $"Original language hint: {lang}."
            : "Detect the original language automatically.";

        var systemPrompt = $"""
            You are a translator. Translate the user's text to clear, natural English.

            Rules:
            1. Preserve meaning exactly; do not add new content.
            2. Keep code, product names, and proper nouns intact.
            3. Keep numbers and expressions as spoken.
            4. Preserve line breaks if they exist.
            5. Return ONLY the translated text, no explanations.

            {languageHint}
            """;

        try
        {
            return await _apiClient.ChatCompletionAsync(provider, apiKey, model, systemPrompt, text, 0.1, ct);
        }
        catch
        {
            return text; // fallback to original
        }
    }

    /// <summary>Full processing pipeline: fillers → LLM enhancement.</summary>
    public async Task<string> ProcessTextAsync(
        string text, AppSettings settings, CancellationToken ct = default)
    {
        var cleaned = RemoveFillers(text, settings.EffectiveLanguage, settings.EnableCodeSwitching);

        if (settings.EnableLLMEnhancement && !string.IsNullOrWhiteSpace(cleaned))
        {
            try
            {
                return await EnhanceWithLLMAsync(cleaned, settings, ct);
            }
            catch
            {
                return cleaned; // fallback to filler-removed text
            }
        }

        return cleaned;
    }

    // ── Prompt builders ─────────────────────────────────────────

    private static string BuildStandardPrompt(string? language)
    {
        var languageHint = language is not null
            ? $"The text is in {language}."
            : "Detect the language automatically.";

        return $"""
            You are a speech-to-text post-processor. Your job is to clean up transcribed speech and produce polished, final text. {languageHint}

            Rules:
            1. **Self-corrections (CRITICAL)**: Detect when the speaker corrects themselves and REPLACE the wrong part with the correction. Look for these correction markers:
               - Spanish: "no", "digo", "quiero decir", "mejor dicho", "o sea", "bueno", "en realidad", "perdón"
               - English: "no", "I mean", "actually", "wait", "sorry", "rather", "well"
               When you see "[wrong] [marker] [correct]", output ONLY the sentence with [correct], removing [wrong] and [marker] entirely.
            2. **Repetitions**: Remove stutters and repeated words/phrases (e.g., "I I think" → "I think")
            3. **False starts**: Remove abandoned sentence beginnings
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

            Self-correction examples (VERY IMPORTANT):
            Input: "necesito cinco no seis archivos"
            Output: "Necesito seis archivos."

            Input: "I need the red one no the blue one"
            Output: "I need the blue one."
            """;
    }

    private static string BuildCodeSwitchingPrompt()
    {
        return """
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
            7. Add question marks for questions
            8. Add exclamation marks for emphatic statements
            9. Capitalize the first word of each sentence
            10. Capitalize proper nouns according to each language's conventions
            11. Capitalize acronyms (API, URL, HTML, etc.)
            12. Always capitalize "I" in English and apply appropriate capitalization rules for each language
            13. Maintain grammatical coherence when languages switch
            14. Resolve fragmented speech into coherent, natural phrasing while preserving original intent
            15. Return ONLY the cleaned text, no explanations

            Code-switching examples:
            Input: "hey can you send me el documento that we discussed yesterday porque lo necesito para la reunión"
            Output: "Hey, can you send me el documento that we discussed yesterday? Porque lo necesito para la reunión."
            """;
    }
}
