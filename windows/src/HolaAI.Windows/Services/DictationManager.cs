using HolaAI.Windows.Models;

namespace HolaAI.Windows.Services;

public sealed class DictationManager : IDisposable
{
    private readonly AudioCaptureService _audioCaptureService;
    private readonly ApiClient _apiClient;
    private readonly TextProcessingService _textProcessingService;
    private readonly TextInsertionService _textInsertionService;
    private readonly SettingsService _settingsService;

    public DictationManager(
        AudioCaptureService audioCaptureService,
        ApiClient apiClient,
        TextProcessingService textProcessingService,
        TextInsertionService textInsertionService,
        SettingsService settingsService)
    {
        _audioCaptureService = audioCaptureService;
        _apiClient = apiClient;
        _textProcessingService = textProcessingService;
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

        await _audioCaptureService.StartAsync(cancellationToken);
    }

    public async Task StopAsync(DictationOptions options, CancellationToken cancellationToken = default)
    {
        var audioPath = await _audioCaptureService.StopAsync(cancellationToken);
        if (string.IsNullOrWhiteSpace(audioPath))
            return;

        try
        {
            var settings = await _settingsService.LoadAsync(cancellationToken);

            // Validate STT API key
            var sttKey = settings.GetSttApiKey();
            if (string.IsNullOrWhiteSpace(sttKey))
                throw new InvalidOperationException($"No API key configured for {settings.SttProvider}. Open Settings to add it.");

            // 1. Transcribe
            var text = await _apiClient.TranscribeAsync(audioPath, settings, cancellationToken);

            // 2. Process based on intent
            string processedText;
            switch (options.Intent)
            {
                case DictationIntent.Prompt:
                    processedText = await _textProcessingService.EnhancePromptAsync(text, settings, cancellationToken);
                    break;

                case DictationIntent.Transcription:
                default:
                    processedText = await _textProcessingService.ProcessTextAsync(text, settings, cancellationToken);
                    if (options.TranslateToEnglish)
                    {
                        processedText = await _textProcessingService.TranslateToEnglishAsync(
                            processedText, settings, cancellationToken);
                    }
                    break;
            }

            // 3. Insert into active app
            await _textInsertionService.InsertTextAsync(processedText, cancellationToken);
            TranscriptionReady?.Invoke(processedText);
        }
        finally
        {
            // Clean up temp audio file
            try { File.Delete(audioPath); } catch { /* ignore */ }
        }
    }

    public void Dispose()
    {
        _audioCaptureService.Dispose();
    }
}
