#Requires -Version 5.1
<#
.SYNOPSIS
    BuyCheck – prüft einen gebrauchten Windows-Laptop vor dem Kauf (Hardware, Manipulationen, Sperren).

.DESCRIPTION
    Startet ein Auswahlfenster, in dem du festlegst, welche Tests laufen sollen (Voreinstellungen:
    Schnellcheck vor Ort, Gründlich, Linux-Plan, nur automatische Tests). Danach werden die Tests
    ausgeführt und ein HTML-Bericht im Ordner "Berichte" neben diesem Skript erstellt (USB-Stick).

    GRUNDSATZ: BuyCheck verändert nichts am geprüften Laptop. Es installiert nichts, ändert keine
    Einstellungen und schreibt nichts auf den internen Datenträger (alle Datenträgertests sind
    rein lesend). Berichte landen auf dem USB-Stick. Siehe README.md.

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
$script:BCVersion = '1.0.0'
$script:BCRoot = if ($PSScriptRoot) { $PSScriptRoot } else { Split-Path -Parent $MyInvocation.MyCommand.Path }
$script:BCReportDir = $null

function Stop-BCWithMessage {
    param([string]$Message, [int]$Code = 1)
    Write-Host ''
    Write-Host $Message -ForegroundColor Red
    Write-Host ''
    [void](Read-Host 'Enter drücken zum Beenden')
    exit $Code
}

function Get-BCWindowsPowerShell { return (Join-Path $env:SystemRoot 'System32\WindowsPowerShell\v1.0\powershell.exe') }

function Get-BCRelaunchArgs {
    $a = @('-NoProfile', '-ExecutionPolicy', 'Bypass', '-STA', '-File', ('"{0}"' -f $PSCommandPath))
    if ($ReportRoot) { $a += @('-ReportRoot', ('"{0}"' -f $ReportRoot)) }
    if ($NoElevate) { $a += '-NoElevate' }
    return $a
}

# ---------------------------------------------------------------- Umgebung prüfen
if ($PSVersionTable.PSEdition -eq 'Core') {
    if ($IsWindows) {
        # WinForms und Add-Type sind mit Windows PowerShell 5.1 am zuverlässigsten
        Start-Process -FilePath (Get-BCWindowsPowerShell) -ArgumentList (Get-BCRelaunchArgs)
        exit 0
    }
    Write-Host 'BuyCheck läuft nur unter Windows.' -ForegroundColor Red
    exit 1
}

$principal = New-Object Security.Principal.WindowsPrincipal([Security.Principal.WindowsIdentity]::GetCurrent())
$script:BCIsAdmin = $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
if (-not $script:BCIsAdmin -and -not $NoElevate) {
    Write-Host 'BuyCheck braucht Administratorrechte (zum Lesen von SSD-, Akku-, BIOS- und Protokolldaten).' -ForegroundColor Yellow
    Write-Host 'Gleich erscheint eine Windows-Sicherheitsabfrage – bitte mit "Ja" bestätigen.' -ForegroundColor Yellow
    try {
        Start-Process -FilePath (Get-BCWindowsPowerShell) -ArgumentList (Get-BCRelaunchArgs) -Verb RunAs -WorkingDirectory $script:BCRoot -ErrorAction Stop
        exit 0
    } catch {
        Write-Host 'Ohne Administratorrechte sind viele Prüfungen nicht möglich (SSD-Werte, BIOS, Protokolle).' -ForegroundColor Yellow
        $a = Read-Host 'Trotzdem mit eingeschränkten Rechten fortfahren? (j/n)'
        if ($a -notmatch '^[jJyY]') { exit 1 }
    }
}
if ([Threading.Thread]::CurrentThread.GetApartmentState() -ne [Threading.ApartmentState]::STA) {
    Start-Process -FilePath (Get-BCWindowsPowerShell) -ArgumentList (Get-BCRelaunchArgs) -WorkingDirectory $script:BCRoot
    exit 0
}

try { $Host.UI.RawUI.WindowTitle = "BuyCheck $script:BCVersion – Prüfung gebrauchter Laptops" } catch { }
Clear-Host
Write-Host ''
Write-Host '  ____              ____ _               _    ' -ForegroundColor Cyan
Write-Host ' | __ ) _   _ _   _/ ___| |__   ___  ___| | __' -ForegroundColor Cyan
Write-Host ' |  _ \| | | | | | | |   | ''_ \ / _ \/ __| |/ /' -ForegroundColor Cyan
Write-Host ' | |_) | |_| | |_| | |___| | | |  __/ (__|   < ' -ForegroundColor Cyan
Write-Host ' |____/ \__,_|\__, |\____|_| |_|\___|\___|_|\_\' -ForegroundColor Cyan
Write-Host '              |___/   Gebrauchtlaptop-Check' $script:BCVersion -ForegroundColor Cyan
Write-Host ''
Write-Host ' BuyCheck verändert nichts an diesem Laptop: keine Installation, keine Einstellungen,' -ForegroundColor DarkGray
Write-Host ' keine Schreibzugriffe auf die interne SSD. Berichte landen auf dem USB-Stick.' -ForegroundColor DarkGray
if (-not $script:BCIsAdmin) { Write-Host ' ACHTUNG: ohne Administratorrechte – viele Werte sind nicht lesbar.' -ForegroundColor Yellow }

