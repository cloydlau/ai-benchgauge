using System.Security.Cryptography;
using System.Text;
using System.Text.Json;
using BenchGauge.Shared;
using Org.BouncyCastle.Crypto.Parameters;
using Org.BouncyCastle.Crypto.Signers;
using Org.BouncyCastle.Security;

// Stable data timestamps, boundary ages and language forms; rendering alone
// must never fabricate a just-now timestamp from the presence of quota cards.
var ageNow = DateTimeOffset.Parse("2026-10-01T12:00:00Z");
foreach (var sample in new[] {
    (Seconds: 0, En: "just now", Zh: "刚刚", Hant: "剛剛"),
    (Seconds: 59, En: "just now", Zh: "刚刚", Hant: "剛剛"),
    (Seconds: 60, En: "1 min ago", Zh: "1 分钟前", Hant: "1 分鐘前"),
    (Seconds: 3599, En: "59 min ago", Zh: "59 分钟前", Hant: "59 分鐘前"),
    (Seconds: 3600, En: "1 hr ago", Zh: "1 小时前", Hant: "1 小時前"),
    (Seconds: 86399, En: "23 hr ago", Zh: "23 小时前", Hant: "23 小時前"),
    (Seconds: 86400, En: "1 day ago", Zh: "1 天前", Hant: "1 天前"),
    (Seconds: 172800, En: "2 days ago", Zh: "2 天前", Hant: "2 天前") })
{
    var date = ageNow.AddSeconds(-sample.Seconds);
    if (UpdateAge.Format(date, ageNow, "en") != sample.En || UpdateAge.Format(date, ageNow, "zh") != sample.Zh || UpdateAge.Format(date, ageNow, "zh-Hant") != sample.Hant)
        throw new Exception("Incorrect relative update age");
}
if (UpdateAge.Parse("invalid") is not null || UpdateAge.Format(null, ageNow, "zh") != "待更新" ||
    UpdateAge.Format(ageNow.AddSeconds(30), ageNow, "zh") != "刚刚" ||
    UpdateAge.Parse("2026-10-01T20:00:00+08:00") != ageNow) throw new Exception("Incorrect unknown or offset update time");
var oldState = JsonSerializer.Deserialize<DisplayState>("{\"boards\":[],\"quotas\":[],\"quotaNeedsCCSwitch\":false,\"quotaUnavailable\":false,\"alerts\":[]}", AppConfig.Json)!;
if (oldState.QuotaUpdatedAt is not null) throw new Exception("Missing data timestamp must remain unknown");

var keys = new Ed25519PrivateKeyParameters(new SecureRandom());
var publicKey = Convert.ToBase64String(keys.GeneratePublicKey().GetEncoded());
const string repository = "cloydlau/ai-benchgauge";
var valid = new WindowsUpdate("1.2.3", "https://github.com/cloydlau/ai-benchgauge/releases/download/v1.2.3/AI-BenchGauge-1.2.3-windows-x64-setup.exe", new string('a', 64), 123, "Release notes");
byte[] Encode(WindowsUpdate update) => JsonSerializer.SerializeToUtf8Bytes(update, AppConfig.Json);
string Sign(byte[] data)
{
    var signer = new Ed25519Signer(); signer.Init(true, keys); signer.BlockUpdate(data, 0, data.Length);
    return Convert.ToBase64String(signer.GenerateSignature());
}
void Reject(Action action)
{
    try { action(); } catch (Exception e) when (e is CryptographicException or JsonException or FormatException or ArgumentException) { return; }
    throw new Exception("Accepted invalid update");
}
var bytes = Encode(valid);
if (UpdateClient.Verify(bytes, Sign(bytes), publicKey, repository) != valid) throw new Exception("Could not verify update");
var tampered = bytes.ToArray(); tampered[10] ^= 1;
Reject(() => UpdateClient.Verify(tampered, Sign(bytes), publicKey, repository));
var wrongKey = Convert.ToBase64String(new Ed25519PrivateKeyParameters(new SecureRandom()).GeneratePublicKey().GetEncoded());
Reject(() => UpdateClient.Verify(bytes, Sign(bytes), wrongKey, repository));
Reject(() => UpdateClient.Verify(bytes, Convert.ToBase64String(new byte[63]), publicKey, repository));
foreach (var invalid in new[] {
    valid with { Url = "https://evil.example/installer.exe" }, valid with { Url = valid.Url + "?token=anything" },
    valid with { Version = "1.2.3-beta" }, valid with { Version = "01.2.3" }, valid with { Length = 0 },
    valid with { Length = 1_073_741_825 }, valid with { Sha256 = "bad" } })
{
    var bad = Encode(invalid); Reject(() => UpdateClient.Verify(bad, Sign(bad), publicKey, repository));
}
var oversized = Encoding.UTF8.GetBytes(new string('x', 65_537));
Reject(() => UpdateClient.Verify(oversized, Sign(oversized), publicKey, repository));
if (AppConfig.Load().Repository != repository) throw new Exception("Wrong embedded repository");
if (Version.Parse("1.10.0") <= Version.Parse("1.9.99")) throw new Exception("Version comparison must be numeric");
// Every ordering of download completion, activation, visibility and modal state.
var gateCases = 0;
foreach (var visible in new[] { false, true })
foreach (var active in new[] { false, true })
foreach (var modal in new[] { false, true })
foreach (var closing in new[] { false, true })
{
    var gate = new PreparedUpdate();
    if (gate.TryPresent(visible, active, modal, closing)) throw new Exception("Prompt before download");
    gate.Ready("verified-installer.exe");
    if (gate.Confirm() is not null) throw new Exception("Install before presenting");
    var expected = visible && active && !modal && !closing;
    if (gate.TryPresent(visible, active, modal, closing) != expected) throw new Exception("Incorrect update presentation gate");
    if (expected)
    {
        if (gate.TryPresent(true, true, false, false)) throw new Exception("Duplicate update dialog");
        if (gate.Confirm() != "verified-installer.exe" || gate.Confirm() is not null) throw new Exception("Install must be confirmed once");
        gate.InstallationFailed();
        if (gate.Confirm() != "verified-installer.exe") throw new Exception("Failed installer must be retryable");
    }
    else if (!gate.TryPresent(true, true, false, false)) throw new Exception("Deferred prompt lost after activation");
    gateCases++;
}
var pending = new PreparedUpdate();
pending.Ready("first.exe"); pending.Ready("second.exe");
if (!pending.TryPresent(true, true, false, false) || pending.Confirm() != "first.exe") throw new Exception("Pending installer changed under the dialog");

