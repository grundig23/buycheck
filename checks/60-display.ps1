# BuyCheck – Bildschirm & Grafik: Panel-Daten (EDID), Grafikchip, Pixeltest, externer Bildausgang

Register-BuyCheck -Id 'display.info' -Category 'Bildschirm & Grafik' -Order 10 -RunOrder 60 -Seconds 5 `
    -Title 'Display-Daten (Panel, Auflösung, Baujahr)' `
    -Description 'Liest aus dem Display selbst (EDID) Panelhersteller, Panel-Teilenummer, Herstellungsjahr, native Auflösung und Bildwiederholrate. Mit der Teilenummer lassen sich die Panel-Daten (IPS/TN, Helligkeit, Farbraum) nachschlagen. Ein deutlich jüngeres Panel als der Rest des Geräts deutet auf einen Displaytausch hin.' `
    -Profiles @('quick', 'thorough', 'linux', 'auto') `
    -Run {
    $mons = @(Get-BCMonitors)
    if ($mons.Count -eq 0) { Add-BCFinding -Level Fehler -Title 'Keine Bildschirmdaten verfügbar'; return }
    $vc = @(Get-BCCim Win32_VideoController | Where-Object { $_.CurrentHorizontalResolution -gt 0 })
    $internal = @($mons | Where-Object { $_.Internal })
    if ($internal.Count -eq 0 -and $mons.Count -eq 1) { $internal = $mons }
    foreach ($m in $mons) {
        $e = $m.Edid
        $maker = if ($e -and $e.Valid) { $e.ManufacturerId } else { $m.Manufacturer }
        $makerName = if ($script:BCPanelMakers.ContainsKey("$maker")) { $script:BCPanelMakers["$maker"] } else { $maker }
        $texts = if ($e -and $e.Valid) { @($e.TextDescriptors) } else { @() }
        # Teilenummer = Textfeld mit Ziffern (z. B. "NV140FHM-N4B"); andere Felder enthalten oft nur den Herstellernamen
        $part = (@($texts | Where-Object { $_ -match '\d' -and $_.Length -ge 6 }) -join ' / ')
        if (-not $part) { $part = ($texts -join ' / ') }
        $diag = if ($e -and $e.Valid -and $e.DiagonalInches -gt 5) { "$(Format-BCNum $e.DiagonalInches 1)""" } elseif ($m.WidthCm -gt 0) { "$(Format-BCNum ([math]::Sqrt($m.WidthCm * $m.WidthCm + $m.HeightCm * $m.HeightCm) / 2.54) 1)""" } else { '' }
        $native = if ($e -and $e.Valid -and $e.NativeWidth -gt 0) { "$($e.NativeWidth) × $($e.NativeHeight) @ $(Format-BCNum $e.NativeRefreshHz 0) Hz" } else { '' }
        $title = if ($m.Internal) { 'Eingebautes Display' } else { "Externer Bildschirm ($($m.FriendlyName))" }
        Add-BCFacts -Title $title -Data ([ordered]@{
                'Panelhersteller (Kennung)'  = "$makerName ($maker)"
                'Panel-Teilenummer'          = $part
                'Name'                       = if ($e -and $e.MonitorName) { $e.MonitorName } else { $m.FriendlyName }
                'Produktcode'                = if ($e -and $e.Valid) { $e.ProductCodeHex } else { $m.ProductCode }
                'Herstellungsjahr / Woche'   = if ($m.Year -gt 0) { "$($m.Year) / KW $($m.Week)" } else { '' }
                'Diagonale (aus EDID)'       = $diag
                'Native Auflösung'           = $native
                'Anschluss'                  = if ($m.Internal) { 'intern (eDP/LVDS)' } else { "extern (Typ $($m.Technology))" }
            })
        if ($m.Internal) {
            Set-BCFact 'panel.year' $m.Year
            $res = ''
            if ($vc.Count -gt 0) { $res = "$($vc[0].CurrentHorizontalResolution) × $($vc[0].CurrentVerticalResolution) @ $($vc[0].CurrentRefreshRate) Hz" }
            Set-BCSummary 'Display' ("{0}{1}, {2}{3}" -f $diag, $(if ($native) { ' ' + $native } else { '' }), $makerName, $(if ($part) { " $part" } else { '' }))
            Add-BCFinding -Level Info -Title "Eingebautes Display: $diag $native" -Detail "Panel: $makerName $part · Baujahr $($m.Year)"
            if ($part) {
                $q = [uri]::EscapeDataString("$part panel datasheet")
                Add-BCLink -Title "Panel-Datenblatt suchen ($part): IPS/TN, Helligkeit, Farbraum" -Url "https://duckduckgo.com/?q=$q"
            }
            if ($e -and $e.Valid -and $vc.Count -gt 0 -and $e.NativeWidth -gt 0 -and [int]$vc[0].CurrentHorizontalResolution -lt $e.NativeWidth -and $mons.Count -eq 1) {
                Add-BCFinding -Level Info -Title 'Windows nutzt nicht die native Auflösung' -Detail "Aktuell $res, nativ $($e.NativeWidth) × $($e.NativeHeight). Bild wirkt dadurch unscharf (Einstellungssache)."
            }
            if ($maker -in @('LEN', 'DEL', 'HWP')) {
                Add-BCFinding -Level Info -Title 'Panel meldet die Kennung des Laptop-Herstellers' -Detail 'Der eigentliche Panelhersteller ist so nicht erkennbar (bei Markengeräten üblich).'
            }
        }
    }
    if ($internal.Count -eq 0) { Add-BCFinding -Level Warnung -Title 'Kein eingebautes Display erkannt' -Detail 'Bei Laptops ungewöhnlich (Display defekt/abgeschaltet, oder nur externer Bildschirm aktiv).' }
}

