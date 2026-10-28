using System;
using System.IO;
using System.Reflection;
using System.Text.Json;
using System.Windows;
using System.Windows.Media;

namespace BenchGauge;

// Consume the same generated outlines and placement as iPhone/iPad. In
// particular, I is its own glyph and only the network A receives the shear.
sealed class EnglishBrandArtwork
{
    public static readonly EnglishBrandArtwork Shared = new();
    public double BaseSize { get; }
    public double Width { get; }
    public double Height { get; }
    readonly double logoWidth, logoHeight, logoTop, logoShear;
    readonly Geometry letters;
    readonly Brush lightInk = Ink(false), darkInk = Ink(true);

    EnglishBrandArtwork()
    {
        using var stream = Assembly.GetExecutingAssembly().GetManifestResourceStream("BrandWordmark.json")
            ?? throw new InvalidDataException("Missing shared brand wordmark");
        using var document = JsonDocument.Parse(stream);
        var root = document.RootElement;
        var layout = root.GetProperty("layouts").GetProperty("english");
        BaseSize = root.GetProperty("baseSize").GetDouble();
        Width = layout.GetProperty("width").GetDouble();
        Height = layout.GetProperty("height").GetDouble();
        logoWidth = layout.GetProperty("logoWidth").GetDouble();
        logoHeight = layout.GetProperty("logoHeight").GetDouble();
        logoTop = layout.GetProperty("logoTop").GetDouble();
        logoShear = layout.GetProperty("logoShear").GetDouble();
        var paths = new GeometryGroup { FillRule = FillRule.Nonzero };
        foreach (var placement in layout.GetProperty("glyphs").EnumerateArray())
        {
            var path = new StreamGeometry { FillRule = FillRule.Nonzero };
            using (var context = path.Open())
            {
                var x = placement.GetProperty("x").GetDouble();
                var y = placement.GetProperty("y").GetDouble();
                foreach (var command in root.GetProperty("glyphs").GetProperty(placement.GetProperty("key").GetString()!)
                    .GetProperty("commands").EnumerateArray())
                {
                    Point P(int index) => new(command[index].GetDouble() + x, command[index + 1].GetDouble() + y);
                    switch (command[0].GetString())
                    {
                        case "M": context.BeginFigure(P(1), true, true); break;
                        case "L": context.LineTo(P(1), true, false); break;
                        case "Q": context.QuadraticBezierTo(P(1), P(3), true, false); break;
                        case "C": context.BezierTo(P(1), P(3), P(5), true, false); break;
                        case "Z": break; // Each wordmark contour is closed by BeginFigure.
                        default: throw new InvalidDataException("Unsupported wordmark path command");
                    }
                }
            }
            paths.Children.Add(path);
        }
        paths.Freeze(); letters = paths;
    }

    public void Draw(DrawingContext drawing, ImageSource logo, bool dark, double fontSize, double top)
    {
        var scale = fontSize / BaseSize;
        drawing.PushTransform(new MatrixTransform(scale, 0, 0, scale, 0, top));
        drawing.DrawGeometry(dark ? darkInk : lightInk, null, letters);
        drawing.PushTransform(new MatrixTransform(1, 0, -logoShear, 1, logoHeight * logoShear, logoTop));
        drawing.DrawImage(logo, new Rect(0, 0, logoWidth, logoHeight));
        drawing.Pop(); drawing.Pop();
    }

    static Brush Ink(bool dark)
    {
        var colors = dark ? new[] { "#F5F7FA", "#A5AFBC", "#E0E6EE", "#8D99A8" }
            : new[] { "#303945", "#8894A2", "#414D5C", "#6C7888" };
        var stops = new GradientStopCollection();
        var positions = new[] { 0, 0.42, 0.5, 1 };
        for (var i = 0; i < colors.Length; i++)
            stops.Add(new GradientStop((Color)ColorConverter.ConvertFromString(colors[i]), positions[i]));
        var brush = new LinearGradientBrush(stops, new Point(0, 0), new Point(0, 1));
        brush.Freeze(); return brush;
    }
}
