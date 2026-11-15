# BuyCheck – Grundgerüst: Testregistrierung, Befunde, Datensammler, Hilfsfunktionen
#
# GRUNDSATZ: Alles hier ist LESEND. Es werden keine Einstellungen, Registry-Werte, Dateien oder Treiber
# auf dem geprüften Laptop verändert. Ausgaben (Berichte) landen im Berichtsordner auf dem USB-Stick.

$script:BCChecks = New-Object 'System.Collections.Generic.List[object]'
$script:BCResults = New-Object 'System.Collections.Generic.List[object]'
$script:BCCache = @{}
$script:BCCurrent = $null
$script:BCSummary = [ordered]@{}
$script:BCFacts = @{}
$script:BCCulture = [Globalization.CultureInfo]::GetCultureInfo('de-DE')
$script:BCDebug = New-Object 'System.Collections.Generic.List[string]'

# Diagnoseprotokoll: optionale Abfragen dürfen scheitern (z. B. Dell-Schnittstelle auf einem Lenovo),
# sollen aber nachvollziehbar bleiben. Wird am Ende als diagnose.txt in den Berichtsordner geschrieben.
function Write-BCDebug {
    param([string]$Message)
    $script:BCDebug.Add(('{0:HH:mm:ss} {1}' -f (Get-Date), $Message))
}

$script:BCCategories = [ordered]@{
    'Grunddaten & Sperren'              = 1
    'Prozessor (CPU)'                   = 2
    'Arbeitsspeicher (RAM)'             = 3
    'Datenträger (SSD/HDD)'             = 4
    'Akku & Stromversorgung'            = 5
    'Bildschirm & Grafik'               = 6
    'Eingabe, Anschlüsse & Multimedia'  = 7
    'Netzwerk & Funk'                   = 8
    'System & Protokolle'               = 9
    'Windows'                           = 10
    'Linux'                             = 11
    'Abschluss'                         = 12
}

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
    $info = New-Object BuyCheck.CheckInfo
    $info.Id = $Id
    $info.Category = $Category
    $info.CategoryOrder = if ($script:BCCategories.Contains($Category)) { [int]$script:BCCategories[$Category] } else { 50 }
    $info.Order = $Order
    $info.Title = $Title
    $info.Description = $Description
    $info.BaseSeconds = $Seconds
    $info.Interactive = [bool]$Interactive
    $info.NeedsAcPower = [bool]$NeedsAcPower
    $info.Profiles = [string[]]$Profiles
    foreach ($o in $Options) {
        $spu = 0; if ($o.ContainsKey('SecondsPerUnit')) { $spu = [int]$o.SecondsPerUnit }
        $unit = ''; if ($o.ContainsKey('Unit')) { $unit = [string]$o.Unit }
        [void]$info.AddOption([string]$o.Key, [string]$o.Label, [decimal]$o.Default, [decimal]$o.Min, [decimal]$o.Max, $spu, $unit)
    }
    $script:BCChecks.Add([pscustomobject]@{ Id = $Id; Info = $info; Run = $Run; RunOrder = $RunOrder })
}

