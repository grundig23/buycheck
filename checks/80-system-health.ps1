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
        [pscustomobject]@{ 'Gerät' = "$($p.Name)"; 'Klasse' = "$($p.PNPClass)"; 'Code' = $code; 'Bedeutung' = if ($script:BCPnpCodes.ContainsKey($code)) { $script:BCPnpCodes[$code] } else { 'unbekannt' }; 'Kennung' = "$($p.PNPDeviceID)" }
    }
    Add-BCTable -Title 'Geräte mit Problemen' -Rows @($rows)
    foreach ($p in $problem) {
        $code = [int]$p.ConfigManagerErrorCode
        $important = $script:BCImportantClasses -contains "$($p.PNPClass)"
        $name = "$($p.Name)"; if (-not $name) { $name = "$($p.PNPDeviceID)" }
        switch ($code) {
            22 {
                $lvl = if ($important) { 'Warnung' } else { 'Info' }
                Add-BCFinding -Level $lvl -Title "Deaktiviert: $name ($($p.PNPClass))" -Advice 'Verkäufer bitten, das Gerät zu aktivieren und zu zeigen, dass es funktioniert.'
            }
            28 { Add-BCFinding -Level Info -Title "Kein Treiber: $name" -Detail 'Nach Neuinstallation üblich; Funktion dieses Bauteils damit nicht prüfbar.' }
            29 { Add-BCFinding -Level Info -Title "Im BIOS deaktiviert: $name" -Detail 'Kann gewollt sein; ggf. im BIOS aktivieren lassen und testen.' }
            43 { Add-BCFinding -Level Warnung -Title "Gerät meldet Fehler (Code 43): $name ($($p.PNPClass))" -Advice 'Häufig ein Hardwaredefekt des Bauteils.' }
            default {
                $lvl = if ($important) { 'Warnung' } else { 'Info' }
                $mean = if ($script:BCPnpCodes.ContainsKey($code)) { $script:BCPnpCodes[$code] } else { "Code $code" }
                Add-BCFinding -Level $lvl -Title "Geräteproblem: $name – $mean"
            }
        }
    }
}

