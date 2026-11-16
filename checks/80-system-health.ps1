# BuyCheck – System & Protokolle: Geräte-Manager-Fehler, Ereignisprotokolle (Vorgeschichte des Geräts)

$script:BCPnpCodes = @{
    1 = 'nicht konfiguriert'; 3 = 'Treiber beschädigt'; 10 = 'Gerät kann nicht gestartet werden'; 12 = 'Ressourcenkonflikt'
    14 = 'Neustart nötig'; 18 = 'Treiber neu installieren'; 19 = 'Registry-Problem'; 21 = 'wird entfernt'; 22 = 'deaktiviert'
    24 = 'nicht vorhanden/fehlerhaft'; 28 = 'kein Treiber installiert'; 29 = 'in der Firmware (BIOS) deaktiviert'; 31 = 'funktioniert nicht richtig'
    32 = 'Treiber deaktiviert'; 37 = 'Treiberinitialisierung fehlgeschlagen'; 39 = 'Treiber fehlt/beschädigt'; 41 = 'Hardware nicht gefunden'
    43 = 'Gerät hat Fehler gemeldet (oft Hardwaredefekt)'; 45 = 'nicht angeschlossen'; 47 = 'zum Entfernen vorbereitet'; 48 = 'blockiert'; 52 = 'Signatur ungültig'
}
$script:BCImportantClasses = @('Display', 'Net', 'Bluetooth', 'Camera', 'Image', 'MEDIA', 'AudioEndpoint', 'Biometric', 'HIDClass', 'Mouse', 'Keyboard', 'USB', 'SCSIAdapter', 'HDC', 'DiskDrive', 'Battery', 'SoftwareComponent', 'SmartCardReader', 'Sensor')

Register-BuyCheck -Id 'system.devices' -Category 'System & Protokolle' -Order 10 -RunOrder 80 -Seconds 5 `
    -Title 'Geräte-Manager: Fehler & deaktivierte Geräte' `
    -Description 'Sucht Geräte mit Fehlercode (z. B. Code 43 = Hardware meldet Fehler) und deaktivierte Geräte. Ein Verkäufer könnte ein defektes Bauteil (Kamera, WLAN, Lautsprecher) einfach deaktiviert haben, damit es nicht auffällt.' `
    -Profiles @('quick', 'thorough', 'linux', 'auto') `
    -Run {
    $problem = @(Get-BCPnp | Where-Object { [int]$_.ConfigManagerErrorCode -ne 0 -and [int]$_.ConfigManagerErrorCode -ne 45 })
    if ($problem.Count -eq 0) { Add-BCFinding -Level OK -Title 'Keine Geräte mit Fehlern oder deaktivierte Geräte'; return }
    $rows = foreach ($p in $problem) {
        $code = [int]$p.ConfigManagerErrorCode
        (New-BCObject @('Gerät', "$($p.Name)", 'Klasse', "$($p.PNPClass)", 'Code', $code, 'Bedeutung', $(if ($script:BCPnpCodes.ContainsKey($code)) { $script:BCPnpCodes[$code] } else { 'unbekannt' }), 'Kennung', "$($p.PNPDeviceID)"))
    }
    Add-BCTable -Title 'Geräte mit Problemen' -Rows @($rows)
    foreach ($p in $problem) {
        $code = [int]$p.ConfigManagerErrorCode
        $important = $script:BCImportantClasses -contains "$($p.PNPClass)"
        $name = "$($p.Name)"; if (-not $name) { $name = "$($p.PNPDeviceID)" }
        switch ($code) {
            22 {
                $lvl = if ($important) { 'Warnung' } else { 'Info' }
                Add-BCFinding -Level $lvl -Title "Deaktiviert: $name ($($p.PNPClass))" -Detail 'Jemand hat dieses Bauteil im Geräte-Manager abgeschaltet. So lässt sich ein Defekt verbergen; manchmal ist es aber auch gewollt (z. B. Kamera aus Datenschutzgründen).' -Advice 'Den Verkäufer bitten, das Gerät zu aktivieren und zu zeigen, dass es funktioniert.'
            }
            28 { Add-BCFinding -Level Info -Title "Kein Treiber: $name" -Detail 'Nach Neuinstallation üblich; Funktion dieses Bauteils damit nicht prüfbar.' }
            29 { Add-BCFinding -Level Info -Title "Im BIOS deaktiviert: $name" -Detail 'Kann gewollt sein; ggf. im BIOS aktivieren lassen und testen.' }
            43 { Add-BCFinding -Level Warnung -Title "Gerät meldet Fehler (Code 43): $name ($($p.PNPClass))" -Detail 'Windows hat das Bauteil abgeschaltet, weil es selbst einen Fehler gemeldet hat.' -Advice 'Häufig ein Hardwaredefekt dieses Bauteils, manchmal nur ein Treiberproblem. Den Verkäufer fragen und prüfen, ob die Funktion (z. B. WLAN, Kamera, Ton) trotzdem geht.' }
            default {
                $lvl = if ($important) { 'Warnung' } else { 'Info' }
                $mean = if ($script:BCPnpCodes.ContainsKey($code)) { $script:BCPnpCodes[$code] } else { "Code $code" }
                Add-BCFinding -Level $lvl -Title "Geräteproblem: $name – $mean" -Detail "Windows meldet für dieses Bauteil Code $code ($mean). Meist ein Treiberproblem, das sich nach dem Kauf beheben lässt." -Advice $(if ($lvl -eq 'Warnung') { 'Prüfen, ob die Funktion des Bauteils trotzdem geht; sonst den Verkäufer fragen.' } else { '' })
            }
        }
    }
}