# Führt einen Test aus. Fehler im Test brechen nie das ganze Programm ab, sondern werden als "nicht prüfbar" vermerkt.
function Invoke-BCCheck {
    param($Check, [int]$Index, [int]$Total)
    $info = $Check.Info
    $result = [pscustomobject]@{
        Id = $info.Id; Title = $info.Title; Category = $info.Category; CategoryOrder = $info.CategoryOrder; Order = $info.Order
        Status = 'läuft'; Seconds = 0.0; Error = $null
        Findings = (New-Object 'System.Collections.Generic.List[object]')
        Sections = (New-Object 'System.Collections.Generic.List[object]')
    }
    $script:BCResults.Add($result)
    $script:BCCurrent = $result
    Write-Host ''
    Write-Host ('[{0}/{1}] {2}' -f $Index, $Total, $info.Title) -ForegroundColor Cyan
    $opts = @{}
    foreach ($o in $info.Options) { $opts[$o.Key] = [double]$o.Value }
    $sw = [Diagnostics.Stopwatch]::StartNew()
    try {
        $null = & $Check.Run $opts
        $result.Status = 'fertig'
    } catch {
        $result.Status = 'Fehler'
        $result.Error = "$($_.Exception.Message)"
        Write-BCDebug "Test '$($info.Id)' abgebrochen: $($_.Exception.Message) | $($_.ScriptStackTrace -replace '\s+', ' ')"
        Add-BCFinding -Level Fehler -Title 'Test konnte nicht vollständig ausgeführt werden' -Detail ('{0} (Zeile {1})' -f $_.Exception.Message, $_.InvocationInfo.ScriptLineNumber)
    } finally {
        $sw.Stop()
        $result.Seconds = [math]::Round($sw.Elapsed.TotalSeconds, 1)
        Write-Progress -Activity 'BuyCheck' -Completed
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
    $f = [pscustomobject]@{
        Level = $Level; Title = $Title; Detail = $Detail; Advice = $Advice
        CheckId = $script:BCCurrent.Id; CheckTitle = $script:BCCurrent.Title
    }
    $script:BCCurrent.Findings.Add($f)
    Write-BCFindingLine $f
}

function Add-BCTable {
    param([string]$Title, [object[]]$Rows, [string[]]$Columns)
    if (-not $script:BCCurrent) { return }
    $rows = @($Rows | Where-Object { $null -ne $_ })
    if ($rows.Count -eq 0) { return }
    if (-not $Columns) { $Columns = @($rows[0].PSObject.Properties | ForEach-Object { $_.Name }) }
    $script:BCCurrent.Sections.Add([pscustomobject]@{ Type = 'table'; Title = $Title; Rows = $rows; Columns = $Columns })
}

function Add-BCFacts {
    param([string]$Title, [System.Collections.IDictionary]$Data)
    if (-not $script:BCCurrent -or -not $Data -or $Data.Count -eq 0) { return }
    $copy = [ordered]@{}
    foreach ($k in $Data.Keys) {
        $v = $Data[$k]
        if ($null -ne $v -and "$v" -ne '') { $copy[[string]$k] = [string]$v }
    }
    if ($copy.Count -gt 0) { $script:BCCurrent.Sections.Add([pscustomobject]@{ Type = 'facts'; Title = $Title; Data = $copy }) }
}

function Add-BCText {
    param([string]$Title, [string]$Text)
    if (-not $script:BCCurrent -or [string]::IsNullOrWhiteSpace($Text)) { return }
    $script:BCCurrent.Sections.Add([pscustomobject]@{ Type = 'text'; Title = $Title; Text = $Text })
}

function Add-BCChart {
    param([string]$Title, [double[]]$Values, [string]$Unit = '', [double]$Reference = [double]::NaN, [string]$ReferenceLabel = '')
    if (-not $script:BCCurrent -or -not $Values -or $Values.Count -lt 2) { return }
    $script:BCCurrent.Sections.Add([pscustomobject]@{ Type = 'chart'; Title = $Title; Values = $Values; Unit = $Unit; Reference = $Reference; ReferenceLabel = $ReferenceLabel })
}

function Add-BCLink {
    param([string]$Title, [string]$Url, [string]$Text = '')
    if (-not $script:BCCurrent) { return }
    $script:BCCurrent.Sections.Add([pscustomobject]@{ Type = 'link'; Title = $Title; Url = $Url; Text = $Text })
}

# Steckbrief-Zeile für den Berichtskopf
function Set-BCSummary { param([string]$Key, [string]$Value) if ($Value) { $script:BCSummary[$Key] = $Value } }
# Fakten für die Plausibilitätsprüfung (Gerätealter usw.)
function Set-BCFact { param([string]$Key, $Value) if ($null -ne $Value) { $script:BCFacts[$Key] = $Value } }
function Get-BCFact { param([string]$Key) if ($script:BCFacts.ContainsKey($Key)) { return $script:BCFacts[$Key] } return $null }

# ============================================================== Konsolenausgabe
function Write-BCHeader {
    param([string]$Text)
    Write-Host ''
    Write-Host ('=' * 78) -ForegroundColor DarkCyan
    Write-Host ('  ' + $Text) -ForegroundColor Cyan
    Write-Host ('=' * 78) -ForegroundColor DarkCyan
}

function Write-BCFindingLine {
    param($Finding)
    $color = switch ($Finding.Level) { 'OK' { 'Green' } 'Info' { 'Gray' } 'Warnung' { 'Yellow' } 'Kritisch' { 'Red' } default { 'DarkYellow' } }
    Write-Host ('   [{0,-9}] {1}' -f $script:BCLevelLabel[$Finding.Level], $Finding.Title) -ForegroundColor $color
    if ($Finding.Detail) {
        $d = $Finding.Detail
        if ($d.Length -gt 300) { $d = $d.Substring(0, 297) + '…' }
        Write-Host ('                {0}' -f $d) -ForegroundColor DarkGray
    }
}

function Write-BCStep { param([string]$Text) Write-Host ('   … ' + $Text) -ForegroundColor DarkGray }

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
    $base = if ($Binary) { 1024.0 } else { 1000.0 }
    $units = @('B', 'KB', 'MB', 'GB', 'TB', 'PB')
    $i = 0
    while ($b -ge $base -and $i -lt $units.Count - 1) { $b /= $base; $i++ }
    $dec = if ($b -ge 100 -or $i -eq 0) { 0 } elseif ($b -ge 10) { 1 } else { 2 }
    return (Format-BCNum $b $dec) + ' ' + $units[$i]
}

function Format-BCDate {
    param($Date)
    if ($null -eq $Date) { return '–' }
    try { return ([datetime]$Date).ToString('dd.MM.yyyy', $script:BCCulture) } catch { return "$Date" }
}

function Format-BCHours {
    param($Hours)
    if ($null -eq $Hours) { return '–' }
    $h = [double]$Hours
    $years = $h / 8760.0
    return (Format-BCNum $h 0) + ' h (≈ ' + (Format-BCNum ($h / 24.0) 0) + ' Tage Dauerbetrieb' + $(if ($years -ge 1) { ', ' + (Format-BCNum $years 1) + ' Jahre' } else { '' }) + ')'
}

function Get-BCHtml { param([string]$Text) return [System.Net.WebUtility]::HtmlEncode("$Text") }

# ============================================================== Zwischenspeicher und CIM-Abfragen
function Get-BCCached {
    param([string]$Key, [scriptblock]$Factory)
    if (-not $script:BCCache.ContainsKey($Key)) {
        $value = $null
        try { $value = & $Factory } catch { $value = $null; Write-BCDebug "Datensammler '$Key' fehlgeschlagen: $($_.Exception.Message) | $($_.ScriptStackTrace -replace '\s+', ' ')" }
        $script:BCCache[$Key] = $value
    }
    return $script:BCCache[$Key]
}

