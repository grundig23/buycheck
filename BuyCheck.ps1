<#
.SYNOPSIS
    BuyCheck – prüft einen gebrauchten Windows-Laptop vor dem Kauf (Hardware, Manipulationen, Sperren).

.DESCRIPTION
    Zeigt ein Textmenü, in dem du festlegst, welche Tests laufen sollen (Voreinstellungen: Schnellcheck
    vor Ort, Gründlich, Linux-Plan, nur automatische Tests – oder jeden Test einzeln an-/abwählen).
    Danach laufen die Tests und es entsteht ein Bericht (HTML und Text) im Ordner "Berichte" neben
    diesem Skript (also auf dem USB-Stick).

    GRUNDSATZ: BuyCheck verändert nichts am geprüften Gerät. Es installiert nichts, kompiliert nichts,
    ändert keine Einstellungen und schreibt nichts auf den internen Datenträger (alle Datenträgertests
    sind rein lesend). Anleitung: README.md auf https://github.com/grundig23/buycheck

    Läuft mit jeder Windows PowerShell ab Version 2.0, also ab Windows 7 – ohne Updates am Gerät.
    Starten am besten über "Start-BuyCheck.cmd" (Doppelklick).

.PARAMETER NoElevate
    Nicht automatisch mit Administratorrechten neu starten (nur für Tests; viele Prüfungen brauchen Adminrechte).

.PARAMETER ReportRoot
    Anderer Ordner für die Berichte (Standard: Unterordner "Berichte" neben diesem Skript).
#>
[CmdletBinding()]
param(
    [switch]$NoElevate,
    [string]$ReportRoot
)

$ErrorActionPreference = 'Continue'
$script:BCVersion = '2.0.0'
$script:BCScriptPath = $MyInvocation.MyCommand.Definition
$script:BCRoot = Split-Path -Parent $script:BCScriptPath

# Fehler beim Start: Meldung zeigen, in BuyCheck-Fehler.txt festhalten (auf dem Stick, sonst im TEMP-Ordner) und warten
function Write-BCStartError {
    param([string]$Message)
    $text = @(
        ('BuyCheck {0} – Fehler beim Start ({1:dd.MM.yyyy HH:mm:ss})' -f $script:BCVersion, (Get-Date)),
        $Message,
        '',
        ('PowerShell {0} · {1} · {2} Bit · Pfad {3}' -f $PSVersionTable.PSVersion, [Environment]::OSVersion.VersionString, ([IntPtr]::Size * 8), $script:BCScriptPath)
    ) -join "`r`n"
    foreach ($dir in @($script:BCRoot, $env:TEMP)) {
        try {
            $f = Join-Path $dir 'BuyCheck-Fehler.txt'
            [IO.File]::WriteAllText($f, $text, (New-Object Text.UTF8Encoding($true)))
            return $f
        } catch { }
    }
    return $null
}

function Stop-BCWithMessage {
    param([string]$Message, [int]$Code = 1)
    Write-Host ''
    Write-Host $Message -ForegroundColor Red
    $f = Write-BCStartError $Message
    if ($f) { Write-Host ''; Write-Host "Die Meldung wurde gespeichert: $f" -ForegroundColor Yellow }
    Write-Host ''
    [void](Read-Host 'Enter drücken zum Beenden')
    exit $Code
}

# 64-Bit-PowerShell bevorzugen (aus einem 32-Bit-Prozess nur über "Sysnative" erreichbar)
function Get-BCWindowsPowerShell {
    $native = Join-Path $env:SystemRoot 'Sysnative\WindowsPowerShell\v1.0\powershell.exe'
    if (Test-Path -LiteralPath $native) { return $native }
    return (Join-Path $env:SystemRoot 'System32\WindowsPowerShell\v1.0\powershell.exe')
}

function Get-BCRelaunchArgs {
    $a = @('-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', ('"{0}"' -f $script:BCScriptPath))
    if ($ReportRoot) { $a += @('-ReportRoot', ('"{0}"' -f $ReportRoot)) }
    if ($NoElevate) { $a += '-NoElevate' }
    return $a
}