Register-BuyCheck -Id 'gpu.info' -Category 'Bildschirm & Grafik' -Order 20 -RunOrder 70 -Seconds 5 `
    -Title 'Grafikchip(s): Echtheit & Fehlerstatus' `
    -Description 'Listet die Grafikchips mit ihren PCI-Kennungen. Prüft, ob der angezeigte Name zum tatsächlichen Hersteller-Code passt (umbenannte Grafikkarten), ob ein Grafiktreiber installiert ist und ob der Chip einen Fehler meldet (Code 43 deutet oft auf einen Hardwaredefekt).' `
    -Profiles @('quick', 'thorough', 'linux', 'auto') `
    -Run {
    $gpus = @(Get-BCCim Win32_VideoController)
    if ($gpus.Count -eq 0) { Add-BCFinding -Level Warnung -Title 'Kein Grafikchip gefunden'; return }
    $rows = @(); $names = @()
    foreach ($g in $gpus) {
        $ids = Get-BCPciIds "$($g.PNPDeviceID)"
        $vendor = Get-BCVendorName $ids.Ven
        $vram = $null
        try {
            foreach ($k in @(Get-ChildItem 'HKLM:\SYSTEM\CurrentControlSet\Control\Class\{4d36e968-e325-11ce-bfc1-08002be10318}' -ErrorAction Stop)) {
                $mid = Get-BCRegValue $k.PSPath 'MatchingDeviceId'
                if ($mid -and $ids.Ven -and "$mid" -match "ven_$($ids.Ven)&dev_$($ids.Dev)") {
                    $q = Get-BCRegValue $k.PSPath 'HardwareInformation.qwMemorySize'
                    if ($q) { $vram = [double]$q; break }
                }
            }
        } catch { }
        $rows += [pscustomobject]@{
            'Name' = "$($g.Name)"; 'Hersteller (PCI)' = if ($vendor) { "$vendor ($($ids.Ven))" } else { "$($ids.Ven)" }; 'Geräte-ID' = "$($ids.Dev)"
            'Grafikspeicher' = if ($vram) { Format-BCBytes $vram -Binary } else { '' }
            'Treiber' = "$($g.DriverVersion) ($(Format-BCDate $g.DriverDate))"; 'Status' = "$($g.Status) / Code $($g.ConfigManagerErrorCode)"
        }
        $names += "$($g.Name)"
        $n = "$($g.Name)"
        $mismatch = $false
        if ($n -match '(?i)NVIDIA|GeForce|Quadro|\bRTX\b|\bGTX\b|\bMX\s?\d{3}') { if ($ids.Ven -and $ids.Ven -ne '10DE') { $mismatch = $true } }
        elseif ($n -match '(?i)Radeon|\bAMD\b|FirePro') { if ($ids.Ven -and $ids.Ven -ne '1002') { $mismatch = $true } }
        elseif ($n -match '(?i)\bIntel\b|Iris|UHD Graphics|Arc\b') { if ($ids.Ven -and $ids.Ven -ne '8086') { $mismatch = $true } }
        if ($mismatch) {
            Add-BCFinding -Level Kritisch -Title "Grafikchip-Name passt nicht zum Hersteller-Code: $n" -Detail "PCI-Hersteller ist $vendor ($($ids.Ven))." -Advice 'Hinweis auf einen umbenannten (gefälschten) Grafikchip. Vom Kauf abraten.'
        }
        if ($n -match '(?i)Microsoft Basic Display|Microsoft Basic Render|Standard VGA') {
            Add-BCFinding -Level Warnung -Title 'Kein Grafiktreiber installiert (Microsoft-Standardtreiber)' -Detail 'Grafikchip kann so nicht vollständig geprüft werden; manchmal Zeichen eines defekten Chips.' -Advice 'Verkäufer fragen; Treiber nach dem Kauf installieren.'
        }
        $code = [int]$g.ConfigManagerErrorCode
        if ($code -eq 43) {
            Add-BCFinding -Level Kritisch -Title "Grafikchip meldet Fehler (Code 43): $n" -Advice 'Häufig ein Hardwaredefekt (z. B. Grafikchip/Lötstellen). Vom Kauf abraten oder nur als Defektgerät.'
        } elseif ($code -eq 22) {
            Add-BCFinding -Level Warnung -Title "Grafikchip ist deaktiviert: $n" -Advice 'Deaktivierte Geräte können einen Defekt verbergen. Verkäufer fragen.'
        } elseif ($code -ne 0) {
            Add-BCFinding -Level Warnung -Title "Grafikchip mit Problem (Code $code): $n"
        }
        if ($ids.Ven -and $ids.Dev) { Add-BCLink -Title "Geräte-ID nachschlagen: $n ($($ids.Ven):$($ids.Dev))" -Url "https://devicehunt.com/view/type/pci/vendor/$($ids.Ven)/device/$($ids.Dev)" }
    }
    Add-BCTable -Title 'Grafikchips' -Rows $rows
    Set-BCSummary 'Grafik' ($names -join ' + ')
    if (@($gpus | Where-Object { [int]$_.ConfigManagerErrorCode -eq 0 }).Count -eq $gpus.Count) {
        Add-BCFinding -Level OK -Title "Grafik: $($names -join ' + ')" -Detail 'Kein Fehlerstatus gemeldet.'
    }
}

