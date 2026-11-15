# BuyCheck – direkte Windows-Funktionen OHNE Compiler
#
# Die wenigen nötigen Windows-Funktionen (kernel32, ntdll, user32, winmm) werden per Reflection.Emit nur
# im Arbeitsspeicher dieses PowerShell-Prozesses bekannt gemacht. Es wird nichts kompiliert, keine Datei
# geschrieben und nichts installiert. Alle Datenträgerzugriffe sind LESEND (GENERIC_READ oder ganz ohne
# Zugriffsrechte für reine Abfragen).
#
# Kompatibel mit Windows PowerShell 2.0 bis 5.1 (32 und 64 Bit, auch ARM64).

$script:BCW32 = $null
$script:BCNativeTried = $false
$script:BCNativeError = $null
$script:BCLastWin32 = 0
$script:BCGenericRead = [int]0x80000000          # GENERIC_READ (als Int32: -2147483648)
$script:BCFlagNoBuffering = 0x20000000
$script:BCFlagSequential = 0x08000000

function Add-BCPInvoke {
    param($Builder, [string]$Dll, [string]$Name, [Type]$Return, [Type[]]$Parameters, [int[]]$OutIndexes, [bool]$SetLastError)
    $attrs = [System.Reflection.MethodAttributes]'Public, Static, PinvokeImpl, HideBySig'
    $method = $Builder.DefineMethod($Name, $attrs, $Return, $Parameters)
    foreach ($i in @($OutIndexes)) { if ($i -gt 0) { [void]$method.DefineParameter($i, [System.Reflection.ParameterAttributes]::Out, $null) } }
    $dllImport = [System.Runtime.InteropServices.DllImportAttribute]
    $fields = [System.Reflection.FieldInfo[]]@($dllImport.GetField('SetLastError'), $dllImport.GetField('CallingConvention'),
        $dllImport.GetField('CharSet'), $dllImport.GetField('EntryPoint'), $dllImport.GetField('ExactSpelling'))
    $values = [object[]]@($SetLastError, [System.Runtime.InteropServices.CallingConvention]::Winapi,
        [System.Runtime.InteropServices.CharSet]::Unicode, $Name, $true)
    $ctor = $dllImport.GetConstructor([Type[]]@([string]))
    $cab = New-Object System.Reflection.Emit.CustomAttributeBuilder($ctor, [object[]]@($Dll), [System.Reflection.PropertyInfo[]]@(), [object[]]@(), $fields, $values)
    $method.SetCustomAttribute($cab)
}

