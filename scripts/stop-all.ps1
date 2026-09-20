$ErrorActionPreference = "SilentlyContinue"

foreach ($port in 3000, 8083) {
    $rows = netstat -ano | Select-String ":$port\s.*LISTENING"
    $pids = $rows | ForEach-Object { ($_ -split '\s+')[-1] } | Sort-Object -Unique
    foreach ($procId in $pids) {
        if ($procId -match '^\d+$') {
            Stop-Process -Id $procId -Force -ErrorAction SilentlyContinue
            Write-Host "[STOP] port $port pid $procId"
        }
    }
}
