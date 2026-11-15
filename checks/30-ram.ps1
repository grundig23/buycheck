# BuyCheck – Arbeitsspeicher: Ausstattung und Test des freien RAM

$script:BCMemTypes = @{ 18 = 'DDR'; 19 = 'DDR2'; 20 = 'DDR2 FB-DIMM'; 24 = 'DDR3'; 26 = 'DDR4'; 27 = 'LPDDR'; 28 = 'LPDDR2'; 29 = 'LPDDR3'; 30 = 'LPDDR4'; 34 = 'DDR5'; 35 = 'LPDDR5' }
$script:BCFormFactors = @{ 1 = 'Sonstige'; 2 = 'Unbekannt'; 5 = 'Chip (verlötet)'; 9 = 'DIMM'; 11 = 'Chipreihe (verlötet)'; 13 = 'SO-DIMM (steckbar)'; 16 = 'Die (verlötet)'; 17 = 'CAMM' }

Register-BuyCheck -Id 'ram.info' -Category 'Arbeitsspeicher (RAM)' -Order 10 -RunOrder 30 -Seconds 5 `
    -Title 'RAM-Ausstattung' `
    -Description 'Zeigt Größe, Typ, Takt, Module und Steckplätze. Erkennt Single-Channel-Bestückung (nur ein Modul, bremst die integrierte Grafik) und verlöteten Speicher (nicht aufrüstbar). So lässt sich die Angabe in der Anzeige überprüfen.' `
    -Profiles @('quick', 'thorough', 'linux', 'auto') `
    -Run {
    $ms = [BuyCheck.SystemState]::MemoryStatus()
    $total = [double]$ms[0]
    $installedKB = [double][BuyCheck.SystemState]::InstalledMemoryKB()
    $installed = if ($installedKB -gt 0) { $installedKB * 1024 } else { $total }
    $devices = @(Get-BCSmbiosType 17)
    $arrays = @(Get-BCSmbiosType 16 | Where-Object { $_.Byte(5) -eq 3 })   # Verwendung: Systemspeicher
    $slots = 0
    foreach ($a in $arrays) { $n = $a.Word(0x0D); if ($n -gt 0) { $slots += $n } }
    $rows = New-Object 'System.Collections.Generic.List[object]'
    $populated = 0; $soldered = 0; $types = @()
    foreach ($d in $devices) {
        $size = $d.Word(0x0C)
        $mb = 0
        if ($size -eq 0x7FFF) { $mb = $d.Dword(0x1C) }
        elseif ($size -gt 0 -and $size -ne 0xFFFF) { $mb = if (($size -band 0x8000) -ne 0) { ($size -band 0x7FFF) / 1024 } else { $size } }
        $ff = $d.Byte(0x0E); $mt = $d.Byte(0x12)
        $speed = $d.Word(0x15); $conf = $d.Word(0x20)
        if ($mb -gt 0) {
            $populated++
            if (@(5, 11, 16) -contains $ff) { $soldered++ }
            if ($script:BCMemTypes.ContainsKey($mt)) { $types += $script:BCMemTypes[$mt] }
        }
        $rows.Add([pscustomobject]@{
                'Steckplatz' = "$($d.Str(0x10)) $($d.Str(0x11))".Trim()
                'Größe'      = if ($mb -gt 0) { Format-BCBytes ($mb * 1MB) -Binary } else { 'leer' }
                'Typ'        = if ($script:BCMemTypes.ContainsKey($mt)) { $script:BCMemTypes[$mt] } else { "$mt" }
                'Bauform'    = if ($script:BCFormFactors.ContainsKey($ff)) { $script:BCFormFactors[$ff] } else { "$ff" }
                'Takt'       = if ($speed -gt 0 -and $speed -ne 0xFFFF) { "$speed MT/s" + $(if ($conf -gt 0 -and $conf -ne $speed -and $conf -ne 0xFFFF) { " (läuft mit $conf)" } else { '' }) } else { '' }
                'Hersteller' = "$($d.Str(0x17))"
                'Teilenummer' = "$($d.Str(0x1A))".Trim()
            })
    }
    if ($rows.Count -eq 0) {
        foreach ($m in (Get-BCCim Win32_PhysicalMemory)) {
            $populated++
            $rows.Add([pscustomobject]@{ 'Steckplatz' = "$($m.DeviceLocator) $($m.BankLabel)".Trim(); 'Größe' = Format-BCBytes ([double]$m.Capacity) -Binary; 'Takt' = "$($m.Speed) MT/s"; 'Hersteller' = "$($m.Manufacturer)"; 'Teilenummer' = "$($m.PartNumber)".Trim() })
        }
    }
    Add-BCTable -Title 'Speichermodule' -Rows $rows.ToArray()
    $typeText = (@($types | Select-Object -Unique) -join '/')
    Set-BCSummary 'Arbeitsspeicher' ("{0} {1}{2}" -f (Format-BCBytes $installed -Binary), $typeText, $(if ($soldered -gt 0 -and $soldered -eq $populated) { ', verlötet' } else { '' })).Trim()
    Add-BCFacts -Title 'Übersicht' -Data ([ordered]@{
            'Installiert'               = Format-BCBytes $installed -Binary
            'Für Windows nutzbar'       = Format-BCBytes $total -Binary
            'Belegte Module / Steckplätze' = "$populated / $(if ($slots -gt 0) { $slots } else { '?' })"
            'Typ'                       = $typeText
        })
    Add-BCFinding -Level Info -Title ("Arbeitsspeicher: {0} {1}" -f (Format-BCBytes $installed -Binary), $typeText) -Detail "Bitte mit der Angabe in der Anzeige vergleichen."

    if ($installed -gt 0 -and ($installed - $total) / $installed -gt 0.25) {
        Add-BCFinding -Level Info -Title 'Ein großer Teil des RAM ist für Windows nicht nutzbar' -Detail ("Installiert {0}, nutzbar {1}. Meist für die integrierte Grafik reserviert; sonst BIOS-Einstellung prüfen." -f (Format-BCBytes $installed -Binary), (Format-BCBytes $total -Binary))
    }
    if ($populated -eq 1 -and $slots -ge 2 -and $soldered -eq 0) {
        Add-BCFinding -Level Info -Title 'Nur ein Speichermodul (Single-Channel)' -Detail 'Ein zweites Modul würde vor allem die Grafikleistung spürbar verbessern; ein Steckplatz ist frei.'
    }
    if ($soldered -gt 0 -and $soldered -eq $populated) {
        Add-BCFinding -Level Info -Title 'Arbeitsspeicher ist verlötet' -Detail 'Nicht aufrüstbar – die Größe muss für die geplante Nutzung reichen.'
    }
    if ($installed -lt 7.5GB) {
        Add-BCFinding -Level Info -Title 'Wenig Arbeitsspeicher für aktuelle Nutzung' -Detail 'Unter 8 GB wird es mit Windows 11 und modernen Browsern schnell eng.'
    }
}

