# BuyCheck – Datenträger: Gesundheit (NVMe/SMART), Fälschungsindizien, Lesegeschwindigkeit, Oberflächen-Lesetest
# Alle Zugriffe sind LESEND. Es wird nichts auf die Datenträger geschrieben.

# Marken mit eigenem Controller: Modellname -> erwartete PCI-Hersteller-ID des NVMe-Controllers
$script:BCBrandVid = @(
    @{ Pattern = '(?i)\bSAMSUNG\b|^MZ[0-9A-Z]{6,}'; Vids = @('144D'); Brand = 'Samsung'; Strict = $true },
    @{ Pattern = '(?i)\bWDC\b|\bWD[ _]|Western Digital|SanDisk'; Vids = @('15B7', '1B96', '1C58'); Brand = 'Western Digital/SanDisk'; Strict = $false },
    @{ Pattern = '(?i)SK ?hynix|^HFM\d|^HFS\d'; Vids = @('1C5C'); Brand = 'SK hynix'; Strict = $false },
    @{ Pattern = '(?i)KIOXIA|TOSHIBA|^KXG|^KBG|^THNSN'; Vids = @('1179', '1E0F'); Brand = 'Kioxia/Toshiba'; Strict = $false },
    @{ Pattern = '(?i)^Micron|^MTFD'; Vids = @('1344'); Brand = 'Micron'; Strict = $false },
    @{ Pattern = '(?i)^INTEL|SSDPEK|SSDPE[0-9]'; Vids = @('8086', '025E'); Brand = 'Intel'; Strict = $false },
    @{ Pattern = '(?i)Solidigm'; Vids = @('025E', '8086'); Brand = 'Solidigm'; Strict = $false }
)

$script:BCNvmeWarnBits = @{
    0 = 'Reserveblöcke unter dem Grenzwert'; 1 = 'Temperatur außerhalb des Grenzwerts'
    2 = 'Zuverlässigkeit durch Medien-/interne Fehler beeinträchtigt'; 3 = 'Laufwerk im Nur-Lese-Modus'
    4 = 'Sicherungsspeicher (flüchtiger Cache) defekt'; 5 = 'Persistenter Speicherbereich schreibgeschützt'
}

function Get-BCDiskLabel { param($Disk) return "Datenträger $($Disk.Number): $($Disk.Model) ($(Format-BCBytes $Disk.SizeBytes))" }

function Test-BCNvmeBrand {
    param($Disk)
    $id = $Disk.Identify
    if (-not $id) { return }
    $vid = $id.VendorIdHex
    $vname = Get-BCVendorName $vid
    foreach ($b in $script:BCBrandVid) {
        if ($Disk.Model -match $b.Pattern -or "$($id.Model)" -match $b.Pattern) {
            if ($b.Vids -contains $vid) {
                Add-BCFinding -Level OK -Title "Controller passt zur Marke ($($b.Brand))" -Detail "PCI-Hersteller-ID $vid$(if ($vname) { " = $vname" })"
            } elseif ($b.Strict) {
                Add-BCFinding -Level Kritisch -Title "Verdacht auf gefälschte $($b.Brand)-SSD" `
                    -Detail "Das Laufwerk heißt '$($Disk.Model)', der Controller stammt aber nicht von $($b.Brand) (PCI-Hersteller-ID $vid$(if ($vname) { " = $vname" }))." `
                    -Advice 'Echte Samsung-SSDs haben immer einen Samsung-Controller (ID 144D). Bekannte Fälschungen nutzen z. B. Maxio-Controller (1E4B).'
            } else {
                Add-BCFinding -Level Warnung -Title "Controller passt nicht zur Marke $($b.Brand)" `
                    -Detail "Modell '$($Disk.Model)', Controller-ID $vid$(if ($vname) { " ($vname)" }). Bei dieser Marke ungewöhnlich." `
                    -Advice 'Modell und Herkunft der SSD prüfen; ggf. Hersteller-Tool zur Echtheitsprüfung nutzen.'
            }
            return
        }
    }
    Add-BCFinding -Level Info -Title "SSD-Controller: $(if ($vname) { $vname } else { 'Hersteller-ID ' + $vid })" -Detail "Marke '$($Disk.Model)' nutzt keinen eindeutig zuordenbaren Eigen-Controller – kein Abgleich möglich."
}

