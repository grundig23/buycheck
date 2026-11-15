# BuyCheck – Grundgerüst: Testregistrierung, Befunde, Datensammler, Hilfsfunktionen
#
# GRUNDSATZ: Alles hier ist LESEND. Es werden keine Einstellungen, Registry-Werte, Dateien oder Treiber
# auf dem geprüften Gerät verändert. Ausgaben (Berichte) landen im Berichtsordner auf dem USB-Stick.
#
# KOMPATIBILITÄT: Läuft mit Windows PowerShell 2.0 (Windows 7) bis 5.1. Deshalb bewusst ohne neuere
# Sprachmittel ([ordered], [pscustomobject], -in, -shl/-shr, CIM- und JSON-Cmdlets) und nur mit
# Funktionen aus .NET 2.0. Neuere Windows-Cmdlets werden nur benutzt, wenn es sie auf dem Gerät gibt.

# ============================================================== Hilfsmittel für ältere PowerShell-Versionen
# Geordnetes Wörterbuch aus abwechselnd Schlüssel und Wert:  New-BCOrdered @('a', 1, 'b', 2)
function New-BCOrdered {
    param([object[]]$Pairs)
    $d = New-Object System.Collections.Specialized.OrderedDictionary
    if ($null -ne $Pairs) {
        for ($i = 0; $i + 1 -lt $Pairs.Count; $i += 2) { $d[[string]$Pairs[$i]] = $Pairs[$i + 1] }
    }
    return $d
}

# Objekt mit Eigenschaften in fester Reihenfolge:  New-BCObject @('Name', 'x', 'Wert', 1)
function New-BCObject {
    param([object[]]$Pairs)
    return (New-Object PSObject -Property (New-BCOrdered $Pairs))
}

# Ersatz für [string]::IsNullOrWhiteSpace (gibt es erst ab .NET 4)
function Test-BCBlank { param($Value) return (($null -eq $Value) -or ("$Value".Trim().Length -eq 0)) }

# Ersatz für ($Value -shr $Shift) -band $Mask (Schiebeoperatoren gibt es erst ab PowerShell 3.0)
function Get-BCBits {
    param([double]$Value, [int]$Shift, [int64]$Mask)
    return ([int64][math]::Floor($Value / [math]::Pow(2, $Shift))) -band $Mask
}

# Datumswerte aus WMI ('20190601000000.000000+000') oder als Text/DateTime
function ConvertFrom-BCWmiDate {
    param($Value)
    if ($null -eq $Value) { return $null }
    if ($Value -is [datetime]) { return $Value }
    $s = "$Value".Trim()
    if ($s -eq '') { return $null }
    if ($s -match '^(\d{14})\.\d{6}([+-])(\d{3})$') {
        if ($s.StartsWith('0000')) { return $null }
        $d = [datetime]::MinValue
        if (-not [datetime]::TryParseExact($Matches[1], 'yyyyMMddHHmmss', [Globalization.CultureInfo]::InvariantCulture, [Globalization.DateTimeStyles]::None, [ref]$d)) { return $null }
        # Angabe ist Ortszeit mit Versatz zu UTC in Minuten -> in lokale Zeit umrechnen
        $off = [int]$Matches[3]
        if ($Matches[2] -eq '-') { $off = -$off }
        return [datetime]::SpecifyKind($d.AddMinutes(-$off), [DateTimeKind]::Utc).ToLocalTime()
    }
    $d = [datetime]::MinValue
    if ([datetime]::TryParse($s, [Globalization.CultureInfo]::InvariantCulture, [Globalization.DateTimeStyles]::None, [ref]$d)) { return $d }
    return $null
}

$script:BCCommandCache = @{}
function Test-BCCommand {
    param([string]$Name)
    if (-not $script:BCCommandCache.ContainsKey($Name)) { $script:BCCommandCache[$Name] = [bool](Get-Command $Name -ErrorAction SilentlyContinue) }
    return $script:BCCommandCache[$Name]
}

# ============================================================== Zustand
$script:BCChecks = New-Object 'System.Collections.Generic.List[object]'
$script:BCResults = New-Object 'System.Collections.Generic.List[object]'
$script:BCCache = @{}
$script:BCCurrent = $null
$script:BCSummary = New-BCOrdered @()
$script:BCFacts = @{}
$script:BCCulture = New-Object Globalization.CultureInfo 'de-DE'
$script:BCDebug = New-Object 'System.Collections.Generic.List[string]'
$script:BCReportDir = $null

# Diagnoseprotokoll: optionale Abfragen dürfen scheitern (z. B. Dell-Schnittstelle auf einem Lenovo),
# sollen aber nachvollziehbar bleiben. Wird am Ende als diagnose.txt in den Berichtsordner geschrieben.
function Write-BCDebug {
    param([string]$Message)
    $script:BCDebug.Add(('{0:HH:mm:ss} {1}' -f (Get-Date), $Message))
}

$script:BCCategories = New-BCOrdered @(
    'Grunddaten & Sperren', 1,
    'Prozessor (CPU)', 2,
    'Arbeitsspeicher (RAM)', 3,
    'Datenträger (SSD/HDD)', 4,
    'Akku & Stromversorgung', 5,
    'Bildschirm & Grafik', 6,
    'Eingabe, Anschlüsse & Multimedia', 7,
    'Netzwerk & Funk', 8,
    'System & Protokolle', 9,
    'Windows', 10,
    'Linux', 11,
    'Abschluss', 12
)

# ============================================================== Registrierung der Tests
function Register-BuyCheck {
    param(
        [Parameter(Mandatory = $true)][string]$Id,
        [Parameter(Mandatory = $true)][string]$Category,
        [Parameter(Mandatory = $true)][string]$Title,
        [string]$Description = '',
        [int]$Order = 100,
        [int]$RunOrder = 500,
        [int]$Seconds = 10,
        [switch]$Interactive,
        [switch]$NeedsAcPower,
        [string[]]$Profiles = @('quick', 'thorough'),
        [object[]]$Options = @(),
        [Parameter(Mandatory = $true)][scriptblock]$Run
    )
    $opts = New-Object 'System.Collections.Generic.List[object]'
    foreach ($o in @($Options)) {
        if ($null -eq $o) { continue }
        $spu = 0.0; if ($o.ContainsKey('SecondsPerUnit')) { $spu = [double]$o.SecondsPerUnit }
        $unit = ''; if ($o.ContainsKey('Unit')) { $unit = [string]$o.Unit }
        $opts.Add((New-BCObject @('Key', [string]$o.Key, 'Label', [string]$o.Label, 'Default', [double]$o.Default, 'Min', [double]$o.Min,
                    'Max', [double]$o.Max, 'SecondsPerUnit', $spu, 'Unit', $unit, 'Value', [double]$o.Default)))
    }
    $catOrder = 50
    if ($script:BCCategories.Contains($Category)) { $catOrder = [int]$script:BCCategories[$Category] }
    $info = New-BCObject @('Id', $Id, 'Category', $Category, 'CategoryOrder', $catOrder, 'Order', $Order, 'Title', $Title,
        'Description', $Description, 'BaseSeconds', $Seconds, 'Interactive', [bool]$Interactive, 'NeedsAcPower', [bool]$NeedsAcPower,
        'Profiles', ([string[]]$Profiles), 'Options', $opts.ToArray(), 'Selected', $false)
    $script:BCChecks.Add((New-BCObject @('Id', $Id, 'Info', $info, 'Run', $Run, 'RunOrder', $RunOrder)))
}

function Test-BCInProfile {
    param($Info, [string]$ProfileId)
    if ($ProfileId -eq 'all') { return $true }
    if ($ProfileId -eq 'none') { return $false }
    return (@($Info.Profiles) -contains $ProfileId)
}

function Get-BCCheckSeconds {
    param($Info)
    $s = [double]$Info.BaseSeconds
    foreach ($o in @($Info.Options)) { if ($o) { $s += [double]$o.Value * [double]$o.SecondsPerUnit } }
    return $s
}

function Get-BCCheckOption { param($Info, [string]$Key) foreach ($o in @($Info.Options)) { if ($o -and $o.Key -eq $Key) { return $o } } return $null }

# Führt einen Test aus. Fehler im Test brechen nie das ganze Programm ab, sondern werden als "nicht prüfbar" vermerkt.
function Invoke-BCCheck {
    param($Check, [int]$Index, [int]$Total)
    $info = $Check.Info
    $result = New-BCObject @('Id', $info.Id, 'Title', $info.Title, 'Category', $info.Category, 'CategoryOrder', $info.CategoryOrder,
        'Order', $info.Order, 'Status', 'läuft', 'Seconds', 0.0, 'Error', $null,
        'Findings', (New-Object 'System.Collections.Generic.List[object]'), 'Sections', (New-Object 'System.Collections.Generic.List[object]'))
    $script:BCResults.Add($result)
    $script:BCCurrent = $result
    Write-BCCheckTitle -Index $Index -Total $Total -Title $info.Title
    $opts = @{}
    foreach ($o in @($info.Options)) { if ($o) { $opts[$o.Key] = [double]$o.Value } }
    $sw = [Diagnostics.Stopwatch]::StartNew()
    try {
        $null = & $Check.Run $opts
        $result.Status = 'fertig'
    } catch {
        $result.Status = 'Fehler'
        $result.Error = "$($_.Exception.Message)"
        $line = 0; try { $line = $_.InvocationInfo.ScriptLineNumber } catch { }
        Write-BCDebug "Test '$($info.Id)' abgebrochen: $($_.Exception.Message) (Zeile $line) $($_.ScriptStackTrace)"
        Add-BCFinding -Level Fehler -Title 'Test konnte nicht vollständig ausgeführt werden' -Detail ('{0} (Zeile {1})' -f $_.Exception.Message, $line)
    } finally {
        $sw.Stop()
        $result.Seconds = [math]::Round($sw.Elapsed.TotalSeconds, 1)
        Complete-BCProgress
        $script:BCCurrent = $null
    }
}

