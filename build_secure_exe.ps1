# ==============================================================================
# DeskFlow Security & EXE Build Pipeline Script
# ==============================================================================

Write-Host "========================================================" -ForegroundColor Cyan
Write-Host " DeskFlow Secure EXE Build Engine" -ForegroundColor Green
Write-Host "========================================================" -ForegroundColor Cyan

$scriptPath = Join-Path $PSScriptRoot "OfficeStatusGenerator.ps1"
$outputPath = Join-Path $PSScriptRoot "DeskFlow.exe"
$iconPath   = Join-Path $PSScriptRoot "image\logo.ico"

if (-not (Test-Path $scriptPath)) {
    Write-Error "Source script OfficeStatusGenerator.ps1 not found at $scriptPath"
    exit 1
}

# 1. Ensure ps2exe is installed
if (-not (Get-Module -ListAvailable -Name ps2exe)) {
    Write-Host "[*] Installing ps2exe module..." -ForegroundColor Yellow
    Install-Module ps2exe -Scope CurrentUser -Force -AllowClobber
}

Import-Module ps2exe -Force

# 2. Build parameters
$params = @{
    InputFile     = $scriptPath
    OutputFile    = $outputPath
    NoConsole     = $true
    STA           = $true
    Title         = "DeskFlow"
    Description   = "Automated Status & Attendance Productivity Assistant"
    Company       = "Cross Tech"
    Product       = "DeskFlow"
    Copyright     = "Copyright 2026 Cross Tech. All rights reserved."
    Version       = "1.0.0.0"
}

if (Test-Path $iconPath) {
    $params["IconFile"] = $iconPath
}

Write-Host "[*] Compiling OfficeStatusGenerator.ps1 -> DeskFlow.exe..." -ForegroundColor Yellow
try {
    Invoke-PS2EXE @params
    Write-Host "[BUILD SUCCESSFUL] Executable generated at: $outputPath" -ForegroundColor Green
} catch {
    Write-Host "Build failed: $_" -ForegroundColor Red
}
