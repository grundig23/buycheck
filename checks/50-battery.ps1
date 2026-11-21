# BuyCheck – Akku & Stromversorgung: Gesundheit, Verlauf/Manipulation, Ladefunktion, Entladetest

function Get-BCBatteryReportXml {
    # Erzeugt den Windows-Akkubericht direkt im Berichtsordner (USB-Stick) – nicht auf dem Laptop.
    return Get-BCCached 'batteryReportXml' {
        if (-not $script:BCReportDir) { return $null }
        $xmlPath = Join-Path $script:BCReportDir 'akkubericht-windows.xml'
        $htmlPath = Join-Path $script:BCReportDir 'akkubericht-windows.html'
        try {
            & powercfg.exe /batteryreport /xml /output "$xmlPath" 2>&1 | Out-Null
            & powercfg.exe /batteryreport /output "$htmlPath" 2>&1 | Out-Null
        } catch { }
        if (Test-Path -LiteralPath $xmlPath) {
            try { return [xml]([IO.File]::ReadAllText($xmlPath)) } catch { return $null }
        }
        return $null
    }
}

function ConvertFrom-BCSbdsDate {
    param([int]$Value)
    if ($Value -le 0 -or $Value -eq 0xFFFF) { return $null }
    $y = (Get-BCBits $Value 9 0x7F) + 1980; $m = Get-BCBits $Value 5 0xF; $d = $Value -band 0x1F
    try { return Get-Date -Year $y -Month $m -Day $d } catch { return $null }
}