function Get-BCCim {
    param([Parameter(Mandatory = $true)][string]$ClassName, [string]$Namespace = 'root/cimv2', [string]$Filter)
    try {
        if ($Filter) { return @(Get-CimInstance -Namespace $Namespace -ClassName $ClassName -Filter $Filter -ErrorAction Stop) }
        return @(Get-CimInstance -Namespace $Namespace -ClassName $ClassName -ErrorAction Stop)
    } catch {
        Write-BCDebug "CIM $Namespace/$ClassName$(if ($Filter) { " [$Filter]" }): $($_.Exception.Message)"
        return @()
    }
}

function Get-BCRegValue {
    param([string]$Path, [string]$Name)
    try { return (Get-ItemProperty -Path $Path -Name $Name -ErrorAction Stop).$Name } catch { return $null }
}

function Test-BCPlaceholder {
    param([string]$Value)
    if ([string]::IsNullOrWhiteSpace($Value)) { return $true }
    $v = $Value.Trim().ToLowerInvariant()
    $bad = @('to be filled by o.e.m.', 'to be filled by oem', 'default string', 'system serial number', 'not specified',
        'not applicable', 'none', 'n/a', 'na', '0', '00000000', '0123456789', '123456789', 'chassis serial number',
        'serial', 'no asset tag', 'no asset information', 'asset-1234567890', 'oem', 'system manufacturer', 'system product name',
        'invalid', 'unknown', 'base board serial number', 'type1productconfigid', 'sku')
    return ($bad -contains $v) -or ($v -match '^0+$') -or ($v -match '^(x|f)+$')
}

# ============================================================== Firmware / SMBIOS
function Get-BCSmbios {
    $s = Get-BCCached 'smbios' { , ([BuyCheck.Firmware]::ReadSmbios().ToArray()) }
    return @($s)
}

function Get-BCSmbiosType { param([int]$Type) return @(Get-BCSmbios | Where-Object { $_.Type -eq $Type }) }

function ConvertFrom-BCSmbiosDate {
    param([string]$Text)
    if ([string]::IsNullOrWhiteSpace($Text)) { return $null }
    $formats = @('MM/dd/yyyy', 'MM/dd/yy', 'yyyy-MM-dd', 'dd.MM.yyyy')
    foreach ($f in $formats) {
        $d = [datetime]::MinValue
        if ([datetime]::TryParseExact($Text.Trim(), $f, [Globalization.CultureInfo]::InvariantCulture, [Globalization.DateTimeStyles]::None, [ref]$d)) { return $d }
    }
    return $null
}

# ============================================================== System-Grunddaten
function Get-BCSystem {
    return Get-BCCached 'system' {
        $cs = Get-BCCim Win32_ComputerSystem | Select-Object -First 1
        $csp = Get-BCCim Win32_ComputerSystemProduct | Select-Object -First 1
        $bios = Get-BCCim Win32_BIOS | Select-Object -First 1
        $bb = Get-BCCim Win32_BaseBoard | Select-Object -First 1
        $enc = Get-BCCim Win32_SystemEnclosure | Select-Object -First 1
        $os = Get-BCCim Win32_OperatingSystem | Select-Object -First 1
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
        $serialSmbios = if ($t1) { "$($t1.Str(7))".Trim() } else { '' }
        $biosDate = $null
        if ($t0) { $biosDate = ConvertFrom-BCSmbiosDate $t0.Str(8) }
        if (-not $biosDate -and $bios.ReleaseDate) { $biosDate = [datetime]$bios.ReleaseDate }
        $chassis = @()
        if ($enc -and $enc.ChassisTypes) { $chassis = @($enc.ChassisTypes | ForEach-Object { [int]$_ }) }
        elseif ($t3) { $chassis = @($t3.Byte(5) -band 0x7F) }
        $asset = "$($enc.SMBIOSAssetTag)".Trim()
        if ((Test-BCPlaceholder $asset) -and $t3) { $asset = "$($t3.Str(8))".Trim() }
        if (Test-BCPlaceholder $asset) { $asset = '' }
        $ubr = Get-BCRegValue $cvPath 'UBR'
        $build = "$(Get-BCRegValue $cvPath 'CurrentBuild')"
        [pscustomobject]@{
            Manufacturer        = $manu
            Model               = $model
            DisplayModel        = $display
            ProductVersion      = $version
            Family              = "$($cs.SystemFamily)".Trim()
            Sku                 = "$($cs.SystemSKUNumber)".Trim()
            Serial              = $serial
            SerialSmbios        = $serialSmbios
            Uuid                = "$($csp.UUID)"
            BoardVendor         = "$($bb.Manufacturer)".Trim()
            BoardProduct        = "$($bb.Product)".Trim()
            BoardSerial         = "$($bb.SerialNumber)".Trim()
            BiosVendor          = "$($bios.Manufacturer)".Trim()
            BiosVersion         = "$($bios.SMBIOSBIOSVersion)".Trim()
            BiosDate            = $biosDate
            ChassisTypes        = $chassis
            IsPortable          = [bool](@($chassis | Where-Object { @(8, 9, 10, 11, 14, 30, 31, 32) -contains $_ }).Count -gt 0)
            AssetTag            = $asset
            OsCaption           = "$($os.Caption)".Trim()
            OsVersion           = "$($os.Version)"
            OsBuild             = if ($ubr) { "$build.$ubr" } else { $build }
            OsBuildNumber       = [int]("0$build")
            OsDisplayVersion    = "$(Get-BCRegValue $cvPath 'DisplayVersion')"
            OsEdition           = "$(Get-BCRegValue $cvPath 'EditionID')"
            OsInstallDate       = $os.InstallDate
            OsArchitecture      = "$($os.OSArchitecture)"
            LastBoot            = $os.LastBootUpTime
            RegisteredOwner     = "$(Get-BCRegValue $cvPath 'RegisteredOwner')"
            RegisteredOrg       = "$(Get-BCRegValue $cvPath 'RegisteredOrganization')"
            ComputerName        = "$($cs.Name)"
            PartOfDomain        = [bool]$cs.PartOfDomain
            Domain              = "$($cs.Domain)"
            TotalPhysicalMemory = [int64]$cs.TotalPhysicalMemory
        }
    }
}

