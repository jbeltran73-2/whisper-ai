using System.Windows;
using System.Windows.Controls;
using HolaAI.Windows.Models;
using HolaAI.Windows.Services;

namespace HolaAI.Windows;

public partial class SettingsWindow : Window
{
    private readonly SettingsService _settingsService;
    private AppSettings _settings = new();
    private bool _loading;

    public SettingsWindow(SettingsService settingsService)
    {
        _settingsService = settingsService;
        InitializeComponent();
    }

    private async void Window_OnLoaded(object sender, RoutedEventArgs e)
    {
        _loading = true;

        _settings = await _settingsService.LoadAsync();

        // Language
        LanguageCombo.Items.Clear();
        foreach (var (code, name) in ProviderDefaults.SupportedLanguages)
        {
            LanguageCombo.Items.Add(new ComboBoxItem { Content = name, Tag = code });
        }
        SelectComboByTag(LanguageCombo, _settings.Language);

        CodeSwitchingCheck.IsChecked = _settings.EnableCodeSwitching;
        LLMEnhancementCheck.IsChecked = _settings.EnableLLMEnhancement;
        ShowOverlayCheck.IsChecked = _settings.ShowOverlayOnStartup;
        LanguageCombo.IsEnabled = !_settings.EnableCodeSwitching;

        // STT Provider
        SttProviderCombo.Items.Clear();
        foreach (var p in Enum.GetValues<STTProvider>())
            SttProviderCombo.Items.Add(new ComboBoxItem { Content = p.ToString(), Tag = p });
        SelectComboByTag(SttProviderCombo, _settings.SttProvider);
        SttModelBox.Text = _settings.SttModel;

        // Dictation LLM Provider
        DictationLLMProviderCombo.Items.Clear();
        foreach (var p in Enum.GetValues<LLMProvider>())
            DictationLLMProviderCombo.Items.Add(new ComboBoxItem { Content = p.ToString(), Tag = p });
        SelectComboByTag(DictationLLMProviderCombo, _settings.DictationLLMProvider);
        DictationLLMModelBox.Text = _settings.DictationLLMModel;

        // Prompt LLM Provider
        PromptLLMProviderCombo.Items.Clear();
        foreach (var p in Enum.GetValues<LLMProvider>())
            PromptLLMProviderCombo.Items.Add(new ComboBoxItem { Content = p.ToString(), Tag = p });
        SelectComboByTag(PromptLLMProviderCombo, _settings.PromptLLMProvider);
        PromptModelBox.Text = _settings.PromptModel;

        // API Keys - show placeholder if stored
        if (!string.IsNullOrWhiteSpace(_settings.GroqApiKey))
            GroqKeyBox.Password = "********";
        if (!string.IsNullOrWhiteSpace(_settings.CerebrasApiKey))
            CerebrasKeyBox.Password = "********";
        if (!string.IsNullOrWhiteSpace(_settings.OpenRouterApiKey))
            OpenRouterKeyBox.Password = "********";

        _loading = false;
    }

    private void SttProvider_Changed(object sender, SelectionChangedEventArgs e)
    {
        if (_loading || SttProviderCombo.SelectedItem is not ComboBoxItem item) return;
        var provider = (STTProvider)item.Tag;
        if (string.IsNullOrWhiteSpace(SttModelBox.Text) || IsDefaultModel(SttModelBox.Text, typeof(STTProvider)))
            SttModelBox.Text = provider.DefaultModel();
    }

    private void DictationLLMProvider_Changed(object sender, SelectionChangedEventArgs e)
    {
        if (_loading || DictationLLMProviderCombo.SelectedItem is not ComboBoxItem item) return;
        var provider = (LLMProvider)item.Tag;
        if (string.IsNullOrWhiteSpace(DictationLLMModelBox.Text) || IsDefaultModel(DictationLLMModelBox.Text, typeof(LLMProvider)))
            DictationLLMModelBox.Text = provider.DefaultModel();
    }

