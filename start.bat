@echo off
title Battery Alert 🔋
powershell.exe -ExecutionPolicy Bypass -File "%~dp0src\battery_alert.ps1" %*
pause
