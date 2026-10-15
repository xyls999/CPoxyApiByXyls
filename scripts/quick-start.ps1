param(
    [switch]$OpenBrowser = $true
)

$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent $PSScriptRoot
$gatewayDir = 'E:\cpa\new-api'
$geminiDir = Join-Path $root 'bin\gemini-web2api-go'
$chatgptDir = 'E:\chatgpt-web2api-trial'
$chatgptPython = Join-Path $chatgptDir '.venv\Scripts\python.exe'
$chatgptConfig = Join-Path $chatgptDir '.runtime\config.json'
$geminiEdge = 'C:\Program Files (x86)\Microsoft\Edge\Application\msedge.exe'
if (-not (Test-Path $geminiEdge)) { $geminiEdge = 'C:\Program Files\Microsoft\Edge\Application\msedge.exe' }
$geminiProfile = Join-Path $root '.runtime\gemini-browser-profile'
$geminiCookieImporter = Join-Path $PSScriptRoot 'import-gemini-cdp-cookie.py'
$grokRoot = Join-Path $root '.runtime\research'
$grokExe = Join-Path $grokRoot 'grok2api-trial.exe'
$grokConfig = Join-Path $grokRoot 'grok2api-config.yaml'
$lanIp = (Get-NetIPAddress -AddressFamily IPv4 -ErrorAction SilentlyContinue |
    Where-Object { $_.IPAddress -notlike '127.*' -and $_.IPAddress -notlike '169.254.*' } |
    Select-Object -First 1 -ExpandProperty IPAddress)
if (-not $lanIp) { $lanIp = '127.0.0.1' }

function Test-Port([int]$Port) {
    $connection = Get-NetTCPConnection -State Listen -LocalPort $Port -ErrorAction SilentlyContinue |
        Where-Object { $_.LocalAddress -in @('127.0.0.1', '0.0.0.0', '::', '::1') } |
        Select-Object -First 1
    return $null -ne $connection
}

function Wait-Port([int]$Port, [string]$Name, [int]$Seconds = 45) {
    for ($i = 0; $i -lt ($Seconds * 2); $i++) {
        if (Test-Port $Port) {
            Write-Host "[OK] $Name :$Port"
            return
        }
        Start-Sleep -Milliseconds 500
    }
    throw "$Name did not start on :$Port"
}

function Start-LoggedProcess([string]$FilePath, [string]$WorkingDirectory, [string[]]$ArgumentList, [string]$LogPrefix) {
    $stdout = Join-Path $grokRoot "$LogPrefix.stdout.log"
    $stderr = Join-Path $grokRoot "$LogPrefix.stderr.log"
    Start-Process -FilePath $FilePath -WorkingDirectory $WorkingDirectory -ArgumentList $ArgumentList `
        -RedirectStandardOutput $stdout -RedirectStandardError $stderr -WindowStyle Hidden | Out-Null
}

foreach ($required in @(
    (Join-Path $gatewayDir 'new-api.exe'),
    (Join-Path $geminiDir 'gemini-web2api-go.exe'),
    $chatgptPython, $chatgptConfig, $geminiEdge, $geminiCookieImporter, $grokExe, $grokConfig
)) {
    if (-not (Test-Path $required)) { throw "Required local component missing: $required" }
}

# Reuse the existing guarded starter for Gemini, Argon and the production database.
& (Join-Path $PSScriptRoot 'start-all.ps1') -NewApiDir $gatewayDir -GeminiApiDir $geminiDir -GeminiProxy 'http://127.0.0.1:7897'

if (-not (Test-Port 19447)) {
    Write-Host '[START] Dedicated Gemini Edge'
    New-Item -ItemType Directory -Force -Path $geminiProfile | Out-Null
    Start-Process -FilePath $geminiEdge -ArgumentList @(
        '--remote-debugging-port=19447',
        "--user-data-dir=$geminiProfile",
        '--no-first-run',
        '--no-default-browser-check',
        '--new-window',
        'https://gemini.google.com/'
    ) -WindowStyle Normal | Out-Null
}
Wait-Port 19447 'Dedicated Gemini Edge' 30
try {
    & $chatgptPython $geminiCookieImporter --config (Join-Path $root '.runtime\argon-trial\trial-config.json')
    if ($LASTEXITCODE -eq 2) { Write-Host '[INFO] Gemini login required; startup continues' }
} catch {
    Write-Warning "Gemini Cookie auto-import skipped: $($_.Exception.Message)"
}

if (-not (Test-Port 18080)) {
    Write-Host '[START] ChatGPT Web'
    Start-LoggedProcess $chatgptPython $chatgptDir @('-m', 'chatgpt_web2api', 'start', '--config', $chatgptConfig) 'chatgpt-web'
}
Wait-Port 18080 'ChatGPT Web'

if (-not (Test-Port 18084)) {
    Write-Host '[START] Grok Web'
    Start-LoggedProcess $grokExe $grokRoot @('--config', $grokConfig, '--listen', '127.0.0.1:18084') 'grok2api'
}
Wait-Port 18084 'Grok Web'

Write-Host ''
Write-Host 'CPoxy services are ready (Chaoxing intentionally remains stopped):'
Write-Host "  LAN Home:   http://$lanIp`:3000/"
Write-Host "  LAN API:    http://$lanIp`:3000/v1"
Write-Host "  LAN Models: http://$lanIp`:3000/v1/models"
Write-Host '  Gemini login: http://127.0.0.1:19447'
Write-Host '  Gemini admin: http://127.0.0.1:18083/admin'
Write-Host '  Grok admin:   http://127.0.0.1:18084/'
Write-Host '  ChatGPT:      http://127.0.0.1:18080/health'

if ($OpenBrowser) {
    Start-Process "http://$lanIp`:3000/"
    Start-Process 'https://gemini.google.com/'
    Start-Process 'http://127.0.0.1:18083/admin'
}
