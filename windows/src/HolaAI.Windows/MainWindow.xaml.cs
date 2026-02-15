using System.Windows;
using System.Windows.Input;
using System.Windows.Interop;
using HolaAI.Windows.Services;
using HolaAI.Windows.ViewModels;

namespace HolaAI.Windows;

public partial class MainWindow : Window
{
    private readonly OverlayViewModel _viewModel = new();
    private readonly GlobalHotkeyService _hotkeyService = new();
    private readonly SettingsService _settingsService = new();
    private readonly DictationManager _dictationManager;

    public MainWindow()
    {
        InitializeComponent();
        DataContext = _viewModel;

        _dictationManager = new DictationManager(
            new AudioCaptureService(),
            new OpenRouterClient(),
            new TextInsertionService(),
            _settingsService);

        _dictationManager.AudioLevelChanged += level => { /* TODO: bind level meter */ };
        _dictationManager.TranscriptionReady += text =>
        {
            _viewModel.LastText = text;
            _viewModel.IsRecording = false;
        };

        Loaded += OnLoaded;
        Closed += OnClosed;
    }

    private void OnLoaded(object sender, RoutedEventArgs e)
    {
        var handle = new WindowInteropHelper(this).Handle;
        _hotkeyService.Register(handle);
        _hotkeyService.ToggleDictationPressed += async () => await ToggleDictationAsync();
        _hotkeyService.ToggleModePressed += () => _viewModel.IsPromptMode = !_viewModel.IsPromptMode;
    }

    private void OnClosed(object? sender, EventArgs e)
    {
        _hotkeyService.Dispose();
        _dictationManager.Dispose();
    }

    private async Task ToggleDictationAsync()
    {
        try
        {
            await Dispatcher.InvokeAsync(() => _viewModel.IsRecording = !_viewModel.IsRecording);
            await _dictationManager.ToggleAsync(_viewModel.ToOptions());
        }
        catch (Exception ex)
        {
            await Dispatcher.InvokeAsync(() =>
            {
                _viewModel.IsRecording = false;
                MessageBox.Show(this, ex.Message, "Hola-AI", MessageBoxButton.OK, MessageBoxImage.Warning);
            });
        }
    }

    private async void RecordButton_OnClick(object sender, RoutedEventArgs e)
    {
        await ToggleDictationAsync();
    }

    private void CopyButton_OnClick(object sender, RoutedEventArgs e)
    {
        if (!string.IsNullOrWhiteSpace(_viewModel.LastText))
        {
            Clipboard.SetText(_viewModel.LastText);
        }
    }

    private void CloseButton_OnClick(object sender, RoutedEventArgs e)
    {
        Close();
    }

    private void SettingsButton_OnClick(object sender, RoutedEventArgs e)
    {
        var settingsWindow = new SettingsWindow(_settingsService)
        {
            Owner = this
        };
        settingsWindow.ShowDialog();
    }

    private void Root_OnMouseLeftButtonDown(object sender, MouseButtonEventArgs e)
    {
        if (e.ButtonState == MouseButtonState.Pressed)
        {
            DragMove();
        }
    }
}
