# BuyCheck – Linux-Eignung: Bauteile, die unter Linux häufig Probleme machen (Stand 2026)

Register-BuyCheck -Id 'linux.compat' -Category 'Linux' -Order 10 -RunOrder 140 -Seconds 10 `
    -Title 'Linux-Eignung' `
    -Description 'Prüft Bauteile, die unter Linux erfahrungsgemäß Ärger machen: Webcams mit Intel IPU6/IPU7 (MIPI), Intel VMD/RAID-Modus der SSD (Installer findet die SSD nicht), Broadcom-WLAN, Fingerabdruckleser, NVIDIA-Hybridgrafik, ARM-Prozessoren (Snapdragon) und ob Secure Boot für Linux freigegeben ist (Microsoft-Drittanbieter-Zertifikat).' `
    -Profiles @('thorough', 'linux') `
    -Run {
    $c = Get-BCCpu
    $pnp = @(Get-BCPnp)
    $rows = New-Object 'System.Collections.Generic.List[object]'
    $add = { param($part, $found, $rating) $rows.Add((New-BCObject @('Bauteil', $part, 'Gefunden', $found, 'Linux', $rating))) }

    # Prozessor-Architektur
    if ($c.Architecture -eq 12 -or $c.Vendor -eq 'Qualcomm') {
        & $add 'Prozessor' $c.BestName 'problematisch'
        Add-BCFinding -Level Kritisch -Title 'ARM-Prozessor (Snapdragon): Linux nur eingeschränkt nutzbar' `
            -Advice 'Stand 2026 laufen Snapdragon-X-Laptops unter Linux nur mit Einschränkungen (Firmware, Energieverwaltung, Treiber). Für einen Linux-Plan ungeeignet.'
    } else { & $add 'Prozessor' $c.BestName 'gut (x86)' }

    # Webcam: USB-UVC ist unproblematisch, MIPI/IPU problematisch
    $cams = @($pnp | Where-Object { @('Camera', 'Image') -contains "$($_.PNPClass)" })
    $ipu = @($pnp | Where-Object { "$($_.Name)" -match '(?i)AVStream|IPU|Imaging Signal Processor|Control Logic|MIPI|Intel\(R\) (?:Camera|iVSC)|Visual Sensing' -or "$($_.PNPDeviceID)" -match '(?i)INT3472|OVTI|HIMX|INTC10[0-9A-F]{2}|\\IPU' })
    if ($ipu.Count -gt 0) {
        & $add 'Webcam' (@($ipu | ForEach-Object { $_.Name } | Select-Object -Unique) -join ', ') 'problematisch'
        Add-BCFinding -Level Warnung -Title 'MIPI-Kamera mit Intel IPU erkannt – unter Linux oft nicht oder nur mit Aufwand nutzbar' `
            -Advice 'Die häufigste Linux-Baustelle 2026. Braucht sehr neue Kernel/libcamera; bei vielen Distributionen funktioniert die Kamera nicht. Ggf. USB-Webcam einplanen.'
    } elseif (@($cams | Where-Object { "$($_.PNPDeviceID)" -match '^USB\\' }).Count -gt 0) {
        & $add 'Webcam' (@($cams | ForEach-Object { $_.Name }) -join ', ') 'gut (USB/UVC)'
    } elseif ($cams.Count -gt 0) { & $add 'Webcam' (@($cams | ForEach-Object { $_.Name }) -join ', ') 'vermutlich gut' }
    else { & $add 'Webcam' 'keine erkannt' '–' }

    # Speicher-Controller: Intel VMD / RST-RAID
    $vmd = @($pnp | Where-Object { "$($_.Name)" -match '(?i)\bVMD\b|Volume Management Device|Rapid Storage|RST\b|RAID' -and @('SCSIAdapter', 'HDC', 'System') -contains "$($_.PNPClass)" })
    $raidDisk = @(Get-BCInternalDisks | Where-Object { $_.Bus -eq 'RAID' })
    if ($vmd.Count -gt 0 -or $raidDisk.Count -gt 0) {
        & $add 'SSD-Controller' ((@($vmd | ForEach-Object { $_.Name }) + @($raidDisk | ForEach-Object { "Bus RAID: $($_.Model)" })) -join ', ') 'Achtung'
        Add-BCFinding -Level Warnung -Title 'SSD hängt am Intel-VMD/RST-Controller (RAID-Modus)' `
            -Advice 'Manche Linux-Installer finden die SSD so nicht. Lösung: im BIOS VMD abschalten bzw. auf AHCI stellen – dafür ist BIOS-Zugang (kein Supervisor-Passwort!) nötig. Neuere Distributionen kommen oft auch so zurecht.'
    } else { & $add 'SSD-Controller' 'Standard (NVMe/AHCI)' 'gut' }

    # WLAN-Chip
    $nets = @()
    $nets = @(Get-BCNetAdapters | Where-Object { $_.NdisPhysicalMedium -eq 9 -or "$($_.InterfaceDescription)" -match '(?i)Wi-?Fi|Wireless|WLAN|802\.11' })
    foreach ($n in $nets) {
        $ids = Get-BCPciIds "$($n.PnPDeviceID)"
        $v = "$($ids.Ven)".ToUpper()
        $rating = switch ($v) {
            '8086' { 'gut (Intel)' }
            '14E4' { 'problematisch (Broadcom)' }
            '10EC' { 'meist ok, neuer Kernel nötig (Realtek)' }
            '0BDA' { 'meist ok, neuer Kernel nötig (Realtek USB)' }
            '14C3' { 'meist ok, neuer Kernel nötig (MediaTek)' }
            '168C' { 'gut (Qualcomm Atheros)' }
            '17CB' { 'gut (Qualcomm)' }
            default { 'unbekannt' }
        }
        & $add 'WLAN' "$($n.InterfaceDescription) ($v`:$($ids.Dev))" $rating
        if ($v -eq '14E4') { Add-BCFinding -Level Warnung -Title 'Broadcom-WLAN – unter Linux oft nur mit proprietärem Treiber' -Advice 'Je nach Chip und Distribution aufwendig oder gar nicht nutzbar. Tausch gegen eine Intel-Karte ist oft möglich (wenn steckbar).' }
    }

    # Fingerabdruckleser
    $fp = @($pnp | Where-Object { "$($_.PNPClass)" -eq 'Biometric' -and "$($_.Name)" -notmatch '(?i)Windows Hello Face' })
    if ($fp.Count -gt 0) {
        $txt = @($fp | ForEach-Object { $ids = Get-BCPciIds "$($_.PNPDeviceID)"; "$($_.Name) ($($ids.Ven):$($ids.Dev))" }) -join ', '
        & $add 'Fingerabdruckleser' $txt 'unklar – Liste prüfen'
        Add-BCFinding -Level Info -Title 'Fingerabdruckleser: Linux-Unterstützung prüfen' -Detail $txt
        Add-BCLink -Title 'libfprint: unterstützte Fingerabdruckleser (USB-ID vergleichen)' -Url 'https://fprint.freedesktop.org/supported-devices.html'
    }

    # Grafik
    $gpus = @(Get-BCWmi Win32_VideoController)
    $nv = @($gpus | Where-Object { (Get-BCPciIds "$($_.PNPDeviceID)").Ven -eq '10DE' })
    if ($nv.Count -gt 0) {
        & $add 'Grafik' (@($gpus | ForEach-Object { $_.Name }) -join ' + ') 'ok mit proprietärem Treiber'
        Add-BCFinding -Level Info -Title 'NVIDIA-Grafik: unter Linux proprietärer Treiber empfohlen' -Detail 'Hybridgrafik (Intel/AMD + NVIDIA) funktioniert, braucht aber etwas Einrichtung.'
    } else { & $add 'Grafik' (@($gpus | ForEach-Object { $_.Name }) -join ' + ') 'gut (Intel/AMD)' }

    # Secure Boot: ist das Microsoft-Drittanbieter-Zertifikat (für Linux-Bootloader) freigegeben?
    $sbState = 'unbekannt'
    try {
        $on = Confirm-SecureBootUEFI -ErrorAction Stop
        $sbState = if ($on) { 'aktiv' } else { 'aus' }
        $db = Get-SecureBootUEFI -Name db -ErrorAction Stop
        $text = [Text.Encoding]::ASCII.GetString($db.Bytes)
        $third = ($text -match 'Microsoft Corporation UEFI CA 2011') -or ($text -match 'Microsoft UEFI CA 2023')
        if ($third) {
            & $add 'Secure Boot' "$sbState, Drittanbieter-CA vorhanden" 'gut (Linux-Bootloader erlaubt)'
        } else {
            & $add 'Secure Boot' "$sbState, Drittanbieter-CA fehlt" 'Achtung'
            Add-BCFinding -Level Warnung -Title 'Secure Boot erlaubt keine Linux-Bootloader (Microsoft-Drittanbieter-Zertifikat fehlt)' `
                -Advice 'Typisch für „Secured-core“-Geräte. Im BIOS „Allow Microsoft 3rd Party UEFI CA“ aktivieren oder Secure Boot abschalten – beides braucht BIOS-Zugang.'
        }
    } catch [System.PlatformNotSupportedException] {
        & $add 'Secure Boot' 'kein UEFI/Secure Boot' 'gut (keine Hürde)'
    } catch {
        & $add 'Secure Boot' $sbState 'nicht prüfbar'
    }

    # Audio (Intel Smart Sound / SOF)
    $sst = @($pnp | Where-Object { "$($_.Name)" -match '(?i)Smart Sound Technology|SST' })
    if ($sst.Count -gt 0) { & $add 'Audio' 'Intel Smart Sound (DSP)' 'meist ok mit aktueller Distribution (SOF-Firmware)' }

    Add-BCTable -Title 'Linux-Einschätzung je Bauteil' -Rows $rows.ToArray()
    if (Get-BCFact 'bios.supervisor') {
        Add-BCFinding -Level Kritisch -Title 'BIOS-Supervisor-Passwort verhindert die Linux-Installation praktisch' -Detail 'Ohne BIOS-Zugang lässt sich weder vom USB-Stick starten noch Secure Boot oder der SSD-Modus ändern.' -Advice 'Nur kaufen, wenn der Verkäufer das Passwort vor Ort im BIOS entfernt.'
    }
    $serious = @($script:BCCurrent.Findings | Where-Object { @('Kritisch', 'Warnung') -contains $_.Level }).Count
    if ($serious -eq 0 -and @($rows | Where-Object { $_.Linux -match 'problematisch|Achtung' }).Count -eq 0) {
        Add-BCFinding -Level OK -Title 'Keine typischen Linux-Problemkandidaten gefunden' -Detail 'Vor dem Kauf idealerweise ein Linux-Live-System vom USB-Stick starten und testen.'
    }
    Add-BCLink -Title 'Linux-Hardware-Datenbank (Modell suchen)' -Url 'https://linux-hardware.org/'
}
