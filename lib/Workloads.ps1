# BuyCheck – Belastungs- und Messroutinen OHNE Compiler
#
# GRUNDSATZ: Das Gerät gehört (noch) nicht uns. Deshalb:
#  - Datenträger werden ausschließlich LESEND geöffnet (GENERIC_READ). Es wird nie etwas geschrieben.
#  - Der RAM-Test nutzt nur gerade freien Arbeitsspeicher innerhalb dieses Prozesses.
#  - Der CPU-Test erzeugt nur Rechenlast; die Überwachung (Temperatur, Abbruch) macht der Aufrufer.
#
# Die eigentliche Arbeit erledigen fertige Windows-/.NET-Funktionen (Hashing, Speicherkopie, Lesen),
# PowerShell steuert nur. Dadurch bleibt die Last echt, ohne dass etwas kompiliert werden muss.

# ============================================================== CPU-Last mit Rechenprüfung
# Jeder Thread berechnet immer wieder SHA-256 über denselben Datenblock und vergleicht das Ergebnis.
# Ein stabiler Prozessor liefert immer dasselbe – jede Abweichung ist ein Rechenfehler.
$script:BCStressWorker = @'
param($Sync, $Index, $Seed)
$data = [Array]::CreateInstance([byte], 262144)
$rnd = [Activator]::CreateInstance([System.Random], [object[]]@($Seed))
$rnd.NextBytes($data)
$hash = $null
try { $hash = [Activator]::CreateInstance([System.Security.Cryptography.SHA256Managed]) } catch { $hash = $null }
if ($null -eq $hash) { $hash = [Activator]::CreateInstance([System.Security.Cryptography.SHA1CryptoServiceProvider]) }
$ref = [Convert]::ToBase64String($hash.ComputeHash($data))
$n = 0
$err = 0
$Sync["s$Index"] = 1
while (-not $Sync['Stop']) {
    $h = [Convert]::ToBase64String($hash.ComputeHash($data))
    if ($h -ne $ref) { $err++; $Sync["e$Index"] = $err }
    $n++
    $Sync["u$Index"] = $n
}
'@

function New-BCStressPool {
    param([int]$Threads, [bool]$Light)
    $iss = $null
    if ($Light) {
        # Leere Sitzung ohne Cmdlets: spart auf schwachen Geräten Arbeitsspeicher und Startzeit
        $iss = [System.Management.Automation.Runspaces.InitialSessionState]::Create()
        $iss.LanguageMode = [System.Management.Automation.PSLanguageMode]::FullLanguage
    } else {
        $iss = [System.Management.Automation.Runspaces.InitialSessionState]::CreateDefault()
    }
    $pool = [System.Management.Automation.Runspaces.RunspaceFactory]::CreateRunspacePool(1, $Threads, $iss, $Host)
    $pool.Open()
    return $pool
}

function Start-BCCpuStress {
    param([int]$Threads)
    if ($Threads -lt 1) { $Threads = 1 }
    foreach ($light in @($true, $false)) {
        $sync = [hashtable]::Synchronized(@{ Stop = $false })
        $pool = $null
        try { $pool = New-BCStressPool -Threads $Threads -Light $light } catch { Write-BCDebug "Runspace-Pool (leicht=$light): $($_.Exception.Message)"; continue }
        $jobs = @()
        for ($i = 0; $i -lt $Threads; $i++) {
            $ps = [System.Management.Automation.PowerShell]::Create()
            $ps.RunspacePool = $pool
            [void]$ps.AddScript($script:BCStressWorker).AddArgument($sync).AddArgument($i).AddArgument(4242)
            $jobs += (New-BCObject @('PS', $ps, 'Handle', $ps.BeginInvoke()))
        }
        $stress = New-BCObject @('Sync', $sync, 'Pool', $pool, 'Jobs', $jobs, 'Threads', $Threads, 'Watch', ([Diagnostics.Stopwatch]::StartNew()))
        # Startkontrolle: laufen die Rechenthreads?
        $ok = $false
        for ($t = 0; $t -lt 40; $t++) {
            Start-Sleep -Milliseconds 100
            if ((Get-BCCpuStressUnits $stress) -gt 0) { $ok = $true; break }
            if (@($jobs | Where-Object { "$($_.PS.InvocationStateInfo.State)" -eq 'Failed' }).Count -gt 0) { break }
        }
        if ($ok) { return $stress }
        $why = @($jobs | ForEach-Object { "$($_.PS.InvocationStateInfo.Reason)" } | Where-Object { $_ }) -join ' | '
        Write-BCDebug "CPU-Last startete nicht (leicht=$light): $why"
        Stop-BCCpuStress $stress
    }
    throw 'Die Rechenlast konnte nicht gestartet werden.'
}