# ---------------------------------------------------------------- Bausteine laden
Write-Host ''
Write-Host ' Lade Programmteile …' -ForegroundColor Gray
foreach ($f in @('lib\Core.ps1', 'lib\CpuDb.ps1', 'lib\Report.ps1')) {
    $p = Join-Path $script:BCRoot $f
    if (-not (Test-Path -LiteralPath $p)) { Stop-BCWithMessage "Datei fehlt: $p – bitte den kompletten BuyCheck-Ordner kopieren." }
    . $p
}
try {
    Add-Type -AssemblyName System.Windows.Forms, System.Drawing
    if (-not ('BuyCheck.CheckInfo' -as [type])) {
        $cs = @('Native.cs', 'Workloads.cs', 'Gui.cs') | ForEach-Object { Join-Path $script:BCRoot "lib\$_" }
        foreach ($p in $cs) { if (-not (Test-Path -LiteralPath $p)) { Stop-BCWithMessage "Datei fehlt: $p" } }
        $refs = @([System.Uri].Assembly.Location, [System.Windows.Forms.Form].Assembly.Location, [System.Drawing.Graphics].Assembly.Location)
        Add-Type -Path $cs -ReferencedAssemblies $refs -ErrorAction Stop
    }
} catch {
    Stop-BCWithMessage ("Die Programmteile konnten nicht geladen werden:`n$($_.Exception.Message)`n`nMögliche Ursache: Ein Virenscanner blockiert das Kompilieren. Siehe README (Problemlösung).")
}
try { [System.Windows.Forms.Application]::EnableVisualStyles() } catch { }

$checkFiles = @(Get-ChildItem -LiteralPath (Join-Path $script:BCRoot 'checks') -Filter '*.ps1' -File | Sort-Object Name)
foreach ($cf in $checkFiles) {
    try { . $cf.FullName }
    catch { Write-Host "   Prüfmodul $($cf.Name) konnte nicht geladen werden: $($_.Exception.Message)" -ForegroundColor Yellow }
}
if ($script:BCChecks.Count -eq 0) { Stop-BCWithMessage 'Keine Prüfmodule gefunden (Ordner "checks").' }

# ---------------------------------------------------------------- Auswahl
$profiles = @(
    (New-Object BuyCheck.ProfileInfo -ArgumentList 'quick', 'Schnellcheck vor Ort', 'Alle wichtigen Prüfungen mit kurzer Laufzeit – ideal beim Verkäufer.'),
    (New-Object BuyCheck.ProfileInfo -ArgumentList 'thorough', 'Gründlich (mit Langzeittests)', 'Zusätzlich RAM-Test, kompletter Lesetest der SSD, Entladetest, Bildausgang und Linux-Eignung.'),
    (New-Object BuyCheck.ProfileInfo -ArgumentList 'linux', 'Linux-Plan (ohne Windows-Themen)', 'Wie der Schnellcheck, aber ohne Windows-11-/Lizenzprüfung und mit Linux-Eignung.'),
    (New-Object BuyCheck.ProfileInfo -ArgumentList 'auto', 'Nur automatische Tests (ohne Mithilfe)', 'Läuft ohne Rückfragen durch – z. B. als erster Überblick.')
)
$settingsPath = Join-Path $script:BCRoot 'BuyCheck.settings.json'
$settings = Read-BCSettings -Path $settingsPath
$profileId = 'quick'
$remember = $false
if ($settings -and $settings.Selected) {
    $remember = $true
    $profileId = "$($settings.Profile)"
    $sel = @($settings.Selected)
    foreach ($c in $script:BCChecks) {
        $c.Info.Selected = $sel -contains $c.Id
        if ($settings.Options -and $settings.Options.PSObject.Properties[$c.Id]) {
            $o = $settings.Options.$($c.Id)
            foreach ($prop in $o.PSObject.Properties) { $c.Info.SetOption($prop.Name, [decimal]$prop.Value) }
        }
    }
} else {
    foreach ($c in $script:BCChecks) { $c.Info.Selected = $c.Info.InProfile('quick') }
}
$header = 'Häkchen setzen, was geprüft werden soll. Tests mit „mit Mithilfe“ fragen dich zwischendurch etwas oder brauchen eine Handlung (z. B. Netzteil abziehen). ' +
'Netzteil bitte angeschlossen lassen. Lange Tests lassen sich mit ESC abbrechen.'
$dlg = New-Object BuyCheck.SelectionDialog -ArgumentList ([BuyCheck.CheckInfo[]]@($script:BCChecks | ForEach-Object { $_.Info })), ([BuyCheck.ProfileInfo[]]$profiles), $profileId, $remember, $header
$res = $dlg.ShowDialog()
$profileId = $dlg.ProfileId
$remember = $dlg.RememberSelection
$dlg.Dispose()
if ($res -ne [System.Windows.Forms.DialogResult]::OK) { Write-Host ' Abgebrochen.' -ForegroundColor Yellow; exit 0 }
if ($remember) { Save-BCSettings -Path $settingsPath -ProfileId $profileId -Checks $script:BCChecks.ToArray() }
elseif (Test-Path -LiteralPath $settingsPath) { Remove-Item -LiteralPath $settingsPath -Force -ErrorAction SilentlyContinue }
$profileLabel = ($profiles | Where-Object { $_.Id -eq $profileId } | Select-Object -First 1).Label
if (-not $profileLabel) { $profileLabel = 'Benutzerdefiniert' }

