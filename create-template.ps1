# Vytvori verejny RunPod template cez RunPod REST API.
# Spustenie:  powershell -ExecutionPolicy Bypass -File create-template.ps1
# API kluc: RunPod -> Settings -> API Keys -> Create API Key (Read/Write). Kluc sa nikam neuklada.

$ErrorActionPreference = "Stop"
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12

$secure = Read-Host "Vloz RunPod API key (nezobrazi sa)" -AsSecureString
$key = [Runtime.InteropServices.Marshal]::PtrToStringAuto([Runtime.InteropServices.Marshal]::SecureStringToBSTR($secure))
if (-not $key) { Write-Host "Chyba: prazdny kluc." -ForegroundColor Red; exit 1 }

$readmePath = if ($PSScriptRoot) { Join-Path $PSScriptRoot "TEMPLATE_README.md" } else { "" }
if ($readmePath -and (Test-Path $readmePath)) {
    $readme = [IO.File]::ReadAllText($readmePath, [Text.Encoding]::UTF8)
} else {
    $wc = New-Object Net.WebClient
    $wc.Encoding = [Text.Encoding]::UTF8
    $readme = $wc.DownloadString("https://raw.githubusercontent.com/Bendzo19/matrix-krea2-runpod/main/TEMPLATE_README.md")
}

$body = [ordered]@{
    name              = "Krea 2 AI Influencer 2K/4K (ComfyUI)"
    imageName         = "ghcr.io/bendzo19/matrix-krea2-runpod:v1.1.0"
    category          = "NVIDIA"
    isPublic          = $true
    isServerless      = $false
    containerDiskInGb = 30
    volumeInGb        = 60
    volumeMountPath   = "/workspace"
    ports             = @("8188/http", "8888/http", "22/tcp")
    env               = [ordered]@{ LORA_URLS = ""; CIVITAI_TOKEN = ""; JUPYTER_PASSWORD = ""; XAI_API_KEY = "" }
    readme            = $readme
}

$headers = @{ Authorization = "Bearer $key" }
$json = $body | ConvertTo-Json -Depth 5
$bytes = [Text.Encoding]::UTF8.GetBytes($json)

try {
    $r = Invoke-RestMethod -Method Post -Uri "https://rest.runpod.io/v1/templates" -Headers $headers `
        -ContentType "application/json; charset=utf-8" -Body $bytes
} catch {
    Write-Host "RunPod API chyba:" -ForegroundColor Red
    if ($_.ErrorDetails.Message) { Write-Host $_.ErrorDetails.Message } else { Write-Host $_.Exception.Message }
    exit 1
}

Write-Host ""
Write-Host "HOTOVO - template vytvoreny" -ForegroundColor Green
Write-Host ("  ID:     " + $r.id)
Write-Host ("  Nazov:  " + $r.name)
Write-Host ("  Public: " + $r.isPublic)
Write-Host ""
Write-Host "Odkaz pre zakaznikov:" -ForegroundColor Cyan
Write-Host ("  https://console.runpod.io/deploy?template=" + $r.id)
