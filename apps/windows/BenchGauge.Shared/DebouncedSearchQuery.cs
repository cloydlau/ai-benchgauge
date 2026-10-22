namespace BenchGauge.Shared;

// UI adapters supply a monotonic clock, keeping timing and cancellation testable.
public sealed class DebouncedSearchQuery
{
    public const int DelayMilliseconds = 250;
    public string Input { get; private set; } = "";
    public string Query { get; private set; } = "";
    public bool Pending => dueAt.HasValue;
    long? dueAt;

    public bool Edit(string value, long now, bool composing = false)
    {
        Input = value;
        dueAt = null;
        if (composing) return false;
        if (string.IsNullOrWhiteSpace(value)) return Apply();
        if (value != Query) dueAt = now + DelayMilliseconds;
        return false;
    }

    public bool ApplyIfReady(long now)
    {
        if (dueAt is not { } due || now < due) return false;
        dueAt = null;
        return Apply();
    }

    bool Apply()
    {
        if (Query == Input) return false;
        Query = Input;
        return true;
    }
}
