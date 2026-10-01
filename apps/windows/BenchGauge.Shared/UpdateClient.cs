using System.Diagnostics;
using System.Security.Cryptography;
using System.Text.Json;
using System.Text.RegularExpressions;
using Org.BouncyCastle.Crypto.Parameters;
using Org.BouncyCastle.Crypto.Signers;

namespace BenchGauge.Shared;
public sealed record WindowsUpdate(string Version, string Url, string Sha256, long Length, string Notes);
public sealed class UpdateClient(AppConfig config, HttpClient? client = null, string? downloadDirectory = null)
{
    static readonly HttpClient sharedHttp = new() { Timeout = TimeSpan.FromMinutes(10) };
    readonly HttpClient http = client ?? sharedHttp;
    public static WindowsUpdate Verify(byte[] payload, string signature, string publicKey, string repository)
    {
        if (payload.Length > 65_536) throw new CryptographicException("Update metadata exceeds limit");
        var verifier = new Ed25519Signer();
        verifier.Init(false, new Ed25519PublicKeyParameters(Convert.FromBase64String(publicKey), 0));
        verifier.BlockUpdate(payload, 0, payload.Length);
        if (!verifier.VerifySignature(Convert.FromBase64String(signature.Trim()))) throw new CryptographicException("Invalid update signature");
        var update = JsonSerializer.Deserialize<WindowsUpdate>(payload, AppConfig.Json) ?? throw new JsonException("Missing update metadata");
        if (!Regex.IsMatch(update.Version, @"^(0|[1-9]\d*)\.(0|[1-9]\d*)\.(0|[1-9]\d*)$")) throw new JsonException("Invalid update version");
        var expected = $"https://github.com/{repository}/releases/download/v{update.Version}/AI-BenchGauge-{update.Version}-windows-x64-setup.exe";
        if (update.Url != expected || !Regex.IsMatch(update.Sha256, "^[a-f0-9]{64}$") || update.Length is <= 0 or > 1_073_741_824) throw new JsonException("Invalid update artifact");
        return update;
    }
    public async Task<WindowsUpdate?> Check()
    {
        var prefix = $"https://github.com/{config.Repository}/releases/latest/download/";
        var payload = await ReadLimited(prefix + "windows-update.json", 65_536);
        var signature = System.Text.Encoding.UTF8.GetString(await ReadLimited(prefix + "windows-update.json.sig", 1024));
        var update = Verify(payload, signature, config.UpdatePublicKey, config.Repository);
        return Version.Parse(update.Version) > Version.Parse(config.Version) ? update : null;
    }
    async Task<byte[]> ReadLimited(string url, int maximum)
    {
        using var response = await http.GetAsync(url, HttpCompletionOption.ResponseHeadersRead);
        response.EnsureSuccessStatusCode();
        if (response.Content.Headers.ContentLength > maximum) throw new IOException("Response exceeds limit");
        await using var stream = await response.Content.ReadAsStreamAsync();
        using var output = new MemoryStream();
        var buffer = new byte[8192];
        int count;
        while ((count = await stream.ReadAsync(buffer)) > 0)
        {
            if (output.Length + count > maximum) throw new IOException("Response exceeds limit");
            output.Write(buffer, 0, count);
        }
        return output.ToArray();
    }
    public async Task<string> Download(WindowsUpdate update, IProgress<double>? progress = null)
    {
        var directory = downloadDirectory ?? Path.Combine(Preferences.DirectoryPath, "updates");
        Directory.CreateDirectory(directory);
        var file = Path.Combine(directory, $"AI-BenchGauge-{update.Version}-setup.exe");
        // Reuse only a cache matching the authenticated version's size and digest.
        if (File.Exists(file) && new FileInfo(file).Length == update.Length)
        {
            await using var cached = File.OpenRead(file);
            var digest = await SHA256.HashDataAsync(cached);
            if (CryptographicOperations.FixedTimeEquals(digest, Convert.FromHexString(update.Sha256))) return file;
        }
        var temp = file + "." + Guid.NewGuid() + ".tmp";
        try
        {
            using var response = await http.GetAsync(update.Url, HttpCompletionOption.ResponseHeadersRead);
            response.EnsureSuccessStatusCode();
            if (response.Content.Headers.ContentLength is { } length && length != update.Length) throw new IOException("Installer length mismatch");
            await using var input = await response.Content.ReadAsStreamAsync();
            using var hash = IncrementalHash.CreateHash(HashAlgorithmName.SHA256);
            await using (var output = new FileStream(temp, FileMode.CreateNew, FileAccess.Write, FileShare.None))
            {
                var buffer = new byte[65_536]; long received = 0; int count;
                while ((count = await input.ReadAsync(buffer)) > 0)
                {
                    received += count;
                    if (received > update.Length) throw new IOException("Installer exceeds expected length");
                    hash.AppendData(buffer, 0, count); await output.WriteAsync(buffer.AsMemory(0, count));
                    progress?.Report((double)received / update.Length);
                }
                if (received != update.Length || !CryptographicOperations.FixedTimeEquals(hash.GetHashAndReset(), Convert.FromHexString(update.Sha256))) throw new CryptographicException("Installer integrity check failed");
            }
            File.Move(temp, file, true);
            return file;
        }
        finally { if (File.Exists(temp)) File.Delete(temp); }
    }
    public static void Install(string installer)
    {
        var start = new ProcessStartInfo(installer) { UseShellExecute = true };
        start.ArgumentList.Add("/UPDATE");
        start.ArgumentList.Add($"/WAITPID={Environment.ProcessId}");
        _ = Process.Start(start) ?? throw new InvalidOperationException("Installer could not start");
    }
}