$selected = @($script:BCChecks | Where-Object { $_.Info.Selected } | Sort-Object RunOrder)
$notRun = @($script:BCChecks | Where-Object { -not $_.Info.Selected })

# ---------------------------------------------------------------- Berichtsordner (auf dem USB-Stick)
$sys = Get-BCSystem
$base = if ($ReportRoot) { $ReportRoot } else { Join-Path $script:BCRoot 'Berichte' }
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
    Write-Host " Der BuyCheck-Ordner ist nicht beschreibbar – Bericht wird vorübergehend hier gespeichert: $dir" -ForegroundColor Yellow
}
$script:BCReportDir = $dir
$transcript = $false
try { Start-Transcript -Path (Join-Path $dir 'protokoll.txt') -Force | Out-Null; $transcript = $true } catch { }

# ---------------------------------------------------------------- Tests ausführen
$started = Get-Date
[BuyCheck.SystemState]::KeepAwake($true)   # verhindert nur für die Laufzeit Standby/Bildschirmabschaltung
try {
    Write-BCHeader ("{0} Tests ausgewählt ({1}) – {2}" -f $selected.Count, $profileLabel, "$($sys.Manufacturer) $($sys.DisplayModel)")
    $i = 0
    foreach ($c in $selected) {
        $i++
        Invoke-BCCheck -Check $c -Index $i -Total $selected.Count
    }
} finally {
    [BuyCheck.SystemState]::KeepAwake($false)
}

# ---------------------------------------------------------------- Bericht
Write-BCHeader 'Bericht wird erstellt'
$reportPath = $null
try { $reportPath = New-BCReport -Directory $dir -ProfileLabel $profileLabel -Started $started -NotRun $notRun }
catch { Write-Host " Bericht konnte nicht erstellt werden: $($_.Exception.Message)" -ForegroundColor Red }

$counts = Get-BCLevelCounts
Write-Host ''
Write-Host (' Ergebnis: {0} kritisch · {1} Warnungen · {2} Hinweise · {3} OK · {4} nicht prüfbar' -f $counts.Kritisch, $counts.Warnung, $counts.Info, $counts.OK, $counts.Fehler) -ForegroundColor White
$top = @()
foreach ($r in $script:BCResults) { foreach ($f in $r.Findings) { if ($f.Level -in @('Kritisch', 'Warnung')) { $top += $f } } }
foreach ($f in ($top | Sort-Object @{ Expression = { $script:BCLevelOrder[$_.Level] }; Descending = $true })) {
    Write-BCFindingLine ([pscustomobject]@{ Level = $f.Level; Title = $f.Title; Detail = '' })
}
if ($reportPath) {
    Write-Host ''
    Write-Host " Bericht: $reportPath" -ForegroundColor Green
    if ($fallback) { Write-Host ' Bitte den Berichtsordner auf deinen USB-Stick kopieren und danach hier löschen.' -ForegroundColor Yellow }
    if (Show-BCInfo -Title 'BuyCheck – fertig' -Message ("Alle ausgewählten Tests sind abgeschlossen.`n`nKritisch: {0}   Warnungen: {1}   Hinweise: {2}`n`nDer Bericht liegt auf dem USB-Stick:`n{3}`n`nJetzt im Browser öffnen?" -f $counts.Kritisch, $counts.Warnung, $counts.Info, $reportPath) -OkText 'Bericht öffnen' -CancelText 'Nicht öffnen') {
        try { Start-Process -FilePath $reportPath } catch { Write-Host " Bericht konnte nicht geöffnet werden: $($_.Exception.Message)" -ForegroundColor Yellow }
    }
}
if ($script:BCDebug.Count -gt 0) {
    try { [IO.File]::WriteAllLines((Join-Path $dir 'diagnose.txt'), $script:BCDebug.ToArray(), (New-Object Text.UTF8Encoding($true))) } catch { }
}
if ($transcript) { try { Stop-Transcript | Out-Null } catch { } }
Write-Host ''
[void](Read-Host ' Enter drücken zum Beenden')
