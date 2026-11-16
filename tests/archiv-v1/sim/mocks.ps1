# ------------------------------------------------------------------ Simulierte Windows-Schnittstellen
$global:SimReg = @{
    'HKLM:\HARDWARE\DESCRIPTION\System\CentralProcessor\0' = @{ ProcessorNameString = 'Intel(R) Core(TM) i7-8650U CPU @ 1.90GHz'; Identifier = 'Intel64 Family 6 Model 142 Stepping 10'; VendorIdentifier = 'GenuineIntel'; 'Platform Specific Field 1' = 16 }
    'HKLM:\SYSTEM\CurrentControlSet\Control\Session Manager\Environment' = @{ PROCESSOR_IDENTIFIER = 'Intel64 Family 6 Model 142 Stepping 10, GenuineIntel' }
    'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion' = @{ UBR = 4317; CurrentBuild = '22631'; DisplayVersion = '23H2'; EditionID = 'Professional'; RegisteredOwner = 'Max'; RegisteredOrganization = '' }
    'HKLM:\SOFTWARE\Microsoft\Provisioning\Diagnostics\Autopilot' = @{ CloudAssignedTenantDomain = 'contoso.onmicrosoft.com'; CloudAssignedTenantId = '1234' }
    'HKLM:\SYSTEM\CurrentControlSet\Enum\DISPLAY\BOE0812\4&2e8a0d9b&0&UID8388688\Device Parameters' = @{ EDID = $null }
    'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Run' = @{ SecurityHealth = '%windir%\system32\SecurityHealthSystray.exe' }
    'HKLM:\SYSTEM\CurrentControlSet\Control\Class\{4d36e968-e325-11ce-bfc1-08002be10318}\0000' = @{ MatchingDeviceId = 'pci\ven_8086&dev_5917'; 'HardwareInformation.qwMemorySize' = [int64]1073741824 }
}
function New-FakeEdid {
    $e = New-Object byte[] 128
    $h = 0x00, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0x00; for ($i = 0; $i -lt 8; $i++) { $e[$i] = $h[$i] }
    $m = ((2 -shl 10) -bor (15 -shl 5) -bor 5)          # B=2, O=15, E=5
    $e[8] = ($m -shr 8) -band 0xFF; $e[9] = $m -band 0xFF; $e[10] = 0x12; $e[11] = 0x08
    $e[16] = 12; $e[17] = 2021 - 1990; $e[18] = 1; $e[19] = 4; $e[20] = 0x95; $e[21] = 31; $e[22] = 17
    $o = 54; $pc = 13865; $e[$o] = $pc -band 0xFF; $e[$o + 1] = $pc -shr 8
    $e[$o + 2] = 1920 -band 0xFF; $e[$o + 3] = 160; $e[$o + 4] = ((1920 -shr 8) -shl 4) -bor 0
    $e[$o + 5] = 1080 -band 0xFF; $e[$o + 6] = 31; $e[$o + 7] = ((1080 -shr 8) -shl 4) -bor 0
    $e[$o + 12] = 309 -band 0xFF; $e[$o + 13] = 174 -band 0xFF; $e[$o + 14] = ((309 -shr 8) -shl 4) -bor (174 -shr 8)
    foreach ($pair in @(@(72, 'BOE CQ'), @(90, 'NV140FHM-N4B'))) {
        $p = $pair[0]; $e[$p + 3] = 0xFE; $t = [Text.Encoding]::ASCII.GetBytes($pair[1] + "`n")
        for ($i = 0; $i -lt 13; $i++) { $e[$p + 5 + $i] = if ($i -lt $t.Length) { $t[$i] } else { 0x20 } }
    }
    $e[108 + 3] = 0x10
    return , $e
}
$global:SimReg['HKLM:\SYSTEM\CurrentControlSet\Enum\DISPLAY\BOE0812\4&2e8a0d9b&0&UID8388688\Device Parameters'].EDID = (New-FakeEdid)

