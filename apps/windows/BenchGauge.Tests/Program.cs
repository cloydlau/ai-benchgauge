using System.Security.Cryptography;
using System.Text;
using System.Text.Json;
using BenchGauge.Shared;
using Org.BouncyCastle.Crypto.Parameters;
using Org.BouncyCastle.Crypto.Signers;
using Org.BouncyCastle.Security;

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
Console.WriteLine("PASS: 13 Windows update signature, tampering, origin, size, configuration and version cases");