# ---------------------------------------------------------------- Umgebung prüfen
if ($PSVersionTable.PSEdition -eq 'Core') {
    # PowerShell 7: an die in Windows eingebaute Windows PowerShell übergeben
    if ($env:OS -eq 'Windows_NT') { Start-Process -FilePath (Get-BCWindowsPowerShell) -ArgumentList (Get-BCRelaunchArgs); exit 0 }
    Write-Host 'BuyCheck läuft nur unter Windows.' -ForegroundColor Red
    exit 1
}
if ($Host.Name -ne 'ConsoleHost') {
    # z. B. PowerShell ISE: BuyCheck braucht eine echte Konsole
    Start-Process -FilePath (Get-BCWindowsPowerShell) -ArgumentList (Get-BCRelaunchArgs)
    exit 0
}
if ([IntPtr]::Size -eq 4 -and $env:PROCESSOR_ARCHITEW6432 -and (Test-Path -LiteralPath (Join-Path $env:SystemRoot 'Sysnative\WindowsPowerShell\v1.0\powershell.exe'))) {
    # 32-Bit-PowerShell auf 64-Bit-Windows: im selben Fenster als 64-Bit neu starten
    $direct = @('-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', $script:BCScriptPath)
    if ($ReportRoot) { $direct += @('-ReportRoot', $ReportRoot) }
    if ($NoElevate) { $direct += '-NoElevate' }
    & (Get-BCWindowsPowerShell) $direct
    exit $LASTEXITCODE
}
if ("$($ExecutionContext.SessionState.LanguageMode)" -ne 'FullLanguage') {
    Stop-BCWithMessage 'Auf diesem Gerät erlaubt eine Richtlinie (z. B. einer Firma oder der S-Modus) nur eingeschränkte PowerShell-Skripte. BuyCheck kann hier nicht laufen.'
}

$principal = New-Object Security.Principal.WindowsPrincipal([Security.Principal.WindowsIdentity]::GetCurrent())
$script:BCIsAdmin = $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
if (-not $script:BCIsAdmin -and -not $NoElevate) {
    Write-Host 'BuyCheck braucht Administratorrechte (zum Lesen von SSD-, Akku-, BIOS- und Protokolldaten).' -ForegroundColor Yellow
    Write-Host 'Gleich erscheint eine Windows-Sicherheitsabfrage - bitte mit "Ja" bestätigen.' -ForegroundColor Yellow
    try {
        # Über den Starter neu starten: dessen Fenster bleibt bei einem Fehler offen
        $starter = Join-Path $script:BCRoot 'Start-BuyCheck.cmd'
        if (Test-Path -LiteralPath $starter) { Start-Process -FilePath $starter -ArgumentList '/erhoeht' -Verb RunAs -ErrorAction Stop }
        else { Start-Process -FilePath (Get-BCWindowsPowerShell) -ArgumentList (@('-NoExit') + (Get-BCRelaunchArgs)) -Verb RunAs -WorkingDirectory $script:BCRoot -ErrorAction Stop }
        exit 0
    } catch {
        Write-Host 'Ohne Administratorrechte sind viele Prüfungen nicht möglich (SSD-Werte, BIOS, Protokolle).' -ForegroundColor Yellow
        $a = Read-Host 'Trotzdem mit eingeschränkten Rechten fortfahren? (j/n)'
        if ($a -notmatch '^[jJyY]') { exit 1 }
    }
}

# ---------------------------------------------------------------- Bausteine laden (reines PowerShell, nichts wird kompiliert)
# lib\Win32.ps1 ist optional: Blockiert ein Virenscanner die Datei, laufen die übrigen Tests trotzdem.
$script:BCLoadProblems = @()
foreach ($f in @('lib\Core.ps1', 'lib\Win32.ps1', 'lib\Native.ps1', 'lib\Ui.ps1', 'lib\Interactive.ps1', 'lib\Workloads.ps1', 'lib\CpuDb.ps1', 'lib\Report.ps1')) {
    $p = Join-Path $script:BCRoot $f
    $optional = ($f -eq 'lib\Win32.ps1')
    if (-not (Test-Path -LiteralPath $p)) {
        if ($optional) { $script:BCLoadProblems += "$f fehlt"; continue }
        Stop-BCWithMessage "Datei fehlt: $p`nBitte den kompletten BuyCheck-Ordner kopieren bzw. die ZIP-Datei vollständig entpacken."
    }
    try { . $p }
    catch {
        $why = "$($_.Exception.Message)"
        if ($optional) { $script:BCLoadProblems += "$f konnte nicht geladen werden: $why"; $script:BCNativeErrorHint = "$f wurde blockiert: $why"; continue }
        $hint = ''
        if ($why -match '(?i)malicious|schädlich|Antivirus|virus') { $hint = "`n`nEin Virenscanner hat die Datei blockiert. BuyCheck verändert nichts am Gerät; den Virenschutz des Verkäufers bitte trotzdem NICHT abschalten." }
        Stop-BCWithMessage "Programmteil $f konnte nicht geladen werden:`n$why$hint"
    }
}

