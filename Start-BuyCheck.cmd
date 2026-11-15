@echo off
rem ------------------------------------------------------------------------
rem  BuyCheck starten (Doppelklick).
rem  - nutzt die in Windows eingebaute Windows PowerShell (ab Windows 7)
rem  - bevorzugt die 64-Bit-Version ("Sysnative", falls aus 32 Bit gestartet)
rem  - "-ExecutionPolicy Bypass" gilt NUR fuer diesen einen Aufruf und
rem    veraendert keine Einstellung am Geraet
rem  - das Skript fragt danach selbst nach Administratorrechten
rem ------------------------------------------------------------------------
setlocal
cd /d "%~dp0"
title BuyCheck
set "PSEXE=%SystemRoot%\System32\WindowsPowerShell\v1.0\powershell.exe"
if exist "%SystemRoot%\Sysnative\WindowsPowerShell\v1.0\powershell.exe" set "PSEXE=%SystemRoot%\Sysnative\WindowsPowerShell\v1.0\powershell.exe"
if not exist "%PSEXE%" goto nops
"%PSEXE%" -NoProfile -ExecutionPolicy Bypass -File "%~dp0BuyCheck.ps1" %*
if errorlevel 1 pause
endlocal
goto :eof

:nops
echo.
echo Windows PowerShell wurde auf diesem Geraet nicht gefunden.
echo BuyCheck braucht Windows 7 oder neuer (PowerShell ist dort eingebaut).
echo.
pause
endlocal
