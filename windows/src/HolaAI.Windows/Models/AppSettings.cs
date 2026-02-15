namespace HolaAI.Windows.Models;

public sealed class AppSettings
{
    public string? OpenRouterApiKey { get; set; }
    public string SttModel { get; set; } = "openai/whisper-1";
    public string PromptModel { get; set; } = "openai/gpt-4o-mini";
    public bool ShowOverlayOnStartup { get; set; } = true;
}
