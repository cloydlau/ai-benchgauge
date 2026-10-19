using System.Security.Cryptography;
using System.Text;
using System.Text.Json;
using BenchGauge.Shared;
using Org.BouncyCastle.Crypto.Parameters;
using Org.BouncyCastle.Crypto.Signers;
using Org.BouncyCastle.Security;

// Model distributions retain unknowns and the China policy without score weighting.
var distributionEntries = new[] {
    new Entry(1, "A", 9999, "Maker", "US", null, null, null, null, "closed"),
    new Entry(2, "B", 1, "Maker", "HK", null, null, null, null, "open"),
    new Entry(3, "C", 0, "Maker", "TW", null, null, null, null, "open"),
    new Entry(4, "D", 0, null, null, null, null, null, null) };
var modelDistribution = LeaderboardDistribution.FromEntries(distributionEntries);
if (modelDistribution.Total != 4 || modelDistribution.Countries.Single(slice => slice.Id == "CN").Count != 2 ||
    !modelDistribution.Sources.Select(slice => slice.Count).SequenceEqual(new[] { 2, 1, 1 }) ||
    LeaderboardDistribution.FromEntries([]).Sources.Any(slice => slice.Percent != "—"))
    throw new Exception("Incorrect full-board distributions");
var knownDistribution = LeaderboardDistribution.FromEntries(distributionEntries.Take(3).ToArray());
if (knownDistribution.Countries.Any(slice => slice.Id == "unknown") ||
    !knownDistribution.Sources.Select(slice => slice.Id).SequenceEqual(new[] { "open", "closed" }) ||
    LeaderboardDistribution.FromEntries([]).Sources.Any(slice => slice.Id == "unknown"))
    throw new Exception("Zero-count unknown chart items must be hidden");
var summaryBoard = JsonSerializer.Deserialize<Board>("""{"kind":"arenaText","title":"Arena","url":"https://example.test","entries":[],"distribution":{"total":8,"countries":[{"id":"CN","count":8,"total":8}],"sources":[{"id":"unknown","count":8,"total":8}]}}""", AppConfig.Json)!;
if (summaryBoard.Distribution is not { } summaryDistribution || summaryDistribution.Total != 8 || summaryDistribution.Countries[0].Percent != "100.0%")
    throw new Exception("Engine distribution must survive empty filtered/company projections");

// Search accepts unordered words, case/width/diacritic variants, and whitespace.
foreach (var sample in new (string Name, string Query, bool Expected)[] {
    ("DeepSeek V3.2 Speciale", "speciale DEEP", true),
    ("Café ＧＰＴ", "cafe gpt", true), ("Claude Sonnet", "   ", true),
    ("GPT-5", "GPT Claude", false), ("OpenAI", "openai", true) })
    if (LeaderboardSearch.Matches(sample.Name, sample.Query) != sample.Expected)
        throw new Exception("Incorrect selected-leaderboard search matching");

foreach (var sample in new[] {
    (Score: 100d, Leader: 100d, Expected: 1d), (50, 100, 0.5), (99.6, 100, 0.996), (0, 100, 0),
    (120, 100, 1), (1, 0, 1), (-1, 100, 1), (double.NaN, 100, 1),
    (double.PositiveInfinity, 100, 1), (1, double.PositiveInfinity, 1), (1, double.NaN, 1) })
    if (ScoreShare.FillRatio(sample.Score, sample.Leader) != sample.Expected)
        throw new Exception("Incorrect score background ratio");

foreach (var sample in new[] {
    (Score: 56d, Leader: 57.6d, Expected: "97%"), (97.5, 100, "98%"), (0, 100, "0%"),
    (100, 100, ""), (99.6, 100, ""), (101, 100, ""), (1, 0, ""), (-1, 100, ""),
    (double.NaN, 100, ""), (1, double.PositiveInfinity, ""), (double.PositiveInfinity, 1, "") })
    if (ScoreShare.Format(sample.Score, sample.Leader) != sample.Expected)
        throw new Exception("Incorrect score share");

foreach (var code in new[] { "CN", "HK", "MO", "TW", " hk ", "mo", "tw", "HKG", "MAC", "TWN", "Hong Kong", "Macao", "Macau", "Taiwan", "香港", "澳门", "澳門", "台湾", "台灣", "臺灣" })
{
    var saved = JsonSerializer.Deserialize<Preferences>(JsonSerializer.Serialize(new { countries = new { arenaText = code } }), AppConfig.Json)!;
    if (saved.Countries["arenaText"] != "china" || LeaderboardCountryPolicy.NormalizeFilter(code) != "china")
        throw new Exception("China country filter migration failed: " + code);
}
if (LeaderboardCountryPolicy.NormalizeFilter("JP") != "JP" || LeaderboardCountryPolicy.NormalizeFilter("unknown") != "unknown")
    throw new Exception("Country migration changed unrelated filters");