Register-BuyCheck -Id 'ram.test' -Category 'Arbeitsspeicher (RAM)' -Order 20 -RunOrder 310 -Seconds 15 `
    -Title 'RAM-Test (freier Arbeitsspeicher)' `
    -Description 'Beschreibt den gerade freien Arbeitsspeicher mit verschiedenen Bitmustern und liest sie zurück. Findet defekte Speicherzellen in diesem Bereich. Den von Windows belegten Teil kann ein Test im laufenden System nicht prüfen; dafür gibt es nach dem Kauf die Windows-Speicherdiagnose oder MemTest86. Die würden jetzt den Startvorgang des fremden Laptops verändern und sind deshalb nicht enthalten.' `
    -Profiles @('thorough') `
    -Options @(@{ Key = 'minutes'; Label = 'Dauer'; Default = 3; Min = 1; Max = 30; SecondsPerUnit = 60; Unit = 'Minuten' }) `
    -Run {
    param($Options)
    $seconds = [int]([double]$Options['minutes'] * 60)
    $ms = [BuyCheck.SystemState]::MemoryStatus()
    $total = [double]$ms[0]; $avail = [double]$ms[1]
    $target = [math]::Min($avail * 0.8, $avail - 1.5GB)
    if (-not [Environment]::Is64BitProcess) { $target = [math]::Min($target, 1.2GB) }
    if ($target -lt 512MB) {
        Add-BCFinding -Level Info -Title 'Zu wenig freier Arbeitsspeicher für einen sinnvollen Test' -Detail ("Frei: {0}" -f (Format-BCBytes $avail -Binary))
        return
    }
    $mt = New-Object BuyCheck.MemTest
    $mt.Start([int64]$target, $seconds, [Environment]::ProcessorCount)
    $cancel = Wait-BCWorkload -Workload $mt -Activity 'RAM-Test' -Status {
        "{0} · reserviert {1} · geprüft {2} · Fehler: {3}" -f $mt.Phase, (Format-BCBytes $mt.AllocatedBytes -Binary), (Format-BCBytes $mt.TestedBytes -Binary), $mt.Errors
    } -Percent { $mt.ElapsedSeconds / $seconds * 100 }
    if ($mt.Error) { Add-BCFinding -Level Fehler -Title 'RAM-Test konnte nicht laufen' -Detail $mt.Error; return }
    $coverage = if ($total -gt 0) { [int]($mt.AllocatedBytes / $total * 100) } else { 0 }
    Add-BCFacts -Title 'Ergebnis' -Data ([ordered]@{
            'Getesteter Speicher' = "{0} ({1} % des nutzbaren RAM)" -f (Format-BCBytes $mt.AllocatedBytes -Binary), $coverage
            'Durchläufe'          = $mt.Pass
            'Geprüfte Datenmenge' = Format-BCBytes $mt.TestedBytes -Binary
            'Dauer'               = "$([int]$mt.ElapsedSeconds) s"
            'Fehler'              = $mt.Errors
        })
    if ($mt.Errors -gt 0) {
        Add-BCFinding -Level Kritisch -Title "Speicherfehler gefunden ($($mt.Errors))" -Detail (@($mt.ErrorSamples) -join ' · ') `
            -Advice 'Defekter Arbeitsspeicher führt zu Abstürzen und Datenfehlern. Bei verlötetem RAM ist das ein Mainboard-Schaden. Vom Kauf abraten.'
    } else {
        $lvl = if ($cancel) { 'Info' } else { 'OK' }
        Add-BCFinding -Level $lvl -Title ("Keine Speicherfehler in {0} getestetem RAM" -f (Format-BCBytes $mt.AllocatedBytes -Binary)) `
            -Detail ("{0} Durchläufe, Abdeckung ca. {1} % des RAM{2}." -f $mt.Pass, $coverage, $(if ($cancel) { ', vorzeitig abgebrochen' } else { '' }))
    }
}
