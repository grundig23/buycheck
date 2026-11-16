# BuyCheck – Plausibilität: passen die Altersangaben der Bauteile zusammen? (deckt Teiletausch und Manipulation auf)

Register-BuyCheck -Id 'summary.plausibility' -Category 'Abschluss' -Order 20 -RunOrder 999 -Seconds 10 `
    -Title 'Plausibilitätsprüfung (Gerätealter, Teiletausch)' `
    -Description 'Vergleicht die Altersangaben der Bauteile: Markteinführung der CPU, BIOS-Stand, Baujahr des Displays, Herstelldatum des Akkus, Betriebsstunden und Schreibmenge der SSD. Widersprüche deuten auf getauschte Teile (z. B. billigere SSD, Ersatzdisplay) oder zurückgesetzte Zähler hin.' `
    -Profiles @('quick', 'thorough', 'linux', 'auto') `
    -Run {
    # Fehlende Fakten selbst ermitteln (falls die zugehörigen Tests abgewählt wurden)
    if (-not (Get-BCFact 'cpu.launchYear')) {
        $c = Get-BCCpu
        if ($c) { $a = Get-BCCpuArch -Vendor $c.Vendor -Family $c.Family -Model $c.Model -Stepping $c.Stepping; if ($a.LaunchYear) { Set-BCFact 'cpu.launchYear' ([int]$a.LaunchYear) } }
    }
    if (-not (Get-BCFact 'bios.date')) { $s = Get-BCSystem; if ($s) { Set-BCFact 'bios.date' $s.BiosDate; Set-BCFact 'os.installDate' $s.OsInstallDate } }
    if (-not (Get-BCFact 'panel.year')) { $m = @(Get-BCMonitors | Where-Object { $_.Internal }) | Select-Object -First 1; if ($m) { Set-BCFact 'panel.year' $m.Year } }
    if ($null -eq (Get-BCFact 'battery.cycles')) {
        $b = Get-BCBattery
        if ($b -and @($b.Batteries).Count -gt 0) {
            $bb = @($b.Batteries)[0]
            Set-BCFact 'battery.cycles' $bb.Cycles; Set-BCFact 'battery.date' $bb.ManufactureDate
            if ($bb.DesignMWh -gt 0 -and $bb.FullMWh -gt 0) { Set-BCFact 'battery.health' ([math]::Round($bb.FullMWh / $bb.DesignMWh * 100, 1)) }
        }
    }
    if ($null -eq (Get-BCFact 'ssd.poh')) {
        $d = @(Get-BCInternalDisks | Where-Object { $_.IsBoot -or $_.IsSystem }) | Select-Object -First 1
        if (-not $d) { $d = @(Get-BCInternalDisks) | Select-Object -First 1 }
        if ($d) {
            Set-BCFact 'ssd.model' $d.Model
            if ($d.Nvme) { Set-BCFact 'ssd.poh' $d.Nvme.PowerOnHours; Set-BCFact 'ssd.tbw' $d.Nvme.TerabytesWritten; Set-BCFact 'ssd.cycles' $d.Nvme.PowerCycles }
            elseif ($d.Smart) {
                $a9 = @($d.Smart.Attributes | Where-Object { $_.Id -eq 9 }) | Select-Object -First 1
                if ($a9) { Set-BCFact 'ssd.poh' ([double]$a9.Raw32) }
            } elseif ($d.Reliability -and $null -ne $d.Reliability.PowerOnHours) { Set-BCFact 'ssd.poh' ([double]$d.Reliability.PowerOnHours) }
        }
    }

    $now = Get-Date
    $cpuYear = Get-BCFact 'cpu.launchYear'
    $biosDate = Get-BCFact 'bios.date'
    $panelYear = Get-BCFact 'panel.year'
    $batDate = Get-BCFact 'battery.date'
    $batCycles = Get-BCFact 'battery.cycles'
    $batHealth = Get-BCFact 'battery.health'
    $poh = Get-BCFact 'ssd.poh'
    $tbw = Get-BCFact 'ssd.tbw'
    $installDate = Get-BCFact 'os.installDate'

    Add-BCTable -Title 'Altersangaben der Bauteile' -Rows @(
        (New-BCObject @('Quelle', 'Markteinführung der CPU-Generation', 'Wert', $(if ($cpuYear) { "ca. $cpuYear" } else { '–' }), 'Bedeutung', 'Gerät kann nicht älter sein'))
        (New-BCObject @('Quelle', 'BIOS-Stand', 'Wert', $(Format-BCDate $biosDate), 'Bedeutung', 'Datum der installierten BIOS-Version (nach Updates jünger)'))
        (New-BCObject @('Quelle', 'Display (EDID)', 'Wert', $(if ($panelYear) { "$panelYear" } else { '–' }), 'Bedeutung', 'Herstellungsjahr des Panels'))
        (New-BCObject @('Quelle', 'Akku', 'Wert', $(if ($batDate) { Format-BCDate $batDate } else { '–' }), 'Bedeutung', 'Herstelldatum laut Akku-Chip'))
        (New-BCObject @('Quelle', 'SSD-Betriebsstunden', 'Wert', $(if ($null -ne $poh) { Format-BCHours $poh } else { '–' }), 'Bedeutung', 'tatsächliche Nutzungsdauer der SSD'))
        (New-BCObject @('Quelle', 'Windows-Installation', 'Wert', $(Format-BCDate $installDate), 'Bedeutung', 'letzte Neuinstallation/großes Update'))
    )

    $issues = 0
    if ($cpuYear) {
        $platformHours = (New-TimeSpan -Start (Get-Date -Year $cpuYear -Month 1 -Day 1) -End $now).TotalHours
        $ageYears = $now.Year - $cpuYear
        if ($null -ne $poh -and $poh -gt $platformHours * 1.02) {
            Add-BCFinding -Level Warnung -Title 'SSD hat mehr Betriebsstunden, als die Geräteplattform alt sein kann' `
                -Detail ("{0} Betriebsstunden, die CPU-Generation gibt es aber erst seit ca. {1}." -f (Format-BCNum $poh), $cpuYear) `
                -Advice 'Die SSD war schon länger in Betrieb, als es dieses Gerät gibt. Sie stammt also aus einem anderen Gerät (gebrauchte SSD eingebaut) oder die Werte sind manipuliert. Den Verkäufer fragen; eine gebrauchte SSD ist nicht schlimm, wenn ihre Gesundheitswerte gut sind.'
            $issues++
        }
        if ($null -ne $poh -and $poh -lt 100 -and $ageYears -ge 3 -and ($null -eq $tbw -or $tbw -lt 0.2)) {
            Add-BCFinding -Level Info -Title 'SSD ist praktisch unbenutzt, das Gerät aber mehrere Jahre alt' `
                -Detail ("{0} Betriebsstunden bei einer Plattform von ca. {1}." -f (Format-BCNum $poh), $cpuYear) `
                -Advice 'Vermutlich nachgerüstet (dann Modell/Marke prüfen: Marken-SSD oder Billigware?) – oder Zähler zurückgesetzt. Nachfragen, Rechnung zeigen lassen.'
            $issues++
        }
        if ($panelYear -and $panelYear -gt 1990) {
            # Geräte einer CPU-Generation werden meist bis ca. 2–3 Jahre nach deren Einführung gebaut.
            # (Das BIOS-Datum taugt nicht als Gerätealter, weil BIOS-Updates jünger sind.)
            if ($panelYear -gt $cpuYear + 3) {
                Add-BCFinding -Level Info -Title "Display ist deutlich jünger als das Gerät (Baujahr $panelYear)" -Detail "CPU-Generation von ca. $cpuYear." `
                    -Advice 'Display vermutlich getauscht. Nicht schlimm, wenn die Qualität stimmt – Panel-Datenblatt (IPS? Helligkeit?) prüfen und nach dem Grund fragen.'
                $issues++
            }
            if ($panelYear -lt $cpuYear - 2) {
                Add-BCFinding -Level Info -Title "Display ist älter als die CPU-Generation (Baujahr $panelYear)" -Detail "CPU-Generation von ca. $cpuYear. Ungewöhnlich; vielleicht ein Ersatzdisplay aus Altbeständen." -Advice 'Den Verkäufer fragen, ob das Display getauscht wurde.'
            }
        }
        if ($batDate) {
            $by = ([datetime]$batDate).Year
            if ($by -lt $cpuYear - 1 -and $by -gt 1990) {
                Add-BCFinding -Level Warnung -Title "Akku-Herstelldatum ($by) liegt vor der CPU-Generation ($cpuYear)" -Detail 'Der Akku wäre älter als das Gerät selbst.' -Advice 'Unplausibel: falsches Datum im Akku-Chip, ein alter Fremdakku oder umprogrammierte Werte. Den Verkäufer nach einem Akkutausch fragen; die Akku-Gesundheit und der Entladetest zeigen den tatsächlichen Zustand.'
                $issues++
            }
        }
        if ($null -ne $batCycles -and $batCycles -eq 0 -and $null -ne $batHealth -and $batHealth -ge 98 -and $ageYears -ge 3) {
            Add-BCFinding -Level Info -Title 'Akku wirkt neuwertig (0 Zyklen) bei mehrere Jahre altem Gerät' `
                -Advice 'Entweder neuer Ersatzakku (Rechnung? Original oder Nachbau?) oder zurückgesetzte Akku-Werte. Nachfragen; Entladetest durchführen.'
            $issues++
        }
    }
    if ($null -ne $poh -and $poh -gt 0 -and $null -ne $tbw -and $tbw -gt [math]::Max(1, $poh * 0.5)) {
        Add-BCFinding -Level Warnung -Title 'SSD-Werte sind unplausibel (sehr viel geschrieben in wenigen Betriebsstunden)' `
            -Detail ("{0} TB geschrieben in nur {1} Betriebsstunden. So viel schafft keine normale Nutzung." -f (Format-BCNum $tbw 1), (Format-BCNum $poh)) -Advice 'Hinweis auf einen zurückgesetzten Betriebsstundenzähler, um die SSD jünger erscheinen zu lassen. Den Verkäufer fragen; auf die verbrauchte Lebensdauer und die Fehlerzähler achten, die sind schwerer zu fälschen.'
        $issues++
    }
    if ($issues -eq 0) { Add-BCFinding -Level OK -Title 'Altersangaben der Bauteile passen zusammen' -Detail 'Kein Hinweis auf getauschte Teile oder zurückgesetzte Zähler.' }
}
