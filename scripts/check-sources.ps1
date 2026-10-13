param([string]$ChatgptConfigPath = $env:CHATGPT_WEB2API_CONFIG)
$ErrorActionPreference = 'Stop'
$runtime = Join-Path (Split-Path -Parent $PSScriptRoot) '.runtime'
$cxPath = Join-Path $runtime 'chaoxing-keys.json'
function Probe([string]$Label, [string]$Url, [string]$Key = '') {
    $headers = @{}
    if ($Key) { $headers.Authorization = "Bearer $Key" }
    try {
        $result = Invoke-RestMethod -Method Get -Uri $Url -Headers $headers -TimeoutSec 15
        $state = if ($result.upstream) { if ($result.upstream.ready) { 'READY' } else { "UNAVAILABLE ($($result.upstream.code))" } }
                 elseif ($result.status) { "$($result.status) (model reply not verified)" }
                 elseif ($result.success) { 'HTTP READY (model reply not verified)' }
                 else { 'HTTP READY (model reply not verified)' }
        Write-Host ('{0,-22} {1}' -f $Label, $state)
    } catch {
        $response = $_.Exception.Response
        $code = if ($response) { [int]$response.StatusCode } else { 'offline' }
        Write-Host ('{0,-22} {1}' -f $Label, "UNAVAILABLE ($code)")
    }
}
Write-Host 'Source status (read-only; a model reply needs a separate end-to-end test):'
Probe 'new-api gateway' 'http://127.0.0.1:3000/api/status'
Probe 'Gemini proxy' 'http://127.0.0.1:8083/'
if (Test-Path $cxPath) {
    $keys = Get-Content -LiteralPath $cxPath -Raw | ConvertFrom-Json
    Probe 'Chaoxing browser' 'http://127.0.0.1:8787/api/status' $keys.service_key
    Probe 'Chaoxing adapter' 'http://127.0.0.1:8788/health' $keys.bridge_key
} else { Write-Host 'Chaoxing               NOT CONFIGURED' }
if ($ChatgptConfigPath -and (Test-Path $ChatgptConfigPath)) {
    $keys = Get-Content -LiteralPath $ChatgptConfigPath -Raw | ConvertFrom-Json
    Probe 'ChatGPT Web browser' 'http://127.0.0.1:18080/health' $keys.api_keys[0]
} else { Write-Host 'ChatGPT Web browser    NOT CONFIGURED' }
