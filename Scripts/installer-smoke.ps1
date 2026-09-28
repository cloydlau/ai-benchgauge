$ErrorActionPreference = 'Stop'
if ($env:CI -ne 'true') { throw 'Installer smoke tests run only in an isolated CI runner' }
$root = Split-Path $PSScriptRoot -Parent
Set-Location $root
$config = Get-Content 'config/app.json' -Raw | ConvertFrom-Json
$local = [Environment]::GetFolderPath('LocalApplicationData')
$installed = Join-Path $local 'Programs/AI-BenchGauge'
if (Test-Path $installed) { throw 'Refusing to replace an existing installation during tests' }
$data = Join-Path $local 'AI-BenchGauge'
New-Item -ItemType Directory -Force $data | Out-Null
$marker = Join-Path $data ("installer-smoke-" + [Guid]::NewGuid() + '.txt')
Set-Content $marker 'Synthetic user data must survive installation and removal'
$settings = Join-Path $data 'settings.json'
$settingsHash = if (Test-Path $settings) { (Get-FileHash $settings).Hash } else { $null }
$installer = Join-Path $root "outputs/release/AI-BenchGauge-$($config.version)-windows-x64-setup.exe"
try {
    $process = Start-Process -FilePath $installer -ArgumentList '/S' -Wait -PassThru
    if ($process.ExitCode -ne 0) { throw "Silent installation failed: $($process.ExitCode)" }
    foreach ($relative in @('AI-BenchGauge.exe', 'engine/benchgauge-engine.exe', 'Licenses/AI-BenchGauge.txt')) {
        $source = Join-Path $root "outputs/windows/app/$relative"
        $destination = Join-Path $installed $relative
        if (!(Test-Path $destination) -or (Get-FileHash $source).Hash -ne (Get-FileHash $destination).Hash) {
            throw "Installed payload differs: $relative"
        }
    }
    $originalPath = $env:PATH
    $node = (Get-Command node).Source
    try {
        $engine = Join-Path $installed 'engine/benchgauge-engine.exe'
        $env:PATH = "$(Split-Path $engine -Parent);$env:SystemRoot/System32;$env:SystemRoot"
        & $node Scripts/engine-smoke.mjs $engine
        if ($LASTEXITCODE -ne 0) { throw 'Installed engine smoke test failed' }
    } finally { $env:PATH = $originalPath }
    $uninstaller = Join-Path $installed 'Uninstall.exe'
    $process = Start-Process -FilePath $uninstaller -ArgumentList '/S' -Wait -PassThru
    if ($process.ExitCode -ne 0) { throw "Silent uninstall failed: $($process.ExitCode)" }
    for ($attempt = 0; $attempt -lt 50 -and (Test-Path $installed); $attempt++) { Start-Sleep -Milliseconds 200 }
    if (Test-Path $installed) { throw 'Uninstall left program files behind' }
    if (!(Test-Path $marker)) { throw 'Uninstall removed user data' }
    if ($settingsHash -and (!(Test-Path $settings) -or (Get-FileHash $settings).Hash -ne $settingsHash)) {
        throw 'Installation or removal changed user preferences'
    }
    Write-Output 'PASS: silent install, installed engine, silent uninstall and preserved user data'
} finally { Remove-Item $marker -ErrorAction SilentlyContinue }
