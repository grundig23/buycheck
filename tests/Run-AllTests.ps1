# Führt alle BuyCheck-Tests aus und legt die Ausgaben in tests/ergebnisse/ ab.
# Läuft mit PowerShell 7 (pwsh) unter Linux; Windows-Funktionen werden in tests/simulation nachgebildet.
# Der Starter-Test (Start-BuyCheck.cmd) braucht zusätzlich wine und x86_64-w64-mingw32-gcc und wird sonst übersprungen.
#
#   pwsh -NoProfile -File tests/Run-AllTests.ps1
param([switch]$SkipStarter)
$ErrorActionPreference = 'Continue'
$root = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
$sim = Join-Path $PSScriptRoot 'simulation'
$out = Join-Path $PSScriptRoot 'ergebnisse'
New-Item -ItemType Directory -Force -Path $out | Out-Null
$results = New-Object System.Collections.Generic.List[string]

function Save-Log([string]$Name, [string[]]$Lines) {
    # Bildschirm-Steuerzeichen entfernen und Pfade dieses Rechners neutralisieren
    $esc = [char]27
    $clean = foreach ($l in $Lines) { ("$l" -replace "$esc\[[0-9;?]*[A-Za-z]", '').Replace($root, '<repo>').Replace([IO.Path]::GetTempPath().TrimEnd('/'), '<temp>') }
    Set-Content -Path (Join-Path $out $Name) -Value $clean -Encoding utf8
    return $clean
}
function Add-Result([string]$Name, [bool]$Ok, [string]$Detail) {
    $line = '{0}  {1}{2}' -f $(if ($Ok) { 'OK    ' } else { 'FEHLER' }), $Name, $(if ($Detail) { "  ($Detail)" } else { '' })
    $results.Add($line); Write-Host $line -ForegroundColor $(if ($Ok) { 'Green' } else { 'Red' })
}
function Test-NoExceptions([string[]]$Lines) { -not ($Lines | Where-Object { $_ -match 'Exception|ParserError|CommandNotFound|RuntimeException' }) }

$product = @(Get-Item (Join-Path $root 'BuyCheck.ps1')) + @(Get-ChildItem (Join-Path $root 'lib'), (Join-Path $root 'checks') -Filter *.ps1) | ForEach-Object { $_.FullName }

# 1) PowerShell-2.0-Kompatibilität und Syntax
$l = Save-Log 'ps2check.txt' (& (Join-Path $PSScriptRoot 'werkzeuge/ps2check.ps1') -Files $product 2>&1)
$parse = @($l | Where-Object { $_ -match 'PARSEFEHLER' }).Count
# Bekannte, geprüfte Meldungen: abgesicherte neuere Cmdlets, Write-Host -NoNewline (gibt es seit PS 1.0), List.Clear() (.NET 2.0)
$open = @($l | Where-Object { $_ -match ':\d+: ' -and $_ -notmatch 'NEUERES CMDLET|-NoNewline|\$chunks\.Clear\(\)' }).Count
Add-Result 'PowerShell-2.0-Kompatibilität' ($parse -eq 0 -and $open -eq 0) "$parse Parsefehler, $open offene Meldungen"

$bom = @($product | Where-Object { $b = [IO.File]::ReadAllBytes($_); -not ($b.Length -ge 3 -and $b[0] -eq 0xEF -and $b[1] -eq 0xBB -and $b[2] -eq 0xBF) })
Add-Result 'UTF-8-BOM in allen Skripten (für Windows PowerShell 5.1 und älter)' ($bom.Count -eq 0) ($bom -join ', ')

# Typografische Anführungszeichen („ “ ‚ ‘) beenden in PowerShell eine Zeichenkette – führt erst zur Laufzeit zum Absturz
$l = Save-Log 'anfuehrungszeichen.txt' (& (Join-Path $PSScriptRoot 'werkzeuge/quotecheck.ps1') -Files $product 2>&1)
Add-Result 'Keine Zeichenketten, die an typografischen Anführungszeichen enden' (($l -match '^Gesamt: 0$').Count -eq 1) (($l | Select-Object -Last 1))

# 2) Einzeltests
$l = Save-Log 'unittests.txt' (& pwsh -NoProfile -File (Join-Path $sim 'unittests.ps1') 2>&1)
Add-Result 'Einzeltests (Parser, Puffer, Töne, EDID, SMBIOS …)' (($l -match '^FEHLER GESAMT: 0$').Count -eq 1) (($l | Select-Object -Last 1))
$l = Save-Log 'cpudb.txt' (& pwsh -NoProfile -File (Join-Path $sim 'cpudb.tests.ps1') 2>&1)
Add-Result 'Prozessor-Datenbank' (($l -match '^FAILED: 0$').Count -eq 1) (($l | Select-Object -Last 1))

# 3) Geräte-Szenarien (A: ThinkPad mit gefälschtem CPU-Namen, B: Billig-Laptop mit Lesefehler, C: Windows-7-Gerät)
foreach ($s in 'A', 'B', 'C') {
    $l = Save-Log "szenario-$s.txt" (& pwsh -NoProfile -File (Join-Path $sim 'run-sim2.ps1') -Scenario $s 2>&1)
    $ok = ($l -contains 'OFFENE HANDLES: 0') -and ($l -contains 'SCHREIBZUGRIFF ANGEFORDERT: False') -and (Test-NoExceptions $l) -and (@($l -match '^BERICHT: ').Count -eq 1)
    Add-Result "Szenario $s" $ok (($l -match '^ZÄHLER: ') -join '')
}

