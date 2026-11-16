# Nachgebaute Windows-Abfragen (WMI, Registry, Cmdlets) und skriptgesteuerte Antworten für die Text-Oberfläche
$S = $global:SimS; $W = [BuyCheckSim.Win32]

# ---------------------------------------------------------------- Registry
$cv = @{ CurrentBuild = '22631'; DisplayVersion = '23H2'; UBR = 4317; EditionID = 'Professional'; RegisteredOwner = 'Max'; RegisteredOrganization = '' }
if ($global:Scenario -eq 'C') { $cv = @{ CurrentBuild = '7601'; EditionID = 'Professional'; RegisteredOwner = 'Benutzer'; RegisteredOrganization = '' } }
$global:SimReg = @{
    'HKLM:\HARDWARE\DESCRIPTION\System\CentralProcessor\0' = @{ ProcessorNameString = $global:RegCpu; Identifier = ('{0} Family {1} Model {2} Stepping {3}' -f $(if ($W::Level -ge 0x10) { 'AMD64' } else { 'Intel64' }), $W::Level, ($W::Revision16 -shr 8), ($W::Revision16 -band 0xFF)); VendorIdentifier = $(if ($W::Level -ge 0x10) { 'AuthenticAMD' } else { 'GenuineIntel' }) }
    'HKLM:\SYSTEM\CurrentControlSet\Control\Session Manager\Environment' = @{ PROCESSOR_IDENTIFIER = ('{0} Family {1} Model {2} Stepping {3}' -f $(if ($W::Level -ge 0x10) { 'AMD64' } else { 'Intel64' }), $W::Level, ($W::Revision16 -shr 8), ($W::Revision16 -band 0xFF)) }
    'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion' = $cv
    'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Run' = @{ SecurityHealth = '%windir%\system32\SecurityHealthSystray.exe' }
    'HKLM:\SYSTEM\CurrentControlSet\Control\Class\{4d36e968-e325-11ce-bfc1-08002be10318}\0000' = @{ MatchingDeviceId = 'pci\ven_8086&dev_5917'; 'HardwareInformation.qwMemorySize' = [int64]1073741824 }
    'HKLM:\SYSTEM\CurrentControlSet\Enum\DISPLAY\BOE0812\4&2e8a0d9b&0&UID8388688\Device Parameters' = @{ EDID = (New-SimEdid -Year $(if ($global:Scenario -eq 'C') { 2011 } else { 2021 })) }
}
if ($global:Scenario -eq 'A') {
    $global:SimReg['HKLM:\SOFTWARE\Microsoft\Provisioning\Diagnostics\Autopilot'] = @{ CloudAssignedTenantDomain = 'contoso.onmicrosoft.com'; CloudAssignedTenantId = '1234' }
    New-Item -ItemType Directory -Force "$env:windir/System32/Tasks" | Out-Null
    Set-Content -Path "$env:windir/System32/Tasks/CpuNameFix" -Value '<Task><Actions><Exec><Command>reg.exe</Command><Arguments>add HKLM\HARDWARE\DESCRIPTION\System\CentralProcessor\0 /v ProcessorNameString /d "Intel(R) Core(TM) i7-1165G7" /f</Arguments></Exec></Actions></Task>'
} else { Remove-Item "$env:windir/System32/Tasks/CpuNameFix" -ErrorAction SilentlyContinue }
if ($global:Scenario -eq 'C') { Remove-Item "$env:windir/System32/dsregcmd.exe" -ErrorAction SilentlyContinue } else { if (-not (Test-Path "$env:windir/System32/dsregcmd.exe")) { Copy-Item "$env:windir/../../sim/bin/dsregcmd.exe" "$env:windir/System32/dsregcmd.exe" -ErrorAction SilentlyContinue } }

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
    [CmdletBinding()] param([Parameter(Position = 0)][string]$Path, [string]$LiteralPath, [string]$Filter, [switch]$Recurse, [switch]$Force)
    $p = if ($Path) { $Path } else { $LiteralPath }
    if ($p -match '^(HKLM:|HKCU:|Registry::)') {
        $prefix = $p.TrimEnd('\') + '\'
        return @($global:SimReg.Keys | Where-Object { $_.StartsWith($prefix) -and ($_.Substring($prefix.Length) -notmatch '\\') } | ForEach-Object { [pscustomobject]@{ PSPath = $_; PSChildName = $_.Substring($prefix.Length) } })
    }
    Microsoft.PowerShell.Management\Get-ChildItem @PSBoundParameters
}