    private void PromptLLMProvider_Changed(object sender, SelectionChangedEventArgs e)
    {
        if (_loading || PromptLLMProviderCombo.SelectedItem is not ComboBoxItem item) return;
        var provider = (LLMProvider)item.Tag;
        if (string.IsNullOrWhiteSpace(PromptModelBox.Text) || IsDefaultModel(PromptModelBox.Text, typeof(LLMProvider)))
            PromptModelBox.Text = provider.DefaultModel();
    }

    private void CodeSwitchingCheck_Changed(object sender, RoutedEventArgs e)
    {
        if (_loading) return;
        LanguageCombo.IsEnabled = !(CodeSwitchingCheck.IsChecked ?? false);
    }

    private async void SaveButton_OnClick(object sender, RoutedEventArgs e)
    {
        // Language
        _settings.Language = (LanguageCombo.SelectedItem as ComboBoxItem)?.Tag as string ?? "auto";
        _settings.EnableCodeSwitching = CodeSwitchingCheck.IsChecked ?? false;
        _settings.EnableLLMEnhancement = LLMEnhancementCheck.IsChecked ?? true;
        _settings.ShowOverlayOnStartup = ShowOverlayCheck.IsChecked ?? true;

        // STT
        if (SttProviderCombo.SelectedItem is ComboBoxItem sttItem)
            _settings.SttProvider = (STTProvider)sttItem.Tag;
        _settings.SttModel = string.IsNullOrWhiteSpace(SttModelBox.Text)
            ? _settings.SttProvider.DefaultModel()
            : SttModelBox.Text.Trim();

        // Dictation LLM
        if (DictationLLMProviderCombo.SelectedItem is ComboBoxItem dictItem)
            _settings.DictationLLMProvider = (LLMProvider)dictItem.Tag;
        _settings.DictationLLMModel = string.IsNullOrWhiteSpace(DictationLLMModelBox.Text)
            ? _settings.DictationLLMProvider.DefaultModel()
            : DictationLLMModelBox.Text.Trim();

        // Prompt LLM
        if (PromptLLMProviderCombo.SelectedItem is ComboBoxItem promptItem)
            _settings.PromptLLMProvider = (LLMProvider)promptItem.Tag;
        _settings.PromptModel = string.IsNullOrWhiteSpace(PromptModelBox.Text)
            ? _settings.PromptLLMProvider.DefaultModel()
            : PromptModelBox.Text.Trim();

        // API Keys - only update if user changed them (not the placeholder)
        var groqPw = GroqKeyBox.Password;
        if (!string.IsNullOrWhiteSpace(groqPw) && groqPw != "********")
            _settings.GroqApiKey = groqPw.Trim();

        var cerebrasPw = CerebrasKeyBox.Password;
        if (!string.IsNullOrWhiteSpace(cerebrasPw) && cerebrasPw != "********")
            _settings.CerebrasApiKey = cerebrasPw.Trim();

        var orPw = OpenRouterKeyBox.Password;
        if (!string.IsNullOrWhiteSpace(orPw) && orPw != "********")
            _settings.OpenRouterApiKey = orPw.Trim();

        await _settingsService.SaveAsync(_settings);
        DialogResult = true;
        Close();
    }

    // ── Helpers ──────────────────────────────────────────────────

    private static void SelectComboByTag<T>(ComboBox combo, T value)
    {
        foreach (ComboBoxItem item in combo.Items)
        {
            if (Equals(item.Tag, value))
            {
                combo.SelectedItem = item;
                return;
            }
        }
        if (combo.Items.Count > 0)
            combo.SelectedIndex = 0;
    }

    private static bool IsDefaultModel(string model, Type providerType)
    {
        if (providerType == typeof(STTProvider))
        {
            foreach (var p in Enum.GetValues<STTProvider>())
                if (p.DefaultModel() == model) return true;
        }
        else if (providerType == typeof(LLMProvider))
        {
            foreach (var p in Enum.GetValues<LLMProvider>())
                if (p.DefaultModel() == model) return true;
        }
        return false;
    }
}