function Get-BCCpuStressUnits {
    param($Stress)
    $s = 0.0
    for ($i = 0; $i -lt $Stress.Threads; $i++) { $v = $Stress.Sync["u$i"]; if ($v) { $s += [double]$v } }
    return $s
}

function Get-BCCpuStressErrors {
    param($Stress)
    $s = 0
    for ($i = 0; $i -lt $Stress.Threads; $i++) { $v = $Stress.Sync["e$i"]; if ($v) { $s += [int]$v } }
    return $s
}

function Stop-BCCpuStress {
    param($Stress)
    if (-not $Stress) { return }
    $Stress.Sync['Stop'] = $true
    foreach ($j in @($Stress.Jobs)) {
        if (-not $j) { continue }
        try { [void]$j.PS.EndInvoke($j.Handle) } catch { }
        try { $j.PS.Dispose() } catch { }
    }
    try { $Stress.Pool.Close(); $Stress.Pool.Dispose() } catch { }
    try { $Stress.Watch.Stop() } catch { }
}

# ============================================================== RAM-Test (nur freier Arbeitsspeicher)
function Set-BCPattern {
    param([byte[]]$Buffer, [int]$Pattern, [int]$Seed)
    if ($Pattern -lt 0) {
        $r = New-Object System.Random $Seed
        $r.NextBytes($Buffer)
        return
    }
    $first = [math]::Min(4096, $Buffer.Length)
    for ($i = 0; $i -lt $first; $i++) { $Buffer[$i] = [byte]$Pattern }
    $filled = $first
    while ($filled -lt $Buffer.Length) {
        $n = [math]::Min($filled, $Buffer.Length - $filled)
        [Array]::Copy($Buffer, 0, $Buffer, $filled, $n)
        $filled += $n
    }
}

function Invoke-BCMemTest {
    param([double]$TargetBytes, [int]$Seconds)
    $chunk = 16MB
    $res = New-BCObject @('AllocatedBytes', 0.0, 'TestedBytes', 0.0, 'Errors', 0, 'Passes', 0, 'Seconds', 0.0, 'Cancelled', $false,
        'Error', $null, 'Samples', (New-Object 'System.Collections.Generic.List[string]'))
    $chunks = New-Object 'System.Collections.Generic.List[object]'
    $ref = $null
    $sw = [Diagnostics.Stopwatch]::StartNew()
    try {
        while ($res.AllocatedBytes + $chunk -le $TargetBytes) {
            $c = $null
            try { $c = New-Object byte[] $chunk } catch { $c = $null }
            if ($null -eq $c) { break }
            $chunks.Add($c)
            $res.AllocatedBytes += $chunk
            if (($chunks.Count % 8) -eq 0) {
                Write-BCProgress ('RAM-Test: reserviere freien Speicher ... {0}' -f (Format-BCBytes $res.AllocatedBytes -Binary))
                if (Test-BCEscape) { $res.Cancelled = $true; break }
            }
        }
        if ($chunks.Count -eq 0) { $res.Error = 'Es konnte kein freier Arbeitsspeicher reserviert werden.'; return $res }
        $ref = New-Object byte[] $chunk
        $patterns = @(0x00, 0xFF, 0x55, 0xAA, -1)
        while (-not $res.Cancelled) {
            $res.Passes++
            $pi = 0
            foreach ($p in $patterns) {
                $pi++
                Set-BCPattern -Buffer $ref -Pattern $p -Seed (1000 + $res.Passes)
                # erst alles beschreiben, dann alles prüfen (so liegen die Daten eine Weile im Speicher)
                for ($i = 0; $i -lt $chunks.Count; $i++) {
                    [Array]::Copy($ref, [byte[]]$chunks[$i], $chunk)
                    if (($i % 16) -eq 0) {
                        Write-BCProgress ('RAM-Test Durchlauf {0}, Muster {1}/5: schreiben · {2} getestet · Fehler: {3}  (Esc = abbrechen)' -f $res.Passes, $pi, (Format-BCBytes $res.AllocatedBytes -Binary), $res.Errors)
                        if (Test-BCEscape) { $res.Cancelled = $true; break }
                    }
                }
                if ($res.Cancelled) { break }
                for ($i = 0; $i -lt $chunks.Count; $i++) {
                    $m = Compare-BCBytes ([byte[]]$chunks[$i]) $ref $chunk
                    if ($m -ge 0) {
                        $res.Errors++
                        if ($res.Samples.Count -lt 20) {
                            $exp = $ref[$m]; $got = ([byte[]]$chunks[$i])[$m]
                            $res.Samples.Add(('Block {0}, Byte {1}: erwartet 0x{2:X2}, gelesen 0x{3:X2}' -f $i, $m, $exp, $got))
                        }
                    }
                    if (($i % 16) -eq 0) {
                        Write-BCProgress ('RAM-Test Durchlauf {0}, Muster {1}/5: prüfen · {2} getestet · Fehler: {3}  (Esc = abbrechen)' -f $res.Passes, $pi, (Format-BCBytes $res.AllocatedBytes -Binary), $res.Errors)
                        if (Test-BCEscape) { $res.Cancelled = $true; break }
                    }
                }
                if ($res.Cancelled) { break }
                $res.TestedBytes += $res.AllocatedBytes
            }
            if ($sw.Elapsed.TotalSeconds -ge $Seconds) { break }
        }
    } catch {
        $res.Error = "$($_.Exception.Message)"
    } finally {
        $chunks.Clear()
        $ref = $null
        [GC]::Collect()
        $res.Seconds = $sw.Elapsed.TotalSeconds
        Complete-BCProgress
    }
    return $res
}