# ============================================================== Befunde und Berichtsabschnitte
$script:BCLevelOrder = @{ 'Kritisch' = 4; 'Warnung' = 3; 'Fehler' = 2; 'Info' = 1; 'OK' = 0 }
$script:BCLevelLabel = @{ 'Kritisch' = 'KRITISCH'; 'Warnung' = 'WARNUNG'; 'Fehler' = 'N. PRÜFB.'; 'Info' = 'HINWEIS'; 'OK' = 'OK' }

function Add-BCFinding {
    param(
        [ValidateSet('OK', 'Info', 'Warnung', 'Kritisch', 'Fehler')][string]$Level,
        [Parameter(Mandatory = $true)][string]$Title,
        [string]$Detail = '',
        [string]$Advice = ''
    )
    if (-not $script:BCCurrent) { return }
    $f = New-BCObject @('Level', $Level, 'Title', $Title, 'Detail', $Detail, 'Advice', $Advice,
        'CheckId', $script:BCCurrent.Id, 'CheckTitle', $script:BCCurrent.Title)
    $script:BCCurrent.Findings.Add($f)
    Write-BCFindingLine $f
}

function Add-BCTable {
    param([string]$Title, [object[]]$Rows, [string[]]$Columns)
    if (-not $script:BCCurrent) { return }
    $list = @($Rows | Where-Object { $null -ne $_ })
    if ($list.Count -eq 0) { return }
    if (-not $Columns) { $Columns = @($list[0].PSObject.Properties | ForEach-Object { $_.Name }) }
    $script:BCCurrent.Sections.Add((New-BCObject @('Type', 'table', 'Title', $Title, 'Rows', $list, 'Columns', $Columns)))
}

function Add-BCFacts {
    param([string]$Title, [System.Collections.IDictionary]$Data)
    if (-not $script:BCCurrent -or -not $Data -or $Data.Count -eq 0) { return }
    $copy = New-BCOrdered @()
    foreach ($k in @($Data.Keys)) {
        $v = $Data[$k]
        if ($null -ne $v -and "$v" -ne '') { $copy[[string]$k] = [string]$v }
    }
    if ($copy.Count -gt 0) { $script:BCCurrent.Sections.Add((New-BCObject @('Type', 'facts', 'Title', $Title, 'Data', $copy))) }
}

function Add-BCText {
    param([string]$Title, [string]$Text)
    if (-not $script:BCCurrent -or (Test-BCBlank $Text)) { return }
    $script:BCCurrent.Sections.Add((New-BCObject @('Type', 'text', 'Title', $Title, 'Text', $Text)))
}

function Add-BCChart {
    param([string]$Title, [double[]]$Values, [string]$Unit = '', [double]$Reference = [double]::NaN, [string]$ReferenceLabel = '')
    if (-not $script:BCCurrent -or -not $Values -or $Values.Count -lt 2) { return }
    $script:BCCurrent.Sections.Add((New-BCObject @('Type', 'chart', 'Title', $Title, 'Values', $Values, 'Unit', $Unit, 'Reference', $Reference, 'ReferenceLabel', $ReferenceLabel)))
}

function Add-BCLink {
    param([string]$Title, [string]$Url, [string]$Text = '')
    if (-not $script:BCCurrent) { return }
    $script:BCCurrent.Sections.Add((New-BCObject @('Type', 'link', 'Title', $Title, 'Url', $Url, 'Text', $Text)))
}

# Steckbrief-Zeile für den Berichtskopf
function Set-BCSummary { param([string]$Key, [string]$Value) if ($Value) { $script:BCSummary[$Key] = $Value } }
# Fakten für die Plausibilitätsprüfung (Gerätealter usw.)
function Set-BCFact { param([string]$Key, $Value) if ($null -ne $Value) { $script:BCFacts[$Key] = $Value } }
function Get-BCFact { param([string]$Key) if ($script:BCFacts.ContainsKey($Key)) { return $script:BCFacts[$Key] } return $null }

# Ergebnis eines interaktiven Tests (Verdict OK/Problem/Skip, Comment, Problems, Details) in Befunde umsetzen
function New-BCTestResult {
    param([string]$Verdict = 'Skip', [string]$Comment = '', [string[]]$Problems = @(), [string[]]$Details = @())
    return (New-BCObject @('Verdict', $Verdict, 'Comment', $Comment, 'Problems', $Problems, 'Details', $Details))
}

function Add-BCInteractiveResult {
    param($Result, [string]$OkTitle, [string]$ProblemTitle, [ValidateSet('Warnung', 'Kritisch')][string]$ProblemLevel = 'Warnung', [string]$Advice = '')
    $details = @($Result.Details | Where-Object { $_ })
    switch ($Result.Verdict) {
        'OK' {
            $txt = @($details | Select-Object -First 2) + @($Result.Comment) | Where-Object { $_ }
            Add-BCFinding -Level OK -Title $OkTitle -Detail (@($txt) -join ' · ')
        }
        'Problem' {
            $txt = @($Result.Problems) + @($Result.Comment) | Where-Object { $_ }
            Add-BCFinding -Level $ProblemLevel -Title $ProblemTitle -Detail (@($txt) -join ' · ') -Advice $Advice
        }
        default { Add-BCFinding -Level Info -Title 'Test übersprungen' -Detail $Result.Comment }
    }
    if ($details.Count -gt 0) { Add-BCText -Title 'Protokoll' -Text ($details -join "`n") }
}

# ============================================================== Formatierung (deutsche Schreibweise)
function Format-BCNum {
    param($Value, [int]$Decimals = 0)
    if ($null -eq $Value -or "$Value" -eq '') { return '–' }
    try { return ([double]$Value).ToString('N' + $Decimals, $script:BCCulture) } catch { return "$Value" }
}

function Format-BCBytes {
    param($Bytes, [switch]$Binary)
    if ($null -eq $Bytes) { return '–' }
    $b = [double]$Bytes
    $base = 1000.0; if ($Binary) { $base = 1024.0 }
    $units = @('B', 'KB', 'MB', 'GB', 'TB', 'PB')
    $i = 0
    while ($b -ge $base -and $i -lt $units.Count - 1) { $b /= $base; $i++ }
    $dec = 2
    if ($b -ge 100 -or $i -eq 0) { $dec = 0 } elseif ($b -ge 10) { $dec = 1 }
    return (Format-BCNum $b $dec) + ' ' + $units[$i]
}

function Format-BCDate {
    param($Date)
    $d = ConvertFrom-BCWmiDate $Date
    if ($null -eq $d) { return '–' }
    return $d.ToString('dd.MM.yyyy', $script:BCCulture)
}

function Format-BCHours {
    param($Hours)
    if ($null -eq $Hours) { return '–' }
    $h = [double]$Hours
    $years = $h / 8760.0
    $y = ''; if ($years -ge 1) { $y = ', ' + (Format-BCNum $years 1) + ' Jahre' }
    return (Format-BCNum $h 0) + ' h (ca. ' + (Format-BCNum ($h / 24.0) 0) + ' Tage Dauerbetrieb' + $y + ')'
}

function Format-BCDuration {
    param([double]$Seconds)
    if ($Seconds -lt 60) { return ('{0} s' -f [int]$Seconds) }
    $m = [int][math]::Round($Seconds / 60)
    if ($m -lt 60) { return ('{0} Min.' -f $m) }
    return ('{0} h {1:00} Min.' -f [int][math]::Floor($m / 60), ($m % 60))
}

function Get-BCHtml {
    param($Text)
    if ($null -eq $Text) { return '' }
    return ("$Text").Replace('&', '&amp;').Replace('<', '&lt;').Replace('>', '&gt;').Replace('"', '&quot;').Replace("'", '&#39;')
}

# ============================================================== Zwischenspeicher, WMI, Registry
function Get-BCCached {
    param([string]$Key, [scriptblock]$Factory)
    if (-not $script:BCCache.ContainsKey($Key)) {
        $value = $null
        try { $value = & $Factory } catch { $value = $null; Write-BCDebug "Datensammler '$Key' fehlgeschlagen: $($_.Exception.Message) $($_.ScriptStackTrace)" }
        $script:BCCache[$Key] = $value
    }
    return $script:BCCache[$Key]
}

