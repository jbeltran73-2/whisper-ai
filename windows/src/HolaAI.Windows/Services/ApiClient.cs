using System.Net.Http;
using System.Net.Http.Headers;
using System.Text;
using System.Text.Json;
using System.IO;
using HolaAI.Windows.Models;

namespace HolaAI.Windows.Services;

/// <summary>
/// Unified API client supporting Groq, Cerebras, and OpenRouter providers.
/// </summary>
public sealed class ApiClient
{
    private readonly HttpClient _httpClient;

    public ApiClient(HttpClient? httpClient = null)
    {
        _httpClient = httpClient ?? new HttpClient { Timeout = TimeSpan.FromSeconds(60) };
    }

    // ── STT ─────────────────────────────────────────────────────

    /// <summary>Transcribe audio using the configured STT provider.</summary>
    public async Task<string> TranscribeAsync(
        string audioFilePath,
        AppSettings settings,
        CancellationToken ct = default)
    {
        var apiKey = settings.GetSttApiKey()
            ?? throw new InvalidOperationException($"No API key configured for {settings.SttProvider}.");

        return settings.SttProvider switch
        {
            STTProvider.Groq => await TranscribeWithGroqAsync(audioFilePath, apiKey, settings, ct),
            STTProvider.OpenRouter => await TranscribeWithOpenRouterAsync(audioFilePath, apiKey, settings, ct),
            _ => throw new InvalidOperationException($"Unknown STT provider: {settings.SttProvider}")
        };
    }

    /// <summary>Groq native Whisper API (multipart/form-data).</summary>
    private async Task<string> TranscribeWithGroqAsync(
        string audioFilePath, string apiKey, AppSettings settings, CancellationToken ct)
    {
        var audioBytes = await File.ReadAllBytesAsync(audioFilePath, ct);
        var fileName = Path.GetFileName(audioFilePath);

        using var form = new MultipartFormDataContent();
        form.Add(new ByteArrayContent(audioBytes)
        {
            Headers = { ContentType = new MediaTypeHeaderValue("audio/wav") }
        }, "file", fileName);

        form.Add(new StringContent(settings.SttModel), "model");
        form.Add(new StringContent("json"), "response_format");

        if (settings.EffectiveLanguage is { } lang && !settings.EnableCodeSwitching)
        {
            form.Add(new StringContent(lang), "language");
        }

        using var request = new HttpRequestMessage(HttpMethod.Post, settings.SttProvider.BaseUrl());
        request.Headers.Authorization = new AuthenticationHeaderValue("Bearer", apiKey);
        request.Content = form;

        using var response = await _httpClient.SendAsync(request, ct);
        var raw = await response.Content.ReadAsStringAsync(ct);
        EnsureSuccess(response, raw, "Groq STT");

        using var doc = JsonDocument.Parse(raw);
        return doc.RootElement.GetProperty("text").GetString()?.Trim()
            ?? throw new InvalidOperationException("Groq returned empty transcription.");
    }

    /// <summary>OpenRouter audio via chat completions (base64).</summary>
    private async Task<string> TranscribeWithOpenRouterAsync(
        string audioFilePath, string apiKey, AppSettings settings, CancellationToken ct)
    {
        var audioBytes = await File.ReadAllBytesAsync(audioFilePath, ct);
        var ext = Path.GetExtension(audioFilePath).TrimStart('.').ToLowerInvariant();
        if (string.IsNullOrWhiteSpace(ext)) ext = "wav";

        var languageHint = settings.EffectiveLanguage is { } lang && !settings.EnableCodeSwitching
            ? $"Language hint: {lang}."
            : "Detect language automatically (may include code-switching).";

        var systemPrompt = $"""
            You are a speech-to-text transcriber. Transcribe the audio and return a clean, final text.

            Rules:
            1. Preserve the original language(s). Do NOT translate.
            2. Remove filler words, elongated fillers, stutters, and repeated phrases.
            3. Resolve self-corrections: if the speaker corrects themselves, output ONLY the corrected version.
            4. Remove false starts and abandoned sentence beginnings.
            5. Add punctuation and capitalization for readability.
            6. Keep numbers and expressions as spoken; do not solve them.
            7. Return ONLY the cleaned transcript, no explanations.

            {languageHint}
            """;

        var body = new
        {
            model = settings.SttModel,
            messages = new object[]
            {
                new { role = "system", content = systemPrompt },
                new
                {
                    role = "user",
                    content = new object[]
                    {
                        new { type = "input_text", text = "Transcribe the audio following the system rules." },
                        new { type = "input_audio", input_audio = new { data = Convert.ToBase64String(audioBytes), format = ext } }
                    }
                }
            },
            temperature = 0.2,
            max_tokens = 1024
        };

        return await PostChatCompletionAsync(STTProvider.OpenRouter.BaseUrl(), apiKey, body, isOpenRouter: true, ct);
    }

    // ── LLM (text processing) ───────────────────────────────────

    /// <summary>Make a chat completion request to any OpenAI-compatible provider.</summary>
    public async Task<string> ChatCompletionAsync(
        LLMProvider provider,
        string apiKey,
        string model,
        string systemPrompt,
        string userMessage,
        double temperature = 0.1,
        CancellationToken ct = default)
    {
        var body = new
        {
            model,
            messages = new object[]
            {
                new { role = "system", content = systemPrompt },
                new { role = "user", content = userMessage }
            },
            temperature,
            max_tokens = 1024
        };

        return await PostChatCompletionAsync(
            provider.BaseUrl(), apiKey, body,
            isOpenRouter: provider == LLMProvider.OpenRouter, ct);
    }

    // ── Shared ──────────────────────────────────────────────────

    private async Task<string> PostChatCompletionAsync(
        string url, string apiKey, object body, bool isOpenRouter, CancellationToken ct)
    {
        using var request = new HttpRequestMessage(HttpMethod.Post, url);
        request.Headers.Authorization = new AuthenticationHeaderValue("Bearer", apiKey);
        if (isOpenRouter) request.Headers.Add("X-Title", "Hola-AI Windows");
        request.Content = new StringContent(JsonSerializer.Serialize(body), Encoding.UTF8, "application/json");

        using var response = await _httpClient.SendAsync(request, ct);
        var raw = await response.Content.ReadAsStringAsync(ct);
        EnsureSuccess(response, raw, isOpenRouter ? "OpenRouter" : "API");

        using var doc = JsonDocument.Parse(raw);
        var content = doc.RootElement
            .GetProperty("choices")[0]
            .GetProperty("message")
            .GetProperty("content")
            .GetString();

        return content?.Trim()
            ?? throw new InvalidOperationException("API returned empty content.");
    }

    private static void EnsureSuccess(HttpResponseMessage response, string raw, string providerName)
    {
        if (response.IsSuccessStatusCode) return;

        var message = raw;
        try
        {
            using var doc = JsonDocument.Parse(raw);
            if (doc.RootElement.TryGetProperty("error", out var err) &&
                err.TryGetProperty("message", out var msg))
            {
                message = msg.GetString() ?? raw;
            }
        }
        catch { /* raw is fine */ }

        var code = (int)response.StatusCode;
        if (code == 429)
            throw new InvalidOperationException($"{providerName}: Rate limited. Please wait a moment and try again.");

        throw new InvalidOperationException($"{providerName} request failed ({code}): {message}");
    }
}
