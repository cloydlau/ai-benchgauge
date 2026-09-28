param([switch]$Installer)
$ErrorActionPreference = 'Stop'
$root = Split-Path $PSScriptRoot -Parent
Set-Location $root
$env:DOTNET_CLI_TELEMETRY_OPTOUT = '1'
$env:DOTNET_NOLOGO = '1'
$env:DOTNET_CLI_HOME = Join-Path $root 'work/dotnet-home'
$env:NUGET_PACKAGES = Join-Path $root 'work/nuget'
$env:CLANG_MODULE_CACHE_PATH = Join-Path $root 'work/clang-modules'
function Invoke-Checked($program, [string[]]$arguments) {
    & $program @arguments
    if ($LASTEXITCODE -ne 0) { throw "$program failed with exit code $LASTEXITCODE" }
}
Invoke-Checked node @('Scripts/validate-app-config.mjs')
Invoke-Checked swift @('test', '--disable-xctest', '--scratch-path', 'work/swift-windows-tests')
Invoke-Checked dotnet @('restore', 'apps/windows/BenchGauge.Tests', '--locked-mode')
Invoke-Checked node @('Scripts/windows-tests.mjs')
Invoke-Checked dotnet @('restore', 'apps/windows/BenchGauge', '-r', 'win-x64', '--locked-mode')
Invoke-Checked dotnet @('publish', 'apps/windows/BenchGauge', '-c', 'Release', '-r', 'win-x64', '--self-contained', 'true', '--no-restore', '-o', 'outputs/windows/app')
Invoke-Checked swift @('build', '-c', 'release', '--product', 'benchgauge-engine', '--scratch-path', 'work/swift-windows-release')
$binaryDirectory = (& swift build -c release --product benchgauge-engine --scratch-path work/swift-windows-release --show-bin-path).Trim()
if ($LASTEXITCODE -ne 0) { throw 'Could not resolve Swift output directory' }
$engineDirectory = Join-Path $root 'outputs/windows/app/engine'
New-Item -ItemType Directory -Force $engineDirectory | Out-Null
$engine = Join-Path $engineDirectory 'benchgauge-engine.exe'
Copy-Item (Join-Path $binaryDirectory 'benchgauge-engine.exe') $engine -Force
# Copy only the engine's dependency closure, not the Swift compiler/toolchain.
$swiftBin = Split-Path (Get-Command swift).Source -Parent
$swiftRoot = (Get-Item $swiftBin).Parent.Parent.Parent.Parent.FullName
$runtimeFiles = Get-ChildItem $swiftRoot -Recurse -Filter '*.dll' -File
$lookup = @{}
foreach ($file in ($runtimeFiles | Sort-Object { if ($_.FullName -match '[\\/]Runtimes[\\/]') { 0 } else { 1 } })) {
    $key = $file.Name.ToLowerInvariant()
    if (!$lookup.ContainsKey($key)) { $lookup[$key] = $file.FullName }
}
$pending = [Collections.Generic.Queue[string]]::new()
$pending.Enqueue($engine)
$copied = [Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)
while ($pending.Count -gt 0) {
    $file = $pending.Dequeue()
    $dependencies = & dumpbin /nologo /dependents $file
    if ($LASTEXITCODE -ne 0) { throw "Could not read dependencies of $file" }
    foreach ($line in $dependencies) {
        if ($line -match '^\s+([A-Za-z0-9_.-]+\.dll)\s*$') {
            $name = $Matches[1]
            if ($name -match '^(api-ms-|ext-ms-)') { continue }
            if ($lookup.ContainsKey($name.ToLowerInvariant())) {
                if ($copied.Add($name)) {
                    $destination = Join-Path $engineDirectory $name
                    Copy-Item $lookup[$name.ToLowerInvariant()] $destination -Force
                    $pending.Enqueue($destination)
                }
            } elseif (!(Test-Path (Join-Path "$env:SystemRoot/System32" $name))) {
                throw "Unresolved runtime dependency: $name"
            }
        }
    }
}
# Include the runtime distribution's complete notices as well as project notices.
$licenseDirectory = Join-Path $root 'outputs/windows/app/Licenses'
foreach ($notice in (Get-ChildItem $swiftRoot -Recurse -File | Where-Object { $_.Name -match '^(LICENSE|NOTICE|COPYING|THIRD-PARTY-NOTICES)(\..*)?$' })) {
    $relative = $notice.FullName.Substring($swiftRoot.Length).TrimStart('\','/')
    $noticeName = 'Swift-Bundled-' + ($relative -replace '[\\/]', '-') + '.txt'
    Copy-Item $notice.FullName (Join-Path $licenseDirectory $noticeName) -Force
}
# Test the packaged engine with no toolchain on PATH and no real account reads.
$originalPath = $env:PATH
$nodeExecutable = (Get-Command node).Source
try {
    $env:PATH = "$engineDirectory;$env:SystemRoot/System32;$env:SystemRoot"
    $smoke = Start-Process -FilePath (Join-Path $root 'outputs/windows/app/AI-BenchGauge.exe') -ArgumentList '--smoke-test' -Wait -PassThru
    if ($smoke.ExitCode -ne 0) { throw 'Native UI smoke test failed' }
    Invoke-Checked $nodeExecutable @('Scripts/engine-smoke.mjs', $engine)
} finally { $env:PATH = $originalPath }
if ($Installer) {
    $prerequisites = Join-Path $root 'outputs/windows/app/prerequisites'
    New-Item -ItemType Directory -Force $prerequisites | Out-Null
    $webviewSetup = Join-Path $prerequisites 'MicrosoftEdgeWebview2Setup.exe'
    Invoke-WebRequest 'https://go.microsoft.com/fwlink/p/?LinkId=2124703' -OutFile $webviewSetup
    $signature = Get-AuthenticodeSignature $webviewSetup
    if ($signature.Status -ne 'Valid' -or $signature.SignerCertificate.Subject -notmatch 'O=Microsoft Corporation') {
        throw 'WebView2 bootstrapper does not have a valid Microsoft signature'
    }
    $config = Get-Content 'config/app.json' -Raw | ConvertFrom-Json
    $outputDirectory = Join-Path $root 'outputs/release'
    New-Item -ItemType Directory -Force $outputDirectory | Out-Null
    $nsis = (Get-Command makensis -ErrorAction SilentlyContinue).Source
    if (!$nsis) { $nsis = "${env:ProgramFiles(x86)}/NSIS/makensis.exe" }
    Invoke-Checked $nsis @("/DVERSION=$($config.version)", "/DPAYLOAD=$root/outputs/windows/app", "/DOUTPUT=$outputDirectory/AI-BenchGauge-$($config.version)-windows-x64-setup.exe", "$root/apps/windows/installer/installer.nsi")
}