# WMI-Abfrage (Get-WmiObject gibt es in jeder Windows-PowerShell-Version). Fehler werden protokolliert.
function Get-BCWmi {
    param([Parameter(Mandatory = $true)][string]$ClassName, [string]$Namespace = 'root\cimv2', [string]$Filter)
    $ns = $Namespace.Replace('/', '\')
    try {
        if ($Filter) { return @(Get-WmiObject -Namespace $ns -Class $ClassName -Filter $Filter -ErrorAction Stop) }
        return @(Get-WmiObject -Namespace $ns -Class $ClassName -ErrorAction Stop)
    } catch {
        $f = ''; if ($Filter) { $f = " [$Filter]" }
        Write-BCDebug "WMI $ns\$ClassName${f}: $($_.Exception.Message)"
        return @()
    }
}

function Get-BCRegValue {
    param([string]$Path, [string]$Name)
    try { return (Get-ItemProperty -Path $Path -Name $Name -ErrorAction Stop).$Name } catch { return $null }
}

function Test-BCPlaceholder {
    param([string]$Value)
    if (Test-BCBlank $Value) { return $true }
    $v = $Value.Trim().ToLowerInvariant()
    $bad = @('to be filled by o.e.m.', 'to be filled by oem', 'default string', 'system serial number', 'not specified',
        'not applicable', 'none', 'n/a', 'na', '0', '00000000', '0123456789', '123456789', 'chassis serial number',
        'serial', 'no asset tag', 'no asset information', 'asset-1234567890', 'oem', 'system manufacturer', 'system product name',
        'invalid', 'unknown', 'base board serial number', 'type1productconfigid', 'sku')
    return ($bad -contains $v) -or ($v -match '^0+$') -or ($v -match '^(x|f)+$')
}

# ============================================================== Firmware / SMBIOS
$script:BCSmbiosVersion = ''
function Get-BCSmbios {
    $s = Get-BCCached 'smbios' {
        $raw = Read-BCSmbiosRaw
        if ($raw) {
            $script:BCSmbiosVersion = "$($raw.Major).$($raw.Minor)"
            , (ConvertFrom-BCSmbios $raw.Data)
        } else { , @() }
    }
    return @($s)
}

function Get-BCSmbiosType { param([int]$Type) return @(Get-BCSmbios | Where-Object { $_.Type -eq $Type }) }

function ConvertFrom-BCSmbiosDate {
    param([string]$Text)
    if (Test-BCBlank $Text) { return $null }
    $formats = @('MM/dd/yyyy', 'MM/dd/yy', 'yyyy-MM-dd', 'dd.MM.yyyy')
    foreach ($f in $formats) {
        $d = [datetime]::MinValue
        if ([datetime]::TryParseExact($Text.Trim(), $f, [Globalization.CultureInfo]::InvariantCulture, [Globalization.DateTimeStyles]::None, [ref]$d)) { return $d }
    }
    return $null
}

# ============================================================== System-Grunddaten
$script:BCPortableChassis = @(8, 9, 10, 11, 14, 30, 31, 32)
$script:BCDesktopChassis = @(3, 4, 5, 6, 7, 13, 15, 16, 17, 23, 24, 35, 36)

function Get-BCSystem {
    return Get-BCCached 'system' {
        $cs = Get-BCWmi Win32_ComputerSystem | Select-Object -First 1
        $csp = Get-BCWmi Win32_ComputerSystemProduct | Select-Object -First 1
        $bios = Get-BCWmi Win32_BIOS | Select-Object -First 1
        $bb = Get-BCWmi Win32_BaseBoard | Select-Object -First 1
        $enc = Get-BCWmi Win32_SystemEnclosure | Select-Object -First 1
        $os = Get-BCWmi Win32_OperatingSystem | Select-Object -First 1
        $cvPath = 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion'
        $t0 = Get-BCSmbiosType 0 | Select-Object -First 1
        $t1 = Get-BCSmbiosType 1 | Select-Object -First 1
        $t3 = Get-BCSmbiosType 3 | Select-Object -First 1

        $manu = "$($cs.Manufacturer)".Trim()
        $model = "$($cs.Model)".Trim()
        $version = "$($csp.Version)".Trim()
        $display = $model
        if ($manu -match 'LENOVO' -and $version -and -not (Test-BCPlaceholder $version)) { $display = "$version ($model)" }
        $serial = "$($bios.SerialNumber)".Trim()
        $serialSmbios = ''
        if ($t1) { $serialSmbios = "$($t1.Str(7))".Trim() }
        $biosDate = $null
        if ($t0) { $biosDate = ConvertFrom-BCSmbiosDate $t0.Str(8) }
        if (-not $biosDate) { $biosDate = ConvertFrom-BCWmiDate $bios.ReleaseDate }
        $chassis = @()
        if ($enc -and $enc.ChassisTypes) { $chassis = @($enc.ChassisTypes | ForEach-Object { [int]$_ }) }
        elseif ($t3) { $chassis = @($t3.Byte(5) -band 0x7F) }
        $pcType = 0
        if ($cs -and $null -ne $cs.PCSystemType) { $pcType = [int]$cs.PCSystemType }
        $portable = (@($chassis | Where-Object { $script:BCPortableChassis -contains $_ }).Count -gt 0) -or ($pcType -eq 2)
        $desktop = (-not $portable) -and (@($chassis | Where-Object { $script:BCDesktopChassis -contains $_ }).Count -gt 0)
        $form = 'unbekannt'
        if ($portable) { $form = 'Notebook' } elseif ($desktop) { $form = 'Desktop' }
        $asset = "$($enc.SMBIOSAssetTag)".Trim()
        if ((Test-BCPlaceholder $asset) -and $t3) { $asset = "$($t3.Str(8))".Trim() }
        if (Test-BCPlaceholder $asset) { $asset = '' }
        $ubr = Get-BCRegValue $cvPath 'UBR'
        $build = "$(Get-BCRegValue $cvPath 'CurrentBuild')"
        if (-not $build -and $os) { $build = "$($os.BuildNumber)" }
        $dispVer = "$(Get-BCRegValue $cvPath 'DisplayVersion')"
        if (-not $dispVer) { $dispVer = "$(Get-BCRegValue $cvPath 'ReleaseId')" }
        if (-not $dispVer -and $os) { $dispVer = "$($os.CSDVersion)" }
        $osBuild = $build
        if ($ubr) { $osBuild = "$build.$ubr" }
        $osArch = "$($os.OSArchitecture)"
        if (-not $osArch) { $osArch = "$env:PROCESSOR_ARCHITECTURE" }
        New-BCObject @(
            'Manufacturer', $manu,
            'Model', $model,
            'DisplayModel', $display,
            'ProductVersion', $version,
            'Family', "$($cs.SystemFamily)".Trim(),
            'Sku', "$($cs.SystemSKUNumber)".Trim(),
            'Serial', $serial,
            'SerialSmbios', $serialSmbios,
            'Uuid', "$($csp.UUID)",
            'BoardVendor', "$($bb.Manufacturer)".Trim(),
            'BoardProduct', "$($bb.Product)".Trim(),
            'BoardSerial', "$($bb.SerialNumber)".Trim(),
            'BiosVendor', "$($bios.Manufacturer)".Trim(),
            'BiosVersion', "$($bios.SMBIOSBIOSVersion)".Trim(),
            'BiosDate', $biosDate,
            'ChassisTypes', $chassis,
            'IsPortable', [bool]$portable,
            'FormFactor', $form,
            'AssetTag', $asset,
            'OsCaption', "$($os.Caption)".Trim(),
            'OsVersion', "$($os.Version)",
            'OsBuild', $osBuild,
            'OsBuildNumber', [int]("0$build"),
            'OsDisplayVersion', $dispVer,
            'OsEdition', "$(Get-BCRegValue $cvPath 'EditionID')",
            'OsInstallDate', (ConvertFrom-BCWmiDate $os.InstallDate),
            'OsArchitecture', $osArch,
            'LastBoot', (ConvertFrom-BCWmiDate $os.LastBootUpTime),
            'RegisteredOwner', "$(Get-BCRegValue $cvPath 'RegisteredOwner')",
            'RegisteredOrg', "$(Get-BCRegValue $cvPath 'RegisteredOrganization')",
            'ComputerName', "$($cs.Name)",
            'PartOfDomain', [bool]$cs.PartOfDomain,
            'Domain', "$($cs.Domain)",
            'TotalPhysicalMemory', [double]$cs.TotalPhysicalMemory,
            'PowerShell', "$($PSVersionTable.PSVersion)"
        )
    }
}

# ============================================================== Prozessor
function Get-BCCpu {
    return Get-BCCached 'cpu' {
        $regPath = 'HKLM:\HARDWARE\DESCRIPTION\System\CentralProcessor\0'
        $regName = "$(Get-BCRegValue $regPath 'ProcessorNameString')".Trim()
        $regIdent = "$(Get-BCRegValue $regPath 'Identifier')"
        $regVendor = "$(Get-BCRegValue $regPath 'VendorIdentifier')"
        $envIdent = "$(Get-BCRegValue 'HKLM:\SYSTEM\CurrentControlSet\Control\Session Manager\Environment' 'PROCESSOR_IDENTIFIER')"
        $wmi = Get-BCWmi Win32_Processor | Select-Object -First 1
        $sig = Get-BCNativeCpuSignature           # direkt aus dem Kernel (nicht manipulierbar per Registry)
        $sigSource = 'Kernel'
        if (-not $sig) {
            # Notlösung: Kennung aus Registry/Umgebung (könnte manipuliert sein)
            $sigSource = 'Registry'
            $f = 0; $m = 0; $st = 0
            if ("$envIdent $regIdent" -match 'Family\s+(\d+)\s+Model\s+(\d+)\s+Stepping\s+(\d+)') { $f = [int]$Matches[1]; $m = [int]$Matches[2]; $st = [int]$Matches[3] }
            $a = "$env:PROCESSOR_ARCHITEW6432"
            if (-not $a) { $a = "$env:PROCESSOR_ARCHITECTURE" }
            $archNum = 9
            if ($a -eq 'x86') { $archNum = 0 } elseif ($a -eq 'ARM64') { $archNum = 12 } elseif ($a -eq 'ARM') { $archNum = 5 }
            $sig = New-BCObject @('Architecture', $archNum, 'Family', $f, 'Model', $m, 'Stepping', $st, 'LogicalCount', [Environment]::ProcessorCount)
        }
        $kernel = Get-BCKernelBrandString
        $topo = Get-BCCpuTopology
        $t4 = Get-BCSmbiosType 4 | Select-Object -First 1
        $family = [int]$sig.Family; $model = [int]$sig.Model; $stepping = [int]$sig.Stepping; $arch = [int]$sig.Architecture

        # Hersteller vorrangig aus der (nicht fälschbaren) Prozessorfamilie; nur bei mehrdeutigen Familien den Herstellertext nutzen
        $vendorText = "$regVendor $($wmi.Manufacturer) $kernel"
        $vendor = 'Unbekannt'
        if ($arch -eq 12 -or $arch -eq 5) {
            $vendor = 'ARM'
            if ("$($wmi.Manufacturer)$kernel$regName" -match 'Qualcomm|Snapdragon') { $vendor = 'Qualcomm' }
        } elseif ($family -eq 6) {
            $vendor = 'Intel'
            if ($vendorText -match 'Zhaoxin|Centaur|VIA') { $vendor = 'Andere' }
        } elseif (@(0x10, 0x11, 0x14, 0x15, 0x16, 0x17, 0x19, 0x1A) -contains $family) {
            $vendor = 'AMD'
        } elseif ($family -eq 0x18) {
            $vendor = 'AMD'
            if ($vendorText -match 'Hygon') { $vendor = 'Andere' }
        } elseif ($family -gt 0) {
            # 15 (Pentium 4/Athlon 64), 18/19 (AMD Llano bzw. neue Intel-Generationen) und künftige Familien
            $vendor = 'Intel'
            if ($vendorText -match 'AuthenticAMD|\bAMD\b') { $vendor = 'AMD' }
            elseif ($vendorText -match 'Zhaoxin|Centaur|VIA|Hygon') { $vendor = 'Andere' }
        }

        $smbName = $null; $smbSig = $null; $smbCores = $null; $smbThreads = $null; $smbMaxMHz = $null
        if ($t4) {
            $smbName = $t4.Str(0x10)
            $eax = $t4.Dword(0x08)
            if ($eax -gt 0) {
                $f = Get-BCBits $eax 8 0xF; $m = Get-BCBits $eax 4 0xF; $s = $eax -band 0xF
                $ef = Get-BCBits $eax 20 0xFF; $em = Get-BCBits $eax 16 0xF
                $df = $f; if ($f -eq 0xF) { $df = $f + $ef }
                $dm = $m; if ($f -eq 6 -or $f -eq 0xF) { $dm = $em * 16 + $m }
                $smbSig = @($df, $dm, $s)
            }
            $smbCores = $t4.Byte(0x23); $smbThreads = $t4.Byte(0x25); $smbMaxMHz = $t4.Word(0x14)
        }
        $cores = [int]$wmi.NumberOfCores; $threads = [int]$wmi.NumberOfLogicalProcessors
        $l2 = [double]$wmi.L2CacheSize * 1024; $l3 = [double]$wmi.L3CacheSize * 1024
        if ($topo) { $cores = $topo.Cores; $threads = $topo.LogicalProcessors; $l2 = [double]$topo.L2Bytes; $l3 = [double]$topo.L3Bytes }
        if ($threads -le 0) { $threads = [Environment]::ProcessorCount }
        $best = $regName
        if ($smbName) { $best = $smbName }
        if ($kernel) { $best = $kernel }
        if (-not $best) { $best = "$($wmi.Name)".Trim() }
        New-BCObject @(
            'Architecture', $arch,
            'Family', $family,
            'Model', $model,
            'Stepping', $stepping,
            'LogicalCount', [int]$sig.LogicalCount,
            'SignatureSource', $sigSource,
            'Vendor', $vendor,
            'KernelName', $kernel,
            'RegistryName', $regName,
            'WmiName', "$($wmi.Name)".Trim(),
            'SmbiosName', $smbName,
            'RegistryIdentifier', $regIdent,
            'RegistryVendor', $regVendor,
            'EnvIdentifier', $envIdent,
            'SmbiosSignature', $smbSig,
            'SmbiosCores', $smbCores,
            'SmbiosThreads', $smbThreads,
            'SmbiosMaxMHz', $smbMaxMHz,
            'Cores', $cores,
            'Threads', $threads,
            'L2Bytes', $l2,
            'L3Bytes', $l3,
            'MaxClockMHz', [int]$wmi.MaxClockSpeed,
            'WmiManufacturer', "$($wmi.Manufacturer)",
            'BestName', $best
        )
    }
}

# ============================================================== Geräte (PnP)
function Get-BCPnp {
    $all = Get-BCCached 'pnp' { , @(Get-BCWmi Win32_PnPEntity) }
    return @($all)
}

function Get-BCPciIds {
    param([string]$InstanceId)
    $r = @{ Ven = $null; Dev = $null; Subsys = $null }
    if ($InstanceId -match 'VEN_([0-9A-F]{4})') { $r.Ven = $Matches[1].ToUpper() }
    if ($InstanceId -match 'DEV_([0-9A-F]{4})') { $r.Dev = $Matches[1].ToUpper() }
    if ($InstanceId -match 'SUBSYS_([0-9A-F]{8})') { $r.Subsys = $Matches[1].ToUpper() }
    if (-not $r.Ven -and $InstanceId -match 'VID_([0-9A-F]{4})') { $r.Ven = $Matches[1].ToUpper() }
    if (-not $r.Dev -and $InstanceId -match 'PID_([0-9A-F]{4})') { $r.Dev = $Matches[1].ToUpper() }
    return $r
}

# Geräteeigenschaften gibt es per Cmdlet erst ab Windows 10 – sonst $null
function Get-BCPnpProperty {
    param([string]$InstanceId, [string]$Key)
    if (-not (Test-BCCommand 'Get-PnpDeviceProperty')) { return $null }
    try {
        $p = Get-PnpDeviceProperty -InstanceId $InstanceId -KeyName $Key -ErrorAction Stop
        return $p.Data
    } catch {
        Write-BCDebug "PnP-Eigenschaft ${Key} für ${InstanceId}: $($_.Exception.Message)"
        return $null
    }
}

$script:BCPciVendors = @{
    '8086' = 'Intel'; '10DE' = 'NVIDIA'; '1002' = 'AMD'; '1022' = 'AMD'; '14E4' = 'Broadcom'; '10EC' = 'Realtek'
    '14C3' = 'MediaTek'; '168C' = 'Qualcomm Atheros'; '17CB' = 'Qualcomm'; '1969' = 'Qualcomm Atheros (Killer)'; '1414' = 'Microsoft'
    '144D' = 'Samsung'; '15B7' = 'SanDisk/Western Digital'; '1B96' = 'Western Digital'; '1C5C' = 'SK hynix'; '1179' = 'Toshiba/Kioxia'
    '1E0F' = 'Kioxia'; '025E' = 'Solidigm'; '1344' = 'Micron'; '1987' = 'Phison'; '126F' = 'Silicon Motion'; '1E4B' = 'Maxio'
    '1D97' = 'Longsys (Lexar/FORESEE)'; '1CC1' = 'ADATA'; '1E49' = 'YMTC'; '1BB1' = 'Seagate'; '1CC4' = 'Union Memory (UMIS)'
    '1D79' = 'Transcend'; '2646' = 'Kingston'; '1F40' = 'Netac'; '1E95' = 'SSSTC (Lite-On)'; '14A4' = 'Lite-On'; '1DBE' = 'InnoGrit'
    '1B4B' = 'Marvell'; '1C58' = 'HGST/Western Digital'; '5143' = 'Qualcomm'; '1217' = 'O2 Micro'; '1180' = 'Ricoh'; '1912' = 'Renesas'
}

function Get-BCVendorName { param([string]$Ven) if ($Ven -and $script:BCPciVendors.ContainsKey($Ven.ToUpper())) { return $script:BCPciVendors[$Ven.ToUpper()] } return $null }

# ============================================================== Netzwerkadapter (Get-NetAdapter erst ab Windows 8, sonst WMI)
function Get-BCNetAdapters {
    $list = Get-BCCached 'netadapters' {
        $out = New-Object 'System.Collections.Generic.List[object]'
        $done = $false
        if (Test-BCCommand 'Get-NetAdapter') {
            try {
                foreach ($a in @(Get-NetAdapter -Physical -IncludeHidden -ErrorAction Stop)) {
                    if (-not $a) { continue }
                    $out.Add((New-BCObject @('InterfaceDescription', "$($a.InterfaceDescription)", 'Status', "$($a.Status)", 'PnPDeviceID', "$($a.PnPDeviceID)",
                                'LinkSpeed', "$($a.LinkSpeed)", 'NdisPhysicalMedium', $a.NdisPhysicalMedium)))
                }
                $done = $true
            } catch { Write-BCDebug "Get-NetAdapter: $($_.Exception.Message)" }
        }
        if (-not $done) {
            # Medientyp je Adapter (9 = WLAN, 14 = Ethernet) – WLAN-Karten heißen oft nicht "Wireless" (z. B. "Centrino Advanced-N")
            $media = @{}
            foreach ($m in @(Get-BCWmi -Namespace 'root\wmi' -ClassName MSNdis_PhysicalMediumType)) { if ($m) { $media["$($m.InstanceName)"] = [int]$m.NdisPhysicalMediumType } }
            foreach ($a in @(Get-BCWmi Win32_NetworkAdapter -Filter 'PhysicalAdapter = TRUE')) {
                if (-not $a) { continue }
                $medium = $null
                if ($media.ContainsKey("$($a.Name)")) { $medium = $media["$($a.Name)"] }
                elseif ("$($a.NetConnectionID)" -match '(?i)Drahtlos|Wireless|WLAN|Wi-?Fi') { $medium = 9 }
                $status = 'Unbekannt'
                if ($a.NetEnabled -eq $false) { $status = 'Disabled' }
                elseif ([int]$a.NetConnectionStatus -eq 2) { $status = 'Up' }
                elseif ($null -ne $a.NetConnectionStatus) { $status = 'Disconnected' }
                $speed = ''
                if ($a.Speed -and [double]$a.Speed -gt 0 -and [double]$a.Speed -lt 1e12) { $speed = (Format-BCNum ([double]$a.Speed / 1e6) 0) + ' Mbit/s' }
                $out.Add((New-BCObject @('InterfaceDescription', "$($a.Name)", 'Status', $status, 'PnPDeviceID', "$($a.PNPDeviceID)", 'LinkSpeed', $speed, 'NdisPhysicalMedium', $medium)))
            }
        }
        , $out.ToArray()
    }
    return @($list)
}

# ============================================================== Datenträger
$script:BCBusTypes = @{ 0 = 'Unknown'; 1 = 'SCSI'; 2 = 'ATAPI'; 3 = 'ATA'; 4 = '1394'; 5 = 'SSA'; 6 = 'Fibre Channel'; 7 = 'USB'; 8 = 'RAID'; 9 = 'iSCSI'; 10 = 'SAS'; 11 = 'SATA'; 12 = 'SD'; 13 = 'MMC'; 14 = 'Virtual'; 15 = 'File Backed Virtual'; 16 = 'Storage Spaces'; 17 = 'NVMe'; 18 = 'SCM'; 19 = 'UFS' }
$script:BCMediaTypes = @{ 0 = 'Unspecified'; 3 = 'HDD'; 4 = 'SSD'; 5 = 'SCM' }

function ConvertTo-BCEnumText {
    param($Value, [hashtable]$Map)
    if ($null -eq $Value) { return 'Unknown' }
    $s = "$Value"
    if ($s -match '^\d+$') { $n = [int]$s; if ($Map.ContainsKey($n)) { return $Map[$n] } return $s }
    return $s
}

# Windows 7 liefert Seriennummern teils als Hex-Text mit vertauschten Byte-Paaren
function ConvertFrom-BCDiskSerial {
    param([string]$Text)
    $t = "$Text".Trim()
    if ($t -match '^[0-9A-Fa-f]{16,}$' -and ($t.Length % 2) -eq 0) {
        $chars = @()
        for ($i = 0; $i + 1 -lt $t.Length; $i += 2) { $chars += [char][Convert]::ToInt32($t.Substring($i, 2), 16) }
        if (@($chars | Where-Object { [int]$_ -lt 32 -or [int]$_ -gt 126 }).Count -eq 0) {
            $sw = New-Object System.Text.StringBuilder
            for ($i = 0; $i + 1 -lt $chars.Count; $i += 2) { [void]$sw.Append($chars[$i + 1]); [void]$sw.Append($chars[$i]) }
            return $sw.ToString().Trim()
        }
    }
    return $t
}

$script:BCSmartNames = @{
    1 = 'Lesefehlerrate'; 5 = 'Ersetzte Sektoren/Blöcke'; 9 = 'Betriebsstunden'; 10 = 'Anlauf-Wiederholungen'; 12 = 'Einschaltvorgänge'
    169 = 'Restlebensdauer %'; 170 = 'Reserveblöcke'; 171 = 'Programmierfehler'; 172 = 'Löschfehler'; 173 = 'Wear Leveling (Löschzyklen)'
    174 = 'Unerwartete Stromverluste'; 175 = 'Programmierfehler (Chip)'; 177 = 'Wear Leveling Count'; 179 = 'Verbrauchte Reserveblöcke'
    180 = 'Freie Reserveblöcke'; 181 = 'Programmierfehler gesamt'; 182 = 'Löschfehler gesamt'; 183 = 'Defekte Blöcke (Laufzeit)'
    184 = 'End-to-End-Fehler'; 187 = 'Nicht korrigierbare Fehler'; 188 = 'Befehls-Timeouts'; 190 = 'Temperatur (Luftstrom)'
    191 = 'Erschütterungsfehler'; 192 = 'Notabschaltungen'; 193 = 'Lade-/Entladezyklen (Kopf)'; 194 = 'Temperatur'
    195 = 'ECC-Korrekturen'; 196 = 'Reallokationsereignisse'; 197 = 'Schwebende Sektoren'; 198 = 'Nicht korrigierbare Sektoren (offline)'
    199 = 'Übertragungsfehler (CRC)'; 202 = 'Restlebensdauer % (Micron/Crucial)'; 206 = 'Flughöhe'; 231 = 'Restlebensdauer (SSD Life Left)'
    232 = 'Reservespeicher'; 233 = 'Verschleißindikator / NAND-Schreibmenge'; 234 = 'NAND-Schreibmenge'; 235 = 'Stromausfall-Wiederherstellungen'
    241 = 'Geschriebene Daten (LBAs)'; 242 = 'Gelesene Daten (LBAs)'; 246 = 'Host-Schreibsektoren'; 249 = 'NAND-Schreibmenge (GiB)'
}

function Get-BCAtaSmart {
    param([string]$PnpId)
    if (Test-BCBlank $PnpId) { return $null }
    $data = @(Get-BCCached 'smartData' { , @(Get-BCWmi -Namespace 'root\wmi' -ClassName MSStorageDriver_FailurePredictData) })
    $thr = @(Get-BCCached 'smartThr' { , @(Get-BCWmi -Namespace 'root\wmi' -ClassName MSStorageDriver_FailurePredictThresholds) })
    $sts = @(Get-BCCached 'smartStatus' { , @(Get-BCWmi -Namespace 'root\wmi' -ClassName MSStorageDriver_FailurePredictStatus) })
    $key = $PnpId.ToUpperInvariant()
    $d = $data | Where-Object { $_ -and "$($_.InstanceName)".ToUpperInvariant().StartsWith($key) } | Select-Object -First 1
    if (-not $d) { return $null }
    $t = $thr | Where-Object { $_ -and "$($_.InstanceName)".ToUpperInvariant().StartsWith($key) } | Select-Object -First 1
    $s = $sts | Where-Object { $_ -and "$($_.InstanceName)".ToUpperInvariant().StartsWith($key) } | Select-Object -First 1
    $vs = [byte[]]$d.VendorSpecific
    $ts = $null
    if ($t) { $ts = [byte[]]$t.VendorSpecific }
    $attrs = New-Object 'System.Collections.Generic.List[object]'
    for ($i = 0; $i -lt 30; $i++) {
        $o = 2 + $i * 12
        if ($o + 11 -ge $vs.Length) { break }
        $id = [int]$vs[$o]
        if ($id -eq 0) { continue }
        $rawBytes = New-Object byte[] 8
        [Array]::Copy($vs, $o + 5, $rawBytes, 0, 6)
        $raw = [BitConverter]::ToUInt64($rawBytes, 0)
        $threshold = 0
        if ($ts) {
            for ($j = 0; $j -lt 30; $j++) {
                $p = 2 + $j * 12
                if ($p + 1 -ge $ts.Length) { break }
                if ([int]$ts[$p] -eq $id) { $threshold = [int]$ts[$p + 1]; break }
            }
        }
        $name = 'Herstellerspezifisch'
        if ($script:BCSmartNames.ContainsKey($id)) { $name = $script:BCSmartNames[$id] }
        $attrs.Add((New-BCObject @('Id', $id, 'Name', $name, 'Current', [int]$vs[$o + 3], 'Worst', [int]$vs[$o + 4], 'Threshold', $threshold,
                    'Raw', [double]$raw, 'Raw32', [double]([BitConverter]::ToUInt32($rawBytes, 0)), 'RawLow', [int]$rawBytes[0])))
    }
    $pf = $null
    if ($s) { $pf = [bool]$s.PredictFailure }
    return (New-BCObject @('Attributes', $attrs.ToArray(), 'PredictFailure', $pf))
}

function Get-BCDisks {
    $disks = Get-BCCached 'disks' {
        $dd = @(Get-BCWmi Win32_DiskDrive)
        $phys = @()
        if (Test-BCCommand 'Get-PhysicalDisk') {
            try { $phys = @(Get-PhysicalDisk -ErrorAction Stop) } catch { Write-BCDebug "Get-PhysicalDisk: $($_.Exception.Message)" }
        }
        $sysDisk = Get-BCSystemDiskNumber
        $numbers = @(@($dd | ForEach-Object { [int]$_.Index }) + @($phys | Where-Object { "$($_.DeviceId)" -match '^\d+$' } | ForEach-Object { [int]$_.DeviceId }) | Sort-Object -Unique)
        $result = New-Object 'System.Collections.Generic.List[object]'
        foreach ($num in $numbers) {
            $p = $phys | Where-Object { "$($_.DeviceId)" -eq "$num" } | Select-Object -First 1
            $d = $dd | Where-Object { [int]$_.Index -eq $num } | Select-Object -First 1
            $desc = Get-BCStorageDescriptor $num
            $geo = Get-BCDiskGeometry $num
            $bus = 'Unknown'
            if ($desc) { $bus = $desc.BusName }
            if ($bus -eq 'Unknown' -and $p) { $bus = ConvertTo-BCEnumText $p.BusType $script:BCBusTypes }
            if ($bus -eq 'Unknown' -and $d -and "$($d.InterfaceType)") { $bus = "$($d.InterfaceType)" }
            $model = ''
            if ($p) { $model = "$($p.FriendlyName)".Trim() }
            if (-not $model -and $d) { $model = "$($d.Model)".Trim() }
            if (-not $model -and $desc) { $model = ("$($desc.Vendor) $($desc.Product)").Trim() }
            $media = 'Unspecified'
            if ($p) { $media = ConvertTo-BCEnumText $p.MediaType $script:BCMediaTypes }
            if ($media -eq 'Unspecified' -or $media -eq 'Unknown') {
                $seek = Get-BCSeekPenalty $num
                if ($seek -eq $false) { $media = 'SSD' } elseif ($seek -eq $true) { $media = 'HDD' } else { $media = 'Unspecified' }
            }
            $pnpId = ''
            if ($d) { $pnpId = "$($d.PNPDeviceID)" }
            $isUsb = ($bus -eq 'USB') -or ($d -and "$($d.InterfaceType)" -eq 'USB') -or ($pnpId -match '^USBSTOR')
            $removable = ($desc -and $desc.Removable) -or ($d -and "$($d.MediaType)" -match 'Removable|Wechsel')
            $isExternal = $isUsb -or ($removable -and @('SD', 'MMC', '1394', 'Unknown') -contains $bus)
            $isVirtual = ($bus -match 'Virtual|iSCSI|Storage Spaces|File Backed')
            $size = 0.0
            if ($geo -and $geo.SizeBytes -gt 0) { $size = [double]$geo.SizeBytes }
            elseif ($p -and $p.Size) { $size = [double]$p.Size }
            elseif ($d -and $d.Size) { $size = [double]$d.Size }
            $serial = ''
            if ($p) { $serial = "$($p.SerialNumber)".Trim() }
            if (-not $serial -and $d) { $serial = ConvertFrom-BCDiskSerial "$($d.SerialNumber)" }
            if (-not $serial -and $desc) { $serial = ConvertFrom-BCDiskSerial $desc.Serial }
            $fw = ''
            if ($p) { $fw = "$($p.FirmwareVersion)".Trim() }
            if (-not $fw -and $d) { $fw = "$($d.FirmwareRevision)".Trim() }
            if (-not $fw -and $desc) { $fw = $desc.Revision }
            $health = ''
            if ($p) { $health = ConvertTo-BCEnumText $p.HealthStatus @{ 0 = 'Healthy'; 1 = 'Warning'; 2 = 'Unhealthy'; 5 = 'Unknown' } }
            elseif ($d) {
                $health = "$($d.Status)"
                if ($health -eq 'OK') { $health = 'Healthy' } elseif ($health -match 'Pred Fail') { $health = 'Unhealthy (SMART sagt Ausfall voraus)' }
            }
            $isSystem = ($null -ne $sysDisk -and [int]$sysDisk -eq [int]$num)
            $o = @{
                Number = [int]$num; Model = $model; Serial = $serial; Firmware = $fw; Bus = $bus; Media = $media; SizeBytes = $size
                Health = $health; IsUsb = [bool]$isExternal; IsVirtual = [bool]$isVirtual; IsBoot = $isSystem; IsSystem = $isSystem
                PnpId = $pnpId; Nvme = $null; NvmeError = $null; Identify = $null; Smart = $null; Reliability = $null
                PciInstance = $null; PciVen = $null; PciDev = $null; LinkSpeed = $null; LinkWidth = $null; MaxLinkSpeed = $null; MaxLinkWidth = $null
                IsSsd = $false; IsNvme = $false; SectorBytes = 512
            }
            if ($geo) { $o.SectorBytes = $geo.BytesPerSector }
            $o.IsNvme = ($bus -eq 'NVMe') -or ($model -match 'NVMe')
            $o.IsSsd = ($media -eq 'SSD') -or $o.IsNvme
            if (-not $isExternal -and -not $isVirtual) {
                # NVMe direkt abfragen (auch bei RAID/SCSI-Bus, z. B. hinter Intel RST – klappt nicht immer)
                if ($o.IsNvme -or $bus -match 'RAID|SCSI|Unknown') {
                    $err = $null
                    $h = Get-BCNvmeHealth -Disk $num -ErrorText ([ref]$err)
                    if ($h) {
                        $o.Nvme = $h; $o.IsNvme = $true; $o.IsSsd = $true
                        $err2 = $null
                        $o.Identify = Get-BCNvmeIdentify -Disk $num -ErrorText ([ref]$err2)
                    } else { $o.NvmeError = $err; Write-BCDebug "NVMe-Abfrage Datenträger $($num): $err" }
                }
                if (-not $o.Nvme) { $o.Smart = Get-BCAtaSmart -PnpId $pnpId }
                if ($p -and (Test-BCCommand 'Get-StorageReliabilityCounter')) {
                    try { $o.Reliability = $p | Get-StorageReliabilityCounter -ErrorAction Stop }
                    catch { Write-BCDebug "Get-StorageReliabilityCounter $($num): $($_.Exception.Message)" }
                }
                # PCIe-Anbindung (Elterngerät des Datenträgers) – nur ab Windows 10 abfragbar
                if ($pnpId) {
                    $parent = Get-BCPnpProperty -InstanceId $pnpId -Key 'DEVPKEY_Device_Parent'
                    if ($parent -and "$parent" -match '^PCI\\') {
                        $ids = Get-BCPciIds "$parent"
                        $o.PciInstance = "$parent"; $o.PciVen = $ids.Ven; $o.PciDev = $ids.Dev
                        $o.LinkSpeed = Get-BCPnpProperty -InstanceId "$parent" -Key 'DEVPKEY_PciDevice_CurrentLinkSpeed'
                        $o.LinkWidth = Get-BCPnpProperty -InstanceId "$parent" -Key 'DEVPKEY_PciDevice_CurrentLinkWidth'
                        $o.MaxLinkSpeed = Get-BCPnpProperty -InstanceId "$parent" -Key 'DEVPKEY_PciDevice_MaxLinkSpeed'
                        $o.MaxLinkWidth = Get-BCPnpProperty -InstanceId "$parent" -Key 'DEVPKEY_PciDevice_MaxLinkWidth'
                    } elseif ($parent) { $o.PciInstance = "$parent" }
                }
                if ($media -eq 'Unspecified' -and $o.Smart) {
                    # SSD-typische Attribute -> SSD
                    $ids = @($o.Smart.Attributes | ForEach-Object { $_.Id })
                    if (@($ids | Where-Object { @(169, 173, 177, 202, 231, 233) -contains $_ }).Count -gt 0) { $o.IsSsd = $true }
                }
            }
            $result.Add((New-Object PSObject -Property $o))
        }
        , $result.ToArray()
    }
    return @($disks)
}

function Get-BCInternalDisks { return @(Get-BCDisks | Where-Object { -not $_.IsUsb -and -not $_.IsVirtual }) }

function Get-BCPcieGen { param($Speed) switch ([int]$Speed) { 1 { 'PCIe 1.x' } 2 { 'PCIe 2.0' } 3 { 'PCIe 3.0' } 4 { 'PCIe 4.0' } 5 { 'PCIe 5.0' } 6 { 'PCIe 6.0' } default { $null } } }

# ============================================================== Akku
function ConvertFrom-BCChemistry {
    param($Value)
    if ($null -eq $Value) { return '' }
    try {
        $b = [BitConverter]::GetBytes([uint32]$Value)
        $s = -join ($b | Where-Object { $_ -ge 32 -and $_ -lt 127 } | ForEach-Object { [char]$_ })
        switch -Regex ($s.Trim()) {
            '^LIP' { return 'Lithium-Polymer' }
            '^LI' { return 'Lithium-Ionen' }
            '^NIMH' { return 'Nickel-Metallhydrid' }
            default { return $s.Trim() }
        }
    } catch { return "$Value" }
}

function Get-BCBattery {
    return Get-BCCached 'battery' {
        $static = @(Get-BCWmi -Namespace 'root\wmi' -ClassName BatteryStaticData)
        $full = @(Get-BCWmi -Namespace 'root\wmi' -ClassName BatteryFullChargedCapacity)
        $cyc = @(Get-BCWmi -Namespace 'root\wmi' -ClassName BatteryCycleCount)
        $w32 = @(Get-BCWmi Win32_Battery)
        $list = New-Object 'System.Collections.Generic.List[object]'
        foreach ($s in $static) {
            if (-not $s) { continue }
            $inst = "$($s.InstanceName)"
            $f = $full | Where-Object { $_ -and "$($_.InstanceName)" -eq $inst } | Select-Object -First 1
            $c = $cyc | Where-Object { $_ -and "$($_.InstanceName)" -eq $inst } | Select-Object -First 1
            $caps = 0; try { $caps = [int64]$s.Capabilities } catch { }
            $fullMWh = $null; if ($f) { $fullMWh = [double]$f.FullChargedCapacity }
            $cycles = $null; if ($c) { $cycles = [int64]$c.CycleCount }
            $list.Add((New-BCObject @(
                        'Instance', $inst,
                        'Name', "$($s.DeviceName)".Trim(),
                        'Manufacturer', "$($s.ManufactureName)".Trim(),
                        'Serial', "$($s.SerialNumber)".Trim(),
                        'Chemistry', (ConvertFrom-BCChemistry $s.Chemistry),
                        'DesignMWh', [double]$s.DesignedCapacity,
                        'FullMWh', $fullMWh,
                        'Cycles', $cycles,
                        'ManufactureDate', (ConvertFrom-BCWmiDate $s.ManufactureDate),
                        'Relative', (($caps -band 0x40000000) -ne 0)
                    )))
        }
        New-BCObject @('Batteries', $list.ToArray(), 'Win32', $w32, 'Present', ($static.Count -gt 0 -or $w32.Count -gt 0))
    }
}

# Aktueller Zustand (nicht zwischengespeichert)
function Get-BCBatteryStatus {
    $st = Get-BCWmi -Namespace 'root\wmi' -ClassName BatteryStatus | Select-Object -First 1
    $w = Get-BCWmi Win32_Battery | Select-Object -First 1
    $ps = Get-BCPowerStatus
    $pct = $null
    if ($w -and $null -ne $w.EstimatedChargeRemaining) { $pct = [int]$w.EstimatedChargeRemaining }
    elseif ($null -ne $ps.Percent) { $pct = $ps.Percent }
    $online = $ps.AcOnline
    if ($st -and $null -ne $st.PowerOnline) { $online = [bool]$st.PowerOnline }
    $rem = $null; $volt = $null; $chg = $null; $dis = $null; $charging = $null; $discharging = $null
    if ($st) {
        $rem = [double]$st.RemainingCapacity; $volt = [double]$st.Voltage; $chg = [double]$st.ChargeRate; $dis = [double]$st.DischargeRate
        $charging = [bool]$st.Charging; $discharging = [bool]$st.Discharging
    }
    return (New-BCObject @('Percent', $pct, 'RemainingMWh', $rem, 'VoltageMV', $volt, 'ChargeRateMW', $chg, 'DischargeRateMW', $dis,
            'PowerOnline', $online, 'Charging', $charging, 'Discharging', $discharging, 'Time', (Get-Date)))
}

# ============================================================== Bildschirme (EDID direkt aus dem Display)
function ConvertFrom-BCEdid {
    param([byte[]]$D)
    $r = @{
        Valid = $false; ManufacturerId = ''; ProductCode = 0; ProductCodeHex = ''; SerialNumber = 0; WeekOfManufacture = 0; YearOfManufacture = 0
        Version = ''; Digital = $false; WidthCm = 0; HeightCm = 0; NativeWidth = 0; NativeHeight = 0; NativeRefreshHz = 0.0
        ImageWidthMm = 0; ImageHeightMm = 0; MonitorName = ''; SerialText = ''; TextDescriptors = @(); ExtensionCount = 0; DiagonalInches = 0.0
    }
    if ($null -eq $D -or $D.Length -lt 128) { return (New-Object PSObject -Property $r) }
    $hdr = @(0, 255, 255, 255, 255, 255, 255, 0)
    for ($i = 0; $i -lt 8; $i++) { if ([int]$D[$i] -ne $hdr[$i]) { return (New-Object PSObject -Property $r) } }
    $r.Valid = $true
    $m = [int]$D[8] * 256 + [int]$D[9]
    $r.ManufacturerId = [string][char](64 + (Get-BCBits $m 10 0x1F)) + [string][char](64 + (Get-BCBits $m 5 0x1F)) + [string][char](64 + ($m -band 0x1F))
    $r.ProductCode = Get-BCU16 $D 10
    $r.ProductCodeHex = '{0:X4}' -f $r.ProductCode
    $r.SerialNumber = Get-BCU32 $D 12
    $r.WeekOfManufacture = [int]$D[16]
    $r.YearOfManufacture = [int]$D[17] + 1990
    $r.Version = "$($D[18]).$($D[19])"
    $r.Digital = (([int]$D[20] -band 0x80) -ne 0)
    $r.WidthCm = [int]$D[21]; $r.HeightCm = [int]$D[22]
    $r.ExtensionCount = [int]$D[126]
    $texts = @()
    $first = $true
    for ($i = 0; $i -lt 4; $i++) {
        $o = 54 + $i * 18
        $pclk = Get-BCU16 $D $o
        if ($pclk -ne 0) {
            if ($first) {
                $first = $false
                $hA = [int]$D[$o + 2] + 16 * ([int]$D[$o + 4] -band 0xF0)
                $hB = [int]$D[$o + 3] + 256 * ([int]$D[$o + 4] -band 0x0F)
                $vA = [int]$D[$o + 5] + 16 * ([int]$D[$o + 7] -band 0xF0)
                $vB = [int]$D[$o + 6] + 256 * ([int]$D[$o + 7] -band 0x0F)
                $r.NativeWidth = $hA; $r.NativeHeight = $vA
                $r.ImageWidthMm = [int]$D[$o + 12] + 16 * ([int]$D[$o + 14] -band 0xF0)
                $r.ImageHeightMm = [int]$D[$o + 13] + 256 * ([int]$D[$o + 14] -band 0x0F)
                $total = [double]($hA + $hB) * ($vA + $vB)
                if ($total -gt 0) { $r.NativeRefreshHz = [math]::Round($pclk * 10000.0 / $total, 1) }
            }
        } else {
            $tag = [int]$D[$o + 3]
            $sb = New-Object System.Text.StringBuilder
            for ($k = 0; $k -lt 13; $k++) {
                $c = [int]$D[$o + 5 + $k]
                if ($c -eq 0x0A -or $c -eq 0) { break }
                if ($c -ge 32 -and $c -lt 127) { [void]$sb.Append([char]$c) } else { [void]$sb.Append(' ') }
            }
            $text = $sb.ToString().Trim()
            if ($tag -eq 0xFC) { $r.MonitorName = $text }
            elseif ($tag -eq 0xFF) { $r.SerialText = $text }
            elseif ($tag -eq 0xFE -and $text.Length -gt 0) { $texts += $text }
        }
    }
    $r.TextDescriptors = $texts
    $w = $r.WidthCm / 2.54; $h = $r.HeightCm / 2.54
    if ($r.ImageWidthMm -gt 0) { $w = $r.ImageWidthMm / 25.4 }
    if ($r.ImageHeightMm -gt 0) { $h = $r.ImageHeightMm / 25.4 }
    $r.DiagonalInches = [math]::Sqrt($w * $w + $h * $h)
    return (New-Object PSObject -Property $r)
}

function Get-BCMonitors {
    $mons = Get-BCCached 'monitors' {
        $ids = @(Get-BCWmi -Namespace 'root\wmi' -ClassName WmiMonitorID)
        $conn = @(Get-BCWmi -Namespace 'root\wmi' -ClassName WmiMonitorConnectionParams)
        $basic = @(Get-BCWmi -Namespace 'root\wmi' -ClassName WmiMonitorBasicDisplayParams)
        $list = New-Object 'System.Collections.Generic.List[object]'
        $toStr = { param($arr) if (-not $arr) { return '' } (-join (@($arr) | Where-Object { $_ -gt 0 } | ForEach-Object { [char][int]$_ })).Trim() }
        foreach ($m in $ids) {
            if (-not $m) { continue }
            $inst = "$($m.InstanceName)"
            $c = $conn | Where-Object { $_ -and "$($_.InstanceName)" -eq $inst } | Select-Object -First 1
            $b = $basic | Where-Object { $_ -and "$($_.InstanceName)" -eq $inst } | Select-Object -First 1
            $tech = $null
            if ($c) { $tech = [int64]$c.VideoOutputTechnology }
            $internal = $false
            if ($null -ne $tech) { $internal = @(6, 11, 13, 2147483648, -2147483648) -contains $tech }
            $edid = $null
            $regPath = 'HKLM:\SYSTEM\CurrentControlSet\Enum\' + ($inst -replace '_\d+$', '') + '\Device Parameters'
            $raw = Get-BCRegValue $regPath 'EDID'
            if ($raw) { $edid = ConvertFrom-BCEdid ([byte[]]$raw) }
            $wcm = $null; $hcm = $null
            if ($b) { $wcm = [int]$b.MaxHorizontalImageSize; $hcm = [int]$b.MaxVerticalImageSize }
            $list.Add((New-BCObject @(
                        'Instance', $inst,
                        'Internal', $internal,
                        'Technology', $tech,
                        'Manufacturer', (& $toStr $m.ManufacturerName),
                        'ProductCode', (& $toStr $m.ProductCodeID),
                        'Serial', (& $toStr $m.SerialNumberID),
                        'FriendlyName', (& $toStr $m.UserFriendlyName),
                        'Year', [int]$m.YearOfManufacture,
                        'Week', [int]$m.WeekOfManufacture,
                        'WidthCm', $wcm,
                        'HeightCm', $hcm,
                        'Edid', $edid
                    )))
        }
        , $list.ToArray()
    }
    return @($mons)
}

$script:BCPanelMakers = @{
    'BOE' = 'BOE'; 'AUO' = 'AU Optronics'; 'LGD' = 'LG Display'; 'SHP' = 'Sharp'; 'CMN' = 'Innolux (Chimei)'; 'INX' = 'Innolux'
    'IVO' = 'InfoVision'; 'SDC' = 'Samsung Display'; 'SEC' = 'Samsung'; 'CSO' = 'CSOT (China Star)'; 'TMX' = 'Tianma'
    'NCP' = 'Nanjing CEC Panda'; 'LEN' = 'Lenovo (Herstellerkennung überschrieben)'; 'DEL' = 'Dell (Herstellerkennung überschrieben)'
    'HWP' = 'HP (Herstellerkennung überschrieben)'; 'APP' = 'Apple'; 'MS_' = 'Microsoft'; 'CHI' = 'Chimei'; 'LPL' = 'LG Philips'
    'HSD' = 'HannStar'; 'BBY' = 'BOE (alt)'; 'STA' = 'STA'; 'ACR' = 'Acer'; 'AUS' = 'ASUS'; 'SAM' = 'Samsung'; 'GSM' = 'LG (Monitor)'
}

# ============================================================== Leistungs- und Temperaturmessung (für Belastungstests)
function Get-BCPerfSample {
    $p = Get-BCWmi -ClassName Win32_PerfFormattedData_Counters_ProcessorInformation -Filter "Name='_Total'" | Select-Object -First 1
    $tz = @(Get-BCWmi -ClassName Win32_PerfFormattedData_Counters_ThermalZoneInformation)
    $acpi = @(Get-BCWmi -Namespace 'root\wmi' -ClassName MSAcpi_ThermalZoneTemperature)
    $temps = New-Object 'System.Collections.Generic.List[double]'
    $passive = New-Object 'System.Collections.Generic.List[double]'
    $throttle = 0
    foreach ($z in $tz) {
        if (-not $z) { continue }
        $t = $null
        if ($z.HighPrecisionTemperature -and [double]$z.HighPrecisionTemperature -gt 0) { $t = [double]$z.HighPrecisionTemperature / 10.0 - 273.15 }
        elseif ($z.Temperature -and [double]$z.Temperature -gt 0) { $t = [double]$z.Temperature - 273.15 }
        if ($null -ne $t -and $t -gt 0 -and $t -lt 150) { $temps.Add($t) }
        if ($null -ne $z.PercentPassiveLimit) { $passive.Add([double]$z.PercentPassiveLimit) }
        if ($z.ThrottleReasons) { $throttle = $throttle -bor [int]$z.ThrottleReasons }
    }
    foreach ($z in $acpi) {
        if ($z -and $z.CurrentTemperature -and [double]$z.CurrentTemperature -gt 0) {
            $t = [double]$z.CurrentTemperature / 10.0 - 273.15
            if ($t -gt 0 -and $t -lt 150) { $temps.Add($t) }
        }
    }
    # "% Processor Performance" gibt es ab Windows 8; Windows 7 kennt nur "% of Maximum Frequency" (ohne Turbo)
    $perf = $null; $util = $null; $base = $null; $limit = $null
    if ($p) {
        if ($null -ne $p.PercentProcessorPerformance) { $perf = [double]$p.PercentProcessorPerformance }
        elseif ($null -ne $p.PercentofMaximumFrequency) { $perf = [double]$p.PercentofMaximumFrequency }
        if ($null -ne $p.PercentProcessorUtility) { $util = [double]$p.PercentProcessorUtility }
        if ($p.ProcessorFrequency) { $base = [double]$p.ProcessorFrequency }
        if ($null -ne $p.PerformanceLimitFlags) { $limit = [int]$p.PerformanceLimitFlags }
    }
    $tMax = $null; if ($temps.Count -gt 0) { $tMax = ($temps | Measure-Object -Maximum).Maximum }
    $pMin = $null; if ($passive.Count -gt 0) { $pMin = ($passive | Measure-Object -Minimum).Minimum }
    return (New-BCObject @('Time', (Get-Date), 'Perf', $perf, 'Utility', $util, 'BaseMHz', $base, 'LimitFlags', $limit,
            'TempMax', $tMax, 'PassiveMin', $pMin, 'Throttle', $throttle))
}

# ============================================================== Einstellungen (letzte Auswahl, als Textdatei auf dem USB-Stick)
function Read-BCSettings {
    param([string]$Path)
    if (-not (Test-Path -LiteralPath $Path)) { return $null }
    try {
        $r = @{ Profile = ''; Selected = @(); Options = @{} }
        foreach ($line in [IO.File]::ReadAllLines($Path)) {
            $l = $line.Trim()
            if ($l -eq '' -or $l.StartsWith('#')) { continue }
            $kv = $l.Split([char[]]@('='), 2)
            if ($kv.Count -ne 2) { continue }
            $k = $kv[0].Trim(); $v = $kv[1].Trim()
            if ($k -eq 'Profil') { $r.Profile = $v }
            elseif ($k -eq 'Tests') { $r.Selected = @($v.Split(',') | ForEach-Object { $_.Trim() } | Where-Object { $_ }) }
            elseif ($k.StartsWith('Option:')) { $r.Options[$k.Substring(7)] = $v }
        }
        return $r
    } catch { return $null }
}

function Save-BCSettings {
    param([string]$Path, [string]$ProfileId, [object[]]$Checks)
    try {
        $inv = [Globalization.CultureInfo]::InvariantCulture
        $lines = New-Object 'System.Collections.Generic.List[string]'
        $lines.Add('# BuyCheck - zuletzt verwendete Auswahl (diese Datei darf geloescht werden)')
        $lines.Add("Profil=$ProfileId")
        $lines.Add('Tests=' + (@($Checks | Where-Object { $_.Info.Selected } | ForEach-Object { $_.Id }) -join ','))
        foreach ($c in $Checks) {
            foreach ($o in @($c.Info.Options)) { if ($o) { $lines.Add(('Option:{0}:{1}={2}' -f $c.Id, $o.Key, ([double]$o.Value).ToString($inv))) } }
        }
        [IO.File]::WriteAllLines($Path, $lines.ToArray())
        return $true
    } catch {
        Write-BCDebug "Auswahl konnte nicht gespeichert werden: $($_.Exception.Message)"
        return $false
    }
}

function Set-BCSettingsToChecks {
    param($Settings, [object[]]$Checks)
    $inv = [Globalization.CultureInfo]::InvariantCulture
    foreach ($c in $Checks) {
        $c.Info.Selected = (@($Settings.Selected) -contains $c.Id)
        foreach ($o in @($c.Info.Options)) {
            if (-not $o) { continue }
            $key = "$($c.Id):$($o.Key)"
            if ($Settings.Options.ContainsKey($key)) {
                $v = 0.0
                if ([double]::TryParse($Settings.Options[$key], [Globalization.NumberStyles]::Float, $inv, [ref]$v)) {
                    $o.Value = [math]::Max($o.Min, [math]::Min($o.Max, $v))
                }
            }
        }
    }
}
