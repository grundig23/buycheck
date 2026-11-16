# Erzeugt Rohdaten (SMBIOS, NVMe, EDID) für die Simulation – so durchlaufen die echten Parser in BuyCheck
function New-SimStruct {
    param([int]$Type, [int]$Length, [hashtable]$Bytes = @{}, [hashtable]$Words = @{}, [hashtable]$Dwords = @{}, [string[]]$Strings = @())
    $f = New-Object byte[] $Length
    $f[0] = $Type; $f[1] = $Length; $f[2] = 0x10; $f[3] = $Type
    foreach ($k in $Bytes.Keys) { $f[[int]$k] = [byte]$Bytes[$k] }
    foreach ($k in $Words.Keys) { $b = [BitConverter]::GetBytes([uint16]$Words[$k]); $f[[int]$k] = $b[0]; $f[[int]$k + 1] = $b[1] }
    foreach ($k in $Dwords.Keys) { $b = [BitConverter]::GetBytes([uint32]$Dwords[$k]); for ($i = 0; $i -lt 4; $i++) { $f[[int]$k + $i] = $b[$i] } }
    $out = New-Object System.Collections.Generic.List[byte]
    $out.AddRange($f)
    if ($Strings.Count -eq 0) { $out.Add(0); $out.Add(0) }
    else { foreach ($s in $Strings) { $out.AddRange([Text.Encoding]::GetEncoding(28591).GetBytes($s)); $out.Add(0) }; $out.Add(0) }
    return , $out.ToArray()
}

function New-SimSmbios {
    param($S)
    $parts = @(
        (New-SimStruct -Type 0 -Length 0x18 -Bytes @{ 4 = 1; 5 = 2; 8 = 3 } -Strings @($S.BiosVendor, $S.BiosVersion, $S.BiosDateText)),
        (New-SimStruct -Type 1 -Length 0x1B -Bytes @{ 4 = 1; 5 = 2; 6 = 3; 7 = 4 } -Strings @($S.Manufacturer, $S.Product, $S.Version, $S.SmbiosSerial)),
        (New-SimStruct -Type 3 -Length 0x15 -Bytes @{ 4 = 1; 5 = $S.Chassis; 8 = 2 } -Strings @($S.Manufacturer, 'No Asset Information')),
        (New-SimStruct -Type 4 -Length 0x30 -Bytes @{ 4 = 1; 7 = 2; 0x10 = 3; 0x23 = $S.Cores; 0x25 = $S.Threads } -Words @{ 0x14 = $S.MaxMHz } -Dwords @{ 8 = $S.CpuEax } -Strings @('U3E1', $S.CpuVendor, $S.SmbiosCpuName)),
        (New-SimStruct -Type 16 -Length 0x17 -Bytes @{ 5 = 3 } -Words @{ 0x0D = $S.Slots }),
        (New-SimStruct -Type 17 -Length 0x28 -Bytes @{ 0x0E = $S.MemForm; 0x10 = 1; 0x11 = 2; 0x12 = $S.MemType; 0x17 = 3; 0x1A = 4 } -Words @{ 0x0C = 8192; 0x15 = 2400; 0x20 = 2400 } -Strings @('ChannelA-DIMM0', 'BANK 0', 'Samsung', 'M471A1K43CB1-CRC')),
        (New-SimStruct -Type 22 -Length 0x1A -Bytes @{ 0x15 = 10 } -Words @{ 0x0A = $S.BatDesignDiv10; 0x12 = $S.BatSbdsDate } -Strings @()),
        (New-SimStruct -Type 127 -Length 4)
    )
    if ($S.Slots -ge 2) { $parts = @($parts[0..5]) + @(, (New-SimStruct -Type 17 -Length 0x28 -Bytes @{ 0x0E = $S.MemForm; 0x10 = 1; 0x11 = 2; 0x12 = $S.MemType } -Words @{ 0x0C = 0 } -Strings @('ChannelB-DIMM0', 'BANK 2'))) + @($parts[6..7]) }
    $all = New-Object System.Collections.Generic.List[byte]
    foreach ($p in $parts) { $all.AddRange([byte[]]$p) }
    return , $all.ToArray()
}

