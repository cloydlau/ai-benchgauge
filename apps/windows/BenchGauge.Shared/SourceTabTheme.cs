using System.Text.Json;

namespace BenchGauge.Shared;

// Full source identifiers select the same brand palette used by mobile tabs.
public static class SourceTabTheme
{
    public sealed record Palette(string Background, string Foreground, string Accent);
    static readonly Dictionary<string, (Palette Light, Palette Dark)> Sources = new();
    static readonly (Palette Light, Palette Dark) Fallback;

    static SourceTabTheme()
    {
        using var stream = typeof(SourceTabTheme).Assembly.GetManifestResourceStream("BenchGauge.Shared.SourceTabThemes.json")
            ?? throw new InvalidOperationException("Missing source themes");
        using var document = JsonDocument.Parse(stream);
        static Palette Read(JsonElement value) => new(value.GetProperty("background").GetString()!,
            value.GetProperty("foreground").GetString()!, value.GetProperty("accent").GetString()!);
        static (Palette, Palette) Variants(JsonElement value) => (Read(value.GetProperty("light")), Read(value.GetProperty("dark")));
        Fallback = Variants(document.RootElement.GetProperty("fallback"));
        foreach (var source in document.RootElement.GetProperty("sources").EnumerateArray())
            foreach (var kind in source.GetProperty("kinds").EnumerateArray())
                Sources.Add(kind.GetString()!, Variants(source));
    }

    public static Palette For(string kind, bool dark)
    {
        var pair = Sources.GetValueOrDefault(kind, Fallback);
        return dark ? pair.Dark : pair.Light;
    }
}
