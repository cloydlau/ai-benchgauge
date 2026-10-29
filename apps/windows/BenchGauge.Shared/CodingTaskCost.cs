using System.Globalization;

namespace BenchGauge.Shared;

public static class CodingTaskCost
{
    public static string Format(double? value) => value is not { } cost || !double.IsFinite(cost) || cost < 0 ? "—"
        : cost == 0 ? "$0" : cost < 0.001 ? "<$0.001"
        : "$" + cost.ToString(cost < 0.01 ? "0.000" : "0.00", CultureInfo.InvariantCulture);

    public static Entry[] Order(IEnumerable<Entry> entries, bool enabled) => enabled
        ? entries.OrderBy(entry => entry.TaskCostUSD is { } cost && double.IsFinite(cost) && cost >= 0 ? cost : double.PositiveInfinity)
            .ThenByDescending(entry => entry.Score).ThenBy(entry => entry.Rank).ToArray()
        : entries.ToArray();
}