# Macht die Windows-Funktionen verfügbar. Gibt $true zurück, wenn das geklappt hat.
function Initialize-BCNative {
    if ($script:BCW32) { return $true }
    if ($script:BCNativeTried) { return $false }
    $script:BCNativeTried = $true
    $existing = 'BuyCheck.Win32' -as [type]
    if ($existing) { $script:BCW32 = $existing; return $true }
    try {
        $name = New-Object System.Reflection.AssemblyName 'BuyCheckNative'
        $access = [System.Reflection.Emit.AssemblyBuilderAccess]::Run
        $define = [AppDomain].GetMethod('DefineDynamicAssembly', [Type[]]@([System.Reflection.AssemblyName], [System.Reflection.Emit.AssemblyBuilderAccess]))
        if ($define) { $asm = [AppDomain]::CurrentDomain.DefineDynamicAssembly($name, $access) }
        else { $asm = [System.Reflection.Emit.AssemblyBuilder]::DefineDynamicAssembly($name, $access) }
        $module = $asm.DefineDynamicModule('BuyCheckNative')
        $tb = $module.DefineType('BuyCheck.Win32', [System.Reflection.TypeAttributes]'Public, Class, Sealed, Abstract')
        $intRef = [int].MakeByRefType()
        $longRef = [long].MakeByRefType()
        $sb = [System.Text.StringBuilder]
        # Dll, Funktion, Rückgabe, Parameter, Out-Parameter (1-basiert), SetLastError
        $defs = @(
            @('kernel32.dll', 'CreateFileW', [IntPtr], @([string], [int], [int], [IntPtr], [int], [int], [IntPtr]), @(), $true),
            @('kernel32.dll', 'CloseHandle', [bool], @([IntPtr]), @(), $true),
            @('kernel32.dll', 'DeviceIoControl', [bool], @([IntPtr], [int], [byte[]], [int], [byte[]], [int], $intRef, [IntPtr]), @(7), $true),
            @('kernel32.dll', 'ReadFile', [bool], @([IntPtr], [IntPtr], [int], $intRef, [IntPtr]), @(4), $true),
            @('kernel32.dll', 'SetFilePointerEx', [bool], @([IntPtr], [long], $longRef, [int]), @(3), $true),
            @('kernel32.dll', 'VirtualAlloc', [IntPtr], @([IntPtr], [UIntPtr], [int], [int]), @(), $true),
            @('kernel32.dll', 'VirtualFree', [bool], @([IntPtr], [UIntPtr], [int]), @(), $true),
            @('kernel32.dll', 'GetNativeSystemInfo', [void], @([byte[]]), @(), $false),
            @('kernel32.dll', 'GetLogicalProcessorInformation', [bool], @([byte[]], $intRef), @(), $true),
            @('kernel32.dll', 'GetSystemFirmwareTable', [int], @([int], [int], [byte[]], [int]), @(), $true),
            @('kernel32.dll', 'GetFirmwareType', [bool], @($intRef), @(1), $true),
            @('kernel32.dll', 'GetFirmwareEnvironmentVariableW', [int], @([string], [string], [IntPtr], [int]), @(), $true),
            @('kernel32.dll', 'SetThreadExecutionState', [int], @([int]), @(), $false),
            @('kernel32.dll', 'IsProcessorFeaturePresent', [bool], @([int]), @(), $false),
            @('kernel32.dll', 'GlobalMemoryStatusEx', [bool], @([byte[]]), @(), $true),
            @('kernel32.dll', 'GetPhysicallyInstalledSystemMemory', [bool], @($longRef), @(1), $true),
            @('kernel32.dll', 'GetSystemPowerStatus', [bool], @([byte[]]), @(), $true),
            @('kernel32.dll', 'GetStdHandle', [IntPtr], @([int]), @(), $true),
            @('kernel32.dll', 'GetConsoleMode', [bool], @([IntPtr], $intRef), @(2), $true),
            @('kernel32.dll', 'SetConsoleMode', [bool], @([IntPtr], [int]), @(), $true),
            @('kernel32.dll', 'GetNumberOfConsoleInputEvents', [bool], @([IntPtr], $intRef), @(2), $true),
            @('kernel32.dll', 'ReadConsoleInputW', [bool], @([IntPtr], [byte[]], [int], $intRef), @(4), $true),
            @('kernel32.dll', 'FlushConsoleInputBuffer', [bool], @([IntPtr]), @(), $true),
            @('kernel32.dll', 'GetConsoleWindow', [IntPtr], @(), @(), $false),
            @('ntdll.dll', 'NtQuerySystemInformation', [int], @([int], [byte[]], [int], $intRef), @(4), $false),
            @('ntdll.dll', 'RtlCompareMemory', [UIntPtr], @([byte[]], [byte[]], [UIntPtr]), @(), $false),
            @('user32.dll', 'GetCursorPos', [bool], @([byte[]]), @(), $true),
            @('user32.dll', 'GetAsyncKeyState', [short], @([int]), @(), $false),
            @('user32.dll', 'GetSystemMetrics', [int], @([int]), @(), $false),
            @('user32.dll', 'ShowWindow', [bool], @([IntPtr], [int]), @(), $false),
            @('winmm.dll', 'mciSendStringW', [int], @([string], $sb, [int], [IntPtr]), @(), $false)
        )
        foreach ($d in $defs) {
            Add-BCPInvoke -Builder $tb -Dll $d[0] -Name $d[1] -Return $d[2] -Parameters ([Type[]]@($d[3])) -OutIndexes ([int[]]@($d[4])) -SetLastError $d[5]
        }
        $script:BCW32 = $tb.CreateType()
        return $true
    } catch {
        $script:BCNativeError = "$($_.Exception.Message)"
        Write-BCDebug "Windows-Funktionen nicht verfügbar: $($_.Exception.Message)"
        return $false
    }
}

# Fehlercode des letzten Windows-Aufrufs. Wird jeweils direkt nach dem Aufruf gelesen, damit kein anderer Aufruf ihn überschreibt.
function Get-BCLastWin32Error { return [System.Runtime.InteropServices.Marshal]::GetLastWin32Error() }

# ============================================================== Byte-Hilfen (für Strukturen aus Windows)
function Get-BCU16 { param([byte[]]$B, [int]$O) if ($null -eq $B -or $O + 1 -ge $B.Length) { return 0 } return ([int]$B[$O] + 256 * [int]$B[$O + 1]) }
function Get-BCU32 { param([byte[]]$B, [int]$O) if ($null -eq $B -or $O + 3 -ge $B.Length) { return [int64]0 } return [int64][BitConverter]::ToUInt32($B, $O) }
function Get-BCU128 {
    param([byte[]]$B, [int]$O)
    if ($null -eq $B -or $O + 15 -ge $B.Length) { return [double]0 }
    return ([double][BitConverter]::ToUInt64($B, $O) + [double][BitConverter]::ToUInt64($B, $O + 8) * 18446744073709551616.0)
}
function Set-BCInt32 { param([byte[]]$B, [int]$O, [int]$V) [Array]::Copy([BitConverter]::GetBytes($V), 0, $B, $O, 4) }

function Get-BCAscii {
    param([byte[]]$B, [int]$O, [int]$Len)
    if ($null -eq $B -or $O -lt 0 -or $O -ge $B.Length) { return '' }
    if ($O + $Len -gt $B.Length) { $Len = $B.Length - $O }
    $z = [Array]::IndexOf($B, [byte]0, $O, $Len)
    if ($z -ge 0) { $Len = $z - $O }
    if ($Len -le 0) { return '' }
    return ([Text.Encoding]::ASCII.GetString($B, $O, $Len) -replace '[^\x20-\x7E]', '?').Trim()
}

function Get-BCHex {
    param([byte[]]$B, [int]$O, [int]$Len)
    if ($null -eq $B) { return '' }
    $sb = New-Object System.Text.StringBuilder
    for ($i = $O; $i -lt $O + $Len -and $i -lt $B.Length; $i++) { [void]$sb.Append($B[$i].ToString('X2')) }
    return $sb.ToString()
}