function Get-BCEvents {
    param([hashtable]$Filter, [int]$Max = 300)
    try { return @(Get-WinEvent -FilterHashtable $Filter -MaxEvents $Max -ErrorAction Stop) } catch { return @() }
}

# Ereignisdaten als Tabelle Name -> Wert (sprachunabhängig über das XML des Ereignisses; unbenannte Werte heißen 0, 1, 2 …)
function Get-BCEventData {
    param($Event)
    $h = @{}
    try {
        $x = [xml]$Event.ToXml()
        $i = 0
        foreach ($d in $x.GetElementsByTagName('Data')) {
            $n = $d.GetAttribute('Name'); if (-not $n) { $n = "$i" }
            $h[$n] = $d.InnerText; $i++
        }
    } catch { }
    return $h
}

function Test-BCEventFlag { param($Value) $v = "$Value".Trim(); return ($v.Length -gt 0 -and $v -ne '0' -and $v -ne 'false') }

# Welcher Datenträger ist gemeint? Liefert die Nummer (Datenträger 0, 1 …) oder $null
function Get-BCEventDiskNumber {
    param($Event, [hashtable]$Data)
    foreach ($v in $Data.Values) { if ("$v" -match '\\Harddisk(\d+)\\') { return [int]$Matches[1] } }
    $m = "$($Event.Message)"
    if ($m -match '\\Harddisk(\d+)\\') { return [int]$Matches[1] }
    if ($m -match '(?:Disk|Datenträger|Laufwerk)\s+(\d+)') { return [int]$Matches[1] }
    return $null
}

# Datenträger-Meldungen: Kurzname, Erklärung, Schwere (0 harmlos, 1 leicht, 2 Verbindung, 3 Datenfehler, 4 Ausfall vorhergesagt)
$script:BCDiskEvents = @{
    'disk 7'    = @('Fehlerhafter Block', 'eine Stelle ließ sich nicht lesen, auch nicht mit Fehlerkorrektur', 3)
    'disk 154'  = @('Hardwarefehler', 'ein Lese- oder Schreibvorgang ist an einem Hardwarefehler gescheitert', 3)
    'disk 52'   = @('Ausfall vorhergesagt', 'der Datenträger hat selbst gemeldet, dass er bald ausfällt (SMART)', 4)
    'disk 11'   = @('Controller-Fehler', 'Fehler in der Verbindung zum Datenträger (Controller, Steckplatz, Kabel)', 2)
    'disk 51'   = @('Fehler beim Auslagern', 'Lesen oder Schreiben der Auslagerungsdatei gestört, meist zusammen mit Verbindungsproblemen', 2)
    'disk 9'    = @('Zeitüberschreitung', 'der Datenträger hat nicht rechtzeitig geantwortet', 2)
    'disk 157'  = @('Plötzlich getrennt', 'der Datenträger war auf einmal nicht mehr verbunden', 2)
    'disk 153'  = @('Vorgang wiederholt', 'ein Zugriff musste wiederholt werden und hat dann geklappt', 1)
    'disk 15'   = @('Nicht bereit', 'der Datenträger war kurz nicht bereit, z. B. beim Aufwachen aus dem Energiesparmodus', 0)
    'ctrl 129'  = @('Verbindung zurückgesetzt', 'Windows musste die Verbindung zum Datenträger neu starten, weil er nicht mehr antwortete', 2)
    'ctrl 9'    = @('Zeitüberschreitung', 'der Datenträger hat nicht rechtzeitig geantwortet', 2)
    'ctrl 11'   = @('Controller-Fehler', 'Fehler in der Verbindung zum Datenträger', 2)
    'ntfs 55'   = @('Dateisystem beschädigt', 'Windows hat eine Beschädigung im Dateisystem gefunden', 2)
    'ntfs 130'  = @('Dateisystem repariert', 'Windows hat das Dateisystem selbst repariert', 1)
    'ntfs 137'  = @('Dateisystem-Protokoll', 'interner Fehler im Änderungsprotokoll des Dateisystems, meist harmlos', 0)
    'ntfs 140'  = @('Schreiben unvollständig', 'Daten wurden nicht vollständig geschrieben, meist weil ein Datenträger ohne „Auswerfen“ abgezogen wurde', 1)
}