Register-BuyCheck -Id 'display.pixeltest' -Category 'Bildschirm & Grafik' -Order 30 -RunOrder 210 -Seconds 90 -Interactive `
    -Title 'Pixelfehler- und Ausleuchtungstest' `
    -Description 'Zeigt den Bildschirm vollflächig in verschiedenen Farben und Farbverläufen. Du suchst nach toten/hellen Pixeln, Flecken, ungleichmäßiger Ausleuchtung (Lichthöfe), Streifen und Druckstellen. Danach wird abgefragt, was dir aufgefallen ist, und ob das Bild beim Bewegen des Deckels flackert (Hinweis auf ein defektes Displaykabel).' `
    -Profiles @('quick', 'thorough', 'linux') `
    -Run {
    if (-not (Show-BCInfo -Title 'Pixeltest' -Message "Gleich wird der Bildschirm vollflächig eingefärbt.`n`n• Leertaste oder Klick = nächste Farbe, Pfeil links = zurück, Esc = beenden`n• Schau dir jede Farbe aus normalem Abstand und leicht schräg an.`n• Am besten Raumlicht etwas abdunkeln und die Helligkeit hochstellen.`n`nAm Ende wirst du gefragt, was dir aufgefallen ist." -OkText 'Test starten' -CancelText 'Überspringen')) {
        Add-BCFinding -Level Info -Title 'Pixeltest übersprungen'; return
    }
    $f = New-Object BuyCheck.PixelTestForm
    try { [void]$f.ShowDialog() } finally { $f.Dispose() }
    $opts = @('Keine Auffälligkeiten', 'Helle oder farbige Dauerpixel', 'Dunkle (tote) Pixel', 'Flecken, Wolken oder ungleichmäßige Helligkeit',
        'Helle Ränder / Lichthöfe (Backlight Bleeding)', 'Streifen oder Linien', 'Kratzer oder Druckstellen', 'Harte Stufen im Farbverlauf')
    $r = Show-BCMulti -Title 'Pixeltest' -Question 'Was ist dir aufgefallen? (Mehrfachauswahl)' -Options $opts -Comment
    $c = $r.Checked
    $problems = $false
    if ($c.Length -ge 8) {
        if ($c[1]) { Add-BCFinding -Level Warnung -Title 'Helle oder farbige Dauerpixel' -Detail $r.Comment -Advice 'Stören meist am meisten; nicht reparierbar (nur Paneltausch).'; $problems = $true }
        if ($c[2]) { Add-BCFinding -Level Warnung -Title 'Tote (dunkle) Pixel' -Detail $r.Comment -Advice 'Einzelne sind nach ISO 9241-307 Klasse II zulässig, beim Gebrauchtkauf aber Verhandlungssache.'; $problems = $true }
        if ($c[3]) { Add-BCFinding -Level Warnung -Title 'Flecken oder ungleichmäßige Helligkeit' -Detail $r.Comment -Advice 'Kann auf Druckschäden oder alternde Hintergrundbeleuchtung hindeuten.'; $problems = $true }
        if ($c[4]) { Add-BCFinding -Level Info -Title 'Lichthöfe am Rand (Backlight Bleeding)' -Detail $r.Comment -Advice 'Bei LCDs in gewissem Maß normal; nur bei starker Ausprägung störend.'; $problems = $true }
        if ($c[5]) { Add-BCFinding -Level Kritisch -Title 'Streifen oder Linien im Bild' -Detail $r.Comment -Advice 'Meist Panel- oder Kabeldefekt – Reparatur teuer.'; $problems = $true }
        if ($c[6]) { Add-BCFinding -Level Warnung -Title 'Kratzer oder Druckstellen' -Detail $r.Comment; $problems = $true }
        if ($c[7]) { Add-BCFinding -Level Info -Title 'Farbverlauf mit harten Stufen' -Detail $r.Comment -Advice 'Typisch für einfache Panels (6-Bit); kein Defekt.'; $problems = $true }
        if ($c[0] -and -not $problems) { Add-BCFinding -Level OK -Title 'Pixeltest ohne Auffälligkeiten' -Detail $r.Comment }
        if (-not $c[0] -and -not $problems) { Add-BCFinding -Level Info -Title 'Pixeltest: keine Angabe gemacht' }
    }
    $hinge = Show-BCChoice -Title 'Displaykabel' -Question 'Bitte den Deckel langsam ganz auf- und wieder halb zuklappen. Flackert das Bild, verfärbt es sich oder fällt es aus?' -Options @('Nein, das Bild bleibt stabil', 'Ja, Flackern/Verfärbung/Ausfall', 'Nicht geprüft')
    switch ($hinge.Choice) {
        0 { Add-BCFinding -Level OK -Title 'Bild bleibt beim Bewegen des Deckels stabil' }
        1 { Add-BCFinding -Level Kritisch -Title 'Bild flackert/fällt aus beim Bewegen des Deckels' -Advice 'Typisch für ein beschädigtes Displaykabel oder Scharnierschaden – Reparatur nötig.' }
        default { Add-BCFinding -Level Info -Title 'Deckel-/Kabeltest nicht durchgeführt' }
    }
}

Register-BuyCheck -Id 'ports.video' -Category 'Bildschirm & Grafik' -Order 40 -RunOrder 280 -Seconds 90 -Interactive `
    -Title 'Bildausgang (HDMI / USB-C / DisplayPort)' `
    -Description 'Prüft mit einem externen Monitor oder Fernseher, ob die Bildausgänge funktionieren. Nur sinnvoll, wenn vor Ort ein Bildschirm und das passende Kabel verfügbar sind.' `
    -Profiles @('thorough') `
    -Run {
    $f = New-Object BuyCheck.ExternalDisplayForm
    $r = Show-BCTestForm $f
    Add-BCInteractiveResult -Result $r -OkTitle 'Bildausgang funktioniert' -ProblemTitle 'Problem mit dem Bildausgang' -ProblemLevel Warnung -Advice 'Defekte Buchse oder Grafikausgang – Reparatur nötig.'
}
