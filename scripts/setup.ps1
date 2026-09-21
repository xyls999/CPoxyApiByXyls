param(
    [string]$InstallRoot
)

$ErrorActionPreference = "Stop"
$ProgressPreference = "SilentlyContinue"

if (-not $InstallRoot) { $InstallRoot = Split-Path -Parent $PSScriptRoot }
$binRoot = Join-Path $InstallRoot "bin"

$GH_HEADERS = @{ "User-Agent" = "CPoxyApiByXyls" }

function Get-LatestAsset([string]$Repo, [string]$Pattern) {
    $rel = Invoke-RestMethod -Uri "https://api.github.com/repos/$Repo/releases/latest" -Headers $GH_HEADERS
    $asset = $rel.assets | Where-Object { $_.name -like $Pattern } | Select-Object -First 1
    if (-not $asset) { throw "no asset matching '$Pattern' in $Repo latest release ($($rel.tag_name))" }
    [pscustomobject]@{ Url = $asset.browser_download_url; Name = $asset.name; Tag = $rel.tag_name; Size = $asset.size }
}

function Get-Checksum([string]$AssetName, [string]$SumUrl) {
    $sums = Invoke-RestMethod -Uri $SumUrl -Headers $GH_HEADERS
    if ($sums -is [byte[]]) { $sums = [Text.Encoding]::UTF8.GetString($sums) }
    foreach ($line in ($sums -split "`n")) {
        $parts = $line.Trim() -split "\s+", 2
        if ($parts.Count -eq 2) {
            $fileName = $parts[1].Trim().TrimStart("*")
            if ($fileName -eq $AssetName) { return $parts[0].ToLower() }
        }
    }
    return $null
}

function Install-Component([string]$Name, [string]$Repo, [string]$AssetPattern, [string]$SumAsset, [string]$DestDir, [string]$FinalName) {
    Write-Host "== $Name =="
    $finalFile = Join-Path $DestDir $FinalName
    if (Test-Path $finalFile) {
        Write-Host "[SKIP] $finalFile already exists"
        return $finalFile
    }
    if (-not (Test-Path $DestDir)) { New-Item -ItemType Directory -Path $DestDir | Out-Null }
    $localZip = Join-Path $DestDir "$FinalName.zip"
    if (Test-Path $localZip) {
        Write-Host "extracting bundled $FinalName.zip ..."
        Expand-Archive -Path $localZip -DestinationPath $DestDir -Force
        return $finalFile
    }
    $asset = Get-LatestAsset $Repo $AssetPattern
    $destFile = Join-Path $DestDir $asset.Name

    Write-Host "downloading $($asset.Tag) / $($asset.Name) ($([math]::Round($asset.Size/1MB,1)) MB) ..."
    Invoke-WebRequest -Uri $asset.Url -OutFile $destFile -Headers $GH_HEADERS -UseBasicParsing

    if ($SumAsset) {
        $sumUrl = "https://github.com/$Repo/releases/download/$($asset.Tag)/$SumAsset"
        $expected = Get-Checksum $asset.Name $sumUrl
        if ($expected) {
            $actual = (Get-FileHash $destFile -Algorithm SHA256).Hash.ToLower()
            if ($actual -ne $expected) { Remove-Item $destFile -Force; throw "SHA256 mismatch for $($asset.Name)" }
            Write-Host "[OK] sha256 verified"
        } else {
            Write-Host "[WARN] no checksum entry found, skipped verification"
        }
    }
    Rename-Item -Path $destFile -NewName $FinalName
    return $finalFile
}

$gwDir = Join-Path $binRoot "new-api"
$gatewayExe = Install-Component "new-api (gateway)" "QuantumNous/new-api" "new-api-*.exe" "checksums-windows.txt" $gwDir "new-api.exe"

$upDir = Join-Path $binRoot "gemini-web2api-go"
$upstreamExe = Install-Component "gemini-web2api-go (upstream)" "zexadev/gemini-web2api-go" "*windows_amd64.exe" "SHA256SUMS.txt" $upDir "gemini-web2api-go.exe"

$upConfig = Join-Path $upDir "config.json"
if (-not (Test-Path $upConfig)) {
    [IO.File]::WriteAllText($upConfig, '{"port":8083,"host":"127.0.0.1","db_path":"./data/gemini.db","admin_enabled":true,"admin_token":"","impersonate":"chrome_146","default_model":"gemini-3.6-flash","retry_attempts":3,"retry_delay_sec":2,"request_timeout_sec":180,"retention_days":30,"per_ip_concurrent":5,"per_ip_rpm":30,"per_ip_rph":80,"log_requests":true}')
    Write-Host "[OK] upstream config.json written (127.0.0.1:8083)"
}

try {
    Add-MpPreference -ExclusionPath $binRoot -ErrorAction Stop
    Write-Host "[OK] Defender exclusion added: $binRoot"
} catch {
    Write-Host "[WARN] could not add Defender exclusion (run as admin): $($_.Exception.Message)"
}

Write-Host ""
Write-Host "setup complete:"
Write-Host "  gateway : $gatewayExe"
Write-Host "  upstream: $upstreamExe"
Write-Host ""
Write-Host "next steps:"
Write-Host "  .\scripts\start-all.ps1     # launch both services"
Write-Host "  open http://127.0.0.1:3000  # first-run setup, then add channel + token"
Write-Host "  .\scripts\test-api.ps1      # end-to-end check"