# ============================================================== Geräte öffnen (nur lesend oder ohne Rechte)
function Open-BCDevice {
    param([string]$Path, [int]$Access, [int]$Flags)
    if (-not (Initialize-BCNative)) { return $null }
    # FILE_SHARE_READ|FILE_SHARE_WRITE = 3, OPEN_EXISTING = 3
    $h = $script:BCW32::CreateFileW($Path, $Access, 3, [IntPtr]::Zero, 3, $Flags, [IntPtr]::Zero); $err = [System.Runtime.InteropServices.Marshal]::GetLastWin32Error()
    if ($h -eq [IntPtr]::Zero -or $h.ToInt64() -eq -1) { $script:BCLastWin32 = $err; return $null }
    return $h
}

function Close-BCHandle { param($Handle) if ($Handle -and $script:BCW32) { try { [void]$script:BCW32::CloseHandle($Handle) } catch { } } }

# IOCTL mit Ein-/Ausgabepuffer. Liefert den Ausgabepuffer oder $null.
function Invoke-BCIoctl {
    param($Handle, [int]$Code, [byte[]]$InBuffer, [int]$OutSize)
    $out = New-Object byte[] $OutSize
    $ret = 0
    $inLen = 0; if ($InBuffer) { $inLen = $InBuffer.Length }
    $ok = $script:BCW32::DeviceIoControl($Handle, $Code, $InBuffer, $inLen, $out, $OutSize, [ref]$ret, [IntPtr]::Zero); $err = [System.Runtime.InteropServices.Marshal]::GetLastWin32Error()
    if (-not $ok) { $script:BCLastWin32 = $err; return $null }
    return , $out
}

# IOCTL_STORAGE_QUERY_PROPERTY (Standardabfrage) – reine Leseabfrage, Handle ohne Zugriffsrechte genügt
function Get-BCStorageQuery {
    param([int]$Disk, [int]$PropertyId, [int]$OutSize)
    $h = Open-BCDevice "\\.\PhysicalDrive$Disk" 0 0
    if (-not $h) { return $null }
    try {
        $in = New-Object byte[] 12
        Set-BCInt32 $in 0 $PropertyId
        return , (Invoke-BCIoctl $h 0x002D1400 $in $OutSize)
    } catch { Write-BCDebug "Speicherabfrage $PropertyId Datenträger ${Disk}: $($_.Exception.Message)"; return $null }
    finally { Close-BCHandle $h }
}

# Anschlussart, Hersteller-/Produktkennung, Seriennummer (STORAGE_DEVICE_DESCRIPTOR) – funktioniert ab Windows XP
function Get-BCStorageDescriptor {
    param([int]$Disk)
    $b = Get-BCStorageQuery $Disk 0 1024
    if ($null -eq $b) { return $null }
    $str = {
        param([int]$at)
        $off = [int](Get-BCU32 $b $at)
        if ($off -le 0 -or $off -ge $b.Length) { return '' }
        return (Get-BCAscii $b $off 256)
    }
    $bus = [int](Get-BCU32 $b 28)
    $busName = 'Unknown'; if ($script:BCBusTypes.ContainsKey($bus)) { $busName = $script:BCBusTypes[$bus] }
    return (New-BCObject @('BusType', $bus, 'BusName', $busName, 'Removable', ($b[10] -ne 0),
            'Vendor', (& $str 12), 'Product', (& $str 16), 'Revision', (& $str 20), 'Serial', (& $str 24)))
}

# SSD-Erkennung ab Windows 7: Laufwerke ohne Suchzeit-Nachteil sind SSDs ($true = HDD, $false = SSD, $null = unbekannt)
function Get-BCSeekPenalty {
    param([int]$Disk)
    $b = Get-BCStorageQuery $Disk 7 12
    if ($null -eq $b) { return $null }
    if ((Get-BCU32 $b 4) -lt 9) { return $null }
    return ($b[8] -ne 0)
}

# Größe und Sektorgröße (IOCTL_DISK_GET_DRIVE_GEOMETRY_EX, ohne Zugriffsrechte)
function Get-BCDiskGeometry {
    param([int]$Disk)
    $h = Open-BCDevice "\\.\PhysicalDrive$Disk" 0 0
    if (-not $h) { return $null }
    try {
        $b = Invoke-BCIoctl $h 0x000700A0 $null 256
        if ($null -eq $b) { return $null }
        $bps = [BitConverter]::ToInt32($b, 20)
        if ($bps -lt 512 -or $bps -gt 65536) { $bps = 512 }
        return (New-BCObject @('SizeBytes', [double][BitConverter]::ToInt64($b, 24), 'BytesPerSector', $bps))
    } catch { return $null }
    finally { Close-BCHandle $h }
}

