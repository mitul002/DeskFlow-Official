# ==============================================================================
# DeskFlow Security & EXE Build Pipeline Script (Native C#)
# ==============================================================================

Write-Host "========================================================" -ForegroundColor Cyan
Write-Host " DeskFlow Secure EXE Build Engine (Native C#)" -ForegroundColor Green
Write-Host "========================================================" -ForegroundColor Cyan

$scriptPath = Join-Path $PSScriptRoot "OfficeStatusGenerator.ps1"
$outputPath = Join-Path $PSScriptRoot "DeskFlow.exe"
$iconPath   = Join-Path $PSScriptRoot "image\logo.ico"

if (-not (Test-Path $scriptPath)) {
    Write-Error "Source script OfficeStatusGenerator.ps1 not found at $scriptPath"
    exit 1
}

# 1. Generate C# Launcher Code
Write-Host "[*] Generating C# Launcher Source Code..." -ForegroundColor Yellow

$sourceCode = @"
using System;
using System.Diagnostics;
using System.IO;
using System.Reflection;

[assembly: AssemblyTitle("DeskFlow")]
[assembly: AssemblyDescription("Automated Status & Attendance Productivity Assistant")]
[assembly: AssemblyCompany("Cross Tech")]
[assembly: AssemblyProduct("DeskFlow")]
[assembly: AssemblyCopyright("Copyright 2026 Cross Tech. All rights reserved.")]
[assembly: AssemblyVersion("1.0.3.0")]
[assembly: AssemblyFileVersion("1.0.3.0")]

namespace DeskFlowLauncher
{
    class Program
    {
        static void Main(string[] args)
        {
            try
            {
                string scriptPath = Path.Combine(AppDomain.CurrentDomain.BaseDirectory, "OfficeStatusGenerator.ps1");
                
                if (File.Exists(scriptPath))
                {
                    ProcessStartInfo psi = new ProcessStartInfo();
                    psi.FileName = "powershell.exe";
                    psi.Arguments = "-NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File \"" + scriptPath + "\"";
                    psi.CreateNoWindow = true;
                    psi.UseShellExecute = false;
                    
                    Process.Start(psi);
                }
            }
            catch { }
        }
    }
}
"@

$csPath = Join-Path $PSScriptRoot "DeskFlowLauncher.cs"
Set-Content -Path $csPath -Value $sourceCode -Encoding UTF8

# 2. Compile via csc.exe
Write-Host "[*] Compiling Native DeskFlow.exe via csc.exe..." -ForegroundColor Yellow

$cscPath = "C:\Windows\Microsoft.NET\Framework64\v4.0.30319\csc.exe"
if (-not (Test-Path $cscPath)) {
    $cscPath = "C:\Windows\Microsoft.NET\Framework\v4.0.30319\csc.exe"
}

if (-not (Test-Path $cscPath)) {
    Write-Error "csc.exe (C# Compiler) not found. Please ensure .NET Framework is installed."
    exit 1
}

$compileCmd = "& `"$cscPath`" /nologo /target:winexe /out:`"$outputPath`" /win32icon:`"$iconPath`" `"$csPath`""
Invoke-Expression $compileCmd

if ($LASTEXITCODE -eq 0 -and (Test-Path $outputPath)) {
    Write-Host "[BUILD SUCCESSFUL] Native Executable generated at: $outputPath" -ForegroundColor Green
} else {
    Write-Host "Build failed." -ForegroundColor Red
}

# Cleanup temp cs file
Remove-Item $csPath -Force -ErrorAction SilentlyContinue
