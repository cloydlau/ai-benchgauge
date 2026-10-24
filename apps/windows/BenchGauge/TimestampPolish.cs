using System;
using System.Diagnostics;
using System.Windows;
using System.Windows.Controls;
using System.Windows.Media;
using System.Windows.Media.Animation;
using System.Windows.Threading;

namespace BenchGauge;

// Kept by the window, so quota updates and other WPF rebuilds cannot restart a pass.
sealed class TimestampPolishClock
{
    public const double Interval = 30, Duration = 1.1;
    public double? StartedAt;
    public bool Ready;
    public static double Now => (double)Stopwatch.GetTimestamp() / Stopwatch.Frequency;
    public void Update(bool ready)
    {
        Ready = ready;
        if (!ready) StartedAt = null;
    }
}

sealed class TimestampPolish : Grid
{
    readonly TimestampPolishClock clock;
    readonly TextBlock reflection;
    readonly TranslateTransform position = new();
    readonly DispatcherTimer timer = new();
    Window? owner;
    bool exporting;
    public TimestampPolish(TextBlock label, TimestampPolishClock clock)
    {
        this.clock = clock;
        Children.Add(label);
        reflection = new ReflectionTextBlock { Text = label.Text, FontFamily = label.FontFamily,
            FontSize = label.FontSize, FontWeight = label.FontWeight, VerticalAlignment = label.VerticalAlignment,
            Foreground = Brushes.White, IsHitTestVisible = false, Opacity = 0,
            TextTrimming = label.TextTrimming };
        // The copy inherits the exact ink-centering transform applied on Loaded.
        label.Loaded += (_, _) => reflection.RenderTransform = label.RenderTransform;
        Children.Add(reflection);
        timer.Tick += (_, _) => UpdatePass();
        Loaded += (_, _) => {
            SystemParameters.StaticPropertyChanged += MotionChanged;
            owner = Window.GetWindow(this);
            if (owner is not null) { owner.Activated += ActivityChanged; owner.Deactivated += ActivityChanged; }
            UpdatePass();
        };
        Unloaded += (_, _) => {
            timer.Stop();
            SystemParameters.StaticPropertyChanged -= MotionChanged;
            if (owner is not null) { owner.Activated -= ActivityChanged; owner.Deactivated -= ActivityChanged; owner = null; }
        };
        IsVisibleChanged += (_, _) => UpdatePass();
    }
    void ActivityChanged(object? sender, EventArgs args) => UpdatePass();
    void MotionChanged(object? sender, System.ComponentModel.PropertyChangedEventArgs args)
    {
        if (args.PropertyName == nameof(SystemParameters.ClientAreaAnimation)) Dispatcher.BeginInvoke(UpdatePass);
    }
    public void SetExporting(bool value) { exporting = value; UpdatePass(); }
    void UpdatePass()
    {
        timer.Stop();
        reflection.Opacity = 0;
        position.BeginAnimation(TranslateTransform.XProperty, null);
        if (exporting || !IsLoaded || !IsVisible || owner?.IsActive != true || !SystemParameters.ClientAreaAnimation || !clock.Ready
            || Array.IndexOf(Environment.GetCommandLineArgs(), "--visual-test") >= 0) return;
        var now = TimestampPolishClock.Now;
        if (clock.StartedAt is not { } start || now - start >= TimestampPolishClock.Interval) clock.StartedAt = now;
        var elapsed = now - clock.StartedAt!.Value;
        if (elapsed < TimestampPolishClock.Duration && ActualWidth > 0)
        {
            var width = ActualWidth;
            var mask = new LinearGradientBrush(new GradientStopCollection {
                new(Colors.Transparent, 0), new(Color.FromArgb(217, 255, 255, 255), 0.5), new(Colors.Transparent, 1)
            }, new Point(0, 0), new Point(width * 0.45, 0)) { MappingMode = BrushMappingMode.Absolute, Transform = position };
            reflection.OpacityMask = mask; reflection.Opacity = 1;
            position.BeginAnimation(TranslateTransform.XProperty, new DoubleAnimation(
                width * (-0.45 + elapsed / TimestampPolishClock.Duration * 1.45), width,
                TimeSpan.FromSeconds(TimestampPolishClock.Duration - elapsed)));
            timer.Interval = TimeSpan.FromSeconds(TimestampPolishClock.Duration - elapsed);
        }
        else timer.Interval = TimeSpan.FromSeconds(Math.Max(0.02, TimestampPolishClock.Interval - elapsed));
        timer.Start();
    }
}

sealed class ReflectionTextBlock : TextBlock
{
    protected override System.Windows.Automation.Peers.AutomationPeer? OnCreateAutomationPeer() => null;
}