# ---------------------------------------------------------------- WMI
$global:SimPnp = @(
    [pscustomobject]@{ Name = 'Standard PS/2-Tastatur'; PNPClass = 'Keyboard'; PNPDeviceID = 'ACPI\LEN0071\4&1'; ConfigManagerErrorCode = 0 }
    [pscustomobject]@{ Name = 'Synaptics Pointing Device'; PNPClass = 'Mouse'; PNPDeviceID = 'ACPI\LEN2054\4&2'; ConfigManagerErrorCode = 0 }
    [pscustomobject]@{ Name = 'Integrated Camera'; PNPClass = 'Image'; PNPDeviceID = 'USB\VID_04F2&PID_B604&MI_00\6&1'; ConfigManagerErrorCode = 0 }
    [pscustomobject]@{ Name = 'Realtek High Definition Audio'; PNPClass = 'MEDIA'; PNPDeviceID = 'HDAUDIO\FUNC_01&VEN_10EC&DEV_0257'; ConfigManagerErrorCode = 0 }
    [pscustomobject]@{ Name = 'Intel(R) Wireless Bluetooth(R)'; PNPClass = 'Bluetooth'; PNPDeviceID = 'USB\VID_8087&PID_0026\5&1'; ConfigManagerErrorCode = 0 }
    [pscustomobject]@{ Name = 'Intel(R) USB 3.1 eXtensible Host Controller - 1.10 (Microsoft)'; PNPClass = 'USB'; PNPDeviceID = 'PCI\VEN_8086&DEV_9DED'; ConfigManagerErrorCode = 0 }
)
if ($global:Scenario -ne 'C') {
    $global:SimPnp += [pscustomobject]@{ Name = 'Synaptics FM3297 Fingerprint Reader'; PNPClass = 'Biometric'; PNPDeviceID = 'USB\VID_06CB&PID_009A\1'; ConfigManagerErrorCode = 22 }
    $global:SimPnp += [pscustomobject]@{ Name = 'Intel(R) Active Management Technology - SOL (COM3)'; PNPClass = 'Ports'; PNPDeviceID = 'PCI\VEN_8086&DEV_9DE3'; ConfigManagerErrorCode = 0 }
}
$global:PerfTick = 0
$global:SimDischarge = $false; $global:SimPct = 80.0; $global:SimMWh = 36000.0; $global:SimN = 0
$sw = [Text.Encoding]::ASCII.GetBytes('    WD-WCXA10126042 '); for ($k = 0; $k -lt $sw.Length; $k += 2) { $tmp = $sw[$k]; $sw[$k] = $sw[$k + 1]; $sw[$k + 1] = $tmp }; $global:SimDiskSerialC = -join ($sw | ForEach-Object { $_.ToString('x2') })   # Windows-7-Stil (Hex, Byte-Paare vertauscht)