function Test-BCNvmeHealth {
    param($Disk)
    $h = $Disk.Nvme; $id = $Disk.Identify
    $tb = $h.TerabytesWritten
    $facts = [ordered]@{
        'Verbrauchte Lebensdauer (Percentage Used)' = "$($h.PercentageUsed) %"
        'Reserveblöcke (Available Spare)'           = "$($h.AvailableSpare) % (Grenzwert $($h.AvailableSpareThreshold) %)"
        'Kritische Warnungen'                       = if ($h.CriticalWarning -eq 0) { 'keine' } else { '0x{0:X2}' -f $h.CriticalWarning }
        'Medien-/Datenintegritätsfehler'            = Format-BCNum $h.MediaErrors
        'Einträge im Fehlerprotokoll'               = Format-BCNum $h.ErrorLogEntries
        'Betriebsstunden'                           = Format-BCHours $h.PowerOnHours
        'Einschaltvorgänge'                         = Format-BCNum $h.PowerCycles
        'Unsichere Abschaltungen'                   = Format-BCNum $h.UnsafeShutdowns
        'Geschriebene Daten'                        = (Format-BCNum $tb 2) + ' TB'
        'Gelesene Daten'                            = (Format-BCNum $h.TerabytesRead 2) + ' TB'
        'Temperatur jetzt'                          = if (-not [double]::IsNaN($h.TemperatureCelsius)) { "$([int]$h.TemperatureCelsius) °C" } else { '' }
        'Minuten über Warn-/Kritisch-Temperatur'    = "$($h.WarningTempMinutes) / $($h.CriticalTempMinutes)"
    }
    if ($id) {
        $facts['Modell laut Controller'] = $id.Model
        $facts['Seriennummer laut Controller'] = $id.SerialNumber
        $facts['Firmware'] = $id.Firmware
        $facts['Controller-Hersteller (PCI-ID)'] = "$($id.VendorIdHex)$(if (Get-BCVendorName $id.VendorIdHex) { ' = ' + (Get-BCVendorName $id.VendorIdHex) })"
        $facts['NVMe-Version'] = $id.NvmeVersion
        if ($id.TotalNvmCapacityBytes -gt 0) { $facts['Physische Kapazität laut Controller'] = Format-BCBytes $id.TotalNvmCapacityBytes }
    }
    Add-BCFacts -Title "NVMe-Gesundheitswerte – $(Get-BCDiskLabel $Disk)" -Data $facts

    if ($h.CriticalWarning -ne 0) {
        $bits = @()
        foreach ($k in $script:BCNvmeWarnBits.Keys) { if (($h.CriticalWarning -band (1 -shl $k)) -ne 0) { $bits += $script:BCNvmeWarnBits[$k] } }
        Add-BCFinding -Level Kritisch -Title 'SSD meldet kritische Warnung' -Detail ($bits -join ' · ') -Advice 'Die SSD selbst meldet einen ernsten Zustand. Ersatz einplanen bzw. vom Kauf abraten.'
    }
    if ($h.AvailableSpareThreshold -gt 0 -and $h.AvailableSpare -lt $h.AvailableSpareThreshold) {
        Add-BCFinding -Level Kritisch -Title "Reserveblöcke aufgebraucht ($($h.AvailableSpare) % < Grenzwert $($h.AvailableSpareThreshold) %)" -Advice 'SSD steht kurz vor dem Ausfall bzw. Nur-Lese-Modus.'
    } elseif ($h.AvailableSpare -lt 50) {
        Add-BCFinding -Level Warnung -Title "Nur noch $($h.AvailableSpare) % Reserveblöcke" -Advice 'Viele Blöcke wurden bereits ersetzt – SSD altert stark.'
    } elseif ($h.AvailableSpare -lt 90) {
        Add-BCFinding -Level Info -Title "Reserveblöcke: $($h.AvailableSpare) %" -Detail 'Einige Blöcke wurden bereits ersetzt.'
    }
    $pu = [int]$h.PercentageUsed
    $left = [math]::Max(0, 100 - $pu)
    if ($pu -ge 90) { Add-BCFinding -Level Kritisch -Title "SSD-Lebensdauer weitgehend verbraucht ($pu % verbraucht)" -Advice 'Ersatz-SSD direkt einplanen (Kosten in den Preis einrechnen).' }
    elseif ($pu -ge 70) { Add-BCFinding -Level Warnung -Title "SSD stark genutzt ($pu % der Lebensdauer verbraucht)" -Advice 'Funktioniert noch, aber Ersatz in absehbarer Zeit einplanen.' }
    elseif ($pu -ge 30) { Add-BCFinding -Level Info -Title "SSD deutlich genutzt ($pu % der Lebensdauer verbraucht)" -Detail "Bei normaler Heimnutzung reicht der Rest meist noch viele Jahre. Geschrieben: $(Format-BCNum $tb 1) TB." }
    else { Add-BCFinding -Level OK -Title "SSD-Verschleiß gering ($pu % verbraucht, ca. $left % übrig)" -Detail "Geschrieben: $(Format-BCNum $tb 1) TB · Betriebsstunden: $(Format-BCNum $h.PowerOnHours)" }

    if ($h.MediaErrors -gt 0) {
        Add-BCFinding -Level Kritisch -Title "Nicht korrigierbare Datenfehler aufgetreten ($(Format-BCNum $h.MediaErrors))" `
            -Advice 'Die SSD konnte Daten nicht fehlerfrei lesen/schreiben. Deutliches Ausfallrisiko.'
    } else {
        Add-BCFinding -Level OK -Title 'Keine Medien-/Datenintegritätsfehler'
    }
    if ($h.ErrorLogEntries -gt 0) {
        Add-BCFinding -Level Info -Title "Fehlerprotokoll enthält $(Format-BCNum $h.ErrorLogEntries) Einträge" -Detail 'Für sich genommen meist harmlos (z. B. vom Betriebssystem abgelehnte Befehle); nur zusammen mit Medienfehlern kritisch.'
    }
    if ($h.UnsafeShutdowns -gt 100 -and $h.PowerCycles -gt 0 -and ($h.UnsafeShutdowns / $h.PowerCycles) -gt 0.2) {
        Add-BCFinding -Level Info -Title "Viele unsichere Abschaltungen ($(Format-BCNum $h.UnsafeShutdowns) bei $(Format-BCNum $h.PowerCycles) Starts)" -Detail 'Hinweis auf häufiges hartes Ausschalten oder leer gelaufenen Akku.'
    }
    if (-not [double]::IsNaN($h.TemperatureCelsius) -and $h.TemperatureCelsius -ge 70) {
        Add-BCFinding -Level Warnung -Title "SSD ist sehr warm ($([int]$h.TemperatureCelsius) °C)" -Advice 'Kühlung/Belüftung prüfen.'
    }
    if ($h.CriticalTempMinutes -gt 0) {
        Add-BCFinding -Level Warnung -Title "SSD war $($h.CriticalTempMinutes) Minuten über der kritischen Temperatur" -Advice 'Hitze verkürzt die Lebensdauer; Kühlung des Geräts prüfen.'
    } elseif ($h.WarningTempMinutes -gt 600) {
        Add-BCFinding -Level Info -Title "SSD war $($h.WarningTempMinutes) Minuten über der Warntemperatur"
    }

    Test-BCNvmeBrand -Disk $Disk
    if ($id -and $id.TotalNvmCapacityBytes -gt 0 -and $Disk.SizeBytes -gt $id.TotalNvmCapacityBytes * 1.02) {
        Add-BCFinding -Level Kritisch -Title 'Gemeldete Größe ist größer als der physische Speicher' `
            -Detail ("Windows sieht {0}, der Controller meldet nur {1} physischen Speicher." -f (Format-BCBytes $Disk.SizeBytes), (Format-BCBytes $id.TotalNvmCapacityBytes)) `
            -Advice 'Typisches Merkmal einer Kapazitätsfälschung. Vom Kauf abraten.'
    }
    return [pscustomobject]@{ PowerOnHours = $h.PowerOnHours; TBWritten = $tb; PowerCycles = $h.PowerCycles; LifeLeft = $left }
}

function Test-BCSataHealth {
    param($Disk)
    $attrs = @($Disk.Smart.Attributes)
    $get = { param($i) $attrs | Where-Object { $_.Id -eq $i } | Select-Object -First 1 }
    $rows = $attrs | ForEach-Object {
        [pscustomobject]@{ 'ID' = $_.Id; 'Attribut' = $_.Name; 'Aktuell' = $_.Current; 'Schlechtester' = $_.Worst; 'Grenzwert' = $_.Threshold; 'Rohwert' = $_.Raw }
    }
    Add-BCTable -Title "SMART-Werte – $(Get-BCDiskLabel $Disk)" -Rows @($rows)
    $isSsd = $Disk.IsSsd

    if ($Disk.Smart.PredictFailure) {
        Add-BCFinding -Level Kritisch -Title 'Laufwerk sagt selbst einen Ausfall voraus (SMART-Status)' -Advice 'Ersatz einplanen bzw. vom Kauf abraten.'
    }
    $failed = @($attrs | Where-Object { $_.Threshold -gt 0 -and $_.Current -le $_.Threshold })
    foreach ($a in $failed) {
        Add-BCFinding -Level Kritisch -Title "SMART-Grenzwert unterschritten: $($a.Name) (ID $($a.Id))" -Detail "Aktuell $($a.Current), Grenzwert $($a.Threshold)."
    }
    $bad = 0
    $a5 = & $get 5
    if ($a5 -and $a5.Raw32 -gt 0) {
        $lvl = if ($a5.Raw32 -ge 50) { 'Kritisch' } else { 'Warnung' }
        Add-BCFinding -Level $lvl -Title "$(Format-BCNum $a5.Raw32) ersetzte Sektoren/Blöcke" -Advice 'Das Laufwerk hat bereits defekte Bereiche ausgetauscht.'; $bad++
    }
    $a187 = & $get 187
    if ($a187 -and $a187.Raw32 -gt 0) { Add-BCFinding -Level Kritisch -Title "$(Format-BCNum $a187.Raw32) nicht korrigierbare Fehler gemeldet (ID 187)" -Advice 'Backblaze tauscht Laufwerke ab dem ersten solchen Fehler aus.'; $bad++ }
    $a197 = & $get 197
    if ($a197 -and $a197.Raw32 -gt 0) {
        $lvl = if ($isSsd) { 'Warnung' } else { 'Kritisch' }
        Add-BCFinding -Level $lvl -Title "$(Format-BCNum $a197.Raw32) schwebende (unlesbare) Sektoren (ID 197)"; $bad++
    }
    $a198 = & $get 198
    if ($a198 -and $a198.Raw32 -gt 0) { Add-BCFinding -Level Kritisch -Title "$(Format-BCNum $a198.Raw32) nicht korrigierbare Sektoren (ID 198)"; $bad++ }
    foreach ($i in @(171, 172, 181, 182)) {
        $a = & $get $i
        if ($a -and $a.Raw32 -gt 0) { Add-BCFinding -Level Warnung -Title "$($a.Name): $(Format-BCNum $a.Raw32) (ID $i)"; $bad++ }
    }
    if (-not $isSsd) {
        $a10 = & $get 10
        if ($a10 -and $a10.Raw32 -gt 0) { Add-BCFinding -Level Warnung -Title "Motor-Anlaufprobleme (ID 10): $(Format-BCNum $a10.Raw32)"; $bad++ }
        $a188 = & $get 188
        if ($a188 -and $a188.Raw32 -gt 0) { Add-BCFinding -Level Info -Title "Befehls-Timeouts (ID 188): $(Format-BCNum $a188.Raw32)" }
    }
    $a199 = & $get 199
    if ($a199 -and $a199.Raw32 -gt 0) { Add-BCFinding -Level Info -Title "Übertragungsfehler (CRC, ID 199): $(Format-BCNum $a199.Raw32)" -Detail 'Meist Stecker/Kabel, kein Verschleiß.' }
    if ($bad -eq 0 -and $failed.Count -eq 0) { Add-BCFinding -Level OK -Title 'Keine Fehlerzähler auffällig (ersetzte/defekte Sektoren, unkorrigierbare Fehler)' }

    # Restlebensdauer (normalisierter Wert, je nach Hersteller unterschiedliche ID)
    $life = $null; $lifeId = $null
    foreach ($i in @(231, 202, 169, 177, 233)) {
        $a = & $get $i
        if ($a -and $a.Current -gt 0 -and $a.Current -le 100) { $life = [int]$a.Current; $lifeId = $i; break }
    }
    if ($null -eq $life -and $Disk.Reliability -and $null -ne $Disk.Reliability.Wear) { $life = 100 - [int]$Disk.Reliability.Wear; $lifeId = 'Windows' }
    if ($null -ne $life -and $isSsd) {
        if ($life -lt 10) { Add-BCFinding -Level Kritisch -Title "SSD-Restlebensdauer nur noch ca. $life % (Quelle: $lifeId)" -Advice 'Ersatz einplanen.' }
        elseif ($life -lt 30) { Add-BCFinding -Level Warnung -Title "SSD-Restlebensdauer ca. $life % (Quelle: $lifeId)" }
        elseif ($life -lt 70) { Add-BCFinding -Level Info -Title "SSD-Restlebensdauer ca. $life % (Quelle: $lifeId)" }
        else { Add-BCFinding -Level OK -Title "SSD-Restlebensdauer ca. $life % (Quelle: $lifeId)" }
    }
    $poh = $null; $a9 = & $get 9
    if ($a9) { $poh = [double]$a9.Raw32 }
    $cycles = $null; $a12 = & $get 12
    if ($a12) { $cycles = [double]$a12.Raw32 }
    $tb = $null
    $a241 = & $get 241
    if ($a241 -and $a241.Raw -gt 0) { $tb = [double]$a241.Raw * 512 / 1e12 }
    $a194 = & $get 194
    $facts = [ordered]@{
        'Typ'              = if ($isSsd) { 'SSD (SATA)' } else { 'Festplatte (HDD)' }
        'Betriebsstunden'  = if ($null -ne $poh) { Format-BCHours $poh } else { '' }
        'Einschaltvorgänge' = if ($null -ne $cycles) { Format-BCNum $cycles } else { '' }
        'Geschriebene Daten (Annahme 512-Byte-LBAs)' = if ($null -ne $tb) { (Format-BCNum $tb 2) + ' TB' } else { '' }
        'Temperatur'       = if ($a194) { "$($a194.RawLow) °C" } else { '' }
    }
    Add-BCFacts -Title 'Kennzahlen' -Data $facts
    if (-not $isSsd) {
        Add-BCFinding -Level Info -Title 'Festplatte (HDD) statt SSD' -Detail 'Deutlich langsamer und stoßempfindlicher. Ein Umbau auf SSD ist meist günstig und lohnt sich (in den Preis einrechnen).'
    }
    return [pscustomobject]@{ PowerOnHours = $poh; TBWritten = $tb; PowerCycles = $cycles; LifeLeft = $life }
}

function Test-BCReliabilityOnly {
    param($Disk)
    $r = $Disk.Reliability
    Add-BCFacts -Title "Windows-Zuverlässigkeitszähler – $(Get-BCDiskLabel $Disk)" -Data ([ordered]@{
            'Verschleiß (Wear)'          = if ($null -ne $r.Wear) { "$($r.Wear) %" } else { '' }
            'Betriebsstunden'            = if ($null -ne $r.PowerOnHours) { Format-BCHours $r.PowerOnHours } else { '' }
            'Temperatur / Maximum'       = "$($r.Temperature) / $($r.TemperatureMax) °C"
            'Unkorrigierte Lesefehler'   = $r.ReadErrorsUncorrected
            'Unkorrigierte Schreibfehler' = $r.WriteErrorsUncorrected
            'Start/Stopp-Zyklen'         = $r.StartStopCycleCount
        })
    $ok = $true
    if ($r.ReadErrorsUncorrected -gt 0 -or $r.WriteErrorsUncorrected -gt 0) {
        Add-BCFinding -Level Kritisch -Title 'Unkorrigierte Lese-/Schreibfehler gemeldet' -Detail "Lesen: $($r.ReadErrorsUncorrected), Schreiben: $($r.WriteErrorsUncorrected)"; $ok = $false
    }
    if ($null -ne $r.Wear) {
        $w = [int]$r.Wear
        if ($w -ge 90) { Add-BCFinding -Level Kritisch -Title "Verschleiß $w %"; $ok = $false }
        elseif ($w -ge 70) { Add-BCFinding -Level Warnung -Title "Verschleiß $w %"; $ok = $false }
        elseif ($w -ge 30) { Add-BCFinding -Level Info -Title "Verschleiß $w %" }
    }
    if ($ok) { Add-BCFinding -Level OK -Title 'Windows-Zuverlässigkeitszähler unauffällig' -Detail 'Nur eingeschränkte Daten verfügbar (keine vollständigen SMART-/NVMe-Werte).' }
    return [pscustomobject]@{ PowerOnHours = $r.PowerOnHours; TBWritten = $null; PowerCycles = $r.StartStopCycleCount; LifeLeft = if ($null -ne $r.Wear) { 100 - [int]$r.Wear } else { $null } }
}

Register-BuyCheck -Id 'storage.health' -Category 'Datenträger (SSD/HDD)' -Order 10 -RunOrder 40 -Seconds 15 `
    -Title 'Laufwerks-Gesundheit (SMART/NVMe) & Fälschungsindizien' `
    -Description 'Liest die Gesundheitswerte direkt vom Laufwerk: verbrauchte Lebensdauer, Reserveblöcke, Fehlerzähler, Betriebsstunden, geschriebene Datenmenge, Temperatur. Prüft außerdem, ob der Controller zur angegebenen Marke passt (gefälschte SSDs) und ob die gemeldete Größe zum physischen Speicher passt.' `
    -Profiles @('quick', 'thorough', 'linux', 'auto') `
    -Run {
    $all = @(Get-BCDisks)
    $usb = @($all | Where-Object { $_.IsUsb })
    $internal = @($all | Where-Object { -not $_.IsUsb -and -not $_.IsVirtual })
    if ($usb.Count -gt 0) { Add-BCFinding -Level Info -Title "USB-Datenträger werden nicht bewertet ($($usb.Count))" -Detail (($usb | ForEach-Object { $_.Model }) -join ', ') }
    if ($internal.Count -eq 0) {
        Add-BCFinding -Level Kritisch -Title 'Kein interner Datenträger gefunden' -Advice 'Fehlt die SSD, ist sie defekt, oder hängt sie an einem Controller ohne Treiber? Unbedingt klären.'
        return
    }
    $summary = @()
    foreach ($d in $internal) {
        Write-BCStep (Get-BCDiskLabel $d)
        $link = ''
        if ($d.LinkSpeed) {
            $link = "$(Get-BCPcieGen $d.LinkSpeed) x$($d.LinkWidth)"
            if ($d.MaxLinkSpeed) { $link += " (max. $(Get-BCPcieGen $d.MaxLinkSpeed) x$($d.MaxLinkWidth))" }
        }
        Add-BCFacts -Title (Get-BCDiskLabel $d) -Data ([ordered]@{
                'Modell' = $d.Model; 'Seriennummer' = $d.Serial; 'Firmware' = $d.Firmware; 'Anschluss' = $d.Bus
                'Medientyp' = $d.Media; 'Größe' = Format-BCBytes $d.SizeBytes; 'Systemlaufwerk' = if ($d.IsBoot -or $d.IsSystem) { 'ja' } else { 'nein' }
                'Windows-Zustand' = $d.Health; 'PCIe-Anbindung' = $link
                'Controller (PCI)' = if ($d.PciVen) { "VEN_$($d.PciVen) DEV_$($d.PciDev)$(if (Get-BCVendorName $d.PciVen) { ' = ' + (Get-BCVendorName $d.PciVen) })" } else { $d.PciInstance }
            })
        $res = $null
        if ($d.Nvme) { $res = Test-BCNvmeHealth -Disk $d }
        elseif ($d.Smart) { $res = Test-BCSataHealth -Disk $d }
        elseif ($d.Reliability) { $res = Test-BCReliabilityOnly -Disk $d }
        else {
            Add-BCFinding -Level Fehler -Title "Keine Gesundheitsdaten für $(Get-BCDiskLabel $d)" -Detail "$($d.NvmeError)" `
                -Advice 'Häufig bei Intel-RST/RAID-Treibern. Alternativ nach dem Kauf mit CrystalDiskInfo oder smartctl prüfen – oder den Verkäufer bitten, einen Screenshot zu zeigen.'
        }
        if ($d.Health -match 'Unhealthy') { Add-BCFinding -Level Kritisch -Title 'Windows stuft den Datenträger als fehlerhaft ein' }
        elseif ($d.Health -match 'Warning') { Add-BCFinding -Level Warnung -Title 'Windows meldet eine Warnung für den Datenträger' }
        if ($d.LinkWidth -and $d.MaxLinkWidth -and [int]$d.LinkWidth -lt [int]$d.MaxLinkWidth) {
            Add-BCFinding -Level Info -Title "SSD nutzt nur $($d.LinkWidth) von $($d.MaxLinkWidth) PCIe-Lanes" -Detail 'Kann am Mainboard-Design liegen; sonst Sitz der SSD prüfen.'
        }
        if ($res -and ($d.IsBoot -or $d.IsSystem -or -not (Get-BCFact 'ssd.poh'))) {
            Set-BCFact 'ssd.poh' $res.PowerOnHours
            Set-BCFact 'ssd.tbw' $res.TBWritten
            Set-BCFact 'ssd.cycles' $res.PowerCycles
            Set-BCFact 'ssd.model' $d.Model
        }
        $part = "$($d.Model) $(Format-BCBytes $d.SizeBytes) ($($d.Bus))"
        if ($res -and $null -ne $res.LifeLeft) { $part += " · Lebensdauer ca. $($res.LifeLeft) % übrig" }
        if ($res -and $null -ne $res.PowerOnHours) { $part += " · $(Format-BCNum $res.PowerOnHours) h" }
        $summary += $part
    }
    Set-BCSummary 'Datenträger' ($summary -join ' | ')
}