// Shared images arrive in the engine response; older engines remain readable.
var brandedEntry = JsonSerializer.Deserialize<Entry>("""
    {"rank":1,"name":"New Model","score":99,"organization":"New Maker","brandColor":"#319FA8","logoPNG":"iVBORw0KGgo=","initials":"N"}
    """, AppConfig.Json)!;
if (brandedEntry.BrandColor != "#319FA8" || brandedEntry.LogoPNG != "iVBORw0KGgo=" || brandedEntry.Initials != "N")
    throw new Exception("Shared brand fields lost in engine protocol");
var legacyEntry = JsonSerializer.Deserialize<Entry>("""{"rank":1,"name":"Old Model","score":99}""", AppConfig.Json)!;
if (legacyEntry.BrandColor is not null || legacyEntry.LogoPNG is not null || legacyEntry.Initials is not null)
    throw new Exception("Legacy engine response cannot require brand fields");

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
var recoveryResponse = JsonSerializer.Deserialize<EngineResponse>("""
    {"id":1,"qwenQuotaRefreshNeeded":true,"result":{"boards":[],"quotas":[],"quotaNeedsCCSwitch":false,"quotaUnavailable":false,"alerts":[{"title":"GLM · Quota restored","body":"5h 100%"}]}}
    """, AppConfig.Json)!;
if (recoveryResponse.QwenQuotaRefreshNeeded != true || recoveryResponse.Result?.Alerts.Single().Title != "GLM · Quota restored")
    throw new Exception("Recovery response lost provider identity or website refresh request");
var oldResponse = JsonSerializer.Deserialize<EngineResponse>("{\"id\":2}", AppConfig.Json)!;
if (oldResponse.QwenQuotaRefreshNeeded is not null) throw new Exception("Older responses must not request a website refresh");

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
// The desktop source selection defaults to all three, survives persistence,
// cannot become empty, and keeps separate choices for other categories.
var visibility = new Preferences();
if (!visibility.VisibleBoardKinds().SequenceEqual(new[] { "artificialAnalysis", "arenaText", "epochECI" }))
    throw new Exception("Desktop must default to all three boards");
visibility.ToggleBoard("arenaText"); visibility.ToggleBoard("artificialAnalysis"); visibility.ToggleBoard("epochECI");
if (!visibility.VisibleBoardKinds().SequenceEqual(new[] { "epochECI" })) throw new Exception("Last board was deselected");
visibility = JsonSerializer.Deserialize<Preferences>(JsonSerializer.Serialize(visibility, AppConfig.Json), AppConfig.Json)!;
if (!visibility.VisibleBoardKinds().SequenceEqual(new[] { "epochECI" })) throw new Exception("Board selection did not persist");
visibility.Category = "coding";
if (visibility.VisibleBoardKinds().Length != 2) throw new Exception("Board selections leaked between categories");
visibility.Category = "general"; visibility.ToggleBoard("artificialAnalysis");
if (!visibility.VisibleBoardKinds().SequenceEqual(new[] { "artificialAnalysis", "epochECI" })) throw new Exception("Restored board order is wrong");
foreach (var invalid in new[] { Array.Empty<string>(), new[] { "retired" }, new[] { "arenaTextToImage" } }) {
    visibility.BoardSelections["general"] = invalid;
    if (visibility.VisibleBoardKinds().Length != 3) throw new Exception("Invalid board preferences were not repaired");
}

Console.WriteLine("PASS: desktop board defaults, persistence, minimum selection, category isolation and invalid-preference recovery");
var stagedPreferences = new Preferences();
var draftBoards = stagedPreferences.VisibleBoardKinds().ToHashSet();
draftBoards.Remove("artificialAnalysis"); draftBoards.Remove("arenaText");
if (stagedPreferences.VisibleBoardKinds().Length != 3 || stagedPreferences.BoardSelections.Count != 0)
    throw new Exception("Draft board selection changed preferences before confirmation");
if (!stagedPreferences.SetVisibleBoards(draftBoards) || !stagedPreferences.VisibleBoardKinds().SequenceEqual(new[] { "epochECI" }))
    throw new Exception("Confirmed board selection was not applied as a batch");
if (stagedPreferences.SetVisibleBoards(draftBoards) || stagedPreferences.SetVisibleBoards([]) || stagedPreferences.SetVisibleBoards(["retired"]))
    throw new Exception("Unchanged or invalid selections should not trigger a refresh");
if (!stagedPreferences.SetVisibleBoards(["epochECI", "artificialAnalysis", "epochECI"]) ||
    !stagedPreferences.VisibleBoardKinds().SequenceEqual(new[] { "artificialAnalysis", "epochECI" }))
    throw new Exception("Batch board selection must retain catalog order and remove duplicates");
Console.WriteLine("PASS: desktop board draft isolation and confirmed batch selection");

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
