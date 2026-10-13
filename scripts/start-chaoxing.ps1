param(
    [string]$ChaoxingDir = 'C:\Black hacker\chaoxing-ai-web',
    [int]$ServicePort = 8787,
    [int]$BridgePort = 8788
)
$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent $PSScriptRoot
$runtime = Join-Path $root '.runtime'
New-Item -ItemType Directory -Force $runtime | Out-Null
$account = [Security.Principal.WindowsIdentity]::GetCurrent().Name
& icacls.exe $runtime /inheritance:r /grant:r ($account + ':(OI)(CI)F') 'SYSTEM:(OI)(CI)F' /Q | Out-Null
if ($LASTEXITCODE -ne 0) { throw 'Could not restrict runtime directory to current user and SYSTEM' }
& icacls.exe $runtime /grant ($account + ':F') 'SYSTEM:F' /T /Q | Out-Null
if ($LASTEXITCODE -ne 0) { throw 'Could not grant access to existing runtime files' }
$pidsFile = Join-Path $runtime 'chaoxing-pids.json'
if (Test-Path $pidsFile) { throw 'A managed Chaoxing instance is already recorded; run stop-chaoxing.ps1 first' }
$secretsPath = Join-Path $runtime 'chaoxing-keys.json'
if (-not (Test-Path $secretsPath)) {
    $rng = [Security.Cryptography.RandomNumberGenerator]::Create()
    try {
        $bytes = New-Object byte[] 36
        $rng.GetBytes($bytes)
        $serviceKey = 'cx-' + [Convert]::ToBase64String($bytes).TrimEnd('=').Replace('+', '-').Replace('/', '_')
        $rng.GetBytes($bytes)
        $bridgeKey = 'cx-' + [Convert]::ToBase64String($bytes).TrimEnd('=').Replace('+', '-').Replace('/', '_')
    } finally { $rng.Dispose() }
    @{ service_key = $serviceKey; bridge_key = $bridgeKey } | ConvertTo-Json | Set-Content -LiteralPath $secretsPath -Encoding UTF8
}
$secrets = Get-Content -LiteralPath $secretsPath -Raw | ConvertFrom-Json
if ($secrets.service_key.Length -lt 24 -or $secrets.bridge_key.Length -lt 24) { throw 'Invalid bridge key file' }
if (-not (Test-Path (Join-Path $ChaoxingDir 'src\main.mjs'))) { throw "Chaoxing project missing: $ChaoxingDir" }
$node = (Get-Command node.exe -ErrorAction Stop).Source
function Test-Port([int]$Port) {
    $client = New-Object Net.Sockets.TcpClient
    try { $client.Connect('127.0.0.1', $Port); return $true }
    catch { return $false }
    finally { $client.Dispose() }
}
if (Test-Port $ServicePort) { throw "Port $ServicePort already in use; refusing to attach to an unknown service" }
if (Test-Port $BridgePort) { throw "Port $BridgePort already in use; refusing to attach to an unknown bridge" }
$old = @{ HOST = $env:HOST; PORT = $env:PORT; API_KEY = $env:API_KEY; CHAOXING_BRIDGE_KEY = $env:CHAOXING_BRIDGE_KEY; CHAOXING_SERVICE_KEY = $env:CHAOXING_SERVICE_KEY; CHAOXING_SERVICE_URL = $env:CHAOXING_SERVICE_URL; CHAOXING_BRIDGE_PORT = $env:CHAOXING_BRIDGE_PORT }
$service = $null; $bridge = $null
try {
    $env:HOST = '127.0.0.1'; $env:PORT = "$ServicePort"; $env:API_KEY = $secrets.service_key
    $service = Start-Process -FilePath $node -ArgumentList 'src/main.mjs' -WorkingDirectory $ChaoxingDir -PassThru -WindowStyle Hidden -RedirectStandardOutput (Join-Path $runtime 'chaoxing.stdout.log') -RedirectStandardError (Join-Path $runtime 'chaoxing.stderr.log')
    $env:CHAOXING_BRIDGE_KEY = $secrets.bridge_key; $env:CHAOXING_SERVICE_KEY = $secrets.service_key
    $env:CHAOXING_SERVICE_URL = "http://127.0.0.1:$ServicePort"; $env:CHAOXING_BRIDGE_PORT = "$BridgePort"
    $bridge = Start-Process -FilePath $node -ArgumentList 'bridges/chaoxing-openai/server.mjs' -WorkingDirectory $root -PassThru -WindowStyle Hidden -RedirectStandardOutput (Join-Path $runtime 'chaoxing-bridge.stdout.log') -RedirectStandardError (Join-Path $runtime 'chaoxing-bridge.stderr.log')
    $serviceInfo = Get-CimInstance -ClassName Win32_Process -Filter "ProcessId=$($service.Id)"
    $bridgeInfo = Get-CimInstance -ClassName Win32_Process -Filter "ProcessId=$($bridge.Id)"
    if (-not $serviceInfo -or -not $bridgeInfo) { throw 'Started process disappeared before it could be recorded' }
    @{
        service_pid = $service.Id; service_created = $serviceInfo.CreationDate.ToFileTimeUtc(); service_exe = $serviceInfo.ExecutablePath
        bridge_pid = $bridge.Id; bridge_created = $bridgeInfo.CreationDate.ToFileTimeUtc(); bridge_exe = $bridgeInfo.ExecutablePath
        bridge_port = $BridgePort
    } | ConvertTo-Json | Set-Content -LiteralPath $pidsFile -Encoding UTF8
    $ready = $false
    for ($i = 0; $i -lt 30; $i++) {
        if ((Test-Port $ServicePort) -and (Test-Port $BridgePort)) { $ready = $true; break }
        if ($service.HasExited -or $bridge.HasExited) { break }
        Start-Sleep -Milliseconds 500
    }
    if (-not $ready) { throw 'Service or bridge did not start; inspect the private .runtime logs' }
} catch {
    foreach ($proc in @($bridge, $service)) {
        if ($proc -and -not $proc.HasExited) { Stop-Process -Id $proc.Id -Force -ErrorAction SilentlyContinue }
    }
    Remove-Item -LiteralPath $pidsFile -Force -ErrorAction SilentlyContinue
    throw
} finally {
    foreach ($name in $old.Keys) { [Environment]::SetEnvironmentVariable($name, $old[$name], 'Process') }
}
Write-Host "Chaoxing service and OpenAI bridge started on localhost:$ServicePort and localhost:$BridgePort"
Write-Host 'Source readiness still depends on the real course browser login. The bridge returns 503 while it is unavailable.'
Write-Host "Bridge credential stored in private file: $secretsPath (do not share)"
