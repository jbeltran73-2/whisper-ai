using System.ComponentModel;
using System.Runtime.CompilerServices;
using HolaAI.Windows.Models;

namespace HolaAI.Windows.ViewModels;

public sealed class OverlayViewModel : INotifyPropertyChanged
{
    private bool _isRecording;
    private bool _isPromptMode;
    private bool _translateToEnglish;
    private bool _canCopyLastText;
    private string _lastText = string.Empty;

    public event PropertyChangedEventHandler? PropertyChanged;

    public bool IsRecording
    {
        get => _isRecording;
        set => SetField(ref _isRecording, value);
    }

    public bool IsPromptMode
    {
        get => _isPromptMode;
        set
        {
            if (SetField(ref _isPromptMode, value) && value)
            {
                TranslateToEnglish = true;
            }
        }
    }

    public bool TranslateToEnglish
    {
        get => _translateToEnglish;
        set => SetField(ref _translateToEnglish, value);
    }

    public bool CanCopyLastText
    {
        get => _canCopyLastText;
        set => SetField(ref _canCopyLastText, value);
    }

    public string LastText
    {
        get => _lastText;
        set
        {
            if (SetField(ref _lastText, value))
            {
                CanCopyLastText = !string.IsNullOrWhiteSpace(value);
            }
        }
    }

    public DictationOptions ToOptions() =>
        new(IsPromptMode ? DictationIntent.Prompt : DictationIntent.Transcription, TranslateToEnglish);

    private bool SetField<T>(ref T backingField, T value, [CallerMemberName] string? propertyName = null)
    {
        if (EqualityComparer<T>.Default.Equals(backingField, value))
        {
            return false;
        }

        backingField = value;
        PropertyChanged?.Invoke(this, new PropertyChangedEventArgs(propertyName));
        return true;
    }
}
