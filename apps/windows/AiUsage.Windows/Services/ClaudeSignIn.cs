using System.Diagnostics;

namespace AiUsage.Windows.Services;

internal static class ClaudeSignIn
{
    private static Process? activeProcess;

    public static void CancelActiveProcess()
    {
        if (activeProcess is { HasExited: false } process)
        {
            process.Kill(entireProcessTree: true);
        }
    }

    public static async Task<int> RenewSessionAsync(CancellationToken cancellationToken)
    {
        // Credential verification decides whether startup renewed the session
        return await ExecuteAsync(
            ["--print", "--tools=", "--no-session-persistence", "--setting-sources=",
             "--settings", "{\"disableAllHooks\":true}", "--strict-mcp-config",
             "--mcp-config", "{\"mcpServers\":{}}", "--disable-slash-commands"],
            closeInput: true,
            timeoutDuration: TimeSpan.FromSeconds(30),
            cancellationToken);
    }

    public static async Task SignInAsync(CancellationToken cancellationToken)
    {
        var status = await ExecuteAsync(["auth", "login"], closeInput: false, timeoutDuration: TimeSpan.FromMinutes(10), cancellationToken);
        if (status != 0)
        {
            throw new InvalidOperationException("Claude sign-in did not complete.");
        }
    }

    private static async Task<int> ExecuteAsync(string[] arguments, bool closeInput, TimeSpan timeoutDuration, CancellationToken cancellationToken)
    {
        var executable = FindExecutable() ?? throw new FileNotFoundException("Claude Code was not found.");
        var temporaryDirectory = closeInput ? Directory.CreateTempSubdirectory("ai-usage-claude-") : null;
        try
        {
            return await RunProcessAsync(executable, arguments, temporaryDirectory?.FullName, closeInput, timeoutDuration, cancellationToken);
        }
        finally
        {
            temporaryDirectory?.Delete(recursive: true);
        }
    }

    private static async Task<int> RunProcessAsync(string executable, string[] arguments, string? workingDirectory, bool closeInput, TimeSpan timeoutDuration, CancellationToken cancellationToken)
    {
        var startInfo = new ProcessStartInfo(executable)
        {
            UseShellExecute = false,
            CreateNoWindow = true,
            RedirectStandardInput = true,
            RedirectStandardOutput = true,
            RedirectStandardError = true,
            WorkingDirectory = workingDirectory ?? Environment.GetFolderPath(Environment.SpecialFolder.UserProfile),
        };
        if (Path.GetExtension(executable).Equals(".cmd", StringComparison.OrdinalIgnoreCase))
        {
            startInfo.FileName = Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.System), "WindowsPowerShell", "v1.0", "powershell.exe");
            startInfo.Environment["AI_USAGE_CLAUDE_EXECUTABLE"] = executable;
            startInfo.ArgumentList.Add("-NoProfile");
            startInfo.ArgumentList.Add("-Command");
            var quotedArguments = arguments.Select(argument => "'" + argument.Replace("\"", "\\\"").Replace("'", "''") + "'");
            startInfo.ArgumentList.Add("& $env:AI_USAGE_CLAUDE_EXECUTABLE " + string.Join(" ", quotedArguments) + "; exit $LASTEXITCODE");
        }
        else
        {
            foreach (var argument in arguments)
            {
                startInfo.ArgumentList.Add(argument);
            }
        }

        using var process = new Process { StartInfo = startInfo };
        cancellationToken.ThrowIfCancellationRequested();
        process.Start();
        activeProcess = process;
        if (closeInput)
        {
            process.StandardInput.Close();
        }

        using var timeout = CancellationTokenSource.CreateLinkedTokenSource(cancellationToken);
        timeout.CancelAfter(timeoutDuration);
        var output = process.StandardOutput.BaseStream.CopyToAsync(Stream.Null, timeout.Token);
        var error = process.StandardError.BaseStream.CopyToAsync(Stream.Null, timeout.Token);
        try
        {
            await Task.WhenAll(process.WaitForExitAsync(timeout.Token), output, error);
            cancellationToken.ThrowIfCancellationRequested();

            return process.ExitCode;
        }
        catch (OperationCanceledException) when (!cancellationToken.IsCancellationRequested)
        {
            throw new TimeoutException("Claude sign-in timed out.");
        }
        finally
        {
            activeProcess = null;
            if (!process.HasExited)
            {
                process.Kill(entireProcessTree: true);
                await process.WaitForExitAsync();
            }
        }
    }

    private static string? FindExecutable()
    {
        var home = Environment.GetFolderPath(Environment.SpecialFolder.UserProfile);
        var paths = new[] { Path.Combine(home, ".local", "bin"), Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.ApplicationData), "npm") }
            .Concat((Environment.GetEnvironmentVariable("PATH") ?? "").Split(Path.PathSeparator, StringSplitOptions.RemoveEmptyEntries));

        return paths.SelectMany(path => new[] { Path.Combine(path, "claude.exe"), Path.Combine(path, "claude.cmd") })
            .FirstOrDefault(File.Exists);
    }
}
