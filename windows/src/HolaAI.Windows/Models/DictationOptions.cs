namespace HolaAI.Windows.Models;

public sealed record DictationOptions(
    DictationIntent Intent,
    bool TranslateToEnglish
);