Initialize-BCConsole -Title "BuyCheck $script:BCVersion - Prüfung gebrauchter Laptops"
Clear-Host
Write-Host ''
Write-Host '  ____              ____ _               _    ' -ForegroundColor Cyan
Write-Host ' | __ ) _   _ _   _/ ___| |__   ___  ___| | __' -ForegroundColor Cyan
Write-Host ' |  _ \| | | | | | | |   | ''_ \ / _ \/ __| |/ /' -ForegroundColor Cyan
Write-Host ' | |_) | |_| | |_| | |___| | | |  __/ (__|   < ' -ForegroundColor Cyan
Write-Host ' |____/ \__,_|\__, |\____|_| |_|\___|\___|_|\_\' -ForegroundColor Cyan
Write-Host ('              |___/   Gebrauchtlaptop-Check ' + $script:BCVersion) -ForegroundColor Cyan
Write-Host ''
Write-BCOut -Text 'BuyCheck verändert nichts an diesem Gerät: keine Installation, keine Einstellungen, keine Schreibzugriffe auf die interne SSD. Berichte landen auf dem USB-Stick.' -Indent 1 -Color DarkGray
if (-not $script:BCIsAdmin) { Write-BCOut -Text 'ACHTUNG: ohne Administratorrechte - viele Werte sind nicht lesbar.' -Indent 1 -Color Yellow }
Write-BCOut ''
Write-BCOut -Text 'Lade Prüfmodule ...' -Indent 1
foreach ($lp in $script:BCLoadProblems) { Write-BCDebug "Laden: $lp" }
if ($script:BCNativeErrorHint) { $script:BCNativeError = $script:BCNativeErrorHint }
if (-not (Initialize-BCNative)) {
    $why = ''
    if (-not (Test-BCBlank "$script:BCNativeError")) { $why = " ($script:BCNativeError)" }
    Write-BCOut -Text "Hinweis: Einige direkte Hardware-Abfragen sind auf diesem System nicht möglich$why. Die übrigen Tests laufen normal." -Indent 1 -Color Yellow
}
$checkFiles = @(Get-ChildItem -LiteralPath (Join-Path $script:BCRoot 'checks') -Filter '*.ps1' | Where-Object { -not $_.PSIsContainer } | Sort-Object Name)
foreach ($cf in $checkFiles) {
    try { . $cf.FullName }
    catch { Write-BCOut -Text "Prüfmodul $($cf.Name) konnte nicht geladen werden: $($_.Exception.Message)" -Indent 3 -Color Yellow }
}
if ($script:BCChecks.Count -eq 0) { Stop-BCWithMessage 'Keine Prüfmodule gefunden (Ordner "checks").' }

$sys = Get-BCSystem
Write-BCOut -Text ("Gerät: {0} {1} · {2} {3} · PowerShell {4}" -f $sys.Manufacturer, $sys.DisplayModel, $sys.OsCaption, $sys.OsDisplayVersion, $sys.PowerShell) -Indent 1 -Color White
Start-Sleep -Milliseconds 800

# ---------------------------------------------------------------- Auswahl (Textmenü statt Schalter)
$profiles = @(
    (New-BCObject @('Id', 'quick', 'Label', 'Schnellcheck vor Ort', 'Description', 'Alle wichtigen Prüfungen mit kurzer Laufzeit - ideal beim Verkäufer.')),
    (New-BCObject @('Id', 'thorough', 'Label', 'Gründlich (mit Langzeittests)', 'Description', 'Zusätzlich RAM-Test, kompletter Lesetest der SSD, Entladetest, Bildausgang und Linux-Eignung.')),
    (New-BCObject @('Id', 'linux', 'Label', 'Linux-Plan (ohne Windows-Themen)', 'Description', 'Wie der Schnellcheck, aber ohne Windows-11-/Lizenzprüfung und mit Linux-Eignung.')),
    (New-BCObject @('Id', 'auto', 'Label', 'Nur automatische Tests (ohne Mithilfe)', 'Description', 'Läuft ohne Rückfragen durch - z. B. als erster Überblick.'))
)
$settingsPath = Join-Path $script:BCRoot 'BuyCheck-Auswahl.txt'
$settings = Read-BCSettings -Path $settingsPath
$allChecks = $script:BCChecks.ToArray()
$profileLabel = Show-BCSelection -Checks $allChecks -Profiles $profiles -Settings $settings
if (-not $profileLabel) { Write-BCOut -Text 'Beendet, es wurde nichts geprüft.' -Indent 1 -Color Yellow; exit 0 }
if ($profileLabel -eq 'Eigene Auswahl') { [void](Save-BCSettings -Path $settingsPath -ProfileId 'custom' -Checks $allChecks) }

$selected = @($allChecks | Where-Object { $_.Info.Selected } | Sort-Object RunOrder)
$notRun = @($allChecks | Where-Object { -not $_.Info.Selected })