Register-BuyCheck -Id 'battery.health' -Category 'Akku & Stromversorgung' -Order 10 -RunOrder 50 -Seconds 15 `
    -Title 'Akku-Gesundheit & Kapazitätsverlauf' `
    -Description 'Vergleicht die aktuelle Vollladekapazität mit der Designkapazität (Verschleiß), liest Ladezyklen und Hersteller und wertet den Windows-Akkubericht aus. Sprünge im Kapazitätsverlauf oder widersprüchliche Angaben deuten auf einen Akkutausch oder umprogrammierte Akku-Elektronik hin.' `
    -Profiles @('quick', 'thorough', 'linux', 'auto') `
    -Run {
    $bat = Get-BCBattery
    $sys = Get-BCSystem
    if (-not $bat -or -not $bat.Present -or @($bat.Batteries).Count -eq 0) {
        if ($sys.IsPortable) {
            Add-BCFinding -Level Kritisch -Title 'Kein Akku erkannt' -Detail 'Das Gerät ist ein Notebook, Windows findet aber keinen Akku.' -Advice 'Der Akku fehlt, ist komplett defekt oder nicht angeschlossen. Ohne Netzteil geht das Gerät dann sofort aus.'
        } else { Add-BCFinding -Level Info -Title 'Kein Akku vorhanden (kein Notebook?)' }
        return
    }
    $xml = Get-BCBatteryReportXml
    $repBats = @()
    if ($xml) { $repBats = @($xml.BatteryReport.Batteries.Battery) }
    $t22 = @(Get-BCSmbiosType 22)
    $i = 0
    $summary = @()
    foreach ($b in @($bat.Batteries)) {
        $rb = if ($repBats.Count -gt $i) { $repBats[$i] } else { $null }
        $design = [double]$b.DesignMWh; $full = [double]$b.FullMWh
        if ($rb) {
            if ($design -le 0 -and $rb.DesignCapacity) { $design = [double]$rb.DesignCapacity }
            if ($full -le 0 -and $rb.FullChargeCapacity) { $full = [double]$rb.FullChargeCapacity }
        }
        $cycles = $b.Cycles
        if (($null -eq $cycles -or $cycles -eq 0) -and $rb -and $rb.CycleCount) { $cycles = [int64]$rb.CycleCount }
        $mdate = $b.ManufactureDate
        if (-not $mdate -and $rb -and "$($rb.ManufactureDate)" -match '^\d{4}-') { try { $mdate = [datetime]"$($rb.ManufactureDate)" } catch { } }
        $smb = if ($t22.Count -gt $i) { $t22[$i] } else { $null }
        $smbDesign = $null; $smbDate = $null
        if ($smb) {
            $mult = $smb.Byte(0x15); if ($mult -le 0) { $mult = 1 }
            $cap = $smb.Word(0x0A)
            if ($cap -gt 0 -and $cap -ne 0xFFFF) { $smbDesign = [double]$cap * $mult }
            $smbDate = ConvertFrom-BCSmbiosDate $smb.Str(0x06)
            if (-not $smbDate) { $smbDate = ConvertFrom-BCSbdsDate $smb.Word(0x12) }
        }
        if (-not $mdate -and $smbDate) { $mdate = $smbDate }
        $health = if ($design -gt 0 -and $full -gt 0) { [math]::Round($full / $design * 100, 1) } else { $null }

        Add-BCFacts -Title "Akku $($i + 1)" -Data ((New-BCOrdered @(
            'Bezeichnung', $b.Name,
            'Hersteller', $b.Manufacturer,
            'Seriennummer', $b.Serial,
            'Chemie', $b.Chemistry,
            'Designkapazität', $(if ($design -gt 0) { "$(Format-BCNum ($design / 1000) 1) Wh" } else { '' }),
            'Aktuelle Vollladung', $(if ($full -gt 0) { "$(Format-BCNum ($full / 1000) 1) Wh" } else { '' }),
            'Gesundheit', $(if ($null -ne $health) { "$(Format-BCNum $health 1) %" } else { '' }),
            'Ladezyklen', $(if ($null -ne $cycles -and $cycles -gt 0) { $cycles } else { 'nicht gemeldet' }),
            'Herstelldatum', $(if ($mdate) { Format-BCDate $mdate } else { 'nicht gemeldet' }),
            'Designkapazität laut BIOS', $(if ($smbDesign) { "$(Format-BCNum ($smbDesign / 1000) 1) Wh" } else { '' })
        )))
        if ($b.Relative) { Add-BCFinding -Level Info -Title 'Akku meldet nur relative Werte' -Detail 'Die Kapazitäten sind keine echten mWh-Werte; die Prozentangabe bleibt aber aussagekräftig.' }

        if ($null -ne $health) {
            $txt = "Der Akku fasst noch $(Format-BCNum ($full / 1000) 1) Wh, neu waren es $(Format-BCNum ($design / 1000) 1) Wh."
            if ($health -gt 110) {
                Add-BCFinding -Level Warnung -Title "Vollladekapazität deutlich ÜBER Designwert ($(Format-BCNum $health 0) %)" -Detail $txt `
                    -Advice 'Akkus werden mit der Zeit schwächer, nie stärker. Typisch für Nachbau-Akkus mit falschen Angaben oder umprogrammierte Akku-Elektronik. Der Entladetest zeigt, ob die Laufzeit zur Angabe passt.'
            } elseif ($health -ge 80) {
                Add-BCFinding -Level OK -Title "Akku-Gesundheit $(Format-BCNum $health 0) %" -Detail $txt
                if ($health -gt 103) { Add-BCFinding -Level Info -Title 'Kapazität leicht über Designwert' -Detail 'Bei neuen Akkus normal, bei älteren ungewöhnlich.' }
            } elseif ($health -ge 70) {
                Add-BCFinding -Level Info -Title "Akku-Gesundheit $(Format-BCNum $health 0) %" -Detail "$txt Für ein gebrauchtes Gerät normal, die Laufzeit ist etwas kürzer als neu."
            } elseif ($health -ge 60) {
                Add-BCFinding -Level Warnung -Title "Akku deutlich verschlissen ($(Format-BCNum $health 0) %)" -Detail $txt -Advice 'Die Laufzeit ist entsprechend kürzer als neu.'
            } else {
                Add-BCFinding -Level Kritisch -Title "Akku stark verschlissen ($(Format-BCNum $health 0) %)" -Detail $txt -Advice 'Die Laufzeit ist entsprechend kürzer als neu.'
            }
        } else {
            Add-BCFinding -Level Fehler -Title 'Akku-Kapazitäten nicht lesbar'
        }
        if ($null -ne $cycles -and $cycles -gt 0) {
            if ($cycles -gt 800) { Add-BCFinding -Level Warnung -Title "Viele Ladezyklen: $cycles" -Detail 'Ein Zyklus ist eine volle Ladung (z. B. zweimal von 50 auf 100 %). Laptop-Akkus sind meist für 300–1000 Zyklen ausgelegt, danach lässt die Kapazität deutlich nach.' -Advice 'Die Gesundheit oben zeigt, wie viel Kapazität tatsächlich noch übrig ist.' }
            elseif ($cycles -gt 500) { Add-BCFinding -Level Info -Title "Ladezyklen: $cycles" -Detail 'Ein Zyklus ist eine volle Ladung. Laptop-Akkus sind meist für 300–1000 Zyklen ausgelegt.' }
        }
        if ($b.Manufacturer -match '^(|unknown|generic|oem|default|none|n/a)$') {
            Add-BCFinding -Level Info -Title 'Akku ohne erkennbaren Hersteller' -Detail 'Häufig bei Nachbau-Akkus. Original-Akkus nennen meist den Zellhersteller (z. B. SMP, LGC, Sunwoda, Celxpert, SDI).'
        }
        if ($smbDesign -and $design -gt 0 -and [math]::Abs($smbDesign - $design) / $design -gt 0.1) {
            Add-BCFinding -Level Info -Title 'Akku-Designkapazität weicht von der BIOS-Angabe ab' `
                -Detail ("Akku meldet {0} Wh, BIOS erwartet {1} Wh. Möglich bei Fremd-/Ersatzakkus oder Akkus mit anderer Kapazitätsvariante." -f (Format-BCNum ($design / 1000) 1), (Format-BCNum ($smbDesign / 1000) 1))
        }
        Set-BCFact 'battery.health' $health
        Set-BCFact 'battery.cycles' $cycles
        Set-BCFact 'battery.date' $mdate
        $summary += ("Gesundheit {0} %{1}" -f (Format-BCNum $health 0), $(if ($cycles) { ", $cycles Zyklen" } else { '' }))
        $i++
    }
    Set-BCSummary 'Akku' ($summary -join ' | ')

    # Kapazitätsverlauf aus dem Windows-Akkubericht
    if ($xml) {
        $entries = @()
        foreach ($e in @($xml.BatteryReport.History.HistoryEntry)) {
            try {
                $entries += (New-BCObject @('Start', [datetime]"$($e.LocalStartDate)", 'Full', [double]"$($e.FullChargeCapacity)", 'Design', [double]"$($e.DesignCapacity)", 'Cycles', "$($e.CycleCount)"))
            } catch { }
        }
        $entries = @($entries | Where-Object { $_.Full -gt 0 } | Sort-Object Start)
        if ($entries.Count -ge 2) {
            $span = (New-TimeSpan -Start $entries[0].Start -End $entries[-1].Start).TotalDays
            $jumps = @(); $designChanges = @()
            for ($k = 1; $k -lt $entries.Count; $k++) {
                $a = $entries[$k - 1]; $c = $entries[$k]
                $ref = if ($c.Design -gt 0) { $c.Design } else { $a.Full }
                if (($c.Full - $a.Full) -gt 0.1 * $ref) { $jumps += ('{0}: {1} → {2} Wh' -f (Format-BCDate $c.Start), (Format-BCNum ($a.Full / 1000) 1), (Format-BCNum ($c.Full / 1000) 1)) }
                if ($a.Design -gt 0 -and $c.Design -gt 0 -and $a.Design -ne $c.Design) { $designChanges += ('{0}: {1} → {2} Wh' -f (Format-BCDate $c.Start), (Format-BCNum ($a.Design / 1000) 1), (Format-BCNum ($c.Design / 1000) 1)) }
            }
            $vals = [double[]]@($entries | ForEach-Object { if ($_.Design -gt 0) { $_.Full / $_.Design * 100 } else { 0 } })
            Add-BCChart -Title "Akku-Gesundheit im Verlauf (% der Designkapazität, $([int]$span) Tage Historie)" -Values $vals -Unit '%' -Reference 80 -ReferenceLabel '80 %'
            if ($designChanges.Count -gt 0) {
                Add-BCFinding -Level Warnung -Title 'Designkapazität hat sich im Verlauf geändert' -Detail ('Laut Windows-Akkubericht hatte der Akku früher eine andere Nennkapazität: ' + ($designChanges -join ' · ')) -Advice 'Entweder wurde ein anderer Akku eingebaut (dann harmlos) oder die Akku-Werte wurden umprogrammiert.'
            }
            if ($jumps.Count -gt 0) {
                Add-BCFinding -Level Warnung -Title 'Sprunghafter Anstieg der Akkukapazität im Verlauf' -Detail ('Laut Windows-Akkubericht stieg die Kapazität plötzlich an: ' + ($jumps -join ' · ')) -Advice 'Akkus werden nicht von selbst besser. Mögliche Gründe: neuer Akku, Neukalibrierung oder geschönte Werte. Der Entladetest zeigt, ob die Laufzeit zur Angabe passt.'
            } elseif ($designChanges.Count -eq 0) {
                Add-BCFinding -Level OK -Title "Kapazitätsverlauf unauffällig ($([int]$span) Tage Historie)"
            }
        } else {
            Add-BCFinding -Level Info -Title 'Kein aussagekräftiger Kapazitätsverlauf vorhanden' -Detail 'Windows wurde vermutlich kürzlich neu installiert oder zurückgesetzt.'
        }
        Add-BCText -Title 'Windows-Akkubericht' -Text 'Der vollständige Windows-Akkubericht liegt im Berichtsordner (akkubericht-windows.html).'
    } elseif ($sys.OsBuildNumber -gt 0 -and $sys.OsBuildNumber -lt 9200) {
        Add-BCFinding -Level Info -Title 'Kein Kapazitätsverlauf verfügbar' -Detail 'Den Windows-Akkubericht mit Verlauf gibt es erst ab Windows 8. Aussagekräftig bleiben Gesundheit, Zyklen und der Entladetest.'
    } else {
        Add-BCFinding -Level Info -Title 'Windows-Akkubericht konnte nicht erstellt werden' -Detail 'Kapazitätsverlauf daher nicht auswertbar.'
    }
}

Register-BuyCheck -Id 'power.charging' -Category 'Akku & Stromversorgung' -Order 20 -RunOrder 200 -Seconds 60 -Interactive `
    -Title 'Netzteil & Ladefunktion' `
    -Description 'Prüft, ob das Netzteil erkannt wird und der Akku lädt. Du wirst gebeten, das Netzteil kurz abzuziehen und wieder anzustecken (Buchse/Kabel auf Wackelkontakt prüfen). Hinweis: Viele Laptops haben einen Akkuschonmodus, der nur bis 60–80 % lädt – das ist kein Defekt.' `
    -Profiles @('quick', 'thorough', 'linux') `
    -Run {
    $bat = Get-BCBattery
    if (-not $bat -or -not $bat.Present) { Add-BCFinding -Level Info -Title 'Kein Akku – Ladetest entfällt'; return }
    if (-not (Wait-BCPower -Online $true -Message 'Bitte das Netzteil anschließen.')) {
        Add-BCFinding -Level Warnung -Title 'Netzteil wurde nicht angeschlossen bzw. nicht erkannt' -Detail 'Windows hat während des Tests kein Netzteil erkannt.' -Advice 'Wurde es angeschlossen, liegt die Ursache bei Netzteil, Kabel, Ladebuchse oder Ladeschaltung.'
        return
    }
    Start-Sleep -Seconds 5
    $s1 = Get-BCBatteryStatus
    $chargeInfo = ''
    if ($s1.Charging) { $chargeInfo = "lädt mit ca. $(Format-BCNum ($s1.ChargeRateMW / 1000) 1) W" }
    elseif ($null -ne $s1.Percent -and $s1.Percent -ge 95) { $chargeInfo = 'Akku voll' }
    else {
        Start-Sleep -Seconds 10
        $s1 = Get-BCBatteryStatus
        if ($s1.Charging) { $chargeInfo = "lädt mit ca. $(Format-BCNum ($s1.ChargeRateMW / 1000) 1) W" }
    }
    if ($chargeInfo) { Add-BCFinding -Level OK -Title "Netzteil erkannt, $chargeInfo" -Detail "Ladestand: $($s1.Percent) %" }
    else {
        Add-BCFinding -Level Info -Title "Netzteil erkannt, Akku lädt aber nicht (Ladestand $($s1.Percent) %)" `
            -Detail 'Oft ist ein Akkuschonmodus aktiv (z. B. Lenovo Vantage „Erhaltungsmodus“, Dell „Primär Netzbetrieb“, HP „Battery Care“).' `
            -Advice 'Ist kein Schonmodus aktiv, liegt ein Lade- bzw. Netzteilproblem vor.'
    }

    $unplug = Wait-BCPower -Online $false -Message 'Bitte jetzt das Netzteil abziehen (am Laptop). Achte dabei darauf, ob der Stecker fest sitzt oder wackelt.'
    if (-not $unplug) { Add-BCFinding -Level Info -Title 'Abzieh-Test übersprungen'; return }
    Start-Sleep -Seconds 2
    $s2 = Get-BCBatteryStatus
    $replug = Wait-BCPower -Online $true -Message 'Bitte das Netzteil wieder anstecken.'
    if (-not $replug) {
        Add-BCFinding -Level Warnung -Title 'Netzteil wurde nach dem Wiederanstecken nicht erkannt' -Detail 'Nach dem Abziehen und Wiederanstecken hat Windows das Netzteil nicht erkannt.' -Advice 'Geht die Ladeanzeige beim Bewegen des Steckers an und aus, hat die Buchse einen Wackelkontakt.'
    } else {
        Add-BCFinding -Level OK -Title 'Wechsel Netz ↔ Akku wird korrekt erkannt' -Detail "Im Akkubetrieb: Verbrauch ca. $(Format-BCNum ($s2.DischargeRateMW / 1000) 1) W"
    }
    $q = Show-BCChoice -Title 'Netzteil' -Question 'Welches Netzteil liegt dabei?' -Options @(
        'Original-Netzteil des Herstellers, Leistung (Watt) passt zum Gerät',
        'Fremd-/Universalnetzteil',
        'Original, aber mit geringerer Leistung als vorgesehen',
        'Kein Netzteil dabei / unklar') -Comment
    switch ($q.Choice) {
        0 { Add-BCFinding -Level OK -Title 'Original-Netzteil mit passender Leistung' -Detail $q.Comment }
        1 { Add-BCFinding -Level Info -Title 'Fremd-/Universalnetzteil' -Detail $q.Comment -Advice 'Manche Laptops laden mit fremden Netzteilen langsamer oder drosseln die Leistung.' }
        2 { Add-BCFinding -Level Warnung -Title 'Netzteil mit zu geringer Leistung' -Detail $q.Comment -Advice 'Das Gerät lädt damit langsam und drosselt unter Last die Leistung.' }
        default { Add-BCFinding -Level Info -Title 'Netzteil: keine Angabe' -Detail $q.Comment }
    }
}

Register-BuyCheck -Id 'battery.discharge' -Category 'Akku & Stromversorgung' -Order 30 -RunOrder 330 -Seconds 30 -Interactive `
    -Title 'Entladetest unter Last' `
    -Description 'Misst bei abgezogenem Netzteil und Rechenlast, wie schnell der Akku leer wird (Watt, %/Minute, geschätzte Laufzeit). Schwache Zellen oder geschönte Akkuwerte zeigen sich durch Prozentsprünge oder eine Ladeanzeige, die schneller fällt als die verbrauchte Energie. Stoppt automatisch spätestens bei 20 % Restladung.' `
    -Profiles @('thorough') `
    -Options @(@{ Key = 'minutes'; Label = 'Dauer'; Default = 6; Min = 2; Max = 30; SecondsPerUnit = 60; Unit = 'Minuten' }) `
    -Run {
    param($Options)
    $bat = Get-BCBattery
    if (-not $bat -or -not $bat.Present) { Add-BCFinding -Level Info -Title 'Kein Akku – Entladetest entfällt'; return }
    $s0 = Get-BCBatteryStatus
    if ($null -ne $s0.Percent -and $s0.Percent -lt 35) {
        Add-BCFinding -Level Info -Title "Akku zu leer für den Entladetest ($($s0.Percent) %)" -Detail 'Erst aufladen (mind. 35 %), dann den Test erneut auswählen.'
        return
    }
    $duration = [int]([double]$Options['minutes'] * 60)
    if (-not (Wait-BCPower -Online $false -Message "Bitte das Netzteil abziehen. Der Laptop läuft dann ca. $([int]($duration / 60)) Minuten unter Last im Akkubetrieb (Stopp spätestens bei 20 %).")) {
        Add-BCFinding -Level Info -Title 'Entladetest übersprungen'; return
    }
    $full = [double](@($bat.Batteries)[0].FullMWh)
    $stress = Start-BCCpuStress -Threads ([math]::Max(1, [int]([Environment]::ProcessorCount / 2)))
    $samples = New-Object 'System.Collections.Generic.List[object]'
    $stopReason = 'Zeit abgelaufen'
    $sw = [Diagnostics.Stopwatch]::StartNew()
    try {
        while ($sw.Elapsed.TotalSeconds -lt $duration) {
            $st = Get-BCBatteryStatus
            $samples.Add((New-BCObject @('T', $sw.Elapsed.TotalSeconds, 'Pct', $st.Percent, 'MWh', $st.RemainingMWh, 'MW', $st.DischargeRateMW, 'MV', $st.VoltageMV, 'Online', $st.PowerOnline)))
            Write-BCProgress ("Entladetest: Ladestand {0} % · Verbrauch {1} W · Spannung {2} V · noch {3} s  (Esc = abbrechen)" -f $st.Percent, (Format-BCNum ($st.DischargeRateMW / 1000) 1), (Format-BCNum ($st.VoltageMV / 1000) 2), [int]($duration - $sw.Elapsed.TotalSeconds))
            if ($st.PowerOnline) { $stopReason = 'Netzteil wurde angeschlossen'; break }
            if ($null -ne $st.Percent -and $st.Percent -le 20) { $stopReason = 'Sicherheitsstopp bei 20 % Restladung'; break }
            if (Test-BCEscape) { $stopReason = 'vom Benutzer abgebrochen'; break }
            Start-Sleep -Seconds 5
        }
    } finally {
        Stop-BCCpuStress $stress
        Complete-BCProgress
    }
    [void](Wait-BCPower -Online $true -Message 'Test beendet. Bitte das Netzteil wieder anschließen.')

    $s = @($samples | Where-Object { $null -ne $_.Pct })
    if ($s.Count -lt 3) { Add-BCFinding -Level Fehler -Title 'Zu wenige Messwerte' -Detail $stopReason; return }
    $first = $s[0]; $last = $s[-1]
    $minutes = ($last.T - $first.T) / 60
    $pctDrop = [double]$first.Pct - [double]$last.Pct
    $mwhDrop = if ($first.MWh -and $last.MWh) { [double]$first.MWh - [double]$last.MWh } else { $null }
    $avgW = (@($s | Where-Object { $_.MW -gt 0 } | ForEach-Object { [double]$_.MW }) | Measure-Object -Average).Average / 1000
    $pctPerMin = if ($minutes -gt 0) { $pctDrop / $minutes } else { $null }
    $runtimeH = if ($avgW -gt 0 -and $full -gt 0) { ($full / 1000) / $avgW } else { $null }
    $maxStep = 0
    for ($k = 1; $k -lt $s.Count; $k++) { $maxStep = [math]::Max($maxStep, [double]$s[$k - 1].Pct - [double]$s[$k].Pct) }
    Add-BCFacts -Title 'Entladetest' -Data ((New-BCOrdered @(
        'Dauer', "$(Format-BCNum $minutes 1) Min. ($stopReason)",
        'Ladestand Start → Ende', $("$($first.Pct) % → $($last.Pct) %" + $(if ($null -ne $pctPerMin) { " ($(Format-BCNum $pctPerMin 2) %/Min.)" } else { '' })),
        'Verbrauchte Energie (Akku-Zähler)', $(if ($null -ne $mwhDrop) { "$(Format-BCNum ($mwhDrop / 1000) 2) Wh" } else { '' }),
        'Leistungsaufnahme Ø', $(if ($avgW) { "$(Format-BCNum $avgW 1) W" } else { '' }),
        'Spannung Start → Ende', "$(Format-BCNum ($first.MV / 1000) 2) V → $(Format-BCNum ($last.MV / 1000) 2) V",
        'Geschätzte Laufzeit bei dieser Last', $(if ($runtimeH) { "$(Format-BCNum $runtimeH 1) h (bei voller Ladung)" } else { '' }),
        'Größter Sprung zwischen zwei Messungen', "$maxStep Prozentpunkte (in 5 s)"
    )))
    Add-BCChart -Title 'Ladestand während des Tests (%)' -Values ([double[]]@($s | ForEach-Object { [double]$_.Pct })) -Unit '%'
    if ($maxStep -ge 4) {
        Add-BCFinding -Level Warnung -Title "Ladestand fiel sprunghaft um $maxStep Prozentpunkte" -Detail 'Innerhalb von 5 Sekunden. Normal sind höchstens 1–2 Prozentpunkte.' -Advice 'Typisch für schwache Akkuzellen, die unter Last einbrechen. Solche Geräte gehen oft plötzlich aus, obwohl noch Ladung angezeigt wird.'
    }
    if ($null -ne $mwhDrop -and $mwhDrop -gt 0 -and $full -gt 0 -and $pctDrop -ge 3) {
        $expectedPct = $mwhDrop / $full * 100
        if ($pctDrop -gt $expectedPct * 1.6 + 1) {
            Add-BCFinding -Level Warnung -Title 'Ladeanzeige fällt schneller als die verbrauchte Energie' `
                -Detail ("Verbraucht {0} Wh ≈ {1} %, Anzeige fiel aber um {2} %." -f (Format-BCNum ($mwhDrop / 1000) 2), (Format-BCNum $expectedPct 1), $pctDrop) `
                -Advice 'Der Akku meldet vermutlich mehr Kapazität, als er hat (falsch kalibriert oder geschönt). Die echte Laufzeit wird kürzer sein, als die Gesundheit oben vermuten lässt.'
        }
    }
    if ($runtimeH) {
        if ($runtimeH -lt 0.5) { Add-BCFinding -Level Warnung -Title "Sehr kurze Laufzeit unter Last: ca. $(Format-BCNum ($runtimeH * 60) 0) Minuten" -Detail 'Hochgerechnet auf einen vollen Akku bei der Last während des Tests.' -Advice 'Ohne Netzteil kaum nutzbar.' }
        else { Add-BCFinding -Level OK -Title "Geschätzte Laufzeit unter Last: ca. $(Format-BCNum $runtimeH 1) h" -Detail 'Bei leichter Nutzung (Surfen, Office) entsprechend länger.' }
    }
}
