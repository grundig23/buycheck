@echo off
rem ------------------------------------------------------------------------
rem  BuyCheck starten (Doppelklick).
rem  - prueft, ob der BuyCheck-Ordner vollstaendig entpackt ist
rem  - holt Administratorrechte (Windows-Abfrage); dafuer oeffnet sich ein
rem    zweites Fenster, dieses hier schliesst sich dann
rem  - nutzt die in Windows eingebaute Windows PowerShell (ab Windows 7),
rem    bevorzugt die 64-Bit-Version
rem  - "-ExecutionPolicy Bypass" gilt NUR fuer diesen einen Aufruf und
rem    veraendert keine Einstellung am Geraet
rem  - bei einem Fehler bleibt das Fenster offen
rem ------------------------------------------------------------------------
setlocal
title BuyCheck
cd /d "%~dp0" 2>nul

if not exist "%~dp0BuyCheck.ps1" goto notextracted
if not exist "%~dp0lib\Core.ps1" goto notextracted
if not exist "%~dp0checks\10-system.ps1" goto notextracted

set "PSEXE=%SystemRoot%\System32\WindowsPowerShell\v1.0\powershell.exe"
if exist "%SystemRoot%\Sysnative\WindowsPowerShell\v1.0\powershell.exe" set "PSEXE=%SystemRoot%\Sysnative\WindowsPowerShell\v1.0\powershell.exe"
if not exist "%PSEXE%" goto nops

rem Schon mit Administratorrechten gestartet? ("fltmc" klappt nur dann und aendert nichts)
if /i "%~1"=="/erhoeht" goto run
fltmc >nul 2>&1
if not "%ERRORLEVEL%"=="0" goto elevate

:run
"%PSEXE%" -NoProfile -ExecutionPolicy Bypass -File "%~dp0BuyCheck.ps1" -NoElevate
set "RC=%ERRORLEVEL%"
if not "%RC%"=="0" goto failed
goto end

:elevate
echo.
echo  BuyCheck braucht Administratorrechte, um SSD-, Akku- und BIOS-Werte zu lesen.
echo  Gleich erscheint eine Windows-Abfrage - bitte mit "Ja" bestaetigen.
echo  Danach oeffnet sich ein neues Fenster, dieses hier schliesst sich.
echo.
set "BC_SELF=%~f0"
"%PSEXE%" -NoProfile -ExecutionPolicy Bypass -Command "Start-Process -FilePath $env:BC_SELF -ArgumentList '/erhoeht' -Verb RunAs"
if not "%ERRORLEVEL%"=="0" goto noelevate
goto end

:noelevate
echo.
echo  Die Windows-Abfrage wurde abgebrochen oder hat nicht geklappt.
echo  Ohne Administratorrechte kann BuyCheck nur eingeschraenkt pruefen.
echo.
echo  Beliebige Taste = trotzdem eingeschraenkt starten
echo  Fenster schliessen = abbrechen
pause >nul
"%PSEXE%" -NoProfile -ExecutionPolicy Bypass -File "%~dp0BuyCheck.ps1" -NoElevate
set "RC=%ERRORLEVEL%"
if not "%RC%"=="0" goto failed
goto end

:failed
echo.
echo  BuyCheck wurde unerwartet beendet (Fehlercode %RC%).
echo  Die Meldung steht oben im Fenster. Falls vorhanden, steht sie auch in
echo  der Datei BuyCheck-Fehler.txt im BuyCheck-Ordner.
echo.
pause
goto end

:notextracted
echo.
echo  BuyCheck ist nicht vollstaendig vorhanden.
echo.
echo  Wahrscheinlich wurde Start-BuyCheck.cmd direkt in der ZIP-Datei geoeffnet.
echo  Bitte die ZIP-Datei zuerst komplett entpacken: Rechtsklick auf die ZIP-Datei,
echo  "Alle extrahieren...", dann im entpackten Ordner Start-BuyCheck.cmd starten.
echo.
pause
goto end

:nops
echo.
echo  Windows PowerShell wurde auf diesem Geraet nicht gefunden.
echo  BuyCheck braucht Windows 7 oder neuer, dort ist PowerShell eingebaut.
echo.
pause
goto end

:end
endlocal