# Bekannte Stopcodes von Bluescreens: Name, Bedeutung, Hardware-Hinweis
$script:BCStopCodes = @{
    0x0A = @('IRQL_NOT_LESS_OR_EQUAL', 'meist ein Treiber', $false); 0xD1 = @('DRIVER_IRQL_NOT_LESS_OR_EQUAL', 'meist ein Treiber', $false)
    0x1E = @('KMODE_EXCEPTION_NOT_HANDLED', 'meist ein Treiber', $false); 0x3B = @('SYSTEM_SERVICE_EXCEPTION', 'meist ein Treiber', $false)
    0x7E = @('SYSTEM_THREAD_EXCEPTION_NOT_HANDLED', 'meist ein Treiber', $false); 0x9F = @('DRIVER_POWER_STATE_FAILURE', 'Treiber beim Energiesparen', $false)
    0x116 = @('VIDEO_TDR_FAILURE', 'Grafiktreiber oder Grafikchip', $false); 0x133 = @('DPC_WATCHDOG_VIOLATION', 'Treiber oder SSD-Firmware', $false)
    0xEF = @('CRITICAL_PROCESS_DIED', 'Windows-Dateien oder Datenträger', $false); 0x139 = @('KERNEL_SECURITY_CHECK_FAILURE', 'Treiber oder Arbeitsspeicher', $false)
    0x50 = @('PAGE_FAULT_IN_NONPAGED_AREA', 'Treiber oder Arbeitsspeicher', $false); 0x19 = @('BAD_POOL_HEADER', 'Treiber oder Arbeitsspeicher', $false)
    0xC2 = @('BAD_POOL_CALLER', 'meist ein Treiber', $false); 0x109 = @('CRITICAL_STRUCTURE_CORRUPTION', 'Treiber oder Arbeitsspeicher', $false)
    0x1A = @('MEMORY_MANAGEMENT', 'häufig der Arbeitsspeicher', $true); 0x7A = @('KERNEL_DATA_INPAGE_ERROR', 'Lesefehler von SSD/Festplatte oder Arbeitsspeicher', $true)
    0x77 = @('KERNEL_STACK_INPAGE_ERROR', 'Lesefehler von SSD/Festplatte', $true); 0xF4 = @('CRITICAL_OBJECT_TERMINATION', 'oft SSD/Festplatte oder deren Verbindung', $true)
    0x154 = @('UNEXPECTED_STORE_EXCEPTION', 'oft SSD/Festplatte oder Arbeitsspeicher', $true); 0x124 = @('WHEA_UNCORRECTABLE_ERROR', 'Hardwarefehler (Prozessor, Speicher, Mainboard)', $true)
    0x9C = @('MACHINE_CHECK_EXCEPTION', 'Hardwarefehler (Prozessor, Speicher, Mainboard)', $true); 0x101 = @('CLOCK_WATCHDOG_TIMEOUT', 'Prozessor hängt (Hardware oder Übertaktung)', $true)
}

