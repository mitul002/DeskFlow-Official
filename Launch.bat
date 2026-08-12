@echo off
cd /d "%~dp0"
start "" powershell.exe -WindowStyle Hidden -ExecutionPolicy Bypass -File "%~dp0OfficeStatusGenerator.ps1"
exit