var fixtureDirectory = Path.Combine(Path.GetTempPath(), "BenchGauge-update-tests-" + Guid.NewGuid());
var installerBytes = Encoding.UTF8.GetBytes("Synthetic installer: must never be executed");
var downloadUpdate = valid with { Length = installerBytes.Length, Sha256 = Convert.ToHexStringLower(SHA256.HashData(installerBytes)) };
var fixtureConfig = new AppConfig("1.2.2", repository, publicKey);
var downloadCases = 0;
try
{
    var payload = Encode(downloadUpdate);
    using var handler = new FixtureHttpHandler(request => request.RequestUri!.AbsolutePath.EndsWith(".sig")
        ? Encoding.UTF8.GetBytes(Sign(payload)) : request.RequestUri.AbsolutePath.EndsWith(".json") ? payload : installerBytes);
    using var http = new HttpClient(handler);
    var client = new UpdateClient(fixtureConfig, http, fixtureDirectory);
    if (await client.Check() != downloadUpdate) throw new Exception("Higher signed version not detected");
    downloadCases++;
    var file = await client.Download(downloadUpdate);
    if (!File.ReadAllBytes(file).SequenceEqual(installerBytes)) throw new Exception("Verified installer not saved");
    var requests = handler.Requests;
    if (await client.Download(downloadUpdate) != file || handler.Requests != requests) throw new Exception("Verified cache not reused");
    downloadCases++;
    File.WriteAllBytes(file, new byte[installerBytes.Length]);
    await client.Download(downloadUpdate);
    if (!File.ReadAllBytes(file).SequenceEqual(installerBytes) || handler.Requests != requests + 1) throw new Exception("Corrupt cache not replaced");
    downloadCases++;
    var currentClient = new UpdateClient(fixtureConfig with { Version = "1.2.3" }, http, fixtureDirectory);
    if (await currentClient.Check() is not null) throw new Exception("Same version offered as update");
    var newerClient = new UpdateClient(fixtureConfig with { Version = "1.2.4" }, http, fixtureDirectory);
    if (await newerClient.Check() is not null) throw new Exception("Rollback offered as update");
    downloadCases += 2;
    File.Delete(file);
    foreach (var badBytes in new[] { new byte[installerBytes.Length], installerBytes[..^1], installerBytes.Concat(new byte[] { 0 }).ToArray() })
    {
        using var badHandler = new FixtureHttpHandler(_ => badBytes);
        using var badHttp = new HttpClient(badHandler);
        try { await new UpdateClient(fixtureConfig, badHttp, fixtureDirectory).Download(downloadUpdate); throw new Exception("Accepted corrupt download"); }
        catch (Exception error) when (error is CryptographicException or IOException) { }
        if (Directory.GetFiles(fixtureDirectory).Length != 0) throw new Exception("Failed download left installer or temporary data");
        downloadCases++;
    }
    using var tamperedHandler = new FixtureHttpHandler(request => request.RequestUri!.AbsolutePath.EndsWith(".sig") ? Encoding.UTF8.GetBytes(Sign(payload)) : tampered);
    using var tamperedHttp = new HttpClient(tamperedHandler);
    try { await new UpdateClient(fixtureConfig, tamperedHttp, fixtureDirectory).Check(); throw new Exception("Accepted tampered live metadata"); }
    catch (CryptographicException) { }
    downloadCases++;
}
finally { if (Directory.Exists(fixtureDirectory)) Directory.Delete(fixtureDirectory, true); }
Console.WriteLine($"PASS: 13 signature/configuration cases, {gateCases + 1} update presentation cases, {downloadCases} signed check/download/cache/integrity cases");

sealed class FixtureHttpHandler(Func<HttpRequestMessage, byte[]> response) : HttpMessageHandler
{
    public int Requests { get; private set; }
    protected override Task<HttpResponseMessage> SendAsync(HttpRequestMessage request, CancellationToken cancellationToken)
    {
        Requests++;
        return Task.FromResult(new HttpResponseMessage(System.Net.HttpStatusCode.OK) { Content = new ByteArrayContent(response(request)) });
    }
}
