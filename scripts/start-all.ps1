param(
    [string]$NewApiDir,
    [string]$GeminiApiDir
)

$ErrorActionPreference = "Stop"

if (-not $NewApiDir)     { $NewApiDir     = $env:NEWAPI_DIR;     if (-not $NewApiDir)     { $NewApiDir     = "E:\cpa\new-api" } }
if (-not $GeminiApiDir)  { $GeminiApiDir  = $env:GEMINI_API_DIR; if (-not $GeminiApiDir)  { $GeminiApiDir  = "E:\gemini-webapi-go\gemini-web2api-go" } }

$gatewayExe  = Join-Path $NewApiDir "new-api.exe"
$upstreamExe = Join-Path $GeminiApiDir "bin\gemini-web2api-go.exe"

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
    Start-Process -FilePath $upstreamExe -WorkingDirectory $GeminiApiDir `
        -RedirectStandardOutput (Join-Path $GeminiApiDir "data\server.stdout.log") `
        -RedirectStandardError  (Join-Path $GeminiApiDir "data\server.stderr.log") `
        -WindowStyle Hidden
} else {
    Write-Host "[SKIP] upstream already on :8083"
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
