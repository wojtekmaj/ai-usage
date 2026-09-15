namespace AiUsage.Windows.UI;

/**
 * Keeps log rows distinct for WinUI automation even when their displayed text matches.
 */
public sealed class LogDisplayEntry(string text)
{
    public string Text { get; } = text;

    public override string ToString() => Text;
}