# ============================================================== Datenträger lesen (NUR LESEND)
function Open-BCDiskForRead {
    param([int]$Disk, [int]$Flags)
    if (-not (Initialize-BCNative)) { throw 'Windows-Funktionen nicht verfügbar.' }
    $h = Open-BCDevice "\\.\PhysicalDrive$Disk" $script:BCGenericRead $Flags
    if (-not $h) { throw "Datenträger $Disk lässt sich nicht lesend öffnen (Windows-Fehler $script:BCLastWin32)." }
    return $h
}

# Genaue Größe über IOCTL_DISK_GET_LENGTH_INFO (braucht Lesezugriff)
function Get-BCDiskLength {
    param($Handle)
    $b = Invoke-BCIoctl $Handle 0x0007405C $null 8
    if ($null -eq $b) { return 0.0 }
    return [double][BitConverter]::ToInt64($b, 0)
}

# Sequentielles Lesen und zufällige 4K-Lesezugriffe (Warteschlangentiefe 1)
function Invoke-BCDiskBenchmark {
    param([int]$Disk, [int]$SeqMB = 1536, [int]$RandomSeconds = 8, [int]$SectorBytes = 512)
    $res = New-BCObject @('SeqMBps', 0.0, 'RandIops', 0.0, 'RandMBps', 0.0, 'RandAvgMs', 0.0, 'RandMaxMs', 0.0, 'Error', $null, 'Cancelled', $false, 'DiskBytes', 0.0)
    $h = $null; $buf = [IntPtr]::Zero
    try {
        $h = Open-BCDiskForRead -Disk $Disk -Flags $script:BCFlagNoBuffering
        $size = Get-BCDiskLength $h
        $res.DiskBytes = $size
        if ($size -le 0) { throw 'Größe des Datenträgers nicht ermittelbar.' }
        $block = 4MB
        $buf = New-BCAlignedBuffer $block
        $freq = [double][Diagnostics.Stopwatch]::Frequency
        $newPos = [int64]0
        $got = 0
        # 1) Sequentiell: drei Bereiche im vorderen Teil (dort liegen meist echte Daten; leere Bereiche würden schönen)
        $perRegion = [int64]([math]::Floor(($SeqMB * 1MB / 3) / $block)) * $block
        $total = 0.0
        $t0 = [Diagnostics.Stopwatch]::GetTimestamp()
        $lastUi = $t0
        foreach ($start in @(0.02, 0.08, 0.15)) {
            $pos = [int64]([math]::Floor($size * $start / $block)) * $block
            [void]$script:BCW32::SetFilePointerEx($h, $pos, [ref]$newPos, 0)
            $done = 0.0
            while ($done -lt $perRegion -and ($pos + $block) -le $size) {
                $ok = $script:BCW32::ReadFile($h, $buf, $block, [ref]$got, [IntPtr]::Zero); $err = [System.Runtime.InteropServices.Marshal]::GetLastWin32Error()
                if (-not $ok -or $got -ne $block) { throw ('Lesefehler bei {0} (Windows-Fehler {1})' -f (Format-BCBytes $pos), $err) }
                $done += $got; $pos += $got; $total += $got
                $now = [Diagnostics.Stopwatch]::GetTimestamp()
                if (($now - $lastUi) / $freq -ge 0.5) {
                    $lastUi = $now
                    Write-BCProgress ('Lesegeschwindigkeit Datenträger {0}: sequentiell {1} von {2}  (Esc = abbrechen)' -f $Disk, (Format-BCBytes $total), (Format-BCBytes ($perRegion * 3)))
                    if (Test-BCEscape) { $res.Cancelled = $true; return $res }
                }
            }
        }
        $sec = ([Diagnostics.Stopwatch]::GetTimestamp() - $t0) / $freq
        if ($total -gt 0 -and $sec -gt 0) { $res.SeqMBps = $total / 1MB / $sec }

        # 2) Zufällige 4K-Lesezugriffe in der vorderen Hälfte; gemessen wird nur der Lesevorgang selbst
        $small = [math]::Max(4096, $SectorBytes)
        $range = [int64]([math]::Floor(($size / 2) / $small))
        $rnd = New-Object System.Random 42
        $ops = 0; $sumTicks = 0.0; $maxTicks = 0.0
        $tEnd = [Diagnostics.Stopwatch]::GetTimestamp() + $RandomSeconds * $freq
        while ([Diagnostics.Stopwatch]::GetTimestamp() -lt $tEnd) {
            $off = [int64]([math]::Floor($rnd.NextDouble() * $range)) * $small
            [void]$script:BCW32::SetFilePointerEx($h, $off, [ref]$newPos, 0)
            $a = [Diagnostics.Stopwatch]::GetTimestamp()
            $ok = $script:BCW32::ReadFile($h, $buf, $small, [ref]$got, [IntPtr]::Zero); $err = [System.Runtime.InteropServices.Marshal]::GetLastWin32Error()
            $d = [Diagnostics.Stopwatch]::GetTimestamp() - $a
            if (-not $ok) { throw ('Lesefehler bei {0} (Windows-Fehler {1})' -f (Format-BCBytes $off), $err) }
            $ops++; $sumTicks += $d
            if ($d -gt $maxTicks) { $maxTicks = $d }
            if (($ops % 200) -eq 0) {
                Write-BCProgress ('Lesegeschwindigkeit Datenträger {0}: zufällige 4K-Zugriffe ... {1}  (Esc = abbrechen)' -f $Disk, $ops)
                if (Test-BCEscape) { $res.Cancelled = $true; return $res }
            }
        }
        if ($ops -gt 0) {
            $res.RandAvgMs = $sumTicks / $ops / $freq * 1000
            $res.RandMaxMs = $maxTicks / $freq * 1000
            if ($res.RandAvgMs -gt 0) { $res.RandIops = 1000 / $res.RandAvgMs }
            $res.RandMBps = $res.RandIops * $small / 1MB
        }
    } catch {
        $res.Error = "$($_.Exception.Message)"
    } finally {
        Remove-BCAlignedBuffer $buf
        Close-BCHandle $h
        Complete-BCProgress
    }
    return $res
}