# ============================================================== Prozessor
function Get-BCCpu {
    return Get-BCCached 'cpu' {
        $sig = [BuyCheck.CpuNative]::Signature()   # Architektur, Familie, Modell, Stepping, logische CPUs
        $kernel = [BuyCheck.CpuNative]::KernelBrandString()
        $regPath = 'HKLM:\HARDWARE\DESCRIPTION\System\CentralProcessor\0'
        $regName = "$(Get-BCRegValue $regPath 'ProcessorNameString')".Trim()
        $regIdent = "$(Get-BCRegValue $regPath 'Identifier')"
        $regVendor = "$(Get-BCRegValue $regPath 'VendorIdentifier')"
        $envIdent = "$(Get-BCRegValue 'HKLM:\SYSTEM\CurrentControlSet\Control\Session Manager\Environment' 'PROCESSOR_IDENTIFIER')"
        $wmi = Get-BCCim Win32_Processor | Select-Object -First 1
        $topo = [BuyCheck.CpuNative]::Topology()
        $t4 = Get-BCSmbiosType 4 | Select-Object -First 1
        $family = [int]$sig[1]; $model = [int]$sig[2]; $stepping = [int]$sig[3]; $arch = [int]$sig[0]

        $vendor = 'Unbekannt'
        if ($arch -eq 12 -or $arch -eq 5) {
            $vendor = if ("$($wmi.Manufacturer)$kernel" -match 'Qualcomm|Snapdragon') { 'Qualcomm' } else { 'ARM' }
        } elseif ($family -eq 6 -or $family -ge 18) {
            $vendor = 'Intel'
            if ("$kernel $($wmi.Manufacturer)" -match 'Zhaoxin|Centaur|VIA') { $vendor = 'Andere' }
        } elseif ($family -ge 0x10 -and $family -le 0x1A) {
            $vendor = if ($family -eq 0x18 -and "$kernel" -match 'Hygon') { 'Andere' } else { 'AMD' }
        } elseif ($family -eq 15) {
            $vendor = if ("$($wmi.Manufacturer)" -match 'AMD') { 'AMD' } else { 'Intel' }
        }

        $smbName = $null; $smbSig = $null; $smbCores = $null; $smbThreads = $null; $smbMaxMHz = $null
        if ($t4) {
            $smbName = $t4.Str(0x10)
            $eax = $t4.Dword(0x08)
            if ($eax -gt 0) {
                $f = ($eax -shr 8) -band 0xF; $m = ($eax -shr 4) -band 0xF; $s = $eax -band 0xF
                $ef = ($eax -shr 20) -band 0xFF; $em = ($eax -shr 16) -band 0xF
                $df = if ($f -eq 0xF) { $f + $ef } else { $f }
                $dm = if ($f -eq 6 -or $f -eq 0xF) { ($em -shl 4) + $m } else { $m }
                $smbSig = @($df, $dm, $s)
            }
            $smbCores = $t4.Byte(0x23); $smbThreads = $t4.Byte(0x25); $smbMaxMHz = $t4.Word(0x14)
        }
        [pscustomobject]@{
            Architecture = $arch; Family = $family; Model = $model; Stepping = $stepping; LogicalCount = [int]$sig[4]
            Vendor = $vendor
            KernelName = $kernel; RegistryName = $regName; WmiName = "$($wmi.Name)".Trim(); SmbiosName = $smbName
            RegistryIdentifier = $regIdent; RegistryVendor = $regVendor; EnvIdentifier = $envIdent
            SmbiosSignature = $smbSig; SmbiosCores = $smbCores; SmbiosThreads = $smbThreads; SmbiosMaxMHz = $smbMaxMHz
            Cores = if ($topo) { $topo.Cores } else { [int]$wmi.NumberOfCores }
            Threads = if ($topo) { $topo.LogicalProcessors } else { [int]$wmi.NumberOfLogicalProcessors }
            L2Bytes = if ($topo) { $topo.L2Bytes } else { [int64]$wmi.L2CacheSize * 1024 }
            L3Bytes = if ($topo) { $topo.L3Bytes } else { [int64]$wmi.L3CacheSize * 1024 }
            MaxClockMHz = [int]$wmi.MaxClockSpeed
            WmiManufacturer = "$($wmi.Manufacturer)"
            BestName = if ($kernel) { $kernel } elseif ($smbName) { $smbName } else { $regName }
        }
    }
}

