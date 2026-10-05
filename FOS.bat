@echo off
cd /d "%~dp0"
set FOS_PLAYFAB_TITLE_ID=23EA5
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0FOS.ps1"
