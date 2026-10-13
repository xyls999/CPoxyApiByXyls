$ErrorActionPreference = 'Stop'
$runtime = Join-Path (Split-Path -Parent $PSScriptRoot) '.runtime'
$pidsFile = Join-Path $runtime 'chaoxing-pids.json'
if (-not (Test-Path $pidsFile)) { Write-Host 'No recorded Chaoxing bridge processes.'; exit 0 }
$items = Get-Content -LiteralPath $pidsFile -Raw | ConvertFrom-Json
function Find-OwnedProcess($id, $created, $exe, [string]$marker) {
    if (-not $id -or -not $created -or -not $exe) { throw 'Missing process identity evidence; refusing to stop a PID' }
    $candidate = Get-CimInstance -ClassName Win32_Process -Filter "ProcessId=$id" -ErrorAction SilentlyContinue
    if (-not $candidate) { return $null }
    if ($candidate.Name -ne 'node.exe' -or $candidate.ExecutablePath -ne $exe -or
        $candidate.CreationDate.ToFileTimeUtc() -ne [long]$created -or
        $candidate.CommandLine -notlike "*$marker*") {
        throw "PID $id does not match the process originally started; refusing to stop"
    }
    return $candidate
}
$service = Find-OwnedProcess $items.service_pid $items.service_created $items.service_exe 'src/main.mjs'
$bridge = Find-OwnedProcess $items.bridge_pid $items.bridge_created $items.bridge_exe 'bridges/chaoxing-openai/server.mjs'
if ($bridge) {
    $keys = Get-Content -LiteralPath (Join-Path $runtime 'chaoxing-keys.json') -Raw | ConvertFrom-Json
    $url = "http://127.0.0.1:$($items.bridge_port)/admin/drain"
    $headers = @{ Authorization = "Bearer $($keys.bridge_key)" }
    $drained = $false
    for ($i = 0; $i -lt 160; $i++) {
        $state = Invoke-RestMethod -Method Post -Uri $url -Headers $headers -TimeoutSec 10
        if ($state.draining -ne $true) { throw 'Bridge refused to drain; not force-stopping active requests' }
        if ($state.active_requests -eq 0) { $drained = $true; break }
        Start-Sleep -Seconds 1
    }
    if (-not $drained) { throw 'Bridge still has active browser requests; leave processes running and investigate' }
    # Identity is checked again after waiting, so a recycled PID cannot be killed.
    $bridge = Find-OwnedProcess $items.bridge_pid $items.bridge_created $items.bridge_exe 'bridges/chaoxing-openai/server.mjs'
    if ($bridge) { Stop-Process -Id $bridge.ProcessId -Force; Write-Host "Stopped drained bridge PID $($bridge.ProcessId)" }
}
$service = Find-OwnedProcess $items.service_pid $items.service_created $items.service_exe 'src/main.mjs'
if ($service) { Stop-Process -Id $service.ProcessId -Force; Write-Host "Stopped service PID $($service.ProcessId)" }
Remove-Item -LiteralPath $pidsFile -Force