# ============================================================== Geräte (PnP)
function Get-BCPnp {
    $all = Get-BCCached 'pnp' { Get-BCCim Win32_PnPEntity }
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

function Get-BCPnpProperty {
    param([string]$InstanceId, [string]$Key)
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
    if ([string]::IsNullOrWhiteSpace($PnpId)) { return $null }
    $data = @(Get-BCCached 'smartData' { Get-BCCim -Namespace 'root/wmi' -ClassName MSStorageDriver_FailurePredictData })
    $thr = @(Get-BCCached 'smartThr' { Get-BCCim -Namespace 'root/wmi' -ClassName MSStorageDriver_FailurePredictThresholds })
    $sts = @(Get-BCCached 'smartStatus' { Get-BCCim -Namespace 'root/wmi' -ClassName MSStorageDriver_FailurePredictStatus })
    $key = $PnpId.ToUpperInvariant()
    $d = $data | Where-Object { "$($_.InstanceName)".ToUpperInvariant().StartsWith($key) } | Select-Object -First 1
    if (-not $d) { return $null }
    $t = $thr | Where-Object { "$($_.InstanceName)".ToUpperInvariant().StartsWith($key) } | Select-Object -First 1
    $s = $sts | Where-Object { "$($_.InstanceName)".ToUpperInvariant().StartsWith($key) } | Select-Object -First 1
    $vs = [byte[]]$d.VendorSpecific
    $ts = if ($t) { [byte[]]$t.VendorSpecific } else { $null }
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
        $name = if ($script:BCSmartNames.ContainsKey($id)) { $script:BCSmartNames[$id] } else { 'Herstellerspezifisch' }
        $attrs.Add([pscustomobject]@{
                Id = $id; Name = $name; Current = [int]$vs[$o + 3]; Worst = [int]$vs[$o + 4]; Threshold = $threshold
                Raw = $raw; Raw32 = [uint64]($raw -band 0xFFFFFFFF); RawLow = [int]($raw -band 0xFF)
            })
    }
    return [pscustomobject]@{ Attributes = $attrs.ToArray(); PredictFailure = if ($s) { [bool]$s.PredictFailure } else { $null } }
}