# ---------------------------------------------------------------- Berichtsordner (auf dem USB-Stick)
$base = $ReportRoot
if (-not $base) { $base = Join-Path $script:BCRoot 'Berichte' }
$name = '{0:yyyy-MM-dd_HHmm}_{1}_{2}_{3}' -f (Get-Date), $sys.Manufacturer, $sys.Model, $sys.Serial
$name = ($name -replace '[\\/:*?"<>|\s]+', '_').Trim('_')
if ($name.Length -gt 90) { $name = $name.Substring(0, 90) }
$dir = Join-Path $base $name
$fallback = $false
try {
    New-Item -ItemType Directory -Path $dir -Force -ErrorAction Stop | Out-Null
    $probe = Join-Path $dir '.schreibtest'
    [IO.File]::WriteAllText($probe, 'ok')
    Remove-Item -LiteralPath $probe -Force
} catch {
    $fallback = $true
    $dir = Join-Path $env:TEMP "BuyCheck-Berichte\$name"
    New-Item -ItemType Directory -Path $dir -Force | Out-Null
    Write-BCOut -Text "Der BuyCheck-Ordner ist nicht beschreibbar - der Bericht wird vorübergehend hier gespeichert: $dir" -Indent 1 -Color Yellow
}
$script:BCReportDir = $dir
$transcript = $false
try { Start-Transcript -Path (Join-Path $dir 'protokoll.txt') -Force | Out-Null; $transcript = $true } catch { }

# ---------------------------------------------------------------- Tests ausführen
$started = Get-Date
Set-BCKeepAwake $true   # verhindert nur für die Laufzeit Standby/Bildschirmabschaltung
try {
    Clear-Host
    Write-BCHeader ("{0} Tests ({1}) - {2}" -f $selected.Count, $profileLabel, "$($sys.Manufacturer) $($sys.DisplayModel)")
    $i = 0
    foreach ($c in $selected) {
        $i++
        Invoke-BCCheck -Check $c -Index $i -Total $selected.Count
    }
} finally {
    Set-BCKeepAwake $false
}

# ---------------------------------------------------------------- Bericht
Write-BCHeader 'Bericht wird erstellt'
$reportPath = $null
try { $reportPath = New-BCReport -Directory $dir -ProfileLabel $profileLabel -Started $started -NotRun $notRun }
catch { Write-BCOut -Text "Bericht konnte nicht erstellt werden: $($_.Exception.Message)" -Indent 1 -Color Red }
if ($script:BCDebug.Count -gt 0) {
    try { [IO.File]::WriteAllLines((Join-Path $dir 'diagnose.txt'), $script:BCDebug.ToArray(), (New-Object Text.UTF8Encoding($true))) } catch { }
}

$counts = Get-BCLevelCounts
Write-BCOut ''
$vColor = 'Green'; $vText = 'Keine Auffälligkeiten in den durchgeführten Tests.'
if ($counts.Kritisch -gt 0) { $vColor = 'Red'; $vText = 'Schwerwiegende Befunde gefunden.' }
elseif ($counts.Warnung -gt 0) { $vColor = 'Yellow'; $vText = 'Auffälligkeiten gefunden.' }
Write-BCOut -Text $vText -Indent 1 -Color $vColor
Write-BCOut -Text ('Ergebnis: {0} kritisch · {1} Warnungen · {2} Hinweise · {3} OK · {4} nicht prüfbar' -f $counts.Kritisch, $counts.Warnung, $counts.Info, $counts.OK, $counts.Fehler) -Indent 1 -Color White
$top = @()
foreach ($r in $script:BCResults) { foreach ($f in $r.Findings) { if (@('Kritisch', 'Warnung') -contains $f.Level) { $top += $f } } }
foreach ($f in @($top | Sort-Object @{ Expression = { $script:BCLevelOrder[$_.Level] }; Descending = $true })) {
    Write-BCFindingLine (New-BCObject @('Level', $f.Level, 'Title', $f.Title, 'Detail', '', 'Advice', $f.Advice))
}
if ($top.Count -gt 0) { Write-BCOut -Text 'Genaue Werte und Erklärungen stehen im Bericht.' -Indent 1 -Color DarkGray }
if ($reportPath) {
    Write-BCOut ''
    Write-BCOut -Text "Bericht (zum Öffnen am eigenen Rechner): $reportPath" -Indent 1 -Color Green
    Write-BCOut -Text ('Textfassung: ' + (Join-Path $dir 'BuyCheck-Bericht.txt')) -Indent 1 -Color Green
    if ($fallback) { Write-BCOut -Text 'Bitte den Berichtsordner auf deinen USB-Stick kopieren und danach hier löschen.' -Indent 1 -Color Yellow }
}
if ($transcript) { try { Stop-Transcript | Out-Null } catch { } }
Write-BCOut ''
[void](Read-Host ' Enter drücken zum Beenden')
