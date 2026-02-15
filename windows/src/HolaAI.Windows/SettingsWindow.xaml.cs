using System.Windows;
using HolaAI.Windows.Models;
using HolaAI.Windows.Services;

namespace HolaAI.Windows;

public partial class SettingsWindow : Window
{
    private readonly SettingsService _settingsService;
    private AppSettings _settings = new();

    public SettingsWindow(SettingsService settingsService)
    {
        _settingsService = settingsService;
        InitializeComponent();
    }

    private async void Window_OnLoaded(object sender, RoutedEventArgs e)
    {
        _settings = await _settingsService.LoadAsync();
        ApiKeyBox.Text = _settings.OpenRouterApiKey ?? string.Empty;
        SttModelBox.Text = _settings.SttModel;
        PromptModelBox.Text = _settings.PromptModel;
        ShowOverlayCheck.IsChecked = _settings.ShowOverlayOnStartup;
    }

    private async void SaveButton_OnClick(object sender, RoutedEventArgs e)
    {
        _settings.OpenRouterApiKey = ApiKeyBox.Text.Trim();
        _settings.SttModel = string.IsNullOrWhiteSpace(SttModelBox.Text)
            ? "openai/whisper-1"
            : SttModelBox.Text.Trim();
        _settings.PromptModel = string.IsNullOrWhiteSpace(PromptModelBox.Text)
            ? "openai/gpt-4o-mini"
            : PromptModelBox.Text.Trim();
        _settings.ShowOverlayOnStartup = ShowOverlayCheck.IsChecked ?? true;

        await _settingsService.SaveAsync(_settings);
        DialogResult = true;
        Close();
    }
}