function Get-BCDisks {
    $disks = Get-BCCached 'disks' {
        $phys = @()
        try { $phys = @(Get-PhysicalDisk -ErrorAction Stop) } catch { Write-BCDebug "Get-PhysicalDisk: $($_.Exception.Message)" }
        $dd = Get-BCCim Win32_DiskDrive
        $result = New-Object 'System.Collections.Generic.List[object]'
        $numbers = @()
        if ($phys.Count -gt 0) { $numbers = @($phys | ForEach-Object { [int]$_.DeviceId }) }
        else { $numbers = @($dd | ForEach-Object { [int]$_.Index }) }
        foreach ($num in ($numbers | Sort-Object -Unique)) {
            $p = $phys | Where-Object { [int]$_.DeviceId -eq $num } | Select-Object -First 1
            $d = $dd | Where-Object { [int]$_.Index -eq $num } | Select-Object -First 1
            $disk = $null
            try { $disk = Get-Disk -Number $num -ErrorAction Stop } catch { Write-BCDebug "Get-Disk $($num): $($_.Exception.Message)" }
            $bus = if ($p) { ConvertTo-BCEnumText $p.BusType $script:BCBusTypes } elseif ($d) { "$($d.InterfaceType)" } else { 'Unknown' }
            $media = if ($p) { ConvertTo-BCEnumText $p.MediaType $script:BCMediaTypes } else { 'Unspecified' }
            $model = if ($p) { "$($p.FriendlyName)".Trim() } else { "$($d.Model)".Trim() }
            $isUsb = ($bus -eq 'USB') -or ($d -and "$($d.InterfaceType)" -eq 'USB') -or ($d -and "$($d.PNPDeviceID)" -match '^USBSTOR')
            $isVirtual = $bus -match 'Virtual|iSCSI|Storage Spaces'
            $o = [ordered]@{
                Number = $num; Model = $model; Serial = if ($p) { "$($p.SerialNumber)".Trim() } else { "$($d.SerialNumber)".Trim() }
                Firmware = if ($p) { "$($p.FirmwareVersion)".Trim() } else { "$($d.FirmwareRevision)".Trim() }
                Bus = $bus; Media = $media
                SizeBytes = if ($p -and $p.Size) { [int64]$p.Size } elseif ($d) { [int64]$d.Size } else { 0 }
                Health = if ($p) { ConvertTo-BCEnumText $p.HealthStatus @{ 0 = 'Healthy'; 1 = 'Warning'; 2 = 'Unhealthy'; 5 = 'Unknown' } } else { "$($d.Status)" }
                IsUsb = [bool]$isUsb; IsVirtual = [bool]$isVirtual; IsBoot = [bool]($disk -and $disk.IsBoot); IsSystem = [bool]($disk -and $disk.IsSystem)
                PnpId = if ($d) { "$($d.PNPDeviceID)" } else { '' }
                Nvme = $null; NvmeError = $null; Identify = $null; Smart = $null; Reliability = $null
                PciInstance = $null; PciVen = $null; PciDev = $null; LinkSpeed = $null; LinkWidth = $null; MaxLinkSpeed = $null; MaxLinkWidth = $null
                IsSsd = $false; IsNvme = $false
            }
            $o.IsNvme = ($bus -eq 'NVMe') -or ($model -match 'NVMe')
            $o.IsSsd = ($media -eq 'SSD') -or $o.IsNvme
            if (-not $isUsb -and -not $isVirtual) {
                # NVMe direkt abfragen (auch bei RAID/SCSI-Bus, z. B. hinter Intel RST – klappt nicht immer)
                if ($o.IsNvme -or $bus -match 'RAID|SCSI|Unknown') {
                    $err = $null
                    $h = [BuyCheck.DiskIo]::NvmeHealth($num, [ref]$err)
                    if ($h) {
                        $o.Nvme = $h; $o.IsNvme = $true; $o.IsSsd = $true
                        $err2 = $null
                        $o.Identify = [BuyCheck.DiskIo]::NvmeIdentify($num, [ref]$err2)
                    } else { $o.NvmeError = $err; Write-BCDebug "NVMe-Abfrage Datenträger $($num): $err" }
                }
                if (-not $o.Nvme) { $o.Smart = Get-BCAtaSmart -PnpId $o.PnpId }
                if ($p) {
                    try { $o.Reliability = $p | Get-StorageReliabilityCounter -ErrorAction Stop }
                    catch { Write-BCDebug "Get-StorageReliabilityCounter $($num): $($_.Exception.Message)" }
                }
                # PCIe-Anbindung (Elterngerät des Datenträgers)
                if ($o.PnpId) {
                    $parent = Get-BCPnpProperty -InstanceId $o.PnpId -Key 'DEVPKEY_Device_Parent'
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
            $result.Add([pscustomobject]$o)
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
            '^LI|^LION' { return 'Lithium-Ionen' }
            '^LIP|^LiP' { return 'Lithium-Polymer' }
            '^NIMH|^NiMH' { return 'Nickel-Metallhydrid' }
            default { return $s.Trim() }
        }
    } catch { return "$Value" }
}

function Get-BCBattery {
    return Get-BCCached 'battery' {
        $static = @(Get-BCCim -Namespace 'root/wmi' -ClassName BatteryStaticData)
        $full = @(Get-BCCim -Namespace 'root/wmi' -ClassName BatteryFullChargedCapacity)
        $cyc = @(Get-BCCim -Namespace 'root/wmi' -ClassName BatteryCycleCount)
        $w32 = @(Get-BCCim Win32_Battery)
        $list = New-Object 'System.Collections.Generic.List[object]'
        foreach ($s in $static) {
            $inst = "$($s.InstanceName)"
            $f = $full | Where-Object { "$($_.InstanceName)" -eq $inst } | Select-Object -First 1
            $c = $cyc | Where-Object { "$($_.InstanceName)" -eq $inst } | Select-Object -First 1
            $mdate = $null
            try { if ($s.ManufactureDate) { $mdate = [datetime]$s.ManufactureDate } } catch { }
            $caps = 0; try { $caps = [int64]$s.Capabilities } catch { }
            $list.Add([pscustomobject]@{
                    Instance = $inst; Name = "$($s.DeviceName)".Trim(); Manufacturer = "$($s.ManufactureName)".Trim()
                    Serial = "$($s.SerialNumber)".Trim(); Chemistry = ConvertFrom-BCChemistry $s.Chemistry
                    DesignMWh = [int64]$s.DesignedCapacity; FullMWh = if ($f) { [int64]$f.FullChargedCapacity } else { $null }
                    Cycles = if ($c) { [int64]$c.CycleCount } else { $null }; ManufactureDate = $mdate
                    Relative = (($caps -band 0x40000000) -ne 0)
                })
        }
        [pscustomobject]@{ Batteries = $list.ToArray(); Win32 = $w32; Present = ($static.Count -gt 0 -or $w32.Count -gt 0) }
    }
}

# Aktueller Zustand (nicht zwischengespeichert)
function Get-BCBatteryStatus {
    $st = Get-BCCim -Namespace 'root/wmi' -ClassName BatteryStatus | Select-Object -First 1
    $w = Get-BCCim Win32_Battery | Select-Object -First 1
    $pct = $null
    if ($w -and $null -ne $w.EstimatedChargeRemaining) { $pct = [int]$w.EstimatedChargeRemaining }
    $online = $null
    if ($st) { $online = [bool]$st.PowerOnline } else { try { $online = [BuyCheck.PowerWaitDialog]::IsOnline() } catch { } }
    [pscustomobject]@{
        Percent = $pct; RemainingMWh = if ($st) { [int64]$st.RemainingCapacity } else { $null }
        VoltageMV = if ($st) { [int64]$st.Voltage } else { $null }
        ChargeRateMW = if ($st) { [int64]$st.ChargeRate } else { $null }
        DischargeRateMW = if ($st) { [int64]$st.DischargeRate } else { $null }
        PowerOnline = $online; Charging = if ($st) { [bool]$st.Charging } else { $null }
        Discharging = if ($st) { [bool]$st.Discharging } else { $null }
        Time = Get-Date
    }
}

# ============================================================== Bildschirme
function Get-BCMonitors {
    $mons = Get-BCCached 'monitors' {
        $ids = @(Get-BCCim -Namespace 'root/wmi' -ClassName WmiMonitorID)
        $conn = @(Get-BCCim -Namespace 'root/wmi' -ClassName WmiMonitorConnectionParams)
        $basic = @(Get-BCCim -Namespace 'root/wmi' -ClassName WmiMonitorBasicDisplayParams)
        $list = New-Object 'System.Collections.Generic.List[object]'
        foreach ($m in $ids) {
            $inst = "$($m.InstanceName)"
            $c = $conn | Where-Object { "$($_.InstanceName)" -eq $inst } | Select-Object -First 1
            $b = $basic | Where-Object { "$($_.InstanceName)" -eq $inst } | Select-Object -First 1
            $tech = if ($c) { [int64]$c.VideoOutputTechnology } else { $null }
            $internal = $false
            if ($null -ne $tech) { $internal = @(6, 11, 13, 2147483648, -2147483648) -contains $tech }
            $edid = $null
            $regPath = 'HKLM:\SYSTEM\CurrentControlSet\Enum\' + ($inst -replace '_\d+$', '') + '\Device Parameters'
            $raw = Get-BCRegValue $regPath 'EDID'
            if ($raw) { $edid = [BuyCheck.EdidInfo]::Parse([byte[]]$raw) }
            $toStr = { param($arr) if (-not $arr) { return '' } (-join (@($arr) | Where-Object { $_ -gt 0 } | ForEach-Object { [char][int]$_ })).Trim() }
            $list.Add([pscustomobject]@{
                    Instance = $inst; Internal = $internal; Technology = $tech
                    Manufacturer = & $toStr $m.ManufacturerName; ProductCode = & $toStr $m.ProductCodeID
                    Serial = & $toStr $m.SerialNumberID; FriendlyName = & $toStr $m.UserFriendlyName
                    Year = [int]$m.YearOfManufacture; Week = [int]$m.WeekOfManufacture
                    WidthCm = if ($b) { [int]$b.MaxHorizontalImageSize } else { $null }
                    HeightCm = if ($b) { [int]$b.MaxVerticalImageSize } else { $null }
                    Edid = $edid
                })
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

# ============================================================== Eingaben über Dialoge (mit Konsolen-Notlösung)
function Show-BCInfo {
    param([string]$Title, [string]$Message, [string]$OkText = 'Weiter', [string]$CancelText = 'Überspringen')
    try { return [BuyCheck.Ask]::Info($Title, $Message, $OkText, $CancelText) }
    catch {
        Write-Host $Message -ForegroundColor White
        $a = Read-Host "[$OkText = Enter, $CancelText = s]"
        return ($a -ne 's')
    }
}

function Show-BCChoice {
    param([string]$Title, [string]$Question, [string[]]$Options, [switch]$Comment)
    try { return [BuyCheck.Ask]::Choice($Title, $Question, $Options, [bool]$Comment) }
    catch {
        Write-Host $Question -ForegroundColor White
        for ($i = 0; $i -lt $Options.Count; $i++) { Write-Host ("  {0}) {1}" -f ($i + 1), $Options[$i]) }
        $n = 0
        do { $n = [int](Read-Host 'Nummer') } while ($n -lt 1 -or $n -gt $Options.Count)
        $r = New-Object BuyCheck.AskResult
        $r.Cancelled = $false; $r.Choice = $n - 1; $r.ChoiceText = $Options[$n - 1]
        if ($Comment) { $r.Comment = Read-Host 'Anmerkung (optional)' }
        return $r
    }
}

function Show-BCMulti {
    param([string]$Title, [string]$Question, [string[]]$Options, [switch]$Comment)
    try { return [BuyCheck.Ask]::Multi($Title, $Question, $Options, [bool]$Comment) }
    catch {
        Write-Host $Question -ForegroundColor White
        for ($i = 0; $i -lt $Options.Count; $i++) { Write-Host ("  {0}) {1}" -f ($i + 1), $Options[$i]) }
        $sel = Read-Host 'Nummern (durch Komma getrennt, leer = keine)'
        $r = New-Object BuyCheck.AskResult
        $r.Cancelled = $false
        $r.Checked = New-Object bool[] $Options.Count
        foreach ($t in ($sel -split '[,; ]+' | Where-Object { $_ -match '^\d+$' })) {
            $i = [int]$t - 1
            if ($i -ge 0 -and $i -lt $Options.Count) { $r.Checked[$i] = $true; $r.CheckedTexts.Add($Options[$i]) }
        }
        if ($Comment) { $r.Comment = Read-Host 'Anmerkung (optional)' }
        return $r
    }
}

function Show-BCTestForm {
    param($Form)
    try {
        [void]$Form.ShowDialog()
        return $Form.Result
    } finally { $Form.Dispose() }
}

# Ergebnis eines interaktiven Tests in Befunde umsetzen
function Add-BCInteractiveResult {
    param($Result, [string]$OkTitle, [string]$ProblemTitle, [ValidateSet('Warnung', 'Kritisch')][string]$ProblemLevel = 'Warnung', [string]$Advice = '')
    $details = @($Result.Details)
    switch ($Result.Verdict) {
        'OK' { Add-BCFinding -Level OK -Title $OkTitle -Detail (($details + @($Result.Comment)) -join ' · ').Trim(' ·') }
        'Problem' {
            $txt = @($Result.Problems) + @($Result.Comment) | Where-Object { $_ }
            Add-BCFinding -Level $ProblemLevel -Title $ProblemTitle -Detail ($txt -join ' · ') -Advice $Advice
            if ($details.Count -gt 0) { Add-BCText -Title 'Einzelheiten' -Text ($details -join "`n") }
        }
        default { Add-BCFinding -Level Info -Title 'Test übersprungen' -Detail $Result.Comment }
    }
    if ($details.Count -gt 0 -and $Result.Verdict -eq 'OK' -and $details.Count -gt 2) { Add-BCText -Title 'Protokoll' -Text ($details -join "`n") }
}

# ============================================================== Hintergrund-Tests überwachen (mit ESC-Abbruch)
function Test-BCEscape {
    try {
        while ([Console]::KeyAvailable) {
            $k = [Console]::ReadKey($true)
            if ($k.Key -eq [ConsoleKey]::Escape) { return $true }
        }
    } catch { }
    return $false
}

function Wait-BCWorkload {
    param(
        [Parameter(Mandatory = $true)]$Workload,
        [Parameter(Mandatory = $true)][scriptblock]$Status,
        [string]$Activity = 'Test läuft',
        [int]$IntervalMs = 500,
        [scriptblock]$Percent = $null
    )
    $cancelled = $false
    while (-not $Workload.Done) {
        Start-Sleep -Milliseconds $IntervalMs
        $text = & $Status
        $pct = -1
        if ($Percent) { try { $pct = [int][math]::Max(0, [math]::Min(100, (& $Percent))) } catch { $pct = -1 } }
        if ($pct -ge 0) { Write-Progress -Activity "$Activity  (ESC = abbrechen)" -Status $text -PercentComplete $pct }
        else { Write-Progress -Activity "$Activity  (ESC = abbrechen)" -Status $text }
        if (-not $cancelled -and (Test-BCEscape)) {
            $cancelled = $true
            Write-Host '   Abbruch angefordert …' -ForegroundColor Yellow
            try { $Workload.Cancel() } catch { }
        }
    }
    Write-Progress -Activity $Activity -Completed
    return $cancelled
}

# Leistungs- und Temperaturmessung (für Belastungstests)
function Get-BCPerfSample {
    $p = Get-BCCim -ClassName Win32_PerfFormattedData_Counters_ProcessorInformation -Filter "Name='_Total'" | Select-Object -First 1
    $tz = @(Get-BCCim -ClassName Win32_PerfFormattedData_Counters_ThermalZoneInformation)
    $acpi = @(Get-BCCim -Namespace 'root/wmi' -ClassName MSAcpi_ThermalZoneTemperature)
    $temps = New-Object 'System.Collections.Generic.List[double]'
    $passive = New-Object 'System.Collections.Generic.List[double]'
    $throttle = 0
    foreach ($z in $tz) {
        $t = $null
        if ($z.HighPrecisionTemperature -and [double]$z.HighPrecisionTemperature -gt 0) { $t = [double]$z.HighPrecisionTemperature / 10.0 - 273.15 }
        elseif ($z.Temperature -and [double]$z.Temperature -gt 0) { $t = [double]$z.Temperature - 273.15 }
        if ($null -ne $t -and $t -gt 0 -and $t -lt 150) { $temps.Add($t) }
        if ($null -ne $z.PercentPassiveLimit) { $passive.Add([double]$z.PercentPassiveLimit) }
        if ($z.ThrottleReasons) { $throttle = $throttle -bor [int]$z.ThrottleReasons }
    }
    foreach ($z in $acpi) {
        if ($z.CurrentTemperature -and [double]$z.CurrentTemperature -gt 0) {
            $t = [double]$z.CurrentTemperature / 10.0 - 273.15
            if ($t -gt 0 -and $t -lt 150) { $temps.Add($t) }
        }
    }
    [pscustomobject]@{
        Time = Get-Date
        Perf = if ($p -and $null -ne $p.PercentProcessorPerformance) { [double]$p.PercentProcessorPerformance } else { $null }
        Utility = if ($p -and $null -ne $p.PercentProcessorUtility) { [double]$p.PercentProcessorUtility } else { $null }
        BaseMHz = if ($p -and $p.ProcessorFrequency) { [double]$p.ProcessorFrequency } else { $null }
        LimitFlags = if ($p -and $null -ne $p.PerformanceLimitFlags) { [int]$p.PerformanceLimitFlags } else { $null }
        TempMax = if ($temps.Count -gt 0) { ($temps | Measure-Object -Maximum).Maximum } else { $null }
        PassiveMin = if ($passive.Count -gt 0) { ($passive | Measure-Object -Minimum).Minimum } else { $null }
        Throttle = $throttle
    }
}

# ============================================================== Einstellungen (letzte Auswahl, auf dem USB-Stick)
function Read-BCSettings {
    param([string]$Path)
    try {
        if (Test-Path -LiteralPath $Path) { return (Get-Content -LiteralPath $Path -Raw -Encoding UTF8 | ConvertFrom-Json) }
    } catch { }
    return $null
}

function Save-BCSettings {
    param([string]$Path, [string]$ProfileId, [object[]]$Checks)
    try {
        $sel = @($Checks | Where-Object { $_.Info.Selected } | ForEach-Object { $_.Id })
        $opts = @{}
        foreach ($c in $Checks) {
            if ($c.Info.Options.Count -gt 0) {
                $h = @{}
                foreach ($o in $c.Info.Options) { $h[$o.Key] = [double]$o.Value }
                $opts[$c.Id] = $h
            }
        }
        $obj = [ordered]@{ Version = 1; Profile = $ProfileId; Selected = $sel; Options = $opts; Saved = (Get-Date).ToString('s') }
        $json = $obj | ConvertTo-Json -Depth 5
        [IO.File]::WriteAllText($Path, $json, (New-Object Text.UTF8Encoding($false)))
    } catch { Write-Host "   Auswahl konnte nicht gespeichert werden: $($_.Exception.Message)" -ForegroundColor DarkYellow }
}