function Get-BCEvents {
    param([hashtable]$Filter, [int]$Max = 300)
    try { return @(Get-WinEvent -FilterHashtable $Filter -MaxEvents $Max -ErrorAction Stop) } catch { return @() }
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
    Add-BCFacts -Title 'Ausgewerteter Zeitraum' -Data ([ordered]@{ 'Ältester Eintrag im Systemprotokoll' = Format-BCDate $oldest; 'Ausgewertet ab' = Format-BCDate $start; 'Tage' = $days })
    if ($days -lt 14) { Add-BCFinding -Level Info -Title "Protokolle reichen nur $days Tage zurück" -Detail 'Windows wurde vermutlich kürzlich installiert/zurückgesetzt – keine Vorgeschichte sichtbar.' }

    $rows = @()
    # Hinweis: Gefiltert wird nach Ereignis-IDs; der Anbieter wird erst danach geprüft. So scheitert die Abfrage
    # nicht, wenn ein Anbieter (z. B. ein Intel-RST-Treiber) auf diesem Gerät gar nicht existiert.
    # Datenträger-/Speicherfehler
    $disk = Get-BCEvents @{ LogName = 'System'; Level = @(1, 2, 3); Id = @(7, 9, 11, 15, 51, 52, 129, 153, 154, 157); StartTime = $start } 1000
    $disk = @($disk | Where-Object { "$($_.ProviderName)" -match '^(disk|stornvme|storahci|iaStor\w*|nvme\w*|stornvme\w*)$' })
    $ntfs = @(Get-BCEvents @{ LogName = 'System'; Id = @(55, 130, 137, 140); StartTime = $start } | Where-Object { "$($_.ProviderName)" -match 'Ntfs' })
    $diskAll = @($disk) + @($ntfs)
    if ($diskAll.Count -gt 0) {
        $byId = $diskAll | Group-Object { "$($_.ProviderName) $($_.Id)" } | ForEach-Object { "$($_.Name): $($_.Count)×" }
        $last = ($diskAll | Sort-Object TimeCreated -Descending | Select-Object -First 1).TimeCreated
        $lvl = if (@($disk | Where-Object { @(7, 11, 51, 153) -contains $_.Id }).Count -ge 3) { 'Warnung' } else { 'Info' }
        Add-BCFinding -Level $lvl -Title "Datenträger-/Dateisystem-Fehlermeldungen: $($diskAll.Count)" -Detail (($byId -join ', ') + " · zuletzt $(Format-BCDate $last)") `
            -Advice 'Häufungen von disk 7/11/51/153 deuten auf Lese-/Verbindungsprobleme der SSD/HDD hin.'
        $rows += $diskAll | Sort-Object TimeCreated -Descending | Select-Object -First 15 | ForEach-Object { [pscustomobject]@{ 'Zeit' = $_.TimeCreated.ToString('dd.MM.yyyy HH:mm'); 'Quelle' = $_.ProviderName; 'ID' = $_.Id; 'Meldung' = ("$($_.Message)" -split "`n")[0] } }
    } else { Add-BCFinding -Level OK -Title 'Keine Datenträgerfehler im Protokoll' }

    # WHEA-Hardwarefehler
    $whea = @(Get-BCEvents @{ LogName = 'System'; Id = @(1, 17, 18, 19, 20, 46, 47); StartTime = $start } 3000 | Where-Object { "$($_.ProviderName)" -eq 'Microsoft-Windows-WHEA-Logger' })
    if ($whea.Count -gt 0) {
        $fatal = @($whea | Where-Object { $_.Level -le 2 -and @(1, 18, 20, 46) -contains $_.Id })
        $corr = @($whea | Where-Object { $fatal -notcontains $_ })
        if ($fatal.Count -gt 0) { Add-BCFinding -Level Kritisch -Title "Schwere Hardwarefehler (WHEA) protokolliert: $($fatal.Count)" -Detail ("zuletzt " + (Format-BCDate ($fatal[0].TimeCreated))) -Advice 'Schwere Prozessor-, Speicher- oder PCIe-Fehler führten zu Abstürzen. Vom Kauf abraten.' }
        if ($corr.Count -gt 10) { Add-BCFinding -Level Warnung -Title "Viele korrigierte Hardwarefehler (WHEA): $($corr.Count)" -Detail 'Wurden automatisch korrigiert, deuten aber auf instabile Hardware (oft PCIe/Speicher) hin.' }
        elseif ($corr.Count -gt 0) { Add-BCFinding -Level Info -Title "Korrigierte Hardwarefehler (WHEA): $($corr.Count)" -Detail 'Einzelne korrigierte Fehler sind meist harmlos.' }
        $rows += $whea | Select-Object -First 10 | ForEach-Object { [pscustomobject]@{ 'Zeit' = $_.TimeCreated.ToString('dd.MM.yyyy HH:mm'); 'Quelle' = 'WHEA'; 'ID' = $_.Id; 'Meldung' = ("$($_.Message)" -split "`n")[0] } }
    } else { Add-BCFinding -Level OK -Title 'Keine Hardwarefehler (WHEA) im Protokoll' }

    # Bluescreens
    $bsod = @(Get-BCEvents @{ LogName = 'System'; Id = 1001; StartTime = $start } | Where-Object { "$($_.ProviderName)" -match 'WER-SystemErrorReporting|BugCheck' })
    if ($bsod.Count -gt 0) {
        $codes = @($bsod | ForEach-Object { if ("$($_.Message)" -match '0x[0-9a-fA-F]{8}') { $Matches[0] } } | Select-Object -Unique)
        $lvl = if ($bsod.Count -ge 3) { 'Warnung' } else { 'Info' }
        Add-BCFinding -Level $lvl -Title "Bluescreens (Systemabstürze): $($bsod.Count)" -Detail ("Stopcodes: " + ($codes -join ', ') + " · zuletzt " + (Format-BCDate $bsod[0].TimeCreated)) -Advice 'Häufige Abstürze können Treiber-, aber auch Hardwareursachen (RAM, SSD, Überhitzung) haben.'
    } else { Add-BCFinding -Level OK -Title 'Keine Bluescreens im Protokoll' }
    $dumps = @()
    try { $dumps = @(Get-ChildItem -LiteralPath (Join-Path $env:windir 'Minidump') -Filter *.dmp -ErrorAction SilentlyContinue) } catch { Write-BCDebug "Minidumps: $($_.Exception.Message)" }
    if ($dumps.Count -gt 0) { Add-BCFinding -Level Info -Title "$($dumps.Count) Absturzabbilder (Minidumps) vorhanden" -Detail ("Neuestes: " + (Format-BCDate (($dumps | Sort-Object LastWriteTime -Descending)[0].LastWriteTime))) }

    # Unerwartete Abschaltungen
    $kp = @(Get-BCEvents @{ LogName = 'System'; Id = 41; StartTime = (Get-Date).AddDays(-90) } | Where-Object { "$($_.ProviderName)" -eq 'Microsoft-Windows-Kernel-Power' })
    if ($kp.Count -gt 10) { Add-BCFinding -Level Warnung -Title "Häufige unerwartete Abschaltungen: $($kp.Count) in 90 Tagen" -Advice 'Mögliche Ursachen: Akku bricht ein, Überhitzung, Netzteil, Abstürze.' }
    elseif ($kp.Count -gt 2) { Add-BCFinding -Level Info -Title "Unerwartete Abschaltungen: $($kp.Count) in 90 Tagen" -Detail 'Auch durch hartes Ausschalten (Einschaltknopf halten) möglich.' }

    # Ergebnisse früherer Windows-Speicherdiagnosen
    $mem = @(Get-BCEvents @{ LogName = 'System'; Id = @(1101, 1102, 1201, 1202); StartTime = (Get-Date).AddYears(-5) } | Where-Object { "$($_.ProviderName)" -match 'MemoryDiagnostics' })
    $memBad = @($mem | Where-Object { $_.Id -eq 1202 })
    if ($memBad.Count -gt 0) { Add-BCFinding -Level Kritisch -Title 'Frühere Windows-Speicherdiagnose hat Fehler gefunden' -Detail (Format-BCDate $memBad[0].TimeCreated) -Advice 'Defekter Arbeitsspeicher. Vom Kauf abraten (bei verlötetem RAM ein Mainboard-Schaden).' }
    elseif ($mem.Count -gt 0) { Add-BCFinding -Level Info -Title 'Frühere Windows-Speicherdiagnose ohne Fehler' -Detail (Format-BCDate $mem[0].TimeCreated) }

    if ($rows.Count -gt 0) { Add-BCTable -Title 'Letzte relevante Einträge' -Rows $rows }
}