# 4) Textmenü
$l = Save-Log 'menue.txt' (& pwsh -NoProfile -File (Join-Path $sim 'run-sim2.ps1') -MenuTest 2>&1)
$ok = (Test-NoExceptions $l) -and (@($l -match 'STRESS-DAUER: 7 ').Count -eq 1) -and (@($l -match 'gleich: True').Count -eq 1)
Add-Result 'Textmenü (Auswahl, Dauer, Speichern/Laden)' $ok ''

# 5) Hauptprogramm im Ganzen: normal, ohne lib/Win32.ps1, mit blockiertem lib/Core.ps1
$gen = Join-Path $sim 'gen-main.py'
$main = Join-Path $sim 'BuyCheck-sim.ps1'
& python3 $gen $root $main
$rep = Join-Path $sim 'main-report'
Remove-Item -Recurse -Force $rep -ErrorAction SilentlyContinue
$l = Save-Log 'hauptprogramm.txt' ('' | & pwsh -NoProfile -File $main -ReportRoot $rep 2>&1)
Add-Result 'Hauptprogramm (Profil "Nur automatisch")' ((Test-NoExceptions $l) -and (@($l -match 'Bericht \(zum Öffnen am eigenen Rechner\)').Count -eq 1)) ''

$env:SIM_NO_WIN32 = '1'
$l = Save-Log 'hauptprogramm-ohne-win32.txt' ('' | & pwsh -NoProfile -File $main -ReportRoot $rep 2>&1)
Remove-Item Env:SIM_NO_WIN32
$ok = (Test-NoExceptions $l) -and (@($l -match 'Hardware-Abfragen sind auf diesem System nicht möglich').Count -eq 1) -and (@($l -match 'Bericht \(zum Öffnen am eigenen Rechner\)').Count -eq 1)
Add-Result 'Hauptprogramm ohne lib/Win32.ps1 (Virenscanner blockiert)' $ok ''

$broken = Join-Path ([IO.Path]::GetTempPath()) ('buycheck-blockiert-' + [guid]::NewGuid().ToString('N').Substring(0, 8))
New-Item -ItemType Directory -Path $broken | Out-Null
Copy-Item (Join-Path $root 'BuyCheck.ps1') $broken
Copy-Item (Join-Path $root 'lib'), (Join-Path $root 'checks') $broken -Recurse
[IO.File]::WriteAllText((Join-Path $broken 'lib/Core.ps1'), "throw 'Dieses Skript enthält schädliche Inhalte und wurde von Ihrer Antivirensoftware blockiert.'", (New-Object Text.UTF8Encoding $true))
$brokenMain = Join-Path $sim 'BuyCheck-blockiert.ps1'
& python3 $gen $broken $brokenMain
$l = Save-Log 'hauptprogramm-core-blockiert.txt' ('' | & pwsh -NoProfile -File $brokenMain -ReportRoot $rep 2>&1)
$errFile = Join-Path $broken 'BuyCheck-Fehler.txt'
$ok = (Test-Path $errFile) -and ((Get-Content $errFile -Raw) -match 'lib\\Core\.ps1') -and (@($l -match 'Virenscanner').Count -ge 1)
Add-Result 'Hauptprogramm mit blockiertem lib/Core.ps1 (Meldung + BuyCheck-Fehler.txt)' $ok ''
Remove-Item -Recurse -Force $broken, $rep -ErrorAction SilentlyContinue

# 6) Starter unter Wine
if ($SkipStarter) { $results.Add('--      Starter-Test übersprungen (-SkipStarter)') }
elseif ((Get-Command wine -ErrorAction SilentlyContinue) -and (Get-Command x86_64-w64-mingw32-gcc -ErrorAction SilentlyContinue) -and
    ((& bash -c 'WINEDEBUG=-all timeout 120 wine cmd /c echo BCWINEOK 2>/dev/null' | Out-String) -notmatch 'BCWINEOK')) {
    $results.Add('--      Starter-Test übersprungen (Wine startet in dieser Umgebung nicht; letzter Lauf: ergebnisse/starter.txt)')
}
elseif ((Get-Command wine -ErrorAction SilentlyContinue) -and (Get-Command x86_64-w64-mingw32-gcc -ErrorAction SilentlyContinue)) {
    $l = Save-Log 'starter.txt' (& bash (Join-Path $PSScriptRoot 'starter/Test-Starter.sh') 2>&1)
    Add-Result 'Start-BuyCheck.cmd unter Wine' (($l -match '^FEHLER GESAMT: 0$').Count -eq 1) (($l | Select-Object -Last 1))
}
else { $results.Add('--      Starter-Test übersprungen (wine oder mingw fehlt)') }

$fails = @($results | Where-Object { $_ -like 'FEHLER*' }).Count
$summary = @("BuyCheck-Tests vom $(Get-Date -Format 'dd.MM.yyyy HH:mm'), Stand $(git -C $root describe --always --dirty 2>$null)", '') + $results + @('', "Fehlgeschlagen: $fails")
Set-Content -Path (Join-Path $out 'ZUSAMMENFASSUNG.txt') -Value $summary -Encoding utf8
''; $summary | Select-Object -Last 1
exit $fails