function Get-WmiObject {
    [CmdletBinding()] param([string]$Namespace = 'root\cimv2', [Parameter(Position = 0)][string]$Class, [string]$Filter)
    $win7 = ($global:Scenario -eq 'C')
    switch ($Class) {
        'Win32_ComputerSystem' { [pscustomobject]@{ Manufacturer = $S.Manufacturer; Model = $S.Product; SystemFamily = $S.Version; SystemSKUNumber = $(if ($win7) { $null } else { 'LENOVO_MT_20L5' }); Name = 'PC-SIM'; PartOfDomain = $false; Domain = 'WORKGROUP'; TotalPhysicalMemory = [double]$W::MemTotal; PCSystemType = 2 } }
        'Win32_ComputerSystemProduct' { [pscustomobject]@{ Version = $S.Version; UUID = '1111-2222'; IdentifyingNumber = $S.SmbiosSerial } }
        'Win32_BIOS' { [pscustomobject]@{ SerialNumber = $S.SmbiosSerial; SMBIOSBIOSVersion = $S.BiosVersion; Manufacturer = $S.BiosVendor; ReleaseDate = '20240512000000.000000+000' } }
        'Win32_BaseBoard' { [pscustomobject]@{ Manufacturer = $S.Manufacturer; Product = $S.Product; SerialNumber = 'L1HF81J01ZZ' } }
        'Win32_SystemEnclosure' { [pscustomobject]@{ ChassisTypes = @(10); SMBIOSAssetTag = 'No Asset Information' } }
        'Win32_OperatingSystem' {
            if ($win7) { [pscustomobject]@{ Caption = 'Microsoft Windows 7 Professional'; Version = '6.1.7601'; BuildNumber = '7601'; CSDVersion = 'Service Pack 1'; InstallDate = '20150310120000.000000+060'; OSArchitecture = '64-Bit'; LastBootUpTime = '20261115080000.000000+060'; TotalVisibleMemorySize = 8388608; FreePhysicalMemory = 3145728 } }
            else { [pscustomobject]@{ Caption = 'Microsoft Windows 11 Pro'; Version = '10.0.22631'; BuildNumber = '22631'; InstallDate = '20240210120000.000000+060'; OSArchitecture = '64-Bit'; LastBootUpTime = '20261115080000.000000+060'; TotalVisibleMemorySize = 16777216; FreePhysicalMemory = 9437184 } }
        }
        'Win32_Processor' { [pscustomobject]@{ Name = $global:RegCpu; Manufacturer = $(if ($W::Level -ge 0x10) { 'AuthenticAMD' } else { 'GenuineIntel' }); NumberOfCores = $W::Cores; NumberOfLogicalProcessors = $W::Procs; MaxClockSpeed = 1900; L2CacheSize = 1024; L3CacheSize = 6144 } }
        'Win32_PnPEntity' { if ($Filter -match 'USB') { $global:SimPnp | Where-Object { $_.PNPDeviceID -like 'USB*' } } else { $global:SimPnp } }
        'Win32_DiskDrive' {
            [pscustomobject]@{ Index = 0; PNPDeviceID = $(if ($W::Nvme[0]) { 'SCSI\DISK&VEN_NVME&PROD_SAMSUNG_SSD_980\5&1A2B3C4D&0&000000' } else { 'IDE\DISKSIM\4&ABC&0&0.0.0' }); InterfaceType = $(if ($W::Nvme[0]) { 'SCSI' } else { 'IDE' }); Model = $W::Product[0]; Size = 1000202273280; SerialNumber = $(if ($win7) { $global:SimDiskSerialC } else { $W::Serial[0] }); FirmwareRevision = $W::Revision[0]; Status = 'OK'; MediaType = 'Fixed hard disk media' }
            [pscustomobject]@{ Index = 1; PNPDeviceID = 'USBSTOR\DISK&VEN_SANDISK&PROD_ULTRA\4C53'; InterfaceType = 'USB'; Model = 'SanDisk Ultra USB Device'; Size = 32000000000; SerialNumber = '4C53'; FirmwareRevision = '1.00'; Status = 'OK'; MediaType = 'Removable Media' }
        }
        'Win32_VideoController' { [pscustomobject]@{ Name = 'Intel(R) UHD Graphics 620'; PNPDeviceID = 'PCI\VEN_8086&DEV_5917&SUBSYS_225D17AA&REV_07\3&1'; DriverVersion = '31.0.101.2111'; DriverDate = '20230101000000.000000-000'; Status = 'OK'; ConfigManagerErrorCode = 0; CurrentHorizontalResolution = 1920; CurrentVerticalResolution = 1080; CurrentRefreshRate = 60 } }
        'Win32_Battery' { [pscustomobject]@{ EstimatedChargeRemaining = [int]$global:SimPct } }
        'Win32_PhysicalMemory' { [pscustomobject]@{ Capacity = 8589934592; DeviceLocator = 'ChannelA-DIMM0'; BankLabel = 'BANK 0'; Speed = 2400; Manufacturer = 'Samsung'; PartNumber = 'M471A1K43CB1-CRC' } }
        'BatteryStaticData' {
            $md = $null; if ($global:Scenario -eq 'B') { $md = '20190601000000.000000+000' }
            [pscustomobject]@{ InstanceName = 'ACPI\PNP0C0A\1_0'; DeviceName = $(if ($global:Scenario -eq 'B') { 'CB-X' } else { '01AV489' }); ManufactureName = $(if ($global:Scenario -eq 'B') { '' } else { 'SMP' }); SerialNumber = '1234'; Chemistry = [uint32]0x4E4F494C; DesignedCapacity = $(if ($global:Scenario -eq 'B') { 46200 } else { 57000 }); Capabilities = 0; ManufactureDate = $md }
        }
        'BatteryFullChargedCapacity' { [pscustomobject]@{ InstanceName = 'ACPI\PNP0C0A\1_0'; FullChargedCapacity = $(switch ($global:Scenario) { 'B' { 46200 } 'C' { 31000 } default { 45000 } }) } }
        'BatteryCycleCount' { if ($global:Scenario -ne 'C') { [pscustomobject]@{ InstanceName = 'ACPI\PNP0C0A\1_0'; CycleCount = $(if ($global:Scenario -eq 'B') { 0 } else { 412 }) } } }
        'BatteryStatus' {
            if ($global:SimDischarge -and -not $W::AcOnline) {
                $global:SimN++; $global:SimMWh -= 160; $global:SimPct -= $(if ($global:SimN -eq 6) { 5 } else { 0.3 })
                $W::Percent = [int]$global:SimPct
            }
            [pscustomobject]@{ InstanceName = 'ACPI\PNP0C0A\1_0'; RemainingCapacity = [int]$global:SimMWh; Voltage = 11800 - $global:SimN * 8; ChargeRate = $(if ($W::AcOnline) { 25000 } else { 0 }); DischargeRate = $(if ($W::AcOnline) { 0 } else { 19500 }); PowerOnline = $W::AcOnline; Charging = $W::AcOnline; Discharging = -not $W::AcOnline }
        }
        'WmiMonitorID' { [pscustomobject]@{ InstanceName = 'DISPLAY\BOE0812\4&2e8a0d9b&0&UID8388688_0'; ManufacturerName = [uint16[]]@(66, 79, 69, 0); ProductCodeID = [uint16[]]@(56, 49, 50, 0); SerialNumberID = [uint16[]]@(48); UserFriendlyName = $null; YearOfManufacture = $(if ($global:Scenario -eq 'C') { 2011 } else { 2021 }); WeekOfManufacture = 12 } }
        'WmiMonitorConnectionParams' { [pscustomobject]@{ InstanceName = 'DISPLAY\BOE0812\4&2e8a0d9b&0&UID8388688_0'; VideoOutputTechnology = [uint32]2147483648 } }
        'WmiMonitorBasicDisplayParams' { [pscustomobject]@{ InstanceName = 'DISPLAY\BOE0812\4&2e8a0d9b&0&UID8388688_0'; MaxHorizontalImageSize = 31; MaxVerticalImageSize = 17; Active = $true } }
        'Lenovo_BiosPasswordSettings' { if ($global:Scenario -eq 'A') { [pscustomobject]@{ PasswordState = 2 } } elseif ($global:Scenario -eq 'C') { [pscustomobject]@{ PasswordState = 0 } } }
        'Lenovo_BiosSetting' { if ($S.Manufacturer -eq 'LENOVO') { [pscustomobject]@{ CurrentSetting = 'ComputraceModuleActivation,Disable;[Optional:Disable,Enable,Permanently Disable]' }; [pscustomobject]@{ CurrentSetting = 'SecureBoot,Enable' } } }
        'Win32_Tpm' { if ($global:Scenario -eq 'C') { [pscustomobject]@{ SpecVersion = '1.2, 2, 3' } } else { [pscustomobject]@{ SpecVersion = '2.0, 0, 1.38' } } }
        'SoftwareLicensingService' { [pscustomobject]@{ OA3xOriginalProductKeyDescription = $(if ($win7) { '' } else { '[4.0] Professional OEM:DM' }); KeyManagementServiceMachine = '' } }
        'SoftwareLicensingProduct' { [pscustomobject]@{ Name = 'Windows(R), Professional edition'; Description = 'Windows(R) Operating System, OEM_SLP channel'; LicenseStatus = 1; ProductKeyChannel = $(if ($win7) { $null } else { 'OEM:DM' }); PartialProductKey = 'ABCDE'; KeyManagementServiceMachine = ''; DiscoveredKeyManagementServiceMachineName = '' } }
        'Win32_PerfFormattedData_Counters_ProcessorInformation' {
            $global:PerfTick++
            $p = [math]::Max(60, 140 - $global:PerfTick * 6)
            if ($win7) { [pscustomobject]@{ Name = '_Total'; PercentofMaximumFrequency = [math]::Min(100, $p); ProcessorFrequency = 2500 } }
            else { [pscustomobject]@{ Name = '_Total'; PercentProcessorPerformance = $p; PercentProcessorUtility = 100; ProcessorFrequency = 1900; PerformanceLimitFlags = 0 } }
        }
        'Win32_PerfFormattedData_Counters_ThermalZoneInformation' { if (-not $win7) { [pscustomobject]@{ Name = '\_TZ.THM0'; Temperature = 330 + [math]::Min(40, $global:PerfTick * 3); HighPrecisionTemperature = 0; PercentPassiveLimit = 100; ThrottleReasons = 0 } } }
        'MSAcpi_ThermalZoneTemperature' { if ($win7) { [pscustomobject]@{ CurrentTemperature = 3300 + [math]::Min(400, $global:PerfTick * 30) } } }
        'MSStorageDriver_FailurePredictData' {
            if (-not $W::Nvme[0]) {
                $v = New-Object byte[] 512
                $attrs = switch ($global:Scenario) {
                    'B' { @(@(5, 100, 0), @(9, 100, 12000), @(12, 100, 2500), @(187, 98, 2), @(194, 65, 35), @(197, 100, 0), @(231, 35, 0), @(241, 100, 58593750000)) }
                    default { @(@(1, 100, 0), @(5, 100, 0), @(9, 61, 19800), @(10, 100, 0), @(12, 98, 4100), @(194, 120, 38), @(197, 100, 0), @(198, 100, 0), @(199, 200, 0)) }
                }
                for ($i = 0; $i -lt $attrs.Count; $i++) { $o = 2 + $i * 12; $a = $attrs[$i]; $v[$o] = $a[0]; $v[$o + 3] = $a[1]; $v[$o + 4] = $a[1]; $raw = [BitConverter]::GetBytes([uint64]$a[2]); for ($b = 0; $b -lt 6; $b++) { $v[$o + 5 + $b] = $raw[$b] } }
                [pscustomobject]@{ InstanceName = 'IDE\DISKSIM\4&ABC&0&0.0.0_0'; VendorSpecific = $v }
            }
        }
        'MSStorageDriver_FailurePredictThresholds' { if (-not $W::Nvme[0]) { $t = New-Object byte[] 512; $t[2] = 5; $t[3] = 10; [pscustomobject]@{ InstanceName = 'IDE\DISKSIM\4&ABC&0&0.0.0_0'; VendorSpecific = $t } } }
        'MSStorageDriver_FailurePredictStatus' { if (-not $W::Nvme[0]) { [pscustomobject]@{ InstanceName = 'IDE\DISKSIM\4&ABC&0&0.0.0_0'; PredictFailure = $false } } }
        'Win32_NetworkAdapter' {
            [pscustomobject]@{ Name = 'Intel(R) Centrino(R) Advanced-N 6205'; NetConnectionID = 'Drahtlosnetzwerkverbindung'; NetEnabled = $true; NetConnectionStatus = 2; PNPDeviceID = 'PCI\VEN_8086&DEV_0085&SUBSYS_13118086'; Speed = 144000000 }
            [pscustomobject]@{ Name = 'Intel(R) 82579LM Gigabit Network Connection'; NetEnabled = $true; NetConnectionStatus = 7; PNPDeviceID = 'PCI\VEN_8086&DEV_1502'; Speed = 9223372036854775807 }
        }
        'MSNdis_PhysicalMediumType' { [pscustomobject]@{ InstanceName = 'Intel(R) Centrino(R) Advanced-N 6205'; NdisPhysicalMediumType = 9 }; [pscustomobject]@{ InstanceName = 'Intel(R) 82579LM Gigabit Network Connection'; NdisPhysicalMediumType = 0 } }
        default { @() }
    }
}

# ---------------------------------------------------------------- Neuere Cmdlets (gibt es in Szenario C = Windows 7 nicht)
if ($global:Scenario -ne 'C') {
    function global:Get-PhysicalDisk {
        [CmdletBinding()] param()
        [pscustomobject]@{ DeviceId = '0'; FriendlyName = $W::Product[0]; SerialNumber = $W::Serial[0]; FirmwareVersion = $W::Revision[0]; BusType = $(if ($W::Nvme[0]) { 'NVMe' } else { 'SATA' }); MediaType = 'SSD'; Size = $W::Size[0]; HealthStatus = 'Healthy' }
        [pscustomobject]@{ DeviceId = '1'; FriendlyName = 'SanDisk Ultra'; SerialNumber = '4C53'; FirmwareVersion = '1.00'; BusType = 'USB'; MediaType = 'Unspecified'; Size = 32000000000; HealthStatus = 'Healthy' }
    }
    function global:Get-StorageReliabilityCounter { [CmdletBinding()] param([Parameter(ValueFromPipeline = $true)]$PhysicalDisk) process { [pscustomobject]@{ Wear = 12; Temperature = 37; TemperatureMax = 61; PowerOnHours = 3200; ReadErrorsUncorrected = 0; WriteErrorsUncorrected = 0; StartStopCycleCount = 1500 } } }
    function global:Get-PnpDeviceProperty {
        [CmdletBinding()] param([string]$InstanceId, [string]$KeyName)
        if ($KeyName -eq 'DEVPKEY_Device_Parent' -and $InstanceId -like 'SCSI\DISK&VEN_NVME*') { return [pscustomobject]@{ Data = 'PCI\VEN_1E4B&DEV_1602&SUBSYS_16021E4B&REV_01\4&2a3b' } }
        switch ($KeyName) { 'DEVPKEY_PciDevice_CurrentLinkSpeed' { return [pscustomobject]@{ Data = 3 } } 'DEVPKEY_PciDevice_CurrentLinkWidth' { return [pscustomobject]@{ Data = 2 } } 'DEVPKEY_PciDevice_MaxLinkSpeed' { return [pscustomobject]@{ Data = 3 } } 'DEVPKEY_PciDevice_MaxLinkWidth' { return [pscustomobject]@{ Data = 4 } } }
        throw 'Eigenschaft nicht vorhanden'
    }
    function global:Get-NetAdapter {
        [CmdletBinding()] param([switch]$Physical, [switch]$IncludeHidden)
        [pscustomobject]@{ InterfaceDescription = 'Intel(R) Wi-Fi 6 AX201 160MHz'; NdisPhysicalMedium = 9; Status = 'Up'; PnPDeviceID = 'PCI\VEN_8086&DEV_02F0&SUBSYS_00748086'; LinkSpeed = '866.7 Mbps' }
        [pscustomobject]@{ InterfaceDescription = 'Intel(R) Ethernet Connection (4) I219-V'; NdisPhysicalMedium = 14; Status = 'Disconnected'; PnPDeviceID = 'PCI\VEN_8086&DEV_15D8'; LinkSpeed = '0 bps' }
    }
    function global:Get-Tpm { [CmdletBinding()] param() [pscustomobject]@{ TpmPresent = $true; TpmReady = $true } }
    function global:Confirm-SecureBootUEFI { [CmdletBinding()] param() return $true }
    function global:Get-SecureBootUEFI { [CmdletBinding()] param([string]$Name) [pscustomobject]@{ Bytes = [Text.Encoding]::ASCII.GetBytes('....Microsoft Corporation UEFI CA 2011....Microsoft Windows Production PCA 2011') } }
    function global:Get-BitLockerVolume { [CmdletBinding()] param([string]$MountPoint) [pscustomobject]@{ ProtectionStatus = 'Off' } }
}
function Get-WinEvent {
    [CmdletBinding()] param([hashtable]$FilterHashtable, [int]$MaxEvents, [string]$LogName, [switch]$Oldest)
    if ($LogName -and $Oldest) { return [pscustomobject]@{ TimeCreated = [datetime]'2024-02-10' } }
    $ev = @(
        [pscustomobject]@{ Id = 153; ProviderName = 'disk'; Level = 3; TimeCreated = (Get-Date).AddDays(-20); Message = 'Der E/A-Vorgang an der logischen Blockadresse wurde wiederholt.' }
        [pscustomobject]@{ Id = 41; ProviderName = 'Microsoft-Windows-Kernel-Power'; Level = 1; TimeCreated = (Get-Date).AddDays(-5); Message = 'Neustart ohne Herunterfahren.' }
        [pscustomobject]@{ Id = 17; ProviderName = 'Microsoft-Windows-WHEA-Logger'; Level = 3; TimeCreated = (Get-Date).AddDays(-30); Message = 'Ein korrigierter Hardwarefehler ist aufgetreten.' }
        [pscustomobject]@{ Id = 1001; ProviderName = 'Microsoft-Windows-WER-SystemErrorReporting'; Level = 2; TimeCreated = (Get-Date).AddDays(-60); Message = 'Fehlercode 0x0000009f (0x0000000000000003, ...)' }
    )
    $ids = @($FilterHashtable.Id)
    $r = @($ev | Where-Object { ($ids.Count -eq 0 -or $ids -contains $_.Id) -and $_.TimeCreated -ge $FilterHashtable.StartTime })
    if ($r.Count -eq 0) { throw 'No events were found that match the specified selection criteria.' }
    return $r
}
function Get-Service { [CmdletBinding()] param() @([pscustomobject]@{ Name = 'LMS'; DisplayName = 'Intel(R) Management and Security Application Local Management Service'; Status = 'Running' }) }
function Start-Process { [CmdletBinding()] param([Parameter(Position = 0)][string]$FilePath) Write-Host "      (Simulation: würde starten: $FilePath)" -ForegroundColor DarkGray }
function Start-Sleep { [CmdletBinding()] param([Parameter(Position = 0)][double]$Seconds, [int]$Milliseconds) $ms = if ($Milliseconds) { $Milliseconds } else { $Seconds * 1000 }; Microsoft.PowerShell.Utility\Start-Sleep -Milliseconds ([int]($ms / 10)) }
function Clear-Host { Write-Host '      (Bildschirm gelöscht)' -ForegroundColor DarkGray }

# ---------------------------------------------------------------- Mitmach-Tests: Konsolen-Eingaben werden simuliert
$global:SimOut = New-Object System.Collections.Generic.List[string]
$global:SimUnmatched = New-Object System.Collections.Generic.List[string]
$global:SimKeyQueue = New-Object System.Collections.Generic.Queue[string]
$global:SimLineQueue = New-Object System.Collections.Generic.Queue[string]
$origOut = ${function:Write-BCOut}
function Write-BCOut {
    param([string]$Text = '', [string]$Color = 'Gray', [int]$Indent = 0, [string]$Prefix = '', [switch]$NoNewline)
    $global:SimOut.Add("$Prefix$Text"); while ($global:SimOut.Count -gt 30) { $global:SimOut.RemoveAt(0) }
    & $origOut -Text $Text -Color $Color -Indent $Indent -Prefix $Prefix -NoNewline:$NoNewline
}
# Regeln: Frage (Text der letzten Ausgaben) -> Antwort
$global:SimRules = @(
    @{ M = 'Wie klang der Lüfter'; A = '3' }                                # Schleifen -> Warnung
    @{ M = 'Diese Tasten wurden nicht erkannt'; A = '1' }                   # defekt
    @{ M = 'Wie fühlen sich die Tasten an'; A = '1' }
    @{ M = 'Was ist dir aufgefallen\? \(Mehrfachauswahl\)'; L = '1' }
    @{ M = 'Flackert das Bild'; A = '1' }
    @{ M = 'Was hast du gehört'; L = '1 2 3' }
    @{ M = 'Welches Netzteil liegt dabei'; A = '1' }
    @{ M = 'Scharniere in Ordnung'; A = 'n'; Note = 'Deckel wackelt deutlich' }
    @{ M = 'Akku nicht aufgebläht'; A = $(if ($global:Scenario -eq 'B') { 'n' } else { 'j' }) }
)
function Get-SimContext { return ($global:SimOut -join "`n") }
function Read-BCKey {
    param([string]$Prompt, [string[]]$Allowed)
    if ($global:SimKeyQueue.Count -gt 0) { $a = $global:SimKeyQueue.Dequeue(); Write-Host "      >> $a" -ForegroundColor Magenta; $global:SimOut.Clear(); return $a }
    $ctx = Get-SimContext
    $ans = $null
    foreach ($r in $global:SimRules) { if ($r.A -and $ctx -match $r.M -and $Allowed -contains $r.A) { $ans = $r.A; $global:SimNote = $r.Note; break } }
    if (-not $ans) {
        if ($Allowed -contains 'enter') { $ans = 'enter' } elseif ($Allowed -contains 'j') { $ans = 'j' } else { $ans = $Allowed[0] }
        $q = @($global:SimOut | Where-Object { $_ -match '\?' } | Select-Object -Last 1)
        if ($q.Count -gt 0) { $global:SimUnmatched.Add("$($q[0].Trim()) -> $ans") }
    }
    Write-Host "      >> $ans" -ForegroundColor Magenta
    $global:SimOut.Clear()
    return $ans
}
function Read-BCLine {
    param([string]$Prompt)
    if ($global:SimLineQueue.Count -gt 0) { $a = $global:SimLineQueue.Dequeue(); Write-Host "      >> '$a'" -ForegroundColor Magenta; return $a }
    $ctx = Get-SimContext
    $ans = ''
    foreach ($r in $global:SimRules) { if ($r.L -and $ctx -match $r.M) { $ans = $r.L; break } }
    if ($Prompt -match 'Was fällt auf' -and $global:SimNote) { $ans = $global:SimNote; $global:SimNote = $null }
    Write-Host "      >> '$ans'" -ForegroundColor Magenta
    $global:SimOut.Clear()
    return $ans
}
# Mitmach-Tests, die eine echte Konsole/Hardware brauchen
function Invoke-BCKeyboardCapture {
    if ($global:Scenario -eq 'A') { return [pscustomobject]@{ Pressed = @('Esc', 'F1', 'A'); Missing = @('F5', ([string][char]0xC4)); MissingOptional = @('Menü'); Extra = @(); Stuck = @(); Seconds = 95 } }
    return [pscustomobject]@{ Pressed = @('Esc', 'F1', 'A'); Missing = @(); MissingOptional = @(); Extra = @('VK 255 / Scan 1E3'); Stuck = @('Leertaste'); Seconds = 80 }
}
function Invoke-BCTouchpadCapture { return [pscustomobject]@{ Cells = 12; Visited = 12; Left = $true; Right = $true; Double = $true; TimedOut = $false; Seconds = 30 } }
function Invoke-BCColorScreens { return $true }
function Invoke-BCUsbWatch { return @([pscustomobject]@{ Name = 'USB-Massenspeichergerät'; Location = 'Anschluss 1 an USB-Hub 1'; Instance = 'USB\VID_0781&PID_5581\1'; Seconds = 5 }, [pscustomobject]@{ Name = 'USB-Eingabegerät'; Location = 'Anschluss 2 an USB-Hub 1'; Instance = 'USB\VID_046D&PID_C52B\2'; Seconds = 12 }) }
function Invoke-BCMonitorWatch { return [pscustomobject]@{ Before = 1; Max = 2 } }
$global:SimWavs = 0
function Invoke-BCPlayWav {
    param([byte[]]$Wav)
    $hdr = [Text.Encoding]::ASCII.GetString($Wav, 0, 4) + [Text.Encoding]::ASCII.GetString($Wav, 8, 4)
    $len = [BitConverter]::ToInt32($Wav, 40)
    if ($hdr -ne 'RIFFWAVE' -or $len -ne $Wav.Length - 44 -or ($len % 4) -ne 0) { throw "WAV ungültig ($hdr, $len, $($Wav.Length))" }
    $global:SimWavs++
    Write-Host ("      (Simulation: Ton abgespielt, {0:N1} s)" -f ($len / 176400)) -ForegroundColor DarkGray
}
# Netzteil: der "Benutzer" steckt sofort um
$origWait = ${function:Wait-BCPower}
function Wait-BCPower { param([bool]$Online, [string]$Message, [int]$TimeoutSeconds = 180) $W::AcOnline = $Online; & $origWait -Online $Online -Message $Message -TimeoutSeconds $TimeoutSeconds }
# Datenträgertests in der Simulation kürzer
$origBench = ${function:Invoke-BCDiskBenchmark}
function Invoke-BCDiskBenchmark { param([int]$Disk, [int]$SeqMB = 1536, [int]$RandomSeconds = 8, [int]$SectorBytes = 512) & $origBench -Disk $Disk -SeqMB 256 -RandomSeconds 1 -SectorBytes $SectorBytes }