function Get-ItemProperty {
    [CmdletBinding()] param([Parameter(Position = 0)][string]$Path, [Parameter(Position = 1)][string]$Name, [string]$LiteralPath)
    $p = if ($Path) { $Path } else { $LiteralPath }
    if ($p -match '^(HKLM:|HKCU:|Registry::)') {
        if ($global:SimReg.ContainsKey($p)) {
            $h = $global:SimReg[$p]
            if ($Name -and -not $h.ContainsKey($Name)) { throw "Eigenschaft $Name fehlt" }
            return [pscustomobject]$h
        }
        throw "Registry-Pfad $p fehlt"
    }
    Microsoft.PowerShell.Management\Get-ItemProperty @PSBoundParameters
}
function Test-Path {
    [CmdletBinding()] param([Parameter(Position = 0)][string]$Path, [string]$LiteralPath, [string]$PathType)
    $p = if ($Path) { $Path } else { $LiteralPath }
    if ($p -match '^(HKLM:|HKCU:|Registry::)') { return $global:SimReg.ContainsKey($p) }
    Microsoft.PowerShell.Management\Test-Path @PSBoundParameters
}
function Get-ChildItem {
    [CmdletBinding()] param([Parameter(Position = 0)][string]$Path, [string]$LiteralPath, [string]$Filter, [switch]$Recurse, [switch]$File, [switch]$Directory, [switch]$Force)
    $p = if ($Path) { $Path } else { $LiteralPath }
    if ($p -match '^(HKLM:|HKCU:|Registry::)') {
        $prefix = $p.TrimEnd('\') + '\'
        return @($global:SimReg.Keys | Where-Object { $_.StartsWith($prefix) -and ($_.Substring($prefix.Length) -notmatch '\\') } | ForEach-Object { [pscustomobject]@{ PSPath = $_; PSChildName = $_.Substring($prefix.Length) } })
    }
    Microsoft.PowerShell.Management\Get-ChildItem @PSBoundParameters
}

$global:SimPnp = @(
    [pscustomobject]@{ Name = 'Standard PS/2-Tastatur'; PNPClass = 'Keyboard'; PNPDeviceID = 'ACPI\LEN0071\4&1'; ConfigManagerErrorCode = 0 }
    [pscustomobject]@{ Name = 'Synaptics Pointing Device'; PNPClass = 'Mouse'; PNPDeviceID = 'ACPI\LEN2054\4&2'; ConfigManagerErrorCode = 0 }
    [pscustomobject]@{ Name = 'Integrated Camera'; PNPClass = 'Camera'; PNPDeviceID = 'USB\VID_04F2&PID_B604&MI_00\6&1'; ConfigManagerErrorCode = 0 }
    [pscustomobject]@{ Name = 'Realtek High Definition Audio'; PNPClass = 'MEDIA'; PNPDeviceID = 'HDAUDIO\FUNC_01&VEN_10EC&DEV_0257'; ConfigManagerErrorCode = 0 }
    [pscustomobject]@{ Name = 'Intel(R) Wireless Bluetooth(R)'; PNPClass = 'Bluetooth'; PNPDeviceID = 'USB\VID_8087&PID_0026\5&1'; ConfigManagerErrorCode = 0 }
    [pscustomobject]@{ Name = 'Intel(R) USB 3.1 eXtensible Host Controller – 1.10 (Microsoft)'; PNPClass = 'USB'; PNPDeviceID = 'PCI\VEN_8086&DEV_9DED'; ConfigManagerErrorCode = 0 }
    [pscustomobject]@{ Name = 'Synaptics FM3297 Fingerprint Reader'; PNPClass = 'Biometric'; PNPDeviceID = 'USB\VID_06CB&PID_009A\1'; ConfigManagerErrorCode = 22 }
    [pscustomobject]@{ Name = 'Intel(R) Active Management Technology - SOL (COM3)'; PNPClass = 'Ports'; PNPDeviceID = 'PCI\VEN_8086&DEV_9DE3'; ConfigManagerErrorCode = 0 }
    [pscustomobject]@{ Name = 'Unbekanntes Gerät'; PNPClass = ''; PNPDeviceID = 'ACPI\INT33A1\0'; ConfigManagerErrorCode = 28 }
)
$global:PerfTick = 0
function Get-CimInstance {
    [CmdletBinding()] param([string]$Namespace = 'root/cimv2', [Parameter(Position = 0)][string]$ClassName, [string]$Filter)
    switch ($ClassName) {
        'Win32_ComputerSystem' { [pscustomobject]@{ Manufacturer = 'LENOVO'; Model = '20L5S00G00'; SystemFamily = 'ThinkPad T480'; SystemSKUNumber = 'LENOVO_MT_20L5_BU_Think_FM_ThinkPad T480'; Name = 'DESKTOP-ABC'; PartOfDomain = $false; Domain = 'WORKGROUP'; TotalPhysicalMemory = 17000000000 } }
        'Win32_ComputerSystemProduct' { [pscustomobject]@{ Version = 'ThinkPad T480'; UUID = '1111-2222'; IdentifyingNumber = 'PF1ABCDE' } }
        'Win32_BIOS' { [pscustomobject]@{ SerialNumber = 'PF1ABCDE'; SMBIOSBIOSVersion = 'N2IET98W (1.76 )'; Manufacturer = 'LENOVO'; ReleaseDate = [datetime]'2024-05-12' } }
        'Win32_BaseBoard' { [pscustomobject]@{ Manufacturer = 'LENOVO'; Product = '20L5S00G00'; SerialNumber = 'L1HF81J01ZZ' } }
        'Win32_SystemEnclosure' { [pscustomobject]@{ ChassisTypes = @(10); SMBIOSAssetTag = 'No Asset Information' } }
        'Win32_OperatingSystem' { [pscustomobject]@{ Caption = 'Microsoft Windows 11 Pro'; Version = '10.0.22631'; InstallDate = [datetime]'2024-02-10'; OSArchitecture = '64-Bit'; LastBootUpTime = (Get-Date).AddHours(-2) } }
        'Win32_Processor' { [pscustomobject]@{ Name = 'Intel(R) Core(TM) i7-8650U CPU @ 1.90GHz'; Manufacturer = 'GenuineIntel'; NumberOfCores = 4; NumberOfLogicalProcessors = 8; MaxClockSpeed = 1700; L2CacheSize = 1024; L3CacheSize = 6144 } }
        'Win32_PnPEntity' { $global:SimPnp }
        'Win32_DiskDrive' {
            [pscustomobject]@{ Index = 0; PNPDeviceID = 'SCSI\DISK&VEN_NVME&PROD_SAMSUNG_SSD_980\5&1A2B3C4D&0&000000'; InterfaceType = 'SCSI'; Model = 'Samsung SSD 980 PRO 1TB'; Size = 1000202273280 }
            [pscustomobject]@{ Index = 1; PNPDeviceID = 'USBSTOR\DISK&VEN_SANDISK&PROD_ULTRA\4C53'; InterfaceType = 'USB'; Model = 'SanDisk Ultra USB Device'; Size = 32000000000 }
        }
        'Win32_VideoController' { [pscustomobject]@{ Name = 'Intel(R) UHD Graphics 620'; PNPDeviceID = 'PCI\VEN_8086&DEV_5917&SUBSYS_225D17AA&REV_07\3&1'; DriverVersion = '31.0.101.2111'; DriverDate = [datetime]'2023-01-01'; Status = 'OK'; ConfigManagerErrorCode = 0; CurrentHorizontalResolution = 1920; CurrentVerticalResolution = 1080; CurrentRefreshRate = 60 } }
        'Win32_Battery' { [pscustomobject]@{ EstimatedChargeRemaining = 80 } }
        'BatteryStaticData' { [pscustomobject]@{ InstanceName = 'ACPI\PNP0C0A\1_0'; DeviceName = '01AV489'; ManufactureName = 'SMP'; SerialNumber = '1234'; Chemistry = [uint32]0x4E4F494C; DesignedCapacity = 57000; Capabilities = 0; ManufactureDate = $null } }
        'BatteryFullChargedCapacity' { [pscustomobject]@{ InstanceName = 'ACPI\PNP0C0A\1_0'; FullChargedCapacity = 45000 } }
        'BatteryCycleCount' { [pscustomobject]@{ InstanceName = 'ACPI\PNP0C0A\1_0'; CycleCount = 412 } }
        'BatteryStatus' { [pscustomobject]@{ InstanceName = 'ACPI\PNP0C0A\1_0'; RemainingCapacity = 36000; Voltage = 11800; ChargeRate = 25000; DischargeRate = 9500; PowerOnline = $true; Charging = $true; Discharging = $false } }
        'WmiMonitorID' { [pscustomobject]@{ InstanceName = 'DISPLAY\BOE0812\4&2e8a0d9b&0&UID8388688_0'; ManufacturerName = [uint16[]]@(66, 79, 69, 0); ProductCodeID = [uint16[]]@(56, 49, 50, 0); SerialNumberID = [uint16[]]@(48); UserFriendlyName = $null; YearOfManufacture = 2021; WeekOfManufacture = 12 } }
        'WmiMonitorConnectionParams' { [pscustomobject]@{ InstanceName = 'DISPLAY\BOE0812\4&2e8a0d9b&0&UID8388688_0'; VideoOutputTechnology = [uint32]2147483648 } }
        'WmiMonitorBasicDisplayParams' { [pscustomobject]@{ InstanceName = 'DISPLAY\BOE0812\4&2e8a0d9b&0&UID8388688_0'; MaxHorizontalImageSize = 31; MaxVerticalImageSize = 17 } }
        'Lenovo_BiosPasswordSettings' { [pscustomobject]@{ PasswordState = 2 } }
        'Lenovo_BiosSetting' { [pscustomobject]@{ CurrentSetting = 'ComputraceModuleActivation,Disable;[Optional:Disable,Enable,Permanently Disable]' }; [pscustomobject]@{ CurrentSetting = 'SecureBoot,Enable' }; [pscustomobject]@{ CurrentSetting = 'WakeOnLAN,ACOnly' } }
        'Win32_Tpm' { [pscustomobject]@{ SpecVersion = '2.0, 0, 1.38' } }
        'SoftwareLicensingService' { [pscustomobject]@{ OA3xOriginalProductKeyDescription = '[4.0] Professional OEM:DM'; KeyManagementServiceMachine = '' } }
        'SoftwareLicensingProduct' { [pscustomobject]@{ Name = 'Windows(R), Professional edition'; Description = 'Windows(R) Operating System, OEM_DM channel'; LicenseStatus = 1; ProductKeyChannel = 'OEM:DM'; PartialProductKey = 'ABCDE'; KeyManagementServiceMachine = ''; DiscoveredKeyManagementServiceMachineName = '' } }
        'Win32_PerfFormattedData_Counters_ProcessorInformation' { $global:PerfTick++; [pscustomobject]@{ Name = '_Total'; PercentProcessorPerformance = [math]::Max(60, 140 - $global:PerfTick * 6); PercentProcessorUtility = 100; ProcessorFrequency = 1700; PerformanceLimitFlags = 0 } }
        'Win32_PerfFormattedData_Counters_ThermalZoneInformation' { [pscustomobject]@{ Name = '\_TZ.THM0'; Temperature = 330 + [math]::Min(40, $global:PerfTick * 3); HighPrecisionTemperature = 0; PercentPassiveLimit = 100; ThrottleReasons = 0 } }
        'MSStorageDriver_FailurePredictData' { @() }
        default { @() }
    }
}
function Get-PhysicalDisk {
    [CmdletBinding()] param()
    [pscustomobject]@{ DeviceId = '0'; FriendlyName = 'Samsung SSD 980 PRO 1TB'; SerialNumber = 'S5GXNF0R123456'; FirmwareVersion = 'SN11929'; BusType = 'NVMe'; MediaType = 'SSD'; Size = 1000204886016; HealthStatus = 'Healthy' }
    [pscustomobject]@{ DeviceId = '1'; FriendlyName = 'SanDisk Ultra'; SerialNumber = '4C53'; FirmwareVersion = '1.00'; BusType = 'USB'; MediaType = 'Unspecified'; Size = 32000000000; HealthStatus = 'Healthy' }
}
function Get-StorageReliabilityCounter { [CmdletBinding()] param([Parameter(ValueFromPipeline = $true)]$PhysicalDisk) process { [pscustomobject]@{ Wear = 12; Temperature = 37; TemperatureMax = 61; PowerOnHours = 3200; ReadErrorsUncorrected = 0; WriteErrorsUncorrected = 0; StartStopCycleCount = 1500 } } }
function Get-Disk { [CmdletBinding()] param([int]$Number) [pscustomobject]@{ Number = $Number; IsBoot = ($Number -eq 0); IsSystem = ($Number -eq 0) } }
function Get-PnpDeviceProperty {
    [CmdletBinding()] param([string]$InstanceId, [string]$KeyName)
    if ($KeyName -eq 'DEVPKEY_Device_Parent' -and $InstanceId -like 'SCSI\DISK&VEN_NVME*') { return [pscustomobject]@{ Data = 'PCI\VEN_1E4B&DEV_1602&SUBSYS_16021E4B&REV_01\4&2a3b' } }
    switch ($KeyName) { 'DEVPKEY_PciDevice_CurrentLinkSpeed' { return [pscustomobject]@{ Data = 3 } } 'DEVPKEY_PciDevice_CurrentLinkWidth' { return [pscustomobject]@{ Data = 4 } } 'DEVPKEY_PciDevice_MaxLinkSpeed' { return [pscustomobject]@{ Data = 3 } } 'DEVPKEY_PciDevice_MaxLinkWidth' { return [pscustomobject]@{ Data = 4 } } }
    throw 'Eigenschaft nicht vorhanden'
}
function Get-NetAdapter {
    [CmdletBinding()] param([switch]$Physical, [switch]$IncludeHidden)
    [pscustomobject]@{ InterfaceDescription = 'Intel(R) Wi-Fi 6 AX201 160MHz'; NdisPhysicalMedium = 9; Status = 'Up'; PnPDeviceID = 'PCI\VEN_8086&DEV_02F0&SUBSYS_00748086'; LinkSpeed = '866.7 Mbps' }
    [pscustomobject]@{ InterfaceDescription = 'Intel(R) Ethernet Connection (4) I219-V'; NdisPhysicalMedium = 14; Status = 'Disconnected'; PnPDeviceID = 'PCI\VEN_8086&DEV_15D8'; LinkSpeed = '0 bps' }
}
function Get-WinEvent {
    [CmdletBinding()] param([hashtable]$FilterHashtable, [int]$MaxEvents, [string]$LogName, [switch]$Oldest)
    if ($LogName -and $Oldest) { return [pscustomobject]@{ TimeCreated = [datetime]'2024-02-10' } }
    $ev = @(
        [pscustomobject]@{ Id = 153; ProviderName = 'disk'; Level = 3; TimeCreated = (Get-Date).AddDays(-20); Message = 'Der E/A-Vorgang an der logischen Blockadresse wurde wiederholt.' }
        [pscustomobject]@{ Id = 41; ProviderName = 'Microsoft-Windows-Kernel-Power'; Level = 1; TimeCreated = (Get-Date).AddDays(-5); Message = 'Das System wurde neu gestartet, ohne dass es zuvor ordnungsgemäß heruntergefahren wurde.' }
        [pscustomobject]@{ Id = 41; ProviderName = 'Microsoft-Windows-Kernel-Power'; Level = 1; TimeCreated = (Get-Date).AddDays(-15); Message = 'Neustart ohne Herunterfahren.' }
        [pscustomobject]@{ Id = 41; ProviderName = 'Microsoft-Windows-Kernel-Power'; Level = 1; TimeCreated = (Get-Date).AddDays(-40); Message = 'Neustart ohne Herunterfahren.' }
        [pscustomobject]@{ Id = 17; ProviderName = 'Microsoft-Windows-WHEA-Logger'; Level = 3; TimeCreated = (Get-Date).AddDays(-30); Message = 'Ein korrigierter Hardwarefehler ist aufgetreten. Komponente: PCI Express Root Port' }
        [pscustomobject]@{ Id = 1; ProviderName = 'Microsoft-Windows-Kernel-General'; Level = 4; TimeCreated = (Get-Date).AddDays(-3); Message = 'Zeitänderung' }
        [pscustomobject]@{ Id = 1001; ProviderName = 'Microsoft-Windows-WER-SystemErrorReporting'; Level = 2; TimeCreated = (Get-Date).AddDays(-60); Message = 'Der Computer wurde nach einem schwerwiegenden Fehler neu gestartet. Der Fehlercode war: 0x0000009f (0x0000000000000003, ...)' }
    )
    $ids = @($FilterHashtable.Id)
    $r = @($ev | Where-Object { ($ids.Count -eq 0 -or $ids -contains $_.Id) -and $_.TimeCreated -ge $FilterHashtable.StartTime })
    if ($r.Count -eq 0) { throw 'No events were found that match the specified selection criteria.' }
    return $r
}
function Get-Tpm { [CmdletBinding()] param() [pscustomobject]@{ TpmPresent = $true; TpmReady = $true } }
function Confirm-SecureBootUEFI { [CmdletBinding()] param() return $true }
function Get-SecureBootUEFI { [CmdletBinding()] param([string]$Name) [pscustomobject]@{ Bytes = [Text.Encoding]::ASCII.GetBytes('....Microsoft Corporation UEFI CA 2011....Microsoft Windows Production PCA 2011') } }
function Get-BitLockerVolume { [CmdletBinding()] param([string]$MountPoint) [pscustomobject]@{ ProtectionStatus = 'Off' } }
function Get-Service { [CmdletBinding()] param() @([pscustomobject]@{ Name = 'LMS'; DisplayName = 'Intel(R) Management and Security Application Local Management Service'; Status = 'Running' }) }
function Get-ScheduledTask { [CmdletBinding()] param() @([pscustomobject]@{ TaskName = 'Defrag'; TaskPath = '\Microsoft\Windows\' }) }
function Start-Process { [CmdletBinding()] param([Parameter(Position = 0)][string]$FilePath) Write-Host "      (Simulation: würde starten: $FilePath)" -ForegroundColor DarkGray }
