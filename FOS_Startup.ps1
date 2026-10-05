$ErrorActionPreference="Stop"
$root=Split-Path -Parent $MyInvocation.MyCommand.Path
$cfg=Get-Content "$root\PlayFabConfig.json" -Raw | ConvertFrom-Json
$env:FOS_PLAYFAB_TITLE_ID=$cfg.TitleId
Write-Host ""
Write-Host "FOS v1.0" -ForegroundColor Cyan
Write-Host "PlayFab Title ID: $($cfg.TitleId)" -ForegroundColor Green
Write-Host "PlayFab API: $($cfg.ApiBase)" -ForegroundColor DarkGray
Write-Host ""
& powershell.exe -NoProfile -ExecutionPolicy Bypass -File "$root\FOS.ps1"