Register-BuyCheck -Id 'storage.speed' -Category 'Datenträger (SSD/HDD)' -Order 20 -RunOrder 160 -Seconds 25 `
    -Title 'Lesegeschwindigkeit (nur lesend)' `
    -Description 'Misst sequentielles Lesen und zufällige 4K-Lesezugriffe direkt vom Datenträger. Auffällig langsame Werte deuten auf eine verschlissene, gefälschte oder sehr billige SSD hin. Es wird nichts geschrieben – Schreibtests sind bewusst nicht enthalten, weil der Laptop noch nicht dir gehört.' `
    -Profiles @('quick', 'thorough', 'linux', 'auto') `
    -Run {
    $targets = @(Get-BCInternalDisks | Where-Object { $_.SizeBytes -gt 1GB })
    if ($targets.Count -eq 0) { Add-BCFinding -Level Fehler -Title 'Kein interner Datenträger für die Messung gefunden'; return }
    foreach ($d in $targets) {
        $b = New-Object BuyCheck.DiskReadBenchmark
        $b.Start($d.Number, 1536, 8)
        $cancel = Wait-BCWorkload -Workload $b -Activity "Lesegeschwindigkeit $(Get-BCDiskLabel $d)" -Status { "$($b.Phase) …" } -Percent { $b.Progress * 100 }
        if ($b.Error) { Add-BCFinding -Level Fehler -Title "Messung fehlgeschlagen: $(Get-BCDiskLabel $d)" -Detail $b.Error; continue }
        if ($cancel) { Add-BCFinding -Level Info -Title 'Messung abgebrochen'; continue }
        $seq = [double]$b.SeqReadMBps; $rnd = [double]$b.RandReadMBps
        Add-BCFacts -Title "Lesegeschwindigkeit – $(Get-BCDiskLabel $d)" -Data ([ordered]@{
                'Sequentiell lesen'               = "$(Format-BCNum $seq 0) MB/s"
                'Zufällig 4K lesen (QD1)'         = "$(Format-BCNum $rnd 1) MB/s ($(Format-BCNum $b.RandReadIops 0) IOPS)"
                'Zugriffszeit Ø / max.'           = "$(Format-BCNum $b.RandReadAvgLatencyMs 2) ms / $(Format-BCNum $b.RandReadMaxLatencyMs 0) ms"
            })
        $kind = if ($d.IsNvme) { 'NVMe-SSD' } elseif ($d.IsSsd) { 'SATA-SSD' } else { 'HDD' }
        $seqLvl = 'OK'; $seqNote = ''
        switch ($kind) {
            'NVMe-SSD' { if ($seq -lt 500) { $seqLvl = 'Warnung'; $seqNote = 'Für eine NVMe-SSD sehr langsam.' } elseif ($seq -lt 1000) { $seqLvl = 'Info'; $seqNote = 'Eher langsam für NVMe (Einsteiger-SSD ohne Cache oder Drosselung).' } }
            'SATA-SSD' { if ($seq -lt 200) { $seqLvl = 'Warnung'; $seqNote = 'Für eine SATA-SSD sehr langsam.' } elseif ($seq -lt 350) { $seqLvl = 'Info'; $seqNote = 'Etwas langsam für eine SATA-SSD.' } }
            default { if ($seq -lt 40) { $seqLvl = 'Warnung'; $seqNote = 'Selbst für eine Festplatte sehr langsam.' } elseif ($seq -lt 70) { $seqLvl = 'Info'; $seqNote = 'Langsame Festplatte.' } }
        }
        Add-BCFinding -Level $seqLvl -Title "$kind liest sequentiell mit $(Format-BCNum $seq 0) MB/s" -Detail $seqNote
        if ($kind -ne 'HDD') {
            $minRnd = if ($kind -eq 'NVMe-SSD') { 10 } else { 8 }
            if ($rnd -lt $minRnd) { Add-BCFinding -Level Warnung -Title "Zufällige Lesezugriffe langsam ($(Format-BCNum $rnd 1) MB/s)" -Detail 'Das macht das System im Alltag träge.' }
        }
        if ($b.RandReadMaxLatencyMs -gt 1000) {
            Add-BCFinding -Level Warnung -Title "Einzelner Lesezugriff dauerte $(Format-BCNum $b.RandReadMaxLatencyMs 0) ms" -Detail 'Hänger beim Lesen können auf schwache Speicherbereiche hindeuten.'
        }
    }
}

