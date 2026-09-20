param(
    [string]$ApiKey,
    [string]$BaseUrl = "http://127.0.0.1:3000/v1",
    [string]$Model = "gemini-3.6-flash"
)

$ErrorActionPreference = "Stop"

if (-not $ApiKey) {
    $ApiKey = $env:CODING_API_KEY
}
if (-not $ApiKey) {
    throw "API key required: pass -ApiKey or set `$env:CODING_API_KEY"
}

$headers = @{ Authorization = "Bearer $ApiKey" }
$tmp = Join-Path $env:TEMP "coding-api-req.json"

Write-Host "== models =="
$models = Invoke-RestMethod -Uri "$BaseUrl/models" -Headers $headers
$models.data | ForEach-Object { Write-Host "  $($_.id)" }

Write-Host "== chat (non-stream) =="
$body = @{
    model    = $Model
    messages = @(@{ role = "user"; content = "reply with the word OK only" })
} | ConvertTo-Json -Depth 5
[IO.File]::WriteAllText($tmp, $body)
$resp = Invoke-RestMethod -Method Post -Uri "$BaseUrl/chat/completions" `
    -ContentType "application/json" -Headers $headers -InFile $tmp
Write-Host "  $($resp.choices[0].message.content)"
if ($resp.choices[0].message.content -notmatch "OK") { throw "unexpected non-stream reply" }

Write-Host "== chat (stream, first chunks) =="
$streamBody = @{
    model    = $Model
    stream   = $true
    messages = @(@{ role = "user"; content = "count 1 to 3" })
} | ConvertTo-Json -Depth 5
[IO.File]::WriteAllText($tmp, $streamBody)

$req = [Net.HttpWebRequest]::Create("$BaseUrl/chat/completions")
$req.Method = "POST"
$req.ContentType = "application/json"
$req.Headers.Add("Authorization", "Bearer $ApiKey")
$bytes = [Text.Encoding]::UTF8.GetBytes([IO.File]::ReadAllText($tmp))
$reqStream = $req.GetRequestStream()
$reqStream.Write($bytes, 0, $bytes.Length)
$reqStream.Close()

$reader = New-Object IO.StreamReader($req.GetResponse().GetResponseStream())
$i = 0
$sawDone = $false
while (($line = $reader.ReadLine()) -ne $null -and $i -lt 15) {
    if ($line) {
        Write-Host "  $line"
        if ($line -eq "data: [DONE]") { $sawDone = $true }
        $i++
    }
}
$reader.Close()
if (-not $sawDone) { throw "stream did not terminate with data: [DONE]" }

Write-Host ""
Write-Host "ALL CHECKS PASSED"
