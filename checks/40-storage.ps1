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
                    -Detail "Die SSD heißt '$($Disk.Model)', ihr Steuerchip (Controller) stammt aber von $(if ($vname) { $vname } else { "Hersteller-ID $vid" }). Bei dieser Marke ist das ungewöhnlich, kommt bei einzelnen Modellreihen aber vor." `
                    -Advice 'Kommt bei einzelnen Modellreihen vor, ist aber auch ein Merkmal gefälschter oder umgelabelter SSDs. Die Programme der Hersteller (z. B. WD Dashboard) erkennen nur echte SSDs.'
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
    $facts = (New-BCOrdered @(
        'Verbrauchte Lebensdauer (Percentage Used)', "$($h.PercentageUsed) %",
        'Reserveblöcke (Available Spare)', "$($h.AvailableSpare) % (Grenzwert $($h.AvailableSpareThreshold) %)",
        'Kritische Warnungen', $(if ($h.CriticalWarning -eq 0) { 'keine' } else { '0x{0:X2}' -f $h.CriticalWarning }),
        'Medien-/Datenintegritätsfehler', $(Format-BCNum $h.MediaErrors),
        'Einträge im Fehlerprotokoll', $(Format-BCNum $h.ErrorLogEntries),
        'Betriebsstunden', $(Format-BCHours $h.PowerOnHours),
        'Einschaltvorgänge', $(Format-BCNum $h.PowerCycles),
        'Unsichere Abschaltungen', $(Format-BCNum $h.UnsafeShutdowns),
        'Geschriebene Daten', $((Format-BCNum $tb 2) + ' TB'),
        'Gelesene Daten', $((Format-BCNum $h.TerabytesRead 2) + ' TB'),
        'Temperatur jetzt', $(if (-not [double]::IsNaN($h.TemperatureCelsius)) { "$([int]$h.TemperatureCelsius) °C" } else { '' }),
        'Minuten über Warn-/Kritisch-Temperatur', "$($h.WarningTempMinutes) / $($h.CriticalTempMinutes)"
    ))
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
        foreach ($k in $script:BCNvmeWarnBits.Keys) { if (($h.CriticalWarning -band [int][math]::Pow(2, $k)) -ne 0) { $bits += $script:BCNvmeWarnBits[$k] } }
        Add-BCFinding -Level Kritisch -Title 'SSD meldet selbst einen kritischen Zustand' -Detail ("Die SSD meldet: " + ($bits -join ' · ')) -Advice 'Die SSD kann jederzeit ausfallen.'
    }
    if ($h.AvailableSpareThreshold -gt 0 -and $h.AvailableSpare -lt $h.AvailableSpareThreshold) {
        Add-BCFinding -Level Kritisch -Title "Reserveblöcke aufgebraucht ($($h.AvailableSpare) % übrig, Grenzwert $($h.AvailableSpareThreshold) %)" `
            -Detail 'Für verschlissene Speicherzellen hat jede SSD Ersatzblöcke. Davon ist weniger übrig, als der Hersteller als Untergrenze festlegt.' `
            -Advice 'Die SSD steht kurz vor dem Ausfall oder schaltet bald in einen Nur-Lese-Modus.'
    } elseif ($h.AvailableSpare -lt 50) {
        Add-BCFinding -Level Warnung -Title "Nur noch $($h.AvailableSpare) % Reserveblöcke" `
            -Detail 'Für verschlissene Speicherzellen hat jede SSD Ersatzblöcke. Mehr als die Hälfte davon ist schon verbraucht; neue SSDs zeigen 100 %.' `
            -Advice 'Je weniger Reserve übrig ist, desto näher ist das Ende der Lebensdauer.'
    } elseif ($h.AvailableSpare -lt 90) {
        Add-BCFinding -Level Info -Title "Reserveblöcke: $($h.AvailableSpare) %" -Detail 'Einige Blöcke wurden bereits ersetzt.'
    }
    $pu = [int]$h.PercentageUsed
    $left = [math]::Max(0, 100 - $pu)
    $puText = "Die SSD zählt selbst mit, wie viel der vom Hersteller vorgesehenen Schreibmenge verbraucht ist. Bisher geschrieben: $(Format-BCNum $tb 1) TB."
    if ($pu -ge 90) { Add-BCFinding -Level Kritisch -Title "SSD-Lebensdauer weitgehend verbraucht ($pu % verbraucht)" -Detail $puText -Advice 'Ausfall in absehbarer Zeit wahrscheinlich.' }
    elseif ($pu -ge 70) { Add-BCFinding -Level Warnung -Title "SSD stark genutzt ($pu % der Lebensdauer verbraucht)" -Detail $puText -Advice 'Die SSD funktioniert noch, hat aber den größten Teil ihrer vorgesehenen Lebensdauer hinter sich.' }
    elseif ($pu -ge 30) { Add-BCFinding -Level Info -Title "SSD deutlich genutzt ($pu % der Lebensdauer verbraucht)" -Detail "Bei normaler Heimnutzung reicht der Rest meist noch viele Jahre. Geschrieben: $(Format-BCNum $tb 1) TB." }
    else { Add-BCFinding -Level OK -Title "SSD-Verschleiß gering ($pu % verbraucht, ca. $left % übrig)" -Detail "Geschrieben: $(Format-BCNum $tb 1) TB · Betriebsstunden: $(Format-BCNum $h.PowerOnHours)" }

    if ($h.MediaErrors -gt 0) {
        Add-BCFinding -Level Kritisch -Title "Nicht korrigierbare Datenfehler aufgetreten ($(Format-BCNum $h.MediaErrors))" `
            -Detail 'Die SSD konnte Daten auch mit ihrer Fehlerkorrektur nicht fehlerfrei lesen oder schreiben. Dabei können Dateien beschädigt worden sein. Gesunde SSDs haben hier 0.' `
            -Advice 'Deutliches Ausfallrisiko.'
    } else {
        Add-BCFinding -Level OK -Title 'Keine Medien-/Datenintegritätsfehler'
    }
    if ($h.ErrorLogEntries -gt 0) {
        Add-BCFinding -Level Info -Title "Fehlerprotokoll enthält $(Format-BCNum $h.ErrorLogEntries) Einträge" -Detail 'Für sich genommen meist harmlos (z. B. vom Betriebssystem abgelehnte Befehle); nur zusammen mit Medienfehlern kritisch.'
    }
    if ($h.UnsafeShutdowns -gt 100 -and $h.PowerCycles -gt 0 -and ($h.UnsafeShutdowns / $h.PowerCycles) -gt 0.2) {
        Add-BCFinding -Level Info -Title "Viele unsichere Abschaltungen ($(Format-BCNum $h.UnsafeShutdowns) bei $(Format-BCNum $h.PowerCycles) Starts)" -Detail 'Die SSD wurde oft ohne Herunterfahren vom Strom getrennt (hartes Ausschalten, Akku leer). Für die SSD meist unkritisch.'
    }
    if (-not [double]::IsNaN($h.TemperatureCelsius) -and $h.TemperatureCelsius -ge 70) {
        Add-BCFinding -Level Warnung -Title "SSD ist sehr warm ($([int]$h.TemperatureCelsius) °C)" `
            -Detail 'Gemessen während der Prüfung, also ohne besondere Last. Üblich sind 30–55 °C.' `
            -Advice 'Mögliche Ursachen: schlechte Kühlung (Lüfter verstaubt, Wärmeleitpad fehlt) oder eine weiche Unterlage, die die Lüftung verdeckt.'
    }
    if ($h.CriticalTempMinutes -gt 0) {
        Add-BCFinding -Level Warnung -Title "SSD war $($h.CriticalTempMinutes) Minuten über der kritischen Temperatur" `
            -Detail 'Laut eigener Aufzeichnung der SSD. Ab dieser Temperatur bremst sich die SSD stark ab, um Schäden zu vermeiden.' `
            -Advice 'Hitze verkürzt die Lebensdauer der SSD.'
    } elseif ($h.WarningTempMinutes -gt 600) {
        Add-BCFinding -Level Info -Title "SSD war $($h.WarningTempMinutes) Minuten über der Warntemperatur" -Detail 'Laut eigener Aufzeichnung der SSD. Kurze warme Phasen sind normal, dauerhafte Hitze verkürzt die Lebensdauer.'
    }

    Test-BCNvmeBrand -Disk $Disk
    if ($id -and $id.TotalNvmCapacityBytes -gt 0 -and $Disk.SizeBytes -gt $id.TotalNvmCapacityBytes * 1.02) {
        Add-BCFinding -Level Kritisch -Title 'Gemeldete Größe ist größer als der physische Speicher' `
            -Detail ("Windows sieht {0}, der Controller meldet nur {1} physischen Speicher." -f (Format-BCBytes $Disk.SizeBytes), (Format-BCBytes $id.TotalNvmCapacityBytes)) `
            -Advice 'Typisches Merkmal einer Kapazitätsfälschung: Daten jenseits des echten Speichers gehen verloren.'
    }
    return (New-BCObject @('PowerOnHours', $h.PowerOnHours, 'TBWritten', $tb, 'PowerCycles', $h.PowerCycles, 'LifeLeft', $left))
}

function Test-BCSataHealth {
    param($Disk)
    $attrs = @($Disk.Smart.Attributes)
    $get = { param($i) $attrs | Where-Object { $_.Id -eq $i } | Select-Object -First 1 }
    $rows = $attrs | ForEach-Object {
        (New-BCObject @('ID', $_.Id, 'Attribut', $_.Name, 'Aktuell', $_.Current, 'Schlechtester', $_.Worst, 'Grenzwert', $_.Threshold, 'Rohwert', $_.Raw))
    }
    Add-BCTable -Title "SMART-Werte – $(Get-BCDiskLabel $Disk)" -Rows @($rows)
    $isSsd = $Disk.IsSsd

    if ($Disk.Smart.PredictFailure) {
        Add-BCFinding -Level Kritisch -Title 'Laufwerk sagt selbst einen Ausfall voraus (SMART-Status)' -Detail 'Die Selbstüberwachung des Laufwerks (SMART) meldet, dass es bald ausfallen wird.'
    }
    $failed = @($attrs | Where-Object { $_.Threshold -gt 0 -and $_.Current -le $_.Threshold })
    foreach ($a in $failed) {
        Add-BCFinding -Level Kritisch -Title "SMART-Grenzwert unterschritten: $($a.Name) (ID $($a.Id))" -Detail "Aktueller Wert $($a.Current), der Hersteller setzt die Grenze bei $($a.Threshold). Darunter gilt das Laufwerk als verschlissen oder fehlerhaft."
    }
    $bad = 0
    $a5 = & $get 5
    if ($a5 -and $a5.Raw32 -gt 0) {
        $lvl = if ($a5.Raw32 -ge 50) { 'Kritisch' } else { 'Warnung' }
        $adv = 'Wenige ersetzte Bereiche bedeuten noch keinen Ausfall. Steigt die Zahl weiter, nimmt das Ausfallrisiko zu.'
        if ($lvl -eq 'Kritisch') { $adv = 'Sehr viele ersetzte Bereiche: hohes Ausfallrisiko.' }
        Add-BCFinding -Level $lvl -Title "$(Format-BCNum $a5.Raw32) ersetzte Sektoren/Blöcke (ID 5)" -Detail 'Das Laufwerk hat defekte Bereiche gegen Reserve ausgetauscht. Neue Laufwerke haben hier 0.' -Advice $adv; $bad++
    }
    $a187 = & $get 187
    if ($a187 -and $a187.Raw32 -gt 0) { Add-BCFinding -Level Kritisch -Title "$(Format-BCNum $a187.Raw32) nicht korrigierbare Fehler gemeldet (ID 187)" -Detail 'Daten ließen sich auch mit Fehlerkorrektur nicht lesen. Großanbieter wie Backblaze tauschen Laufwerke schon ab dem ersten solchen Fehler.'; $bad++ }
    $a197 = & $get 197
    if ($a197 -and $a197.Raw32 -gt 0) {
        $lvl = if ($isSsd) { 'Warnung' } else { 'Kritisch' }
        $adv = 'Bei Festplatten ein typisches Zeichen für einen beginnenden Ausfall.'
        if ($isSsd) { $adv = 'Bei SSDs verschwindet der Wert oft beim nächsten Schreiben wieder. Der Lesetest zeigt, ob die Stellen tatsächlich unlesbar sind.' }
        Add-BCFinding -Level $lvl -Title "$(Format-BCNum $a197.Raw32) schwebende (unlesbare) Sektoren (ID 197)" -Detail 'Bereiche, die sich zuletzt nicht lesen ließen und noch nicht gegen Reserve getauscht wurden.' -Advice $adv; $bad++
    }
    $a198 = & $get 198
    if ($a198 -and $a198.Raw32 -gt 0) { Add-BCFinding -Level Kritisch -Title "$(Format-BCNum $a198.Raw32) nicht korrigierbare Sektoren (ID 198)" -Detail 'Bereiche, die bei der Selbstprüfung des Laufwerks unlesbar waren. Daten darin sind verloren.' -Advice 'Deutliches Ausfallrisiko.'; $bad++ }
    foreach ($i in @(171, 172, 181, 182)) {
        $a = & $get $i
        if ($a -and $a.Raw32 -gt 0) { Add-BCFinding -Level Warnung -Title "$($a.Name): $(Format-BCNum $a.Raw32) (ID $i)" -Detail 'Die SSD konnte Speicherzellen nicht beschreiben oder löschen und musste auf Reserve ausweichen. Neue SSDs haben hier 0.' -Advice 'Zeichen von Verschleiß; steigt der Wert weiter, droht ein Ausfall.'; $bad++ }
    }
    if (-not $isSsd) {
        $a10 = & $get 10
        if ($a10 -and $a10.Raw32 -gt 0) { Add-BCFinding -Level Warnung -Title "Motor-Anlaufprobleme (ID 10): $(Format-BCNum $a10.Raw32)" -Detail 'Der Motor der Festplatte kam nicht beim ersten Versuch auf Drehzahl.' -Advice 'Hinweis auf Verschleiß von Motor oder Lager.'; $bad++ }
        $a188 = & $get 188
        if ($a188 -and $a188.Raw32 -gt 0) { Add-BCFinding -Level Info -Title "Befehls-Timeouts (ID 188): $(Format-BCNum $a188.Raw32)" -Detail 'Befehle an die Festplatte liefen in eine Zeitüberschreitung, oft wegen Wackelkontakt oder Stromsparfunktionen.' }
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
        $src = if ($lifeId -eq 'Windows') { 'Laut Windows-Zuverlässigkeitszähler.' } else { "Laut Selbstüberwachung der SSD (SMART-Attribut $lifeId). Neue SSDs zeigen 100 %." }
        if ($life -lt 10) { Add-BCFinding -Level Kritisch -Title "SSD-Restlebensdauer nur noch ca. $life %" -Detail $src -Advice 'Ausfall in absehbarer Zeit wahrscheinlich.' }
        elseif ($life -lt 30) { Add-BCFinding -Level Warnung -Title "SSD-Restlebensdauer ca. $life %" -Detail $src -Advice 'Die SSD funktioniert noch, hat aber den größten Teil ihrer vorgesehenen Lebensdauer hinter sich.' }
        elseif ($life -lt 70) { Add-BCFinding -Level Info -Title "SSD-Restlebensdauer ca. $life %" -Detail "$src Bei normaler Heimnutzung reicht das meist noch viele Jahre." }
        else { Add-BCFinding -Level OK -Title "SSD-Restlebensdauer ca. $life %" -Detail $src }
    }
    $poh = $null; $a9 = & $get 9
    if ($a9) { $poh = [double]$a9.Raw32 }
    $cycles = $null; $a12 = & $get 12
    if ($a12) { $cycles = [double]$a12.Raw32 }
    $tb = $null
    $a241 = & $get 241
    if ($a241 -and $a241.Raw -gt 0) { $tb = [double]$a241.Raw * 512 / 1e12 }
    $a194 = & $get 194
    $facts = (New-BCOrdered @(
        'Typ', $(if ($isSsd) { 'SSD (SATA)' } else { 'Festplatte (HDD)' }),
        'Betriebsstunden', $(if ($null -ne $poh) { Format-BCHours $poh } else { '' }),
        'Einschaltvorgänge', $(if ($null -ne $cycles) { Format-BCNum $cycles } else { '' }),
        'Geschriebene Daten (Annahme 512-Byte-LBAs)', $(if ($null -ne $tb) { (Format-BCNum $tb 2) + ' TB' } else { '' }),
        'Temperatur', $(if ($a194) { "$($a194.RawLow) °C" } else { '' })
    ))
    Add-BCFacts -Title 'Kennzahlen' -Data $facts
    if (-not $isSsd) {
        Add-BCFinding -Level Info -Title 'Festplatte (HDD) statt SSD' -Detail 'Deutlich langsamer und stoßempfindlicher als eine SSD.'
    }
    return (New-BCObject @('PowerOnHours', $poh, 'TBWritten', $tb, 'PowerCycles', $cycles, 'LifeLeft', $life))
}

function Test-BCReliabilityOnly {
    param($Disk)
    $r = $Disk.Reliability
    Add-BCFacts -Title "Windows-Zuverlässigkeitszähler – $(Get-BCDiskLabel $Disk)" -Data ((New-BCOrdered @(
        'Verschleiß (Wear)', $(if ($null -ne $r.Wear) { "$($r.Wear) %" } else { '' }),
        'Betriebsstunden', $(if ($null -ne $r.PowerOnHours) { Format-BCHours $r.PowerOnHours } else { '' }),
        'Temperatur / Maximum', "$($r.Temperature) / $($r.TemperatureMax) °C",
        'Unkorrigierte Lesefehler', $r.ReadErrorsUncorrected,
        'Unkorrigierte Schreibfehler', $r.WriteErrorsUncorrected,
        'Start/Stopp-Zyklen', $r.StartStopCycleCount
    )))
    $ok = $true
    if ($r.ReadErrorsUncorrected -gt 0 -or $r.WriteErrorsUncorrected -gt 0) {
        Add-BCFinding -Level Kritisch -Title 'Unkorrigierte Lese-/Schreibfehler gemeldet' -Detail "Laut Windows-Zuverlässigkeitszähler: $($r.ReadErrorsUncorrected) Lese- und $($r.WriteErrorsUncorrected) Schreibfehler, die nicht korrigiert werden konnten. Gesunde Laufwerke haben hier 0." `
            -Advice 'Deutliches Ausfallrisiko.'; $ok = $false
    }
    if ($null -ne $r.Wear) {
        $w = [int]$r.Wear
        $wd = 'Laut Windows-Zuverlässigkeitszähler ist dieser Anteil der vorgesehenen Lebensdauer verbraucht.'
        if ($w -ge 90) { Add-BCFinding -Level Kritisch -Title "SSD-Verschleiß $w %" -Detail $wd -Advice 'Ausfall in absehbarer Zeit wahrscheinlich.'; $ok = $false }
        elseif ($w -ge 70) { Add-BCFinding -Level Warnung -Title "SSD-Verschleiß $w %" -Detail $wd -Advice 'Die SSD funktioniert noch, hat aber den größten Teil ihrer vorgesehenen Lebensdauer hinter sich.'; $ok = $false }
        elseif ($w -ge 30) { Add-BCFinding -Level Info -Title "SSD-Verschleiß $w %" -Detail "$wd Bei normaler Heimnutzung reicht der Rest meist noch viele Jahre." }
    }
    if ($ok) { Add-BCFinding -Level OK -Title 'Windows-Zuverlässigkeitszähler unauffällig' -Detail 'Nur eingeschränkte Daten verfügbar (keine vollständigen SMART-/NVMe-Werte).' }
    return (New-BCObject @('PowerOnHours', $r.PowerOnHours, 'TBWritten', $null, 'PowerCycles', $r.StartStopCycleCount, 'LifeLeft', $(if ($null -ne $r.Wear) { 100 - [int]$r.Wear } else { $null })))
}

