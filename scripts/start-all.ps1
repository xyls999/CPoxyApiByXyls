param(
    [string]$NewApiDir,
    [string]$GeminiApiDir,
    [string]$GeminiProxy = $env:GEMINI_PROXY_URL
)

$ErrorActionPreference = "Stop"

if (-not $NewApiDir) {
    $NewApiDir = $env:NEWAPI_DIR
    if (-not $NewApiDir) { $NewApiDir = Join-Path (Split-Path -Parent $PSScriptRoot) "bin\new-api" }
}
if (-not $GeminiApiDir) {
    $GeminiApiDir = $env:GEMINI_API_DIR
    if (-not $GeminiApiDir) { $GeminiApiDir = Join-Path (Split-Path -Parent $PSScriptRoot) "bin\gemini-web2api-go" }
}

$gatewayExe  = Join-Path $NewApiDir "new-api.exe"
$upstreamExe = Join-Path $GeminiApiDir "gemini-web2api-go.exe"

if (-not (Test-Path $gatewayExe))  { throw "new-api.exe not found: $gatewayExe" }
if (-not (Test-Path $upstreamExe)) { throw "gemini-web2api-go.exe not found: $upstreamExe" }

function Test-Port([int]$Port) {
    $c = [Net.Sockets.TcpClient]::new()
    try {
        $c.Connect("127.0.0.1", $Port); return $true
    } catch {
        return $false
    } finally {
        $c.Dispose()
    }
}

function Wait-Port([int]$Port, [string]$Name) {
    for ($i = 0; $i -lt 30; $i++) {
        if (Test-Port $Port) { Write-Host "[OK] $Name listening on :$Port"; return }
        Start-Sleep -Milliseconds 500
    }
    throw "$Name did not start on :$Port"
}

if (-not (Test-Port 8083)) {
    Write-Host "starting upstream: $upstreamExe"
    $upstreamArgs = @()
    if ($GeminiProxy) {
        if ($GeminiProxy -notmatch '^http://127\.0\.0\.1:\d{1,5}$') { throw 'GeminiProxy must point to a local HTTP proxy on 127.0.0.1' }
        $upstreamArgs = @('--proxy', $GeminiProxy)
    }
    $upstreamStart = @{
        FilePath = $upstreamExe
        WorkingDirectory = $GeminiApiDir
        RedirectStandardOutput = Join-Path $GeminiApiDir 'data\server.stdout.log'
        RedirectStandardError = Join-Path $GeminiApiDir 'data\server.stderr.log'
        WindowStyle = 'Hidden'
    }
    if ($upstreamArgs.Count) { $upstreamStart.ArgumentList = $upstreamArgs }
    Start-Process @upstreamStart
} else {
    Write-Host "[SKIP] upstream already on :8083"
}

# An unmerged Argon build is strictly opt-in and stays on loopback. Never
# attach new-api to an unrelated process that happens to occupy this port.
$trialDir = Join-Path (Split-Path -Parent $PSScriptRoot) '.runtime\argon-trial'
if (Test-Path (Join-Path $trialDir 'auto-start.enabled')) {
    $trialExe = Join-Path $trialDir 'bin\argon-pr37.exe'
    $trialConfig = Join-Path $trialDir 'trial-config.json'
    $trialDB = Join-Path $trialDir 'trial.db'
    foreach ($path in @($trialExe, $trialConfig, $trialDB)) {
        if (-not (Test-Path $path)) { throw "Experimental Argon component missing: $path" }
    }
    if (-not (Test-Port 18083)) {
        Start-Process -FilePath $trialExe -WorkingDirectory $trialDir `
            -ArgumentList @('--config', $trialConfig, '--db', $trialDB, '--port', '18083') `
            -RedirectStandardOutput (Join-Path $trialDir 'trial.stdout.log') `
            -RedirectStandardError (Join-Path $trialDir 'trial.stderr.log') -WindowStyle Hidden
    }
    Wait-Port 18083 'Argon experimental'
    $listener = @(Get-NetTCPConnection -LocalPort 18083 -State Listen -ErrorAction Stop |
        Where-Object { $_.LocalAddress -eq '127.0.0.1' })
    if ($listener.Count -ne 1) { throw 'Argon experimental service is not exclusively bound to loopback' }
    $owner = Get-CimInstance -ClassName Win32_Process -Filter "ProcessId=$($listener[0].OwningProcess)"
    if ($owner.ExecutablePath -ne $trialExe) { throw 'Argon experimental port is owned by an unknown process' }
}

if (-not (Test-Port 3000)) {
    Write-Host "starting gateway: $gatewayExe"
    Start-Process -FilePath $gatewayExe -WorkingDirectory $NewApiDir `
        -RedirectStandardOutput (Join-Path $NewApiDir "server.stdout.log") `
        -RedirectStandardError  (Join-Path $NewApiDir "server.stderr.log") `
        -WindowStyle Hidden
} else {
    Write-Host "[SKIP] gateway already on :3000"
}

Wait-Port 8083 "upstream"
Wait-Port 3000 "gateway"

Write-Host ""
Write-Host "all services up:"
Write-Host "  coding api : http://127.0.0.1:3000/v1"
Write-Host "  admin ui   : http://127.0.0.1:3000"
Write-Host "  upstream   : http://127.0.0.1:8083"
if (Test-Path (Join-Path $trialDir 'auto-start.enabled')) {
    Write-Host "  Argon trial: http://127.0.0.1:18083 (experimental, admin not exposed to LAN)"
}
