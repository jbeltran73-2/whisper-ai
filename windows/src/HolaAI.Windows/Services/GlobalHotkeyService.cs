using System.Runtime.InteropServices;
using System.Windows.Interop;

namespace HolaAI.Windows.Services;

public sealed class GlobalHotkeyService : IDisposable
{
    private const int HotkeyIdToggleDictation = 0xA001;
    private const int HotkeyIdToggleMode = 0xA002;
    private const int WmHotkey = 0x0312;

    private HwndSource? _source;
    private nint _windowHandle;

    public event Action? ToggleDictationPressed;
    public event Action? ToggleModePressed;

    public void Register(nint windowHandle)
    {
        _windowHandle = windowHandle;
        _source = HwndSource.FromHwnd(windowHandle);
        _source?.AddHook(WndProc);

        // Cmd+Shift+D equivalent on Windows: Ctrl+Shift+D
        RegisterHotKey(windowHandle, HotkeyIdToggleDictation, MOD_CONTROL | MOD_SHIFT, (uint)0x44);
        // Ctrl+Shift+C
        RegisterHotKey(windowHandle, HotkeyIdToggleMode, MOD_CONTROL | MOD_SHIFT, (uint)0x43);
    }

    public void Dispose()
    {
        if (_windowHandle != nint.Zero)
        {
            UnregisterHotKey(_windowHandle, HotkeyIdToggleDictation);
            UnregisterHotKey(_windowHandle, HotkeyIdToggleMode);
        }

        if (_source is not null)
        {
            _source.RemoveHook(WndProc);
            _source = null;
        }
    }

    private nint WndProc(nint hwnd, int msg, nint wParam, nint lParam, ref bool handled)
    {
        if (msg != WmHotkey)
        {
            return nint.Zero;
        }

        switch (wParam.ToInt32())
        {
            case HotkeyIdToggleDictation:
                ToggleDictationPressed?.Invoke();
                handled = true;
                break;
            case HotkeyIdToggleMode:
                ToggleModePressed?.Invoke();
                handled = true;
                break;
        }

        return nint.Zero;
    }

    private const uint MOD_CONTROL = 0x0002;
    private const uint MOD_SHIFT = 0x0004;

    [DllImport("user32.dll", SetLastError = true)]
    private static extern bool RegisterHotKey(nint hWnd, int id, uint fsModifiers, uint vk);

    [DllImport("user32.dll", SetLastError = true)]
    private static extern bool UnregisterHotKey(nint hWnd, int id);
}
