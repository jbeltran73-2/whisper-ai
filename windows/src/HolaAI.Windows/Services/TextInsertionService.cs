using System.Runtime.InteropServices;
using System.Windows;
using System.Windows.Threading;

namespace HolaAI.Windows.Services;

public sealed class TextInsertionService
{
    public async Task InsertTextAsync(string text, CancellationToken cancellationToken = default)
    {
        if (string.IsNullOrWhiteSpace(text))
        {
            return;
        }

        string? previousClipboard = null;
        await Application.Current.Dispatcher.InvokeAsync(() =>
        {
            if (Clipboard.ContainsText())
            {
                previousClipboard = Clipboard.GetText();
            }
            Clipboard.SetText(text);
        }, DispatcherPriority.Send, cancellationToken);

        SimulatePaste();

        await Task.Delay(200, cancellationToken);
        if (previousClipboard is not null)
        {
            await Application.Current.Dispatcher.InvokeAsync(() =>
            {
                Clipboard.SetText(previousClipboard);
            }, DispatcherPriority.Background, cancellationToken);
        }
    }

    private static void SimulatePaste()
    {
        var inputs = new INPUT[]
        {
            CreateKeyboardInput(VK_CONTROL, 0),
            CreateKeyboardInput(VK_V, 0),
            CreateKeyboardInput(VK_V, KEYEVENTF_KEYUP),
            CreateKeyboardInput(VK_CONTROL, KEYEVENTF_KEYUP)
        };

        SendInput((uint)inputs.Length, inputs, Marshal.SizeOf<INPUT>());
    }

    private static INPUT CreateKeyboardInput(ushort vk, uint flags) =>
        new()
        {
            type = INPUT_KEYBOARD,
            U = new InputUnion
            {
                ki = new KEYBDINPUT
                {
                    wVk = vk,
                    wScan = 0,
                    dwFlags = flags,
                    dwExtraInfo = IntPtr.Zero,
                    time = 0
                }
            }
        };

    private const uint INPUT_KEYBOARD = 1;
    private const uint KEYEVENTF_KEYUP = 0x0002;
    private const ushort VK_CONTROL = 0x11;
    private const ushort VK_V = 0x56;

    [DllImport("user32.dll", SetLastError = true)]
    private static extern uint SendInput(uint nInputs, INPUT[] pInputs, int cbSize);

    [StructLayout(LayoutKind.Sequential)]
    private struct INPUT
    {
        public uint type;
        public InputUnion U;
    }

    [StructLayout(LayoutKind.Explicit)]
    private struct InputUnion
    {
        [FieldOffset(0)] public KEYBDINPUT ki;
    }

    [StructLayout(LayoutKind.Sequential)]
    private struct KEYBDINPUT
    {
        public ushort wVk;
        public ushort wScan;
        public uint dwFlags;
        public uint time;
        public IntPtr dwExtraInfo;
    }
}
