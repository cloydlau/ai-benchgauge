using System.Collections.Concurrent;
using System.Diagnostics;
using System.Text;
using System.Text.Json;

namespace BenchGauge.Shared;
public sealed class EngineClient : IDisposable
{
    readonly Process process;
    readonly ConcurrentDictionary<int, TaskCompletionSource<EngineResponse>> pending = new();
    readonly SemaphoreSlim writeLock = new(1);
    int nextId;
    public EngineClient(string executable)
    {
        var start = new ProcessStartInfo(executable) { UseShellExecute = false, CreateNoWindow = true,
            RedirectStandardInput = true, RedirectStandardOutput = true, RedirectStandardError = true,
            StandardInputEncoding = new UTF8Encoding(false), StandardOutputEncoding = Encoding.UTF8 };
        process = Process.Start(start) ?? throw new IOException("Could not start the data engine");
        // Never log helper stderr: upstream diagnostics may contain account data.
        _ = process.StandardError.ReadToEndAsync();
        _ = ReadResponses();
    }
    async Task ReadResponses()
    {
        try
        {
            while (await process.StandardOutput.ReadLineAsync() is { } line)
            {
                if (line.Length > 4_194_304) throw new IOException("Engine response exceeds limit");
                var response = JsonSerializer.Deserialize<EngineResponse>(line, AppConfig.Json);
                if (response is not null && pending.TryRemove(response.Id, out var task)) task.TrySetResult(response);
            }
        }
        catch (Exception e) when (e is IOException or JsonException or InvalidOperationException) { }
        finally { foreach (var entry in pending) if (pending.TryRemove(entry.Key, out var task)) task.TrySetException(new IOException("Data engine disconnected")); }
    }
    public async Task<EngineResponse> Request(string command, Preferences prefs, string? providerID = null, string? loginID = null, string? authorizationURL = null)
    {
        var id = Interlocked.Increment(ref nextId);
        var completion = new TaskCompletionSource<EngineResponse>(TaskCreationOptions.RunContinuationsAsynchronously);
        pending[id] = completion;
        try
        {
            var json = JsonSerializer.Serialize(new { id, command, prefs.Category, prefs.Grouping, prefs.Language, providerID, loginID, authorizationURL }, AppConfig.Json);
            await writeLock.WaitAsync();
            try { await process.StandardInput.WriteLineAsync(json); await process.StandardInput.FlushAsync(); }
            finally { writeLock.Release(); }
            var response = await completion.Task.WaitAsync(TimeSpan.FromSeconds(command == "finishOpenAI" ? 320 : 90));
            if (response.Error is not null) throw new IOException(response.Error);
            return response;
        }
        finally { pending.TryRemove(id, out _); }
    }
    public void Dispose()
    {
        if (!process.HasExited) process.Kill(entireProcessTree: true);
        process.Dispose();
    }
}
