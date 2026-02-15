using System.Net.Http.Headers;
using System.Text;
using System.Text.Json;
using System.Net.Http;

namespace HolaAI.Windows.Services;

public sealed class OpenRouterClient
{
    private readonly HttpClient _httpClient;

    public OpenRouterClient(HttpClient? httpClient = null)
    {
        _httpClient = httpClient ?? new HttpClient();
        _httpClient.BaseAddress = new Uri("https://openrouter.ai/");
    }

    public async Task<string> TranscribeAndCleanAsync(
        string audioFilePath,
        string apiKey,
        string sttModel,
        CancellationToken cancellationToken = default)
    {
        var bytes = await File.ReadAllBytesAsync(audioFilePath, cancellationToken);
        var ext = Path.GetExtension(audioFilePath).Trim('.').ToLowerInvariant();
        if (string.IsNullOrWhiteSpace(ext))
        {
            ext = "wav";
        }

        var systemPrompt = """
                           You are a speech-to-text transcriber.
                           Return only the cleaned final transcript.
                           Rules:
                           - Keep original language.
                           - Remove fillers (umm, aaa, etc), stutters, and false starts.
                           - Resolve self-corrections keeping only the final corrected phrase.
                           - Add punctuation and capitalization.
                           """;

        var body = new
        {
            model = sttModel,
            messages = new object[]
            {
                new
                {
                    role = "system",
                    content = systemPrompt
                },
                new
                {
                    role = "user",
                    content = new object[]
                    {
                        new { type = "input_text", text = "Transcribe and clean this audio." },
                        new
                        {
                            type = "input_audio",
                            input_audio = new
                            {
                                data = Convert.ToBase64String(bytes),
                                format = ext
                            }
                        }
                    }
                }
            },
            temperature = 0.2,
            max_tokens = 1024
        };

        return await PostChatCompletionAsync(apiKey, body, cancellationToken);
    }

    public async Task<string> EnhancePromptToEnglishAsync(
        string text,
        string apiKey,
        string promptModel,
        CancellationToken cancellationToken = default)
    {
        var body = new
        {
            model = promptModel,
            messages = new object[]
            {
                new
                {
                    role = "system",
                    content = """
                              You are a prompt engineer.
                              Rewrite the user's request into a concise, high-quality English prompt.
                              Return only the final prompt text.
                              """
                },
                new
                {
                    role = "user",
                    content = text
                }
            },
            temperature = 0.2,
            max_tokens = 1024
        };

        return await PostChatCompletionAsync(apiKey, body, cancellationToken);
    }

    public async Task<string> TranslateToEnglishAsync(
        string text,
        string apiKey,
        string promptModel,
        CancellationToken cancellationToken = default)
    {
        var body = new
        {
            model = promptModel,
            messages = new object[]
            {
                new
                {
                    role = "system",
                    content = """
                              Translate the user text to natural English.
                              Keep original meaning exactly.
                              Return only translated text.
                              """
                },
                new
                {
                    role = "user",
                    content = text
                }
            },
            temperature = 0.1,
            max_tokens = 1024
        };

        return await PostChatCompletionAsync(apiKey, body, cancellationToken);
    }

    private async Task<string> PostChatCompletionAsync(string apiKey, object body, CancellationToken cancellationToken)
    {
        using var request = new HttpRequestMessage(HttpMethod.Post, "api/v1/chat/completions");
        request.Headers.Authorization = new AuthenticationHeaderValue("Bearer", apiKey);
        request.Headers.Add("X-Title", "Hola-AI Windows");
        request.Content = new StringContent(JsonSerializer.Serialize(body), Encoding.UTF8, "application/json");

        using var response = await _httpClient.SendAsync(request, cancellationToken);
        var raw = await response.Content.ReadAsStringAsync(cancellationToken);
        if (!response.IsSuccessStatusCode)
        {
            throw new InvalidOperationException($"OpenRouter request failed ({(int)response.StatusCode}): {raw}");
        }

        using var doc = JsonDocument.Parse(raw);
        var content = doc.RootElement
            .GetProperty("choices")[0]
            .GetProperty("message")
            .GetProperty("content")
            .GetString();

        if (string.IsNullOrWhiteSpace(content))
        {
            throw new InvalidOperationException("OpenRouter returned empty content.");
        }

        return content.Trim();
    }
}