Register-BuyCheck -Id 'storage.readscan' -Category 'Datenträger (SSD/HDD)' -Order 30 -RunOrder 320 -Seconds 30 `
    -Title 'Oberflächen-Lesetest (nur lesend)' `
    -Description 'Liest den gesamten Datenträger Block für Block (nur lesend) und protokolliert Lesefehler, Hänger und langsame Bereiche. Schwache oder defekte Speicherbereiche zeigen sich hier, auch wenn SMART noch nichts meldet. Bei einer SSD dauert das meist wenige Minuten, bei einer Festplatte deutlich länger (Abdeckung reduzieren).' `
    -Profiles @('thorough') `
    -Options @(
        @{ Key = 'limit'; Label = 'Zeitlimit'; Default = 20; Min = 2; Max = 240; SecondsPerUnit = 60; Unit = 'Minuten' },
        @{ Key = 'coverage'; Label = 'Abdeckung'; Default = 100; Min = 5; Max = 100; SecondsPerUnit = 0; Unit = '% der Fläche' }) `
    -Run {
    param($Options)
    $targets = @(Get-BCInternalDisks | Where-Object { $_.SizeBytes -gt 1GB })
    if ($targets.Count -eq 0) { Add-BCFinding -Level Fehler -Title 'Kein interner Datenträger gefunden'; return }
    $limit = [int]([double]$Options['limit'] * 60 / $targets.Count)
    $coverage = [double]$Options['coverage']
    foreach ($d in $targets) {
        $stride = [int][math]::Max(1, [math]::Round(100 / [math]::Max(1, $coverage)))
        $scan = New-Object BuyCheck.DiskReadScan
        $scan.Start($d.Number, $stride, $limit)
        $cancel = Wait-BCWorkload -Workload $scan -Activity "Oberflächen-Lesetest $(Get-BCDiskLabel $d)" -Status {
            "gelesen {0} von {1} · aktuell {2} MB/s · Lesefehler: {3}" -f (Format-BCBytes $scan.BytesRead), (Format-BCBytes $scan.PlannedBytes), [int]$scan.CurrentMBps, $scan.ReadErrors
        } -Percent { if ($scan.PlannedBytes -gt 0) { $scan.BytesRead / $scan.PlannedBytes * 100 } else { 0 } }
        if ($scan.Error) { Add-BCFinding -Level Fehler -Title "Lesetest fehlgeschlagen: $(Get-BCDiskLabel $d)" -Detail $scan.Error; continue }
        $seg = @($scan.SegmentMBps)
        $median = 0
        if ($seg.Count -gt 0) { $sorted = @($seg | Sort-Object); $median = $sorted[[int][math]::Floor($sorted.Count / 2)] }
        $slowLimit = if ($d.IsSsd) { 150 } else { 20 }
        $slow = New-Object 'System.Collections.Generic.List[string]'
        for ($i = 0; $i -lt $seg.Count; $i++) {
            if ($seg[$i] -lt $median * 0.2 -and $seg[$i] -lt $slowLimit) { $slow.Add(('bei {0} ({1} MB/s)' -f (Format-BCBytes $scan.SegmentOffsets[$i]), [int]$seg[$i])) }
        }
        $covered = if ($scan.DiskBytes -gt 0) { [int]($scan.BytesRead / $scan.DiskBytes * 100) } else { 0 }
        Add-BCFacts -Title "Oberflächen-Lesetest – $(Get-BCDiskLabel $d)" -Data ([ordered]@{
                'Gelesen'                   = "$(Format-BCBytes $scan.BytesRead) von $(Format-BCBytes $scan.DiskBytes) ($covered %)"
                'Dauer'                     = "$([int]$scan.ElapsedSeconds) s"
                'Lesefehler'                = $scan.ReadErrors
                'Typische Geschwindigkeit'  = "$([int]$median) MB/s"
                'Langsamster Abschnitt'     = if ($seg.Count -gt 0) { "$([int](($seg | Measure-Object -Minimum).Minimum)) MB/s" } else { '' }
                'Längster einzelner Lesevorgang' = "$([int]$scan.MaxBlockMs) ms"
                'Abbruchgrund'              = $scan.AbortReason
            })
        if ($seg.Count -gt 1) { Add-BCChart -Title "Lesegeschwindigkeit über die Fläche (MB/s je 256-MB-Abschnitt) – Datenträger $($d.Number)" -Values ([double[]]$seg) -Unit 'MB/s' }
        if ($scan.ReadErrors -gt 0) {
            $offs = @($scan.ErrorOffsets | Select-Object -First 10 | ForEach-Object { Format-BCBytes $_ })
            Add-BCFinding -Level Kritisch -Title "$($scan.ReadErrors) Lesefehler auf dem Datenträger" -Detail ("Positionen: " + ($offs -join ', ')) `
                -Advice 'Unlesbare Bereiche = Datenverlust. Datenträger muss ersetzt werden.'
        } else {
            Add-BCFinding -Level OK -Title "Keine Lesefehler ($covered % der Fläche gelesen)"
        }
        if ($scan.SlowBlocks -gt 0 -or $scan.MaxBlockMs -gt 2000) {
            Add-BCFinding -Level Warnung -Title "Lese-Hänger: $($scan.SlowBlocks) Blöcke brauchten über 1 Sekunde (max. $([int]$scan.MaxBlockMs) ms)" -Advice 'Hinweis auf schwache Speicherbereiche, die nur mit Mühe gelesen werden konnten.'
        }
        if ($slow.Count -gt 0) {
            Add-BCFinding -Level Warnung -Title "$($slow.Count) auffällig langsame Bereiche" -Detail (@($slow | Select-Object -First 8) -join ', ') -Advice 'Bei SSDs können alte, lange nicht neu geschriebene Daten schwer lesbar werden (bekanntes TLC-Problem).'
        }
        if ($scan.Aborted -and -not $cancel) { Add-BCFinding -Level Info -Title "Test vorzeitig beendet: $($scan.AbortReason)" -Detail "Abgedeckt: $covered %" }
        if ($cancel) { Add-BCFinding -Level Info -Title 'Test vom Benutzer abgebrochen' -Detail "Abgedeckt: $covered %" }
    }
}