# Liest den Datenträger abschnittsweise komplett (oder jeden n-ten Abschnitt) und protokolliert Fehler, Hänger, langsame Bereiche
function Invoke-BCDiskScan {
    param([int]$Disk, [int]$Stride = 1, [int]$MaxSeconds = 1200, [int]$SectorBytes = 512)
    $res = New-BCObject @('DiskBytes', 0.0, 'PlannedBytes', 0.0, 'BytesRead', 0.0, 'ReadErrors', 0, 'MaxBlockMs', 0.0, 'SlowBlocks', 0,
        'Aborted', $false, 'AbortReason', '', 'Error', $null, 'Seconds', 0.0, 'Cancelled', $false,
        'ErrorOffsets', (New-Object 'System.Collections.Generic.List[double]'),
        'SegmentMBps', (New-Object 'System.Collections.Generic.List[double]'),
        'SegmentOffsets', (New-Object 'System.Collections.Generic.List[double]'))
    $h = $null; $buf = [IntPtr]::Zero
    $sw = [Diagnostics.Stopwatch]::StartNew()
    try {
        $h = Open-BCDiskForRead -Disk $Disk -Flags ($script:BCFlagNoBuffering -bor $script:BCFlagSequential)
        $size = Get-BCDiskLength $h
        if ($size -le 0) { throw 'Größe des Datenträgers nicht ermittelbar.' }
        $res.DiskBytes = $size
        $block = 4MB
        $segBytes = 256MB
        $gran = [math]::Max(4096, $SectorBytes)
        $buf = New-BCAlignedBuffer $block
        $freq = [double][Diagnostics.Stopwatch]::Frequency
        if ($Stride -lt 1) { $Stride = 1 }
        $segments = [int64][math]::Ceiling($size / $segBytes)
        $planned = [int64][math]::Ceiling($segments / $Stride)
        $res.PlannedBytes = [math]::Min($size, $planned * $segBytes)
        $newPos = [int64]0
        $got = 0
        $lastUi = [Diagnostics.Stopwatch]::GetTimestamp()
        $speedBytes = 0.0; $speedT = $lastUi; $mbps = 0
        for ($seg = 0; $seg -lt $segments; $seg += $Stride) {
            $segStart = [double]$seg * $segBytes
            $segEnd = [math]::Min($size, $segStart + $segBytes)
            $segT0 = [Diagnostics.Stopwatch]::GetTimestamp()
            $segRead = 0.0
            $pos = $segStart
            while ($pos -lt $segEnd) {
                $toRead = [int][math]::Min($block, $segEnd - $pos)
                $toRead = [int]([math]::Floor($toRead / $gran) * $gran)
                if ($toRead -le 0) { break }
                [void]$script:BCW32::SetFilePointerEx($h, [int64]$pos, [ref]$newPos, 0)
                $a = [Diagnostics.Stopwatch]::GetTimestamp()
                $ok = $script:BCW32::ReadFile($h, $buf, $toRead, [ref]$got, [IntPtr]::Zero)
                $ms = ([Diagnostics.Stopwatch]::GetTimestamp() - $a) / $freq * 1000
                if (-not $ok -or $got -ne $toRead) {
                    $res.ReadErrors++
                    if ($res.ErrorOffsets.Count -lt 200) { $res.ErrorOffsets.Add($pos) }
                    if ($res.ReadErrors -ge 50) { $res.Aborted = $true; $res.AbortReason = 'zu viele Lesefehler (50)'; return $res }
                    $pos += $toRead
                    continue
                }
                if ($ms -gt $res.MaxBlockMs) { $res.MaxBlockMs = $ms }
                if ($ms -gt 1000) { $res.SlowBlocks++ }
                $pos += $got; $segRead += $got; $res.BytesRead += $got; $speedBytes += $got
                $now = [Diagnostics.Stopwatch]::GetTimestamp()
                if (($now - $lastUi) / $freq -ge 1) {
                    $mbps = $speedBytes / 1MB / (($now - $speedT) / $freq)
                    $speedBytes = 0.0; $speedT = $now; $lastUi = $now
                    $pct = 0; if ($res.PlannedBytes -gt 0) { $pct = [int]($res.BytesRead / $res.PlannedBytes * 100) }
                    Write-BCProgress ('Lesetest Datenträger {0}: {1} % · {2} von {3} · {4} MB/s · Lesefehler: {5}  (Esc = abbrechen)' -f $Disk, $pct, (Format-BCBytes $res.BytesRead), (Format-BCBytes $res.PlannedBytes), [int]$mbps, $res.ReadErrors)
                    if (Test-BCEscape) { $res.Cancelled = $true; $res.Aborted = $true; $res.AbortReason = 'vom Benutzer abgebrochen'; return $res }
                    if ($MaxSeconds -gt 0 -and $sw.Elapsed.TotalSeconds -gt $MaxSeconds) { $res.Aborted = $true; $res.AbortReason = 'Zeitlimit erreicht'; return $res }
                }
            }
            $segSec = ([Diagnostics.Stopwatch]::GetTimestamp() - $segT0) / $freq
            if ($segRead -gt 0 -and $segSec -gt 0) { $res.SegmentMBps.Add($segRead / 1MB / $segSec); $res.SegmentOffsets.Add($segStart) }
        }
    } catch {
        $res.Error = "$($_.Exception.Message)"
    } finally {
        Remove-BCAlignedBuffer $buf
        Close-BCHandle $h
        $res.Seconds = $sw.Elapsed.TotalSeconds
        Complete-BCProgress
    }
    return $res
}
