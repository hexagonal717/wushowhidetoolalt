@echo off
:: Check for admin rights
>nul 2>&1 "%SystemRoot%\system32\cacls.exe" "%SystemRoot%\system32\config\system"

if '%errorlevel%' NEQ '0' (
    echo Requesting administrative privileges...
    powershell.exe -Command "Start-Process '%0' -Verb RunAs"
    exit
)

:: Run the WUShowHideToolAlt.ps1 script located in the same folder
PowerShell -ExecutionPolicy Bypass -File "%~dp0src\WUShowHideToolAlt.ps1"