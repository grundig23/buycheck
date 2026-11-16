# Szenario B: Chuwi-artige Firmware-Fälschung, SATA-SSD mit Problemen, "neuwertiger" Akku
[BuyCheck.CpuNative]::Brand = 'AMD Ryzen 5 7430U with Radeon Graphics'
[BuyCheck.CpuNative]::Sig = [int[]]@(9, 0x17, 0x68, 1, 12)
[BuyCheck.DiskIo]::NvmeEnabled = $false
$global:SimReg['HKLM:\HARDWARE\DESCRIPTION\System\CentralProcessor\0'] = @{ ProcessorNameString = 'AMD Ryzen 5 7430U with Radeon Graphics'; Identifier = 'AMD64 Family 23 Model 104 Stepping 1'; VendorIdentifier = 'AuthenticAMD' }
$global:SimReg['HKLM:\SYSTEM\CurrentControlSet\Control\Session Manager\Environment'] = @{ PROCESSOR_IDENTIFIER = 'AMD64 Family 23 Model 104 Stepping 1, AuthenticAMD' }
$global:SimReg.Remove('HKLM:\SOFTWARE\Microsoft\Provisioning\Diagnostics\Autopilot')
Remove-Item "$env:windir/System32/Tasks/CpuNameFix" -ErrorAction SilentlyContinue
function New-SmartBytes {
    $v = New-Object byte[] 512; $t = New-Object byte[] 512
    $attrs = @(@(5, 100, 10, 0), @(9, 100, 0, 12000), @(12, 100, 0, 2500), @(187, 98, 0, 2), @(194, 65, 0, 35), @(197, 100, 0, 0), @(199, 100, 0, 0), @(231, 35, 10, 0), @(241, 100, 0, 58593750000))
    for ($i = 0; $i -lt $attrs.Count; $i++) {
        $o = 2 + $i * 12; $a = $attrs[$i]
        $v[$o] = $a[0]; $v[$o + 3] = $a[1]; $v[$o + 4] = $a[1]
        $raw = [BitConverter]::GetBytes([uint64]$a[3]); for ($b = 0; $b -lt 6; $b++) { $v[$o + 5 + $b] = $raw[$b] }
        $t[$o] = $a[0]; $t[$o + 1] = $a[2]
    }
    return @{ V = $v; T = $t }
}
$global:SB = New-SmartBytes
$origCimB = ${function:Get-CimInstance}
function Get-CimInstance {
    [CmdletBinding()] param([string]$Namespace = 'root/cimv2', [Parameter(Position = 0)][string]$ClassName, [string]$Filter)
    $inst = 'SCSI\Disk&Ven_&Prod_KINGSTON_SA400S3\4&abc&0&000000_0'
    switch ($ClassName) {
        'Win32_ComputerSystem' { return [pscustomobject]@{ Manufacturer = 'CHUWI Innovation And Technology(ShenZhen)co.,Ltd'; Model = 'CoreBook X'; SystemFamily = 'CoreBook'; SystemSKUNumber = 'Default string'; Name = 'DESKTOP-XYZ'; PartOfDomain = $false; Domain = 'WORKGROUP'; TotalPhysicalMemory = 17000000000 } }
        'Win32_BIOS' { return [pscustomobject]@{ SerialNumber = 'Default string'; SMBIOSBIOSVersion = 'CBX-1.05'; Manufacturer = 'American Megatrends'; ReleaseDate = [datetime]'2025-01-10' } }
        'Win32_ComputerSystemProduct' { return [pscustomobject]@{ Version = 'Default string'; UUID = '9999' } }
        'Win32_Processor' { return [pscustomobject]@{ Name = 'AMD Ryzen 5 7430U with Radeon Graphics'; Manufacturer = 'AuthenticAMD'; NumberOfCores = 6; NumberOfLogicalProcessors = 12; MaxClockSpeed = 2100; L2CacheSize = 3072; L3CacheSize = 8192 } }
        'Win32_DiskDrive' { return [pscustomobject]@{ Index = 0; PNPDeviceID = 'SCSI\DISK&VEN_&PROD_KINGSTON_SA400S3\4&ABC&0&000000'; InterfaceType = 'IDE'; Model = 'KINGSTON SA400S37480G'; Size = 480103981056 } }
        'MSStorageDriver_FailurePredictData' { return [pscustomobject]@{ InstanceName = $inst; VendorSpecific = $global:SB.V } }
        'MSStorageDriver_FailurePredictThresholds' { return [pscustomobject]@{ InstanceName = $inst; VendorSpecific = $global:SB.T } }
        'MSStorageDriver_FailurePredictStatus' { return [pscustomobject]@{ InstanceName = $inst; PredictFailure = $false } }
        'BatteryStaticData' { return [pscustomobject]@{ InstanceName = 'B1'; DeviceName = 'CB-X'; ManufactureName = ''; SerialNumber = ''; Chemistry = [uint32]0x4E4F494C; DesignedCapacity = 46200; Capabilities = 0; ManufactureDate = [datetime]'2019-06-01' } }
        'BatteryFullChargedCapacity' { return [pscustomobject]@{ InstanceName = 'B1'; FullChargedCapacity = 46200 } }
        'BatteryCycleCount' { return [pscustomobject]@{ InstanceName = 'B1'; CycleCount = 0 } }
        'Lenovo_BiosPasswordSettings' { return @() }
        'WmiMonitorID' { return @() }
        default { & $origCimB -Namespace $Namespace -ClassName $ClassName -Filter $Filter }
    }
}
function Get-PhysicalDisk { [CmdletBinding()] param() [pscustomobject]@{ DeviceId = '0'; FriendlyName = 'KINGSTON SA400S37480G'; SerialNumber = '50026B7784D5'; FirmwareVersion = 'SBFKB1D2'; BusType = 'SATA'; MediaType = 'SSD'; Size = 480103981056; HealthStatus = 'Healthy' } }
