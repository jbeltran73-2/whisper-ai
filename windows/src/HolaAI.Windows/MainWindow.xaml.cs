using System.Windows;
using System.Windows.Input;
using System.Windows.Interop;
using System.Runtime.InteropServices;
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

        var apiClient = new ApiClient();
        var textProcessing = new TextProcessingService(apiClient);

        _dictationManager = new DictationManager(
            new AudioCaptureService(),
            apiClient,
            textProcessing,
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

    protected override void OnSourceInitialized(EventArgs e)
    {
        base.OnSourceInitialized(e);

        var hwnd = new WindowInteropHelper(this).Handle;
        var exStyle = GetWindowLongPtr(hwnd, GWL_EXSTYLE).ToInt64();
        _ = SetWindowLongPtr(hwnd, GWL_EXSTYLE, new IntPtr(exStyle | WS_EX_NOACTIVATE));

        HwndSource.FromHwnd(hwnd)?.AddHook(WndProc);
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

    private IntPtr WndProc(IntPtr hwnd, int msg, IntPtr wParam, IntPtr lParam, ref bool handled)
    {
        if (msg == WM_MOUSEACTIVATE)
        {
            handled = true;
            return new IntPtr(MA_NOACTIVATE);
        }

        return IntPtr.Zero;
    }

    private static IntPtr GetWindowLongPtr(IntPtr hwnd, int index)
    {
        return IntPtr.Size == 8 ? GetWindowLongPtr64(hwnd, index) : GetWindowLong32(hwnd, index);
    }

    private static IntPtr SetWindowLongPtr(IntPtr hwnd, int index, IntPtr value)
    {
        return IntPtr.Size == 8 ? SetWindowLongPtr64(hwnd, index, value) : SetWindowLong32(hwnd, index, value);
    }

    private const int GWL_EXSTYLE = -20;
    private const long WS_EX_NOACTIVATE = 0x08000000L;
    private const int WM_MOUSEACTIVATE = 0x0021;
    private const int MA_NOACTIVATE = 3;

    [DllImport("user32.dll", EntryPoint = "GetWindowLong")]
    private static extern IntPtr GetWindowLong32(IntPtr hwnd, int index);

    [DllImport("user32.dll", EntryPoint = "GetWindowLongPtr")]
    private static extern IntPtr GetWindowLongPtr64(IntPtr hwnd, int index);

    [DllImport("user32.dll", EntryPoint = "SetWindowLong")]
    private static extern IntPtr SetWindowLong32(IntPtr hwnd, int index, IntPtr value);

    [DllImport("user32.dll", EntryPoint = "SetWindowLongPtr")]
    private static extern IntPtr SetWindowLongPtr64(IntPtr hwnd, int index, IntPtr value);
}