function Format-BCEventSpan {
    param([object[]]$Events)
    $t = @($Events | ForEach-Object { $_.TimeCreated } | Sort-Object)
    if ($t.Count -eq 0) { return '' }
    if ($t.Count -eq 1) { return "am $(Format-BCDate $t[0])" }
    return "$(Format-BCDate $t[0]) bis $(Format-BCDate $t[$t.Count - 1])"
}

Register-BuyCheck -Id 'system.eventlog' -Category 'System & Protokolle' -Order 20 -RunOrder 90 -Seconds 20 `
    -Title 'Ereignisprotokolle: Vorgeschichte des Geräts' `
    -Description 'Durchsucht die Windows-Protokolle (nur lesend) nach Datenträgerfehlern, Hardwarefehlern (WHEA), Bluescreens, unerwarteten Abschaltungen und Ergebnissen früherer Speicherdiagnosen. Aussagekräftig nur, wenn Windows nicht frisch installiert wurde.' `
    -Profiles @('quick', 'thorough', 'linux', 'auto') `
    -Run {
    $oldest = $null
    try { $oldest = (Get-WinEvent -LogName System -MaxEvents 1 -Oldest -ErrorAction Stop).TimeCreated } catch { }
    $start = (Get-Date).AddDays(-365)
    if ($oldest -and $oldest -gt $start) { $start = $oldest }
    $days = [int](New-TimeSpan -Start $start -End (Get-Date)).TotalDays
    Add-BCFacts -Title 'Ausgewerteter Zeitraum' -Data ((New-BCOrdered @('Ältester Eintrag im Systemprotokoll', $(Format-BCDate $oldest), 'Ausgewertet ab', $(Format-BCDate $start), 'Tage', $days)))
    if ($days -lt 14) { Add-BCFinding -Level Info -Title "Protokolle reichen nur $days Tage zurück" -Detail 'Windows wurde vermutlich kürzlich installiert oder zurückgesetzt. Die Vorgeschichte des Geräts ist deshalb nicht sichtbar.' -Advice 'Den Verkäufer fragen, warum und wann Windows neu installiert wurde.' }

    $rows = @()
    # ------------------------------------------------ Datenträger- und Dateisystemfehler, getrennt nach eingebautem und anderem Datenträger
    # Gefiltert wird nach Ereignis-IDs; der Anbieter wird erst danach geprüft. So scheitert die Abfrage nicht,
    # wenn ein Anbieter (z. B. ein Intel-RST-Treiber) auf diesem Gerät gar nicht existiert.
    $internal = @{}
    foreach ($d in @(Get-BCInternalDisks)) { $internal[[int]$d.Number] = $d }
    $sysDrive = "$env:SystemDrive".TrimEnd('\').ToUpperInvariant()
    $diskEv = @(Get-BCEvents @{ LogName = 'System'; Level = @(1, 2, 3); Id = @(7, 9, 11, 15, 51, 52, 129, 153, 154, 157); StartTime = $start } 1000 |
        Where-Object { "$($_.ProviderName)" -match '^(disk|stornvme|storahci|iaStor\w*|nvme\w*)$' })
    $ntfsEv = @(Get-BCEvents @{ LogName = 'System'; Id = @(55, 130, 137, 140); StartTime = $start } | Where-Object { "$($_.ProviderName)" -match 'Ntfs' })
    $items = @()
    foreach ($e in (@($diskEv) + @($ntfsEv))) {
        $data = Get-BCEventData $e
        $prov = "$($e.ProviderName)"
        if ($prov -eq 'disk') { $kind = 'disk' } elseif ($prov -match 'Ntfs') { $kind = 'ntfs' } else { $kind = 'ctrl' }
        $num = $null; $where = 'andere'
        if ($kind -eq 'disk') {
            $num = Get-BCEventDiskNumber $e $data
            if ($null -eq $num -or $internal.ContainsKey($num)) { $where = 'intern' }
        } elseif ($kind -eq 'ctrl') { $where = 'intern' }   # SATA-/NVMe-Controller: USB-Datenträger laufen nicht darüber
        else {
            $text = (@($data.Values) -join ' ') + ' ' + "$($e.Message)"
            if ($sysDrive -and $text.ToUpperInvariant() -match ('(^|[^A-Z])' + [regex]::Escape($sysDrive))) { $where = 'intern' }
        }
        $key = "$kind $($e.Id)"
        if (-not $script:BCDiskEvents.ContainsKey($key)) { continue }
        $items += (New-BCObject @('Event', $e, 'Key', $key, 'Where', $where, 'Number', $num, 'Severity', $script:BCDiskEvents[$key][2]))
    }
    if ($items.Count -eq 0) { Add-BCFinding -Level OK -Title 'Keine Datenträgerfehler im Protokoll' }
    else {
        $summary = @()
        foreach ($g in @($items | Group-Object Where, Key | Sort-Object { $_.Group[0].Where }, { - $_.Group[0].Severity })) {
            $first = $g.Group[0]; $info = $script:BCDiskEvents[$first.Key]
            $target = 'anderer Datenträger'
            if ($first.Where -eq 'intern') { $target = 'eingebaut' }
            $summary += (New-BCObject @('Datenträger', $target, 'Meldung', "$($info[0]) ($($first.Key))", 'Bedeutung', $info[1], 'Anzahl', $g.Count,
                    'Zeitraum', (Format-BCEventSpan @($g.Group | ForEach-Object { $_.Event }))))
        }
        Add-BCTable -Title 'Datenträger-Meldungen im Systemprotokoll' -Rows $summary

        $int = @($items | Where-Object { $_.Where -eq 'intern' })
        if ($int.Count -gt 0) {
            $nums = @($int | Where-Object { $null -ne $_.Number } | ForEach-Object { $_.Number } | Select-Object -Unique)
            $name = 'Eingebauter Datenträger'
            if ($nums.Count -eq 1 -and $internal.ContainsKey($nums[0])) {
                $dk = $internal[$nums[0]]
                $name = $(if ($dk.IsSsd) { 'Eingebaute SSD' } else { 'Eingebaute Festplatte' }) + " ($($dk.Model))"
            }
            $cnt = @{}
            foreach ($s in 0..4) { $cnt[$s] = @($int | Where-Object { $_.Severity -eq $s }).Count }
            $lines = @(foreach ($g in @($int | Group-Object Key | Sort-Object { - $_.Group[0].Severity })) {
                $info = $script:BCDiskEvents[$g.Name]
                '{0}× {1}: {2} ({3})' -f $g.Count, $info[0], $info[1], (Format-BCEventSpan @($g.Group | ForEach-Object { $_.Event }))
            })
            $last = ($int | ForEach-Object { $_.Event.TimeCreated } | Sort-Object -Descending | Select-Object -First 1)
            $ago = [int](New-TimeSpan -Start $last -End (Get-Date)).TotalDays
            $lvl = 'Info'
            $advice = 'Einzelne Meldungen dieser Art sind meist harmlos. Auffällig wären erst viele davon in kurzer Zeit oder Fehler im Lesetest.'
            if ($cnt[2] -ge 5) {
                $lvl = 'Warnung'
                $advice = 'Mehrfach gestörte Verbindung zum Datenträger: kann am Steckplatz, an der SSD selbst oder an einem Treiber liegen. Läuft der Lesetest ohne Fehler und ohne Hänger durch, ist es meist unkritisch. Sonst den Verkäufer fragen, ob das Gerät manchmal hängt oder einfriert.'
            }
            if ($cnt[1] -ge 20 -and $lvl -eq 'Info') {
                $lvl = 'Warnung'
                $advice = 'Sehr viele wiederholte Zugriffe. Einzelne sind normal, so viele deuten auf eine schwächelnde SSD oder eine wacklige Verbindung hin. Ergebnis des Lesetests und die SSD-Werte beachten.'
            }
            if ($cnt[3] -ge 1) {
                $lvl = $(if ($cnt[3] -ge 5) { 'Kritisch' } else { 'Warnung' })
                $advice = 'Unlesbare Stellen sind ein Zeichen für eine verschleißende oder defekte SSD/Festplatte. Mit den SSD-Werten und dem Lesetest vergleichen: Zeigen auch diese Fehler, ist ein Austausch fällig (ca. 40–100 €, im Preis berücksichtigen) – oder vom Kauf absehen.'
            }
            if ($cnt[4] -ge 1) {
                $lvl = 'Kritisch'
                $advice = 'Der Datenträger hat selbst seinen baldigen Ausfall gemeldet. Er muss ersetzt werden (im Preis berücksichtigen) – oder vom Kauf absehen.'
            }
            if ($ago -gt 180) { $lines += "Letzte Meldung vor $ago Tagen. Wurde die SSD seitdem getauscht, betreffen die Meldungen das alte Laufwerk." }
            Add-BCFinding -Level $lvl -Title "$($name): $($int.Count) Fehlermeldungen im Windows-Protokoll" -Detail ($lines -join "`n") -Advice $advice
        } else { Add-BCFinding -Level OK -Title 'Keine Fehlermeldungen der eingebauten SSD/Festplatte im Protokoll' }

        $ext = @($items | Where-Object { $_.Where -ne 'intern' })
        if ($ext.Count -gt 0) {
            Add-BCFinding -Level Info -Title "Meldungen von anderen Datenträgern (USB-Stick, Speicherkarte o. Ä.): $($ext.Count)" `
                -Detail 'Betreffen nicht die eingebaute SSD/Festplatte. Entstehen meist, wenn ein Stick ohne „Auswerfen“ abgezogen wird oder alt ist. Für den Kauf ohne Bedeutung.'
        }
        $rows += $items | Sort-Object { $_.Event.TimeCreated } -Descending | Select-Object -First 15 | ForEach-Object {
            $t = 'anderer Datenträger'; if ($_.Where -eq 'intern') { $t = 'eingebaut' }
            (New-BCObject @('Zeit', $_.Event.TimeCreated.ToString('dd.MM.yyyy HH:mm'), 'Quelle', "$($_.Event.ProviderName) $($_.Event.Id)", 'Betrifft', $t, 'Meldung', ("$($_.Event.Message)" -split "`n")[0]))
        }
    }

    # ------------------------------------------------ WHEA-Hardwarefehler
    $whea = @(Get-BCEvents @{ LogName = 'System'; Id = @(1, 17, 18, 19, 20, 46, 47); StartTime = $start } 3000 | Where-Object { "$($_.ProviderName)" -eq 'Microsoft-Windows-WHEA-Logger' })
    if ($whea.Count -gt 0) {
        $fatal = @($whea | Where-Object { $_.Level -le 2 -and @(1, 18, 20, 46) -contains $_.Id })
        $pcie = @($whea | Where-Object { $_.Id -eq 17 -and $fatal -notcontains $_ })
        $core = @($whea | Where-Object { @(19, 47) -contains $_.Id -and $fatal -notcontains $_ })
        if ($fatal.Count -gt 0) {
            Add-BCFinding -Level Kritisch -Title "Schwere Hardwarefehler (WHEA) protokolliert: $($fatal.Count)" `
                -Detail "Prozessor, Arbeitsspeicher oder eine PCIe-Verbindung hatten einen Fehler, der nicht mehr korrigiert werden konnte und zum Absturz führte ($(Format-BCEventSpan $fatal))." `
                -Advice 'Solche Fehler gehen fast immer auf einen Hardwaredefekt zurück (Mainboard, Prozessor, Speicher). Vom Kauf abraten.'
        }
        if ($core.Count -gt 10) {
            Add-BCFinding -Level Warnung -Title "Viele korrigierte Prozessor-/Speicherfehler (WHEA): $($core.Count)" `
                -Detail "Prozessor oder Arbeitsspeicher haben Fehler gemacht, die noch automatisch korrigiert werden konnten ($(Format-BCEventSpan $core))." `
                -Advice 'Deutet auf beginnende Instabilität hin. Belastungs- und Speichertest beachten; bei Auffälligkeiten dort vom Kauf absehen.'
        } elseif ($core.Count -gt 0) { Add-BCFinding -Level Info -Title "Korrigierte Prozessor-/Speicherfehler (WHEA): $($core.Count)" -Detail 'Wurden automatisch korrigiert. Einzelne sind meist harmlos.' }
        if ($pcie.Count -gt 0) {
            Add-BCFinding -Level Info -Title "Korrigierte PCIe-Verbindungsfehler (WHEA): $($pcie.Count)" `
                -Detail 'Wurden automatisch korrigiert. Häufig ein bekanntes, harmloses Energiespar-Problem einzelner Geräte (WLAN-Karte, SSD) und kein Defekt.'
        }
        $rows += $whea | Select-Object -First 10 | ForEach-Object { (New-BCObject @('Zeit', $_.TimeCreated.ToString('dd.MM.yyyy HH:mm'), 'Quelle', "WHEA $($_.Id)", 'Betrifft', 'Hardware', 'Meldung', ("$($_.Message)" -split "`n")[0])) }
    } else { Add-BCFinding -Level OK -Title 'Keine Hardwarefehler (WHEA) im Protokoll' }

    # ------------------------------------------------ Bluescreens
    $bsod = @(Get-BCEvents @{ LogName = 'System'; Id = 1001; StartTime = $start } | Where-Object { "$($_.ProviderName)" -match 'WER-SystemErrorReporting|BugCheck' })
    if ($bsod.Count -gt 0) {
        $codes = @{}
        foreach ($b in $bsod) {
            if ("$($b.Message)" -match '0x([0-9a-fA-F]{8})') {
                $c = [Convert]::ToInt64($Matches[1], 16)
                if ($c -band 0x10000000) { $c = $c -band 0x0FFFFFFF }   # 0x1000007E = 0x7E mit erweiterten Parametern
                if ($codes.ContainsKey($c)) { $codes[$c]++ } else { $codes[$c] = 1 }
            }
        }
        $hw = 0
        $lines = @(foreach ($c in @($codes.Keys | Sort-Object { - $codes[$_] })) {
            $hex = '0x{0:X}' -f $c
            if ($script:BCStopCodes.ContainsKey([int]$c)) {
                $sc = $script:BCStopCodes[[int]$c]
                if ($sc[2]) { $hw += $codes[$c] }
                '{0}× {1} {2}: {3}' -f $codes[$c], $hex, $sc[0], $sc[1]
            } else { '{0}× {1}' -f $codes[$c], $hex }
        })
        $lines += "Zeitraum: $(Format-BCEventSpan $bsod)"
        $lvl = 'Info'
        $advice = 'Einzelne Abstürze sind meist ein Treiberproblem und kein Hardwaredefekt.'
        if ($bsod.Count -ge 3) { $lvl = 'Warnung'; $advice = 'Mehrere Abstürze. Den Verkäufer fragen, wann und wobei sie auftraten. Meist sind Treiber schuld; Belastungs-, Speicher- und Lesetest geben Hinweise auf Hardwareursachen.' }
        if ($hw -gt 0) { $lvl = 'Warnung'; $advice = 'Mindestens ein Absturz deutet auf ein Hardwareproblem hin (siehe Bedeutung). Ergebnisse von Speicher-, Lese- und Belastungstest genau ansehen; zeigen diese Fehler, vom Kauf absehen.' }
        Add-BCFinding -Level $lvl -Title "Bluescreens (Systemabstürze): $($bsod.Count)" -Detail ($lines -join "`n") -Advice $advice
    } else { Add-BCFinding -Level OK -Title 'Keine Bluescreens im Protokoll' }
    $dumps = @()
    try { $dumps = @(Get-ChildItem -LiteralPath (Join-Path $env:windir 'Minidump') -Filter *.dmp -ErrorAction SilentlyContinue) } catch { Write-BCDebug "Minidumps: $($_.Exception.Message)" }
    if ($dumps.Count -gt 0) { Add-BCFinding -Level Info -Title "$($dumps.Count) Absturzabbilder (Minidumps) vorhanden" -Detail ("Windows speichert bei Bluescreens ein Abbild. Neuestes: " + (Format-BCDate (($dumps | Sort-Object LastWriteTime -Descending)[0].LastWriteTime))) }

    # ------------------------------------------------ Nicht ordnungsgemäß beendet (Kernel-Power 41), nach Ursache
    # Zuklappen/Energiesparmodus zählt hier nicht. Gezählt wird nur, wenn Windows ohne Herunterfahren beendet wurde.
    $kp = @(Get-BCEvents @{ LogName = 'System'; Id = 41; StartTime = (Get-Date).AddDays(-90) } | Where-Object { "$($_.ProviderName)" -eq 'Microsoft-Windows-Kernel-Power' })
    if ($kp.Count -eq 0) { Add-BCFinding -Level OK -Title 'Keine unerwarteten Abschaltungen in den letzten 90 Tagen' }
    else {
        $crash = @(); $button = @(); $sleep = @(); $sudden = @()
        foreach ($e in $kp) {
            $d = Get-BCEventData $e
            if (Test-BCEventFlag $d['BugcheckCode']) { $crash += $e }
            elseif ((Test-BCEventFlag $d['PowerButtonTimestamp']) -or (Test-BCEventFlag $d['LongPowerButtonPressDetected'])) { $button += $e }
            elseif ((Test-BCEventFlag $d['SleepInProgress']) -or (Test-BCEventFlag $d['ConnectedStandbyInProgress'])) { $sleep += $e }
            else { $sudden += $e }
        }
        $lines = @()
        if ($button.Count -gt 0) { $lines += "$($button.Count)× mit der Ein-/Aus-Taste hart ausgeschaltet (Taste lange gedrückt)" }
        if ($sleep.Count -gt 0) { $lines += "$($sleep.Count)× im Energiesparmodus/Ruhezustand ausgegangen (meist Akku leer gelaufen)" }
        if ($crash.Count -gt 0) { $lines += "$($crash.Count)× nach einem Absturz (siehe Bluescreens)" }
        if ($sudden.Count -gt 0) { $lines += "$($sudden.Count)× plötzlich aus ohne erkennbaren Grund (Strom weg, Akku leer im Betrieb oder Gerät eingefroren und ausgeschaltet), $(Format-BCEventSpan $sudden)" }
        $lines += 'Zuklappen oder Energiesparmodus zählt nicht mit, nur Beenden ohne Herunterfahren.'
        $recentSudden = @($sudden | Where-Object { $_.TimeCreated -gt (Get-Date).AddDays(-30) }).Count
        $lvl = 'Info'
        $advice = 'Hartes Ausschalten ist meist Gewohnheit und schadet dem Gerät kaum. Für den Kauf ist das kein Mangel.'
        if ($sleep.Count -ge $button.Count -and $sleep.Count -ge $sudden.Count) { $advice = 'Passt zu einem Akku, der im Energiesparmodus leer läuft – das Ergebnis des Akkutests beachten. Für sich genommen kein Mangel.' }
        if ($sudden.Count -gt $button.Count -and $sudden.Count -gt $sleep.Count) { $advice = 'Den Verkäufer fragen, ob das Gerät manchmal von selbst ausgeht oder hängt. Ursache kann ein schwacher Akku, Überhitzung oder das Netzteil sein; Akku- und Belastungstest beachten.' }
        if ($recentSudden -ge 5) {
            $lvl = 'Warnung'
            $advice = "Das Gerät ist allein in den letzten 30 Tagen $recentSudden-mal plötzlich ausgegangen. Den Verkäufer danach fragen. Häufige Ursachen: Akku bricht unter Last ein, Überhitzung, Netzteil oder Mainboard. Akku- und Belastungstest genau beachten."
        }
        Add-BCFinding -Level $lvl -Title "Nicht ordnungsgemäß beendet: $($kp.Count)× in 90 Tagen" -Detail ($lines -join "`n") -Advice $advice
    }

    # ------------------------------------------------ Ergebnisse früherer Windows-Speicherdiagnosen
    $mem = @(Get-BCEvents @{ LogName = 'System'; Id = @(1101, 1102, 1201, 1202); StartTime = (Get-Date).AddYears(-5) } | Where-Object { "$($_.ProviderName)" -match 'MemoryDiagnostics' })
    $memBad = @($mem | Where-Object { $_.Id -eq 1202 })
    if ($memBad.Count -gt 0) {
        Add-BCFinding -Level Kritisch -Title 'Frühere Windows-Speicherdiagnose hat Fehler gefunden' `
            -Detail "Jemand hat den Arbeitsspeicher mit der Windows-Speicherdiagnose geprüft, dabei wurden Fehler gefunden (am $(Format-BCDate $memBad[0].TimeCreated))." `
            -Advice 'Defekter Arbeitsspeicher. Lässt er sich nicht tauschen (oft verlötet), ist das ein Mainboard-Schaden. Vom Kauf abraten.'
    }
    elseif ($mem.Count -gt 0) { Add-BCFinding -Level Info -Title 'Frühere Windows-Speicherdiagnose ohne Fehler' -Detail "Am $(Format-BCDate $mem[0].TimeCreated). Vielleicht gab es damals ein Problem, das untersucht wurde; ggf. den Verkäufer fragen." }

    if ($rows.Count -gt 0) { Add-BCTable -Title 'Letzte relevante Einträge' -Rows $rows }
}