Register-BuyCheck -Id 'storage.health' -Category 'Datenträger (SSD/HDD)' -Order 10 -RunOrder 40 -Seconds 15 `
    -Title 'Laufwerks-Gesundheit (SMART/NVMe) & Fälschungsindizien' `
    -Description 'Liest die Gesundheitswerte direkt vom Laufwerk: verbrauchte Lebensdauer, Reserveblöcke, Fehlerzähler, Betriebsstunden, geschriebene Datenmenge, Temperatur. Prüft außerdem, ob der Controller zur angegebenen Marke passt (gefälschte SSDs) und ob die gemeldete Größe zum physischen Speicher passt.' `
    -Profiles @('quick', 'thorough', 'linux', 'auto') `
    -Run {
    $all = @(Get-BCDisks)
    $usb = @($all | Where-Object { $_.IsUsb })
    $internal = @($all | Where-Object { -not $_.IsUsb -and -not $_.IsVirtual })
    if ($usb.Count -gt 0) { Add-BCFinding -Level Info -Title "Externe Datenträger (USB/SD) werden nicht bewertet ($($usb.Count))" -Detail (($usb | ForEach-Object { $_.Model }) -join ', ') }
    if ($internal.Count -eq 0) {
        Add-BCFinding -Level Kritisch -Title 'Kein interner Datenträger gefunden' -Detail 'Windows meldet keine eingebaute SSD oder Festplatte. Das ist bei einem laufenden Windows sehr ungewöhnlich.' -Advice 'Mögliche Gründe: Windows läuft von einem USB-Datenträger, die SSD fehlt oder ist defekt, oder sie hängt an einem Controller ohne Treiber.'
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
        Add-BCFacts -Title (Get-BCDiskLabel $d) -Data ((New-BCOrdered @(
            'Modell', $d.Model,
            'Seriennummer', $d.Serial,
            'Firmware', $d.Firmware,
            'Anschluss', $d.Bus,
            'Medientyp', $d.Media,
            'Größe', $(Format-BCBytes $d.SizeBytes),
            'Systemlaufwerk', $(if ($d.IsBoot -or $d.IsSystem) { 'ja' } else { 'nein' }),
            'Windows-Zustand', $d.Health,
            'PCIe-Anbindung', $link,
            'Controller (PCI)', $(if ($d.PciVen) { "VEN_$($d.PciVen) DEV_$($d.PciDev)$(if (Get-BCVendorName $d.PciVen) { ' = ' + (Get-BCVendorName $d.PciVen) })" } else { $d.PciInstance })
        )))
        $res = $null
        if ($d.Nvme) { $res = Test-BCNvmeHealth -Disk $d }
        elseif ($d.Smart) { $res = Test-BCSataHealth -Disk $d }
        elseif ($d.Reliability) { $res = Test-BCReliabilityOnly -Disk $d }
        else {
            $why = 'Häufig bei Intel-RST/RAID-Treibern.'
            if ($d.IsNvme -and (Get-BCSystem).OsBuildNumber -lt 10240) { $why = 'NVMe-Gesundheitswerte liefert Windows ohne Zusatzprogramm erst ab Windows 10.' }
            elseif ($d.Bus -match '^(SD|MMC)$') { $why = 'Eingelöteter eMMC-Speicher (typisch für sehr günstige Geräte) liefert keine SMART-Werte.' }
            Add-BCFinding -Level Fehler -Title "Keine Gesundheitsdaten für $(Get-BCDiskLabel $d)" -Detail "$($d.NvmeError)" `
                -Advice "$why Der Lesetest (Gründlich) zeigt trotzdem, ob der Speicher Lesefehler hat."
        }
        if ($d.Health -match 'Unhealthy') { Add-BCFinding -Level Kritisch -Title 'Windows stuft den Datenträger als fehlerhaft ein' -Detail "Windows-Zustand: $($d.Health). Windows wertet dafür die Selbstüberwachung des Laufwerks aus." }
        elseif ($d.Health -match 'Warning') { Add-BCFinding -Level Warnung -Title 'Windows meldet eine Warnung für den Datenträger' -Detail 'Windows wertet dafür die Selbstüberwachung des Laufwerks aus, z. B. hohen Verschleiß oder ersetzte Bereiche. Die Werte oben zeigen den genauen Grund.' }
        if ($d.LinkWidth -and $d.MaxLinkWidth -and [int]$d.LinkWidth -lt [int]$d.MaxLinkWidth) {
            Add-BCFinding -Level Info -Title "SSD nutzt nur $($d.LinkWidth) von $($d.MaxLinkWidth) PCIe-Lanes" -Detail 'Kann am Mainboard-Design liegen oder an einer schlecht sitzenden SSD.'
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
        $b = Invoke-BCDiskBenchmark -Disk $d.Number -SeqMB 1536 -RandomSeconds 8 -SectorBytes $d.SectorBytes
        if ($b.Error) { Add-BCFinding -Level Fehler -Title "Messung fehlgeschlagen: $(Get-BCDiskLabel $d)" -Detail $b.Error; continue }
        if ($b.Cancelled) { Add-BCFinding -Level Info -Title 'Messung abgebrochen'; continue }
        $seq = [double]$b.SeqMBps; $rnd = [double]$b.RandMBps
        Add-BCFacts -Title "Lesegeschwindigkeit – $(Get-BCDiskLabel $d)" -Data ((New-BCOrdered @(
            'Sequentiell lesen', "$(Format-BCNum $seq 0) MB/s",
            'Zufällig 4K lesen (QD1)', "$(Format-BCNum $rnd 1) MB/s ($(Format-BCNum $b.RandIops 0) IOPS)",
            'Zugriffszeit Ø / max.', "$(Format-BCNum $b.RandAvgMs 2) ms / $(Format-BCNum $b.RandMaxMs 0) ms"
        )))
        $kind = if ($d.IsNvme) { 'NVMe-SSD' } elseif ($d.IsSsd) { 'SATA-SSD' } else { 'HDD' }
        $seqLvl = 'OK'; $seqNote = ''
        switch ($kind) {
            'NVMe-SSD' { if ($seq -lt 500) { $seqLvl = 'Warnung'; $seqNote = 'Für eine NVMe-SSD sehr langsam.' } elseif ($seq -lt 1000) { $seqLvl = 'Info'; $seqNote = 'Eher langsam für NVMe (Einsteiger-SSD ohne Cache oder Drosselung).' } }
            'SATA-SSD' { if ($seq -lt 200) { $seqLvl = 'Warnung'; $seqNote = 'Für eine SATA-SSD sehr langsam.' } elseif ($seq -lt 350) { $seqLvl = 'Info'; $seqNote = 'Etwas langsam für eine SATA-SSD.' } }
            default { if ($seq -lt 40) { $seqLvl = 'Warnung'; $seqNote = 'Selbst für eine Festplatte sehr langsam.' } elseif ($seq -lt 70) { $seqLvl = 'Info'; $seqNote = 'Langsame Festplatte.' } }
        }
        if ($seqLvl -eq 'Warnung') {
            Add-BCFinding -Level $seqLvl -Title "$kind liest sequentiell mit $(Format-BCNum $seq 0) MB/s" -Detail "$seqNote Üblich sind bei NVMe-SSDs 1500–7000 MB/s, bei SATA-SSDs um 500 MB/s, bei Festplatten 80–150 MB/s." `
                -Advice 'Mögliche Ursachen: sehr billige oder gefälschte SSD, stark verschlissene SSD, oder ein Programm liest gerade viel (z. B. Virenscan).'
        } else { Add-BCFinding -Level $seqLvl -Title "$kind liest sequentiell mit $(Format-BCNum $seq 0) MB/s" -Detail $seqNote }
        if ($kind -ne 'HDD') {
            $minRnd = if ($kind -eq 'NVMe-SSD') { 10 } else { 8 }
            if ($rnd -lt $minRnd) { Add-BCFinding -Level Warnung -Title "Zufällige Lesezugriffe langsam ($(Format-BCNum $rnd 1) MB/s)" -Detail "Viele kleine Zugriffe nacheinander, wie beim Starten von Programmen. Üblich sind bei SSDs 20–80 MB/s." -Advice 'Das macht das System im Alltag träge. Mögliche Ursachen wie beim langsamen sequentiellen Lesen.' }
        }
        if ($b.RandMaxMs -gt 1000) {
            Add-BCFinding -Level Warnung -Title "Einzelner Lesezugriff dauerte $(Format-BCNum $b.RandMaxMs 0) ms" -Detail 'Normal sind unter 10 ms. So lange Hänger entstehen, wenn das Laufwerk eine Stelle mehrfach lesen muss.' -Advice 'Kann auf schwache Speicherbereiche hindeuten. Im Profil „Gründlich“ zeigt der Lesetest, ob es mehr solche Stellen gibt.'
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
        $scan = Invoke-BCDiskScan -Disk $d.Number -Stride $stride -MaxSeconds $limit -SectorBytes $d.SectorBytes
        $cancel = $scan.Cancelled
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
        Add-BCFacts -Title "Oberflächen-Lesetest – $(Get-BCDiskLabel $d)" -Data ((New-BCOrdered @(
            'Gelesen', "$(Format-BCBytes $scan.BytesRead) von $(Format-BCBytes $scan.DiskBytes) ($covered %)",
            'Dauer', "$([int]$scan.Seconds) s",
            'Lesefehler', $scan.ReadErrors,
            'Typische Geschwindigkeit', "$([int]$median) MB/s",
            'Langsamster Abschnitt', $(if ($seg.Count -gt 0) { "$([int](($seg | Measure-Object -Minimum).Minimum)) MB/s" } else { '' }),
            'Längster einzelner Lesevorgang', "$([int]$scan.MaxBlockMs) ms",
            'Abbruchgrund', $scan.AbortReason
        )))
        if ($seg.Count -gt 1) { Add-BCChart -Title "Lesegeschwindigkeit über die Fläche (MB/s je 256-MB-Abschnitt) – Datenträger $($d.Number)" -Values ([double[]]$seg) -Unit 'MB/s' }
        if ($scan.ReadErrors -gt 0) {
            $offs = @($scan.ErrorOffsets | Select-Object -First 10 | ForEach-Object { Format-BCBytes $_ })
            Add-BCFinding -Level Kritisch -Title "$($scan.ReadErrors) Lesefehler auf dem Datenträger" -Detail ("Diese Stellen ließen sich nicht lesen. Daten dort sind verloren. Positionen: " + ($offs -join ', ')) `
                -Advice 'Der Datenträger ist defekt.'
        } else {
            Add-BCFinding -Level OK -Title "Keine Lesefehler ($covered % der Fläche gelesen)"
        }
        if ($scan.SlowBlocks -gt 0 -or $scan.MaxBlockMs -gt 2000) {
            Add-BCFinding -Level Warnung -Title "Lese-Hänger: $($scan.SlowBlocks) Blöcke brauchten über 1 Sekunde (max. $([int]$scan.MaxBlockMs) ms)" -Detail 'Normal sind wenige Millisekunden. So lange dauert es, wenn das Laufwerk eine Stelle mehrfach lesen muss, bis es klappt.' -Advice 'Schwache Speicherbereiche, die bald unlesbar werden können.'
        }
        if ($slow.Count -gt 0) {
            Add-BCFinding -Level Warnung -Title "$($slow.Count) auffällig langsame Bereiche" -Detail (@($slow | Select-Object -First 8) -join ', ') -Advice 'Bei SSDs werden alte, lange nicht neu geschriebene Daten manchmal langsam lesbar (bekannte Schwäche mancher Modelle). Meist kein Defekt, solange es keine Lesefehler gibt.'
        }
        if ($scan.Aborted -and -not $cancel) { Add-BCFinding -Level Info -Title "Test vorzeitig beendet: $($scan.AbortReason)" -Detail "Abgedeckt: $covered %" }
        if ($cancel) { Add-BCFinding -Level Info -Title 'Test vom Benutzer abgebrochen' -Detail "Abgedeckt: $covered %" }
    }
}