# Nummer des Datenträgers, auf dem Windows liegt (IOCTL_STORAGE_GET_DEVICE_NUMBER auf das Systemlaufwerk)
function Get-BCSystemDiskNumber {
    $drive = "$env:SystemDrive".TrimEnd('\')
    if (-not $drive) { $drive = 'C:' }
    $h = Open-BCDevice "\\.\$drive" 0 0
    if (-not $h) { return $null }
    try {
        $b = Invoke-BCIoctl $h 0x002D1080 $null 12
        if ($null -eq $b) { return $null }
        return [int][BitConverter]::ToInt32($b, 4)
    } catch { return $null }
    finally { Close-BCHandle $h }
}

# ============================================================== NVMe (Windows 10 und neuer, Standardtreiber)
# Reine Leseabfragen (Identify / Get Log Page) über IOCTL_STORAGE_QUERY_PROPERTY.
function Get-BCNvmeData {
    param([int]$Disk, [int]$PropertyId, [int]$DataType, [int]$RequestValue, [int]$DataLength, [ref]$ErrorText)
    if (-not (Initialize-BCNative)) { $ErrorText.Value = 'Windows-Funktionen nicht verfügbar'; return $null }
    $h = Open-BCDevice "\\.\PhysicalDrive$Disk" $script:BCGenericRead 0
    if (-not $h) { $h = Open-BCDevice "\\.\PhysicalDrive$Disk" 0 0 }
    if (-not $h) { $ErrorText.Value = "Datenträger lässt sich nicht öffnen (Windows-Fehler $script:BCLastWin32)"; return $null }
    try {
        $buf = New-Object byte[] (48 + $DataLength)
        Set-BCInt32 $buf 0 $PropertyId      # STORAGE_PROPERTY_QUERY.PropertyId
        Set-BCInt32 $buf 4 0                # PropertyStandardQuery
        Set-BCInt32 $buf 8 3                # ProtocolTypeNvme
        Set-BCInt32 $buf 12 $DataType
        Set-BCInt32 $buf 16 $RequestValue
        Set-BCInt32 $buf 20 0
        Set-BCInt32 $buf 24 40              # ProtocolDataOffset (relativ zu STORAGE_PROTOCOL_SPECIFIC_DATA)
        Set-BCInt32 $buf 28 $DataLength
        $ret = 0
        $ok = $script:BCW32::DeviceIoControl($h, 0x002D1400, $buf, $buf.Length, $buf, $buf.Length, [ref]$ret, [IntPtr]::Zero); $e = [System.Runtime.InteropServices.Marshal]::GetLastWin32Error()
        if (-not $ok) { $ErrorText.Value = "Abfrage abgelehnt (Windows-Fehler $e)"; return $null }
        $version = [BitConverter]::ToInt32($buf, 0); $size = [BitConverter]::ToInt32($buf, 4)
        $off = [BitConverter]::ToInt32($buf, 24); $len = [BitConverter]::ToInt32($buf, 28)
        if ($version -ne 48 -or $size -ne 48) { $ErrorText.Value = "Unerwartete Antwort (Version $version, Größe $size)"; return $null }
        if ($off -lt 40 -or $len -le 0 -or (8 + $off + $len) -gt $buf.Length) { $ErrorText.Value = 'Ungültiger Datenbereich in der Antwort'; return $null }
        $data = New-Object byte[] $len
        [Array]::Copy($buf, 8 + $off, $data, 0, $len)
        return , $data
    } catch {
        $ErrorText.Value = "$($_.Exception.Message)"
        return $null
    } finally { Close-BCHandle $h }
}

function ConvertFrom-BCNvmeIdentify {
    param([byte[]]$D)
    if ($null -eq $D -or $D.Length -lt 520) { return $null }
    $vid = Get-BCU16 $D 0
    $ver = Get-BCU32 $D 80
    $oacs = Get-BCU16 $D 256
    $verText = ''
    if ($ver -gt 0) { $verText = '{0}.{1}.{2}' -f (Get-BCBits $ver 16 0xFFFF), (Get-BCBits $ver 8 0xFF), ($ver -band 0xFF) }
    return (New-BCObject @(
            'VendorId', $vid,
            'VendorIdHex', ('{0:X4}' -f $vid),
            'SubsystemVendorIdHex', ('{0:X4}' -f (Get-BCU16 $D 2)),
            'SerialNumber', (Get-BCAscii $D 4 20),
            'Model', (Get-BCAscii $D 24 40),
            'Firmware', (Get-BCAscii $D 64 8),
            'IeeeOui', ('{0:X2}{1:X2}{2:X2}' -f $D[75], $D[74], $D[73]),
            'ControllerId', (Get-BCU16 $D 78),
            'NvmeVersion', $verText,
            'Oacs', $oacs,
            'SelfTestSupported', (($oacs -band 0x10) -ne 0),
            'WarningTempThresholdKelvin', (Get-BCU16 $D 266),
            'CriticalTempThresholdKelvin', (Get-BCU16 $D 268),
            'TotalNvmCapacityBytes', (Get-BCU128 $D 280),
            'UnallocatedNvmCapacityBytes', (Get-BCU128 $D 296),
            'NamespaceCount', (Get-BCU32 $D 516)
        ))
}

function ConvertFrom-BCNvmeHealth {
    param([byte[]]$D)
    if ($null -eq $D -or $D.Length -lt 232) { return $null }
    $tempK = Get-BCU16 $D 1
    $sensors = @()
    for ($i = 0; $i -lt 8; $i++) { $t = Get-BCU16 $D (200 + $i * 2); if ($t -gt 0) { $sensors += $t } }
    $written = Get-BCU128 $D 48
    $read = Get-BCU128 $D 32
    $tempC = [double]::NaN
    if ($tempK -gt 0) { $tempC = [double]($tempK - 273) }
    return (New-BCObject @(
            'CriticalWarning', [int]$D[0],
            'CompositeTemperatureKelvin', $tempK,
            'TemperatureCelsius', $tempC,
            'AvailableSpare', [int]$D[3],
            'AvailableSpareThreshold', [int]$D[4],
            'PercentageUsed', [int]$D[5],
            'EnduranceGroupCriticalWarning', [int]$D[6],
            'DataUnitsRead', $read,
            'DataUnitsWritten', $written,
            'TerabytesRead', ($read * 512000.0 / 1e12),
            'TerabytesWritten', ($written * 512000.0 / 1e12),
            'HostReadCommands', (Get-BCU128 $D 64),
            'HostWriteCommands', (Get-BCU128 $D 80),
            'ControllerBusyTimeMinutes', (Get-BCU128 $D 96),
            'PowerCycles', (Get-BCU128 $D 112),
            'PowerOnHours', (Get-BCU128 $D 128),
            'UnsafeShutdowns', (Get-BCU128 $D 144),
            'MediaErrors', (Get-BCU128 $D 160),
            'ErrorLogEntries', (Get-BCU128 $D 176),
            'WarningTempMinutes', (Get-BCU32 $D 192),
            'CriticalTempMinutes', (Get-BCU32 $D 196),
            'TempSensorsKelvin', $sensors,
            'ThermalMgmtT1Transitions', (Get-BCU32 $D 216),
            'ThermalMgmtT2Transitions', (Get-BCU32 $D 220),
            'ThermalMgmtT1Seconds', (Get-BCU32 $D 224),
            'ThermalMgmtT2Seconds', (Get-BCU32 $D 228),
            'RawHex', (Get-BCHex $D 0 512)
        ))
}

function Get-BCNvmeIdentify {
    param([int]$Disk, [ref]$ErrorText)
    # StorageAdapterProtocolSpecificProperty (49), NVMeDataTypeIdentify (1), CNS 1 = Controller
    $d = Get-BCNvmeData -Disk $Disk -PropertyId 49 -DataType 1 -RequestValue 1 -DataLength 4096 -ErrorText $ErrorText
    if ($null -eq $d) { return $null }
    return (ConvertFrom-BCNvmeIdentify $d)
}

function Get-BCNvmeHealth {
    param([int]$Disk, [ref]$ErrorText)
    # Log-Seite 02h (SMART/Health); erst über das Gerät (50), dann über den Adapter (49)
    $e1 = $null; $e2 = $null
    $d = Get-BCNvmeData -Disk $Disk -PropertyId 50 -DataType 2 -RequestValue 2 -DataLength 512 -ErrorText ([ref]$e1)
    if ($null -eq $d) { $d = Get-BCNvmeData -Disk $Disk -PropertyId 49 -DataType 2 -RequestValue 2 -DataLength 512 -ErrorText ([ref]$e2) }
    if ($null -eq $d) {
        if ($e1) { $ErrorText.Value = $e1 } elseif ($e2) { $ErrorText.Value = $e2 } else { $ErrorText.Value = 'Keine Daten' }
        return $null
    }
    return (ConvertFrom-BCNvmeHealth $d)
}

# ============================================================== Prozessor
# Name direkt vom Prozessor (vom Windows-Kernel beim Start per CPUID gelesen) – unabhängig von der Registry.
# Gibt es erst ab Windows 8.1/10; auf älteren Systemen $null.
function Get-BCKernelBrandString {
    if (-not (Initialize-BCNative)) { return $null }
    try {
        $buf = New-Object byte[] 256
        $ret = 0
        $status = $script:BCW32::NtQuerySystemInformation(105, $buf, $buf.Length, [ref]$ret)   # SystemProcessorBrandString
        if ($status -ne 0) { return $null }
        $s = Get-BCAscii $buf 0 256
        while ($s.Contains('  ')) { $s = $s.Replace('  ', ' ') }
        if (-not $s) { return $null }
        return $s
    } catch { return $null }
}

# Architektur, Familie, Modell, Stepping und Zahl der logischen Prozessoren aus dem Kernel (GetNativeSystemInfo)
function Get-BCNativeCpuSignature {
    if (-not (Initialize-BCNative)) { return $null }
    try {
        $b = New-Object byte[] 64
        $script:BCW32::GetNativeSystemInfo($b)
        $p = [IntPtr]::Size
        $rev = Get-BCU16 $b (22 + 3 * $p)
        return (New-BCObject @(
                'Architecture', (Get-BCU16 $b 0),
                'Family', (Get-BCU16 $b (20 + 3 * $p)),
                'Model', (Get-BCBits $rev 8 0xFF),
                'Stepping', ($rev -band 0xFF),
                'LogicalCount', [BitConverter]::ToInt32($b, 8 + 3 * $p)
            ))
    } catch { Write-BCDebug "GetNativeSystemInfo: $($_.Exception.Message)"; return $null }
}

# Kerne, Threads und Cache-Größen aus GetLogicalProcessorInformation (Hardware-Angaben, nicht Registry)
function Get-BCCpuTopology {
    if (-not (Initialize-BCNative)) { return $null }
    try {
        $len = 0
        [void]$script:BCW32::GetLogicalProcessorInformation($null, [ref]$len)
        if ($len -le 0) { return $null }
        $b = New-Object byte[] $len
        if (-not $script:BCW32::GetLogicalProcessorInformation($b, [ref]$len)) { return $null }
        $p = [IntPtr]::Size
        $entry = 24; $u = 8
        if ($p -eq 8) { $entry = 32; $u = 16 }
        $cores = 0; $logical = 0; $packages = 0; $l1d = 0; $l1i = 0; $l2 = 0; $l3 = 0; $l3n = 0
        for ($off = 0; $off + $entry -le $len; $off += $entry) {
            $rel = [BitConverter]::ToInt32($b, $off + $p)
            if ($rel -eq 0) {
                $cores++
                if ($p -eq 8) { $mask = [BitConverter]::ToInt64($b, $off) } else { $mask = [int64][BitConverter]::ToUInt32($b, $off) }
                $logical += ([Convert]::ToString($mask, 2).Replace('0', '')).Length
            } elseif ($rel -eq 3) {
                $packages++
            } elseif ($rel -eq 2) {
                $level = [int]$b[$off + $u]
                $size = [int64][BitConverter]::ToUInt32($b, $off + $u + 4)
                $type = [BitConverter]::ToInt32($b, $off + $u + 8)
                if ($level -eq 1) { if ($type -eq 1) { $l1i += $size } else { $l1d += $size } }
                elseif ($level -eq 2) { $l2 += $size }
                elseif ($level -eq 3) { $l3 += $size; $l3n++ }
            }
        }
        return (New-BCObject @('Cores', $cores, 'LogicalProcessors', $logical, 'Packages', $packages, 'L1DataBytes', $l1d,
                'L1InstructionBytes', $l1i, 'L2Bytes', $l2, 'L3Bytes', $l3, 'L3Instances', $l3n))
    } catch { Write-BCDebug "GetLogicalProcessorInformation: $($_.Exception.Message)"; return $null }
}

# $true/$false oder $null, wenn nicht abfragbar
function Test-BCCpuFeature {
    param([int]$Feature)
    if (-not (Initialize-BCNative)) { return $null }
    try { return [bool]$script:BCW32::IsProcessorFeaturePresent($Feature) } catch { return $null }
}

# ============================================================== Firmware (SMBIOS, Firmware-Typ)
function Read-BCSmbiosRaw {
    if (Initialize-BCNative) {
        try {
            $rsmb = 0x52534D42
            $size = $script:BCW32::GetSystemFirmwareTable($rsmb, 0, $null, 0)
            if ($size -gt 8) {
                $buf = New-Object byte[] $size
                $got = $script:BCW32::GetSystemFirmwareTable($rsmb, 0, $buf, $size)
                if ($got -gt 8 -and $got -le $size) {
                    $len = [BitConverter]::ToInt32($buf, 4)
                    if ($len -gt 0 -and (8 + $len) -le $got) {
                        $data = New-Object byte[] $len
                        [Array]::Copy($buf, 8, $data, 0, $len)
                        return (New-BCObject @('Major', [int]$buf[1], 'Minor', [int]$buf[2], 'Data', $data))
                    }
                }
            }
        } catch { Write-BCDebug "SMBIOS (GetSystemFirmwareTable): $($_.Exception.Message)" }
    }
    $w = Get-BCWmi -Namespace 'root\wmi' -ClassName MSSmBios_RawSMBiosTables | Select-Object -First 1
    if ($w -and $w.SMBiosData) { return (New-BCObject @('Major', [int]$w.SmbiosMajorVersion, 'Minor', [int]$w.SmbiosMinorVersion, 'Data', ([byte[]]$w.SMBiosData))) }
    return $null
}

# Zerlegt die SMBIOS-Tabelle in Strukturen mit den Methoden Str/Byte/Word/Dword
function ConvertFrom-BCSmbios {
    param([byte[]]$Data)
    $list = New-Object 'System.Collections.Generic.List[object]'
    if ($null -eq $Data) { return , $list.ToArray() }
    $latin1 = [Text.Encoding]::GetEncoding(28591)
    $end = $Data.Length
    $pos = 0
    while ($pos + 4 -le $end) {
        $type = [int]$Data[$pos]
        $len = [int]$Data[$pos + 1]
        if ($len -lt 4 -or $pos + $len -gt $end) { break }
        $raw = New-Object byte[] $len
        [Array]::Copy($Data, $pos, $raw, 0, $len)
        $strings = New-Object 'System.Collections.Generic.List[string]'
        $sp = $pos + $len
        if ($sp + 1 -lt $end -and $Data[$sp] -eq 0 -and $Data[$sp + 1] -eq 0) {
            $sp += 2
        } else {
            while ($sp -lt $end) {
                $z = [Array]::IndexOf($Data, [byte]0, $sp)
                if ($z -lt 0) { $z = $end }
                $strings.Add($latin1.GetString($Data, $sp, $z - $sp))
                $sp = $z + 1
                if ($sp -lt $end -and $Data[$sp] -eq 0) { $sp++; break }
            }
        }
        $s = New-BCObject @('Type', $type, 'Handle', ([int]$Data[$pos + 2] + 256 * [int]$Data[$pos + 3]), 'Data', $raw, 'Strings', $strings.ToArray())
        Add-Member -InputObject $s -MemberType ScriptMethod -Name Str -Value {
            param([int]$Offset)
            $d = $this.Data
            if ($Offset -ge $d.Length) { return $null }
            $i = [int]$d[$Offset]
            $st = @($this.Strings)
            if ($i -eq 0 -or $i -gt $st.Count) { return $null }
            return ([string]$st[$i - 1]).Trim()
        }
        Add-Member -InputObject $s -MemberType ScriptMethod -Name Byte -Value { param([int]$Offset) if ($Offset -lt $this.Data.Length) { return [int]$this.Data[$Offset] } return -1 }
        Add-Member -InputObject $s -MemberType ScriptMethod -Name Word -Value { param([int]$Offset) $d = $this.Data; if ($Offset + 1 -lt $d.Length) { return ([int]$d[$Offset] + 256 * [int]$d[$Offset + 1]) } return -1 }
        Add-Member -InputObject $s -MemberType ScriptMethod -Name Dword -Value { param([int]$Offset) $d = $this.Data; if ($Offset + 3 -lt $d.Length) { return [int64][BitConverter]::ToUInt32($d, $Offset) } return [int64]-1 }
        $list.Add($s)
        $pos = $sp
        if ($type -eq 127) { break }
    }
    return , $list.ToArray()
}

# 1 = BIOS (Legacy), 2 = UEFI, 0 = unbekannt
function Get-BCFirmwareType {
    $t = "$env:firmware_type"
    if ($t -eq 'UEFI') { return 2 }
    if ($t -eq 'Legacy') { return 1 }
    if (Initialize-BCNative) {
        try { $v = 0; if ($script:BCW32::GetFirmwareType([ref]$v)) { if ($v -eq 1 -or $v -eq 2) { return $v } } } catch { }
        try {
            # Bekannter Test für Windows 7: ohne UEFI antwortet Windows mit ERROR_INVALID_FUNCTION (1)
            [void]$script:BCW32::GetFirmwareEnvironmentVariableW('', '{00000000-0000-0000-0000-000000000000}', [IntPtr]::Zero, 0); $e = [System.Runtime.InteropServices.Marshal]::GetLastWin32Error()
            if ($e -eq 1) { return 1 }
            if ($e -eq 998 -or $e -eq 1314 -or $e -eq 203) { return 2 }
        } catch { }
    }
    # Letzte Möglichkeit: Startprogramm von Windows ansehen (bcdedit /enum ändert nichts)
    try {
        $bcd = Join-Path $env:windir 'System32\bcdedit.exe'
        if (Test-Path -LiteralPath $bcd) {
            $out = (& $bcd /enum '{current}' 2>&1 | Out-String)
            if ($out -match '(?i)winload\.efi') { return 2 }
            if ($out -match '(?i)winload\.exe') { return 1 }
        }
    } catch { }
    return 0
}

# ============================================================== Speicher, Strom, Bereitschaft
function Get-BCMemoryStatus {
    if (Initialize-BCNative) {
        try {
            $b = New-Object byte[] 64
            Set-BCInt32 $b 0 64
            if ($script:BCW32::GlobalMemoryStatusEx($b)) {
                return (New-BCObject @('Total', [double][BitConverter]::ToUInt64($b, 8), 'Available', [double][BitConverter]::ToUInt64($b, 16)))
            }
        } catch { }
    }
    $os = Get-BCWmi Win32_OperatingSystem | Select-Object -First 1
    if ($os) { return (New-BCObject @('Total', ([double]$os.TotalVisibleMemorySize * 1024), 'Available', ([double]$os.FreePhysicalMemory * 1024))) }
    return (New-BCObject @('Total', 0.0, 'Available', 0.0))
}

# Eingebauter RAM laut Firmware (inkl. für Grafik reserviertem Teil)
function Get-BCInstalledMemoryBytes {
    if (Initialize-BCNative) {
        try { $kb = [int64]0; if ($script:BCW32::GetPhysicallyInstalledSystemMemory([ref]$kb) -and $kb -gt 0) { return [double]$kb * 1024 } } catch { }
    }
    $sum = 0.0
    foreach ($m in @(Get-BCWmi Win32_PhysicalMemory)) { if ($m) { $sum += [double]$m.Capacity } }
    return $sum
}

# Netzteil angeschlossen? Ladestand? (GetSystemPowerStatus – sehr schnell, daher für Warteschleifen geeignet)
function Get-BCPowerStatus {
    if (Initialize-BCNative) {
        try {
            $b = New-Object byte[] 12
            if ($script:BCW32::GetSystemPowerStatus($b)) {
                $ac = $null
                if ([int]$b[0] -eq 0) { $ac = $false } elseif ([int]$b[0] -eq 1) { $ac = $true }
                $pct = $null
                if ([int]$b[2] -le 100) { $pct = [int]$b[2] }
                return (New-BCObject @('AcOnline', $ac, 'Percent', $pct, 'NoBattery', (([int]$b[1] -band 128) -ne 0)))
            }
        } catch { }
    }
    return (New-BCObject @('AcOnline', $null, 'Percent', $null, 'NoBattery', $null))
}

# Verhindert nur für die Laufzeit Standby/Bildschirmabschaltung (keine Energieeinstellung wird geändert)
function Set-BCKeepAwake {
    param([bool]$On)
    if (-not (Initialize-BCNative)) { return }
    try {
        if ($On) { [void]$script:BCW32::SetThreadExecutionState([int]0x80000003) }
        else { [void]$script:BCW32::SetThreadExecutionState([int]0x80000000) }
    } catch { }
}

# ============================================================== Konsole, Maus, Tastatur (nur lesen)
function Get-BCConsoleInputHandle {
    if (-not (Initialize-BCNative)) { return $null }
    try {
        $h = $script:BCW32::GetStdHandle(-10)
        if ($h -eq [IntPtr]::Zero -or $h.ToInt64() -eq -1) { return $null }
        $m = 0
        if (-not $script:BCW32::GetConsoleMode($h, [ref]$m)) { return $null }   # keine echte Konsole
        return $h
    } catch { return $null }
}

function Get-BCConsoleMode { param($Handle) $m = 0; if ($script:BCW32::GetConsoleMode($Handle, [ref]$m)) { return $m } return $null }
function Set-BCConsoleMode { param($Handle, [int]$Mode) try { return [bool]$script:BCW32::SetConsoleMode($Handle, $Mode) } catch { return $false } }
function Clear-BCConsoleInput { param($Handle) try { [void]$script:BCW32::FlushConsoleInputBuffer($Handle) } catch { } }

# Liefert alle anstehenden Eingabe-Ereignisse der Konsole (blockiert nicht)
function Read-BCConsoleEvents {
    param($Handle)
    $events = New-Object 'System.Collections.Generic.List[object]'
    $n = 0
    if (-not $script:BCW32::GetNumberOfConsoleInputEvents($Handle, [ref]$n) -or $n -le 0) { return , $events.ToArray() }
    $count = [math]::Min($n, 64)
    $buf = New-Object byte[] (20 * $count)
    $read = 0
    if (-not $script:BCW32::ReadConsoleInputW($Handle, $buf, $count, [ref]$read)) { return , $events.ToArray() }
    for ($i = 0; $i -lt $read; $i++) {
        $o = $i * 20
        $type = Get-BCU16 $buf $o
        if ($type -eq 1) {
            $events.Add((New-BCObject @('Type', 'Key', 'Down', ([BitConverter]::ToInt32($buf, $o + 4) -ne 0),
                        'Repeat', (Get-BCU16 $buf ($o + 8)), 'VK', (Get-BCU16 $buf ($o + 10)), 'Scan', (Get-BCU16 $buf ($o + 12)),
                        'Char', (Get-BCU16 $buf ($o + 14)), 'State', [BitConverter]::ToInt32($buf, $o + 16))))
        } elseif ($type -eq 2) {
            $events.Add((New-BCObject @('Type', 'Mouse', 'X', (Get-BCU16 $buf ($o + 4)), 'Y', (Get-BCU16 $buf ($o + 6)),
                        'Buttons', [BitConverter]::ToInt32($buf, $o + 8), 'Flags', [BitConverter]::ToInt32($buf, $o + 16))))
        }
    }
    return , $events.ToArray()
}

function Get-BCCursorPos {
    if (-not (Initialize-BCNative)) { return $null }
    try {
        $b = New-Object byte[] 8
        if ($script:BCW32::GetCursorPos($b)) { return (New-BCObject @('X', [BitConverter]::ToInt32($b, 0), 'Y', [BitConverter]::ToInt32($b, 4))) }
    } catch { }
    return $null
}

# Liest nur den aktuellen Tastenzustand (kein Tastatur-Hook, nichts wird abgefangen)
function Test-BCKeyDown { param([int]$VirtualKey) try { return (([int]$script:BCW32::GetAsyncKeyState($VirtualKey) -band 0x8000) -ne 0) } catch { return $false } }

function Get-BCScreenSize {
    if (-not (Initialize-BCNative)) { return $null }
    try { return (New-BCObject @('Width', $script:BCW32::GetSystemMetrics(0), 'Height', $script:BCW32::GetSystemMetrics(1))) } catch { return $null }
}

# Konsolenfenster maximieren (3) bzw. wiederherstellen (9) – betrifft nur das eigene Fenster
function Set-BCConsoleWindowState {
    param([int]$Command)
    if (-not (Initialize-BCNative)) { return }
    try { $w = $script:BCW32::GetConsoleWindow(); if ($w -ne [IntPtr]::Zero) { [void]$script:BCW32::ShowWindow($w, $Command) } } catch { }
}

# ============================================================== Audio (MCI, Teil von Windows seit Jahrzehnten)
function Invoke-BCMci {
    param([string]$Command)
    if (-not (Initialize-BCNative)) { return (New-BCObject @('Code', -1, 'Text', '')) }
    $sb = New-Object System.Text.StringBuilder 256
    try {
        $r = $script:BCW32::mciSendStringW($Command, $sb, 256, [IntPtr]::Zero)
        return (New-BCObject @('Code', $r, 'Text', $sb.ToString()))
    } catch { return (New-BCObject @('Code', -1, 'Text', "$($_.Exception.Message)")) }
}

# ============================================================== Speicher für Lesetests
# Seitenausgerichteter Puffer (für ungepuffertes Lesen vom Datenträger nötig)
function New-BCAlignedBuffer {
    param([int]$Size)
    $p = $script:BCW32::VirtualAlloc([IntPtr]::Zero, [UIntPtr][uint64]$Size, 0x3000, 4)
    if ($p -eq [IntPtr]::Zero) { throw 'Lesepuffer konnte nicht reserviert werden.' }
    return $p
}

function Remove-BCAlignedBuffer {
    param($Pointer)
    if ($Pointer -and $Pointer -ne [IntPtr]::Zero -and $script:BCW32) { try { [void]$script:BCW32::VirtualFree($Pointer, [UIntPtr][uint64]0, 0x8000) } catch { } }
}

# Erste abweichende Stelle zweier Byte-Felder (-1 = gleich). Läuft in Windows selbst, daher sehr schnell.
function Compare-BCBytes {
    param([byte[]]$A, [byte[]]$B, [int]$Length)
    $same = [int64]($script:BCW32::RtlCompareMemory($A, $B, [UIntPtr][uint64]$Length)).ToUInt64()
    if ($same -ge $Length) { return -1 }
    return $same
}
