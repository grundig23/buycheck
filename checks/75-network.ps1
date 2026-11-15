# BuyCheck – Netzwerk & Funk: WLAN, Bluetooth, LAN (nur lesend, es wird nichts verbunden oder umgeschaltet)

Register-BuyCheck -Id 'net.wifi' -Category 'Netzwerk & Funk' -Order 10 -RunOrder 150 -Seconds 15 `
    -Title 'WLAN, Bluetooth & LAN' `
    -Description 'Prüft, ob WLAN-, Bluetooth- und LAN-Adapter vorhanden und aktiv sind, und listet erreichbare WLAN-Netze mit Signalstärke (schwacher Empfang trotz Router in der Nähe deutet auf ein abgelöstes Antennenkabel hin). Es wird keine Verbindung hergestellt und nichts umgeschaltet.' `
    -Profiles @('quick', 'thorough', 'linux', 'auto') `
    -Run {
    $adapters = @()
    try { $adapters = @(Get-NetAdapter -Physical -IncludeHidden -ErrorAction Stop) } catch { }
    $wifi = @($adapters | Where-Object { $_.NdisPhysicalMedium -eq 9 -or "$($_.InterfaceDescription)" -match '(?i)Wi-?Fi|Wireless|WLAN|802\.11' })
    $eth = @($adapters | Where-Object { ($_.NdisPhysicalMedium -eq 14 -or "$($_.InterfaceDescription)" -match '(?i)Ethernet|GbE|Gigabit|2\.5G') -and ($wifi -notcontains $_) -and "$($_.InterfaceDescription)" -notmatch '(?i)Bluetooth|Virtual|VPN|TAP' })
    $rows = foreach ($a in @($wifi + $eth)) {
        $ids = Get-BCPciIds "$($a.PnPDeviceID)"
        [pscustomobject]@{ 'Adapter' = "$($a.InterfaceDescription)"; 'Typ' = if ($wifi -contains $a) { 'WLAN' } else { 'LAN' }; 'Status' = "$($a.Status)"; 'Hersteller (PCI/USB)' = "$(Get-BCVendorName $ids.Ven) ($($ids.Ven):$($ids.Dev))"; 'Geschwindigkeit' = "$($a.LinkSpeed)" }
    }
    Add-BCTable -Title 'Netzwerkadapter' -Rows @($rows)

    if ($wifi.Count -eq 0) {
        Add-BCFinding -Level Warnung -Title 'Kein WLAN-Adapter gefunden' -Advice 'WLAN-Karte fehlt, ist defekt oder im BIOS abgeschaltet. Unbedingt klären.'
    } else {
        foreach ($w in $wifi) {
            if ("$($w.Status)" -match 'Disabled|Deaktiviert') {
                Add-BCFinding -Level Warnung -Title "WLAN-Adapter ist deaktiviert: $($w.InterfaceDescription)" -Advice 'Verkäufer bitten, ihn zu aktivieren. Deaktivierte Adapter können einen Defekt verbergen.'
            }
        }
        $ifOut = ''
        try { $ifOut = (& netsh.exe wlan show interfaces 2>&1 | Out-String) } catch { }
        $connSignal = $null
        if ($ifOut -match '(?im)^\s*Signal\s*:\s*(\d+)\s*%') { $connSignal = [int]$Matches[1] }
        $netOut = ''
        try { $netOut = (& netsh.exe wlan show networks mode=bssid 2>&1 | Out-String) } catch { }
        $ssids = [regex]::Matches($netOut, '(?im)^SSID\s+\d+\s*:').Count
        $signals = @([regex]::Matches($netOut, '(?im)^\s*Signal\s*:\s*(\d+)\s*%') | ForEach-Object { [int]$_.Groups[1].Value })
        $blocked = ($netOut -match '(?i)location|Standort|Ortung') -and $ssids -eq 0
        if ($null -ne $connSignal) { Add-BCFinding -Level OK -Title "WLAN verbunden, Signal $connSignal %" }
        if ($ssids -gt 0) {
            $best = ($signals | Measure-Object -Maximum).Maximum
            $lvl = if ($best -ge 50) { 'OK' } else { 'Info' }
            Add-BCFinding -Level $lvl -Title "$ssids WLAN-Netz(e) in Reichweite, bestes Signal $best %" -Detail $(if ($best -lt 50) { 'Eher schwacher Empfang – Abstand zum Router bedenken; sonst Antennen prüfen.' } else { '' })
        } elseif ($blocked) {
            $r = Show-BCChoice -Title 'WLAN' -Question "Windows gibt die WLAN-Liste ohne Standortfreigabe nicht heraus (das Programm ändert diese Einstellung bewusst nicht).`n`nBitte unten rechts in der Taskleiste auf das WLAN-Symbol klicken: Werden Netze in der Umgebung angezeigt?" -Options @(
                'Ja, mehrere Netze mit gutem Empfang', 'Ja, aber nur mit schwachem Empfang', 'Nein, keine Netze / WLAN lässt sich nicht einschalten', 'Nicht geprüft') -Comment
            switch ($r.Choice) {
                0 { Add-BCFinding -Level OK -Title 'WLAN-Netze werden angezeigt (Sichtprüfung)' -Detail $r.Comment }
                1 { Add-BCFinding -Level Info -Title 'WLAN-Netze nur mit schwachem Empfang' -Detail $r.Comment -Advice 'Bei Router in der Nähe Hinweis auf gelöste/defekte Antennenkabel.' }
                2 { Add-BCFinding -Level Warnung -Title 'Keine WLAN-Netze sichtbar' -Detail $r.Comment -Advice 'Flugmodus/WLAN-Schalter prüfen; sonst WLAN-Karte oder Antennen defekt.' }
                default { Add-BCFinding -Level Info -Title 'WLAN-Empfang nicht geprüft' -Detail $r.Comment }
            }
        } else {
            Add-BCFinding -Level Info -Title 'Keine WLAN-Netze gefunden' -Detail 'Flugmodus aktiv, keine Netze in Reichweite oder Empfangsproblem. Mit Handy-Hotspot gegenprüfen.'
        }
    }

    $bt = @(Get-BCPnp | Where-Object { "$($_.PNPClass)" -eq 'Bluetooth' -and "$($_.Name)" -match '(?i)Bluetooth|Wireless' -and "$($_.Name)" -notmatch '(?i)Enumerator|LE Generic|RFCOMM|Avrcp|Microsoft Bluetooth|Gerät|Device \(' })
    if ($bt.Count -eq 0) {
        Add-BCFinding -Level Info -Title 'Kein Bluetooth-Adapter gefunden' -Detail 'Bei den meisten Laptops vorhanden (oft zusammen mit dem WLAN-Chip). Fehlt er, ggf. im BIOS deaktiviert.'
    } else {
        $bad = @($bt | Where-Object { [int]$_.ConfigManagerErrorCode -ne 0 })
        if ($bad.Count -gt 0) { Add-BCFinding -Level Warnung -Title 'Bluetooth-Adapter meldet Problem/ist deaktiviert' -Detail (@($bad | ForEach-Object { "$($_.Name) (Code $($_.ConfigManagerErrorCode))" }) -join ', ') }
        else { Add-BCFinding -Level OK -Title "Bluetooth vorhanden: $(@($bt | ForEach-Object { $_.Name } | Select-Object -Unique) -join ', ')" }
    }
    if ($eth.Count -gt 0) { Add-BCFinding -Level Info -Title "LAN-Anschluss vorhanden: $(@($eth | ForEach-Object { $_.InterfaceDescription }) -join ', ')" -Detail 'Funktion nur mit Netzwerkkabel prüfbar.' }
}
