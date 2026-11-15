@echo off
rem ------------------------------------------------------------------------
rem  BuyCheck starten (Doppelklick).
rem  - nutzt Windows PowerShell 5.1 (auf jedem Windows 10/11 vorhanden)
rem  - "-ExecutionPolicy Bypass" gilt NUR fuer diesen einen Aufruf und
rem    veraendert keine Einstellung am Laptop
rem  - das Skript fragt danach selbst nach Administratorrechten
rem ------------------------------------------------------------------------
setlocal
cd /d "%~dp0"
title BuyCheck
"%SystemRoot%\System32\WindowsPowerShell\v1.0\powershell.exe" -NoProfile -ExecutionPolicy Bypass -STA -File "%~dp0BuyCheck.ps1" %*
if errorlevel 1 pause
endlocal
