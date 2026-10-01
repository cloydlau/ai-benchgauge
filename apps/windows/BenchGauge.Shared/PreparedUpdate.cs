namespace BenchGauge.Shared;

/// Downloaded installers cannot interrupt a hidden/inactive window or another modal.
public sealed class PreparedUpdate
{
    public string? Installer { get; private set; }
    public bool IsPresenting { get; private set; }
    public bool IsInstalling { get; private set; }
    public void Ready(string installer) { if (Installer is null) Installer = installer; }
    public bool TryPresent(bool visible, bool active, bool modalOpen, bool closing)
    {
        if (Installer is null || IsPresenting || IsInstalling || !visible || !active || modalOpen || closing) return false;
        IsPresenting = true;
        return true;
    }
    public string? Confirm()
    {
        if (!IsPresenting || IsInstalling) return null;
        IsInstalling = true;
        return Installer;
    }
    public void InstallationFailed() { IsInstalling = false; }
}
