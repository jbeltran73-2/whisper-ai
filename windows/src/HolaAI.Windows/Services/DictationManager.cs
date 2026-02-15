using HolaAI.Windows.Models;

namespace HolaAI.Windows.Services;

public sealed class DictationManager : IDisposable
{
    private readonly AudioCaptureService _audioCaptureService;
    private readonly OpenRouterClient _openRouterClient;
    private readonly TextInsertionService _textInsertionService;
    private readonly SettingsService _settingsService;

    private string? _currentAudioPath;
    private AppSettings? _settings;

    public DictationManager(
        AudioCaptureService audioCaptureService,
        OpenRouterClient openRouterClient,
        TextInsertionService textInsertionService,
        SettingsService settingsService)
    {
        _audioCaptureService = audioCaptureService;
        _openRouterClient = openRouterClient;
        _textInsertionService = textInsertionService;
        _settingsService = settingsService;
    }

    public bool IsRecording => _audioCaptureService.IsRecording;

    public event Action<float>? AudioLevelChanged
    {
        add => _audioCaptureService.AudioLevelChanged += value;
        remove => _audioCaptureService.AudioLevelChanged -= value;
    }

    public event Action<string>? TranscriptionReady;

    public async Task ToggleAsync(DictationOptions options, CancellationToken cancellationToken = default)
    {
        if (_audioCaptureService.IsRecording)
        {
            await StopAsync(options, cancellationToken);
            return;
        }

        _currentAudioPath = await _audioCaptureService.StartAsync(cancellationToken);
    }

    public async Task StopAsync(DictationOptions options, CancellationToken cancellationToken = default)
    {
        var audioPath = await _audioCaptureService.StopAsync(cancellationToken);
        if (string.IsNullOrWhiteSpace(audioPath))
        {
            return;
        }

        _settings ??= await _settingsService.LoadAsync(cancellationToken);
        if (string.IsNullOrWhiteSpace(_settings.OpenRouterApiKey))
        {
            throw new InvalidOperationException("OpenRouter API key is not configured.");
        }

        var text = await _openRouterClient.TranscribeAndCleanAsync(
            audioPath,
            _settings.OpenRouterApiKey,
            _settings.SttModel,
            cancellationToken);

        if (options.Intent == DictationIntent.Prompt)
        {
            text = await _openRouterClient.EnhancePromptToEnglishAsync(
                text,
                _settings.OpenRouterApiKey,
                _settings.PromptModel,
                cancellationToken);
        }
        else if (options.TranslateToEnglish)
        {
            text = await _openRouterClient.TranslateToEnglishAsync(
                text,
                _settings.OpenRouterApiKey,
                _settings.PromptModel,
                cancellationToken);
        }

        await _textInsertionService.InsertTextAsync(text, cancellationToken);
        TranscriptionReady?.Invoke(text);
    }

    public void Dispose()
    {
        _audioCaptureService.Dispose();
    }
}
