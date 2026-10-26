namespace AiUsage.Windows.Services;

internal sealed class ClaudeSessionStore(CredentialStore credentials)
{
    private const string Account = "claude.oauth-session";
    private string? cached;
    private string? persisted;

    public string? Load()
    {
        if (cached is not null)
        {
            return cached;
        }

        cached = credentials.Load(Account);
        persisted = cached;

        return cached;
    }

    public void Save(string value)
    {
        // Keep rotated tokens in memory if the vault is temporarily unavailable
        cached = value;
        if (persisted == value)
        {
            return;
        }

        credentials.Save(Account, value);
        persisted = value;
    }
}