function Set-SimAscii { param([byte[]]$Buf, [int]$O, [int]$Len, [string]$Text) $t = [Text.Encoding]::ASCII.GetBytes($Text.PadRight($Len)); [Array]::Copy($t, 0, $Buf, $O, $Len) }
function Set-SimU128 { param([byte[]]$Buf, [int]$O, [double]$V) $bytes = [BitConverter]::GetBytes([uint64]$V); [Array]::Copy($bytes, 0, $Buf, $O, 8) }

function New-SimNvmeIdentify {
    param([int]$Vid, [string]$Model, [string]$Serial, [string]$Fw, [double]$Capacity)
    $d = New-Object byte[] 4096
    $b = [BitConverter]::GetBytes([uint16]$Vid); $d[0] = $b[0]; $d[1] = $b[1]; $d[2] = $b[0]; $d[3] = $b[1]
    Set-SimAscii $d 4 20 $Serial; Set-SimAscii $d 24 40 $Model; Set-SimAscii $d 64 8 $Fw
    $d[73] = 0x38; $d[74] = 0x25; $d[75] = 0x00
    $v = [BitConverter]::GetBytes([uint32]0x00010400); [Array]::Copy($v, 0, $d, 80, 4)
    $d[256] = 0x17; $d[266] = 0x57; $d[267] = 0x01; $d[268] = 0x61; $d[269] = 0x01
    Set-SimU128 $d 280 $Capacity
    $d[516] = 1
    return , $d
}

function New-SimNvmeHealth {
    param([int]$Used, [int]$Spare, [double]$Poh, [double]$Cycles, [double]$Unsafe, [double]$Media, [double]$WrittenTB, [int]$TempK = 310, [int]$CritWarn = 0)
    $d = New-Object byte[] 512
    $d[0] = $CritWarn; $d[1] = $TempK -band 0xFF; $d[2] = $TempK -shr 8; $d[3] = $Spare; $d[4] = 10; $d[5] = $Used
    Set-SimU128 $d 32 ($WrittenTB * 1.4 * 1e12 / 512000); Set-SimU128 $d 48 ($WrittenTB * 1e12 / 512000)
    Set-SimU128 $d 112 $Cycles; Set-SimU128 $d 128 $Poh; Set-SimU128 $d 144 $Unsafe; Set-SimU128 $d 160 $Media; Set-SimU128 $d 176 3
    $d[200] = 0x38; $d[201] = 0x01
    return , $d
}

function New-SimEdid {
    param([string]$Maker = 'BOE', [int]$Year = 2021, [string]$Part = 'NV140FHM-N4B')
    $e = New-Object byte[] 128
    $h = 0x00, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0x00; for ($i = 0; $i -lt 8; $i++) { $e[$i] = $h[$i] }
    $c = $Maker.ToCharArray()
    $m = (([int]$c[0] - 64) -shl 10) -bor (([int]$c[1] - 64) -shl 5) -bor ([int]$c[2] - 64)
    $e[8] = ($m -shr 8) -band 0xFF; $e[9] = $m -band 0xFF; $e[10] = 0x12; $e[11] = 0x08
    $e[16] = 12; $e[17] = $Year - 1990; $e[18] = 1; $e[19] = 4; $e[20] = 0x95; $e[21] = 31; $e[22] = 17
    $o = 54; $pc = 13865; $e[$o] = $pc -band 0xFF; $e[$o + 1] = $pc -shr 8
    $e[$o + 2] = 1920 -band 0xFF; $e[$o + 3] = 160; $e[$o + 4] = ((1920 -shr 8) -shl 4) -bor 0
    $e[$o + 5] = 1080 -band 0xFF; $e[$o + 6] = 31; $e[$o + 7] = ((1080 -shr 8) -shl 4) -bor 0
    $e[$o + 12] = 309 -band 0xFF; $e[$o + 13] = 174 -band 0xFF; $e[$o + 14] = ((309 -shr 8) -shl 4) -bor (174 -shr 8)
    foreach ($pair in @(@(72, "$Maker CQ"), @(90, $Part))) {
        $p = $pair[0]; $e[$p + 3] = 0xFE; $t = [Text.Encoding]::ASCII.GetBytes($pair[1] + "`n")
        for ($i = 0; $i -lt 13; $i++) { $e[$p + 5 + $i] = $(if ($i -lt $t.Length) { $t[$i] } else { 0x20 }) }
    }
    $e[108 + 3] = 0x10
    return , $e
}
