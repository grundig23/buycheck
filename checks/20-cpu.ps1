# BuyCheck – Prozessor: Echtheit (Namensfälschung) und Belastungstest (Kühlung, Stabilität)

function ConvertTo-BCCpuKey {
    param([string]$Name)
    if ((Test-BCBlank $Name)) { return '' }
    $n = $Name -replace '\((R|TM|C)\)', ' ' -replace '(?i)\bCPU\b', ' ' -replace '(?i)@\s*[\d.,]+\s*GHz', ' ' -replace '(?i)\bwith Radeon.*$', ' ' -replace '(?i)\bw/ Radeon.*$', ' '
    $n = $n -replace '(?i)\b\d+-Core Processor\b', ' ' -replace '(?i)\bProcessor\b', ' ' -replace '\s+', ' '
    return $n.Trim().ToLowerInvariant()
}

function Get-BCCpuModelToken {
    param([string]$Name)
    if ($Name -match '(?i)(i\d-\w+|Ultra\s+X?\d+\s+\w+|Ryzen\s+(?:AI\s+)?\w+\s+(?:PRO\s+)?\w+|N\d{3,4}\w*|Core\s+[357]\s+\w+)') { return $Matches[1].ToLowerInvariant() }
    return $null
}

# Sucht Autostart-Mechanismen, die den CPU-Namen in der Registry überschreiben (klassischer Betrugstrick)
function Find-BCCpuNameTampering {
    $pattern = '(?i)ProcessorNameString|CentralProcessor\\+0'
    $hits = New-Object 'System.Collections.Generic.List[string]'
    $scanned = New-Object 'System.Collections.Generic.List[string]'
    $scriptExt = '(?i)\.(bat|cmd|ps1|psm1|vbs|vbe|js|jse|wsf|reg)$'

    $checkFile = {
        param([string]$Path, [string]$Origin)
        if ((Test-BCBlank $Path)) { return }
        $p = [Environment]::ExpandEnvironmentVariables($Path.Trim('"', ' '))
        if ($scanned.Contains($p)) { return }
        $scanned.Add($p)
        try {
            if ((Test-Path -LiteralPath $p -PathType Leaf) -and ((Get-Item -LiteralPath $p).Length -lt 5MB)) {
                $t = [IO.File]::ReadAllText($p)
                if ($t -match $pattern) { $hits.Add("$Origin → $p") }
            }
        } catch { }
    }
    $pathsIn = {
        param([string]$Text)
        $r = @()
        foreach ($m in [regex]::Matches("$Text", '(?i)([A-Z]:\\[^"<>|*?\r\n]+?\.(?:bat|cmd|ps1|psm1|vbs|vbe|js|jse|wsf|reg))')) { $r += $m.Groups[1].Value }
        foreach ($m in [regex]::Matches("$Text", '(?i)(%[A-Z_]+%\\[^"<>|*?\r\n]+?\.(?:bat|cmd|ps1|psm1|vbs|vbe|js|jse|wsf|reg))')) { $r += $m.Groups[1].Value }
        return $r
    }

    # 1) Run/RunOnce-Schlüssel (Maschine und alle geladenen Benutzer)
    $runKeys = @(
        'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Run', 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\RunOnce',
        'HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Run', 'HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\RunOnce',
        'HKCU:\Software\Microsoft\Windows\CurrentVersion\Run', 'HKCU:\Software\Microsoft\Windows\CurrentVersion\RunOnce')
    try {
        foreach ($u in (Get-ChildItem -Path 'Registry::HKEY_USERS' -ErrorAction Stop)) {
            if ($u.PSChildName -match '^S-1-5-21-[\d-]+$') {
                $runKeys += "Registry::HKEY_USERS\$($u.PSChildName)\Software\Microsoft\Windows\CurrentVersion\Run"
                $runKeys += "Registry::HKEY_USERS\$($u.PSChildName)\Software\Microsoft\Windows\CurrentVersion\RunOnce"
            }
        }
    } catch { }
    foreach ($k in $runKeys) {
        try {
            $props = Get-ItemProperty -Path $k -ErrorAction Stop
            foreach ($p in $props.PSObject.Properties) {
                if ($p.Name -like 'PS*') { continue }
                $v = "$($p.Value)"
                if ($v -match $pattern) { $hits.Add("Autostart $k → $($p.Name)") }
                foreach ($f in (& $pathsIn $v)) { & $checkFile $f "Autostart $($p.Name)" }
            }
        } catch { }
    }

    # 2) Geplante Aufgaben (XML-Definitionen) und die darin aufgerufenen Skripte
    $taskDir = Join-Path $env:windir 'System32\Tasks'
    foreach ($tf in @(Get-ChildItem -LiteralPath $taskDir -Recurse -Force -ErrorAction SilentlyContinue | Where-Object { -not $_.PSIsContainer })) {
        try {
            $t = [IO.File]::ReadAllText($tf.FullName)
            $rel = $tf.FullName.Substring($taskDir.Length)
            if ($t -match $pattern) { $hits.Add("Geplante Aufgabe $rel") }
            foreach ($f in (& $pathsIn $t)) { & $checkFile $f "Geplante Aufgabe $rel" }
        } catch { }
    }

    # 3) Autostart-Ordner (alle Benutzer) und Gruppenrichtlinien-Startskripte
    $folders = @("$env:ProgramData\Microsoft\Windows\Start Menu\Programs\StartUp",
        "$env:windir\System32\GroupPolicy\Machine\Scripts\Startup", "$env:windir\System32\GroupPolicy\User\Scripts\Logon")
    foreach ($u in @(Get-ChildItem -LiteralPath "$env:SystemDrive\Users" -Force -ErrorAction SilentlyContinue | Where-Object { $_.PSIsContainer })) {
        $folders += (Join-Path $u.FullName 'AppData\Roaming\Microsoft\Windows\Start Menu\Programs\Startup')
    }
    $shell = $null
    try { $shell = New-Object -ComObject WScript.Shell } catch { }
    foreach ($fd in $folders) {
        foreach ($f in @(Get-ChildItem -LiteralPath $fd -Force -ErrorAction SilentlyContinue | Where-Object { -not $_.PSIsContainer })) {
            if ($f.Name -match $scriptExt) { & $checkFile $f.FullName 'Autostart-Ordner' }
            elseif ($f.Extension -eq '.lnk' -and $shell) {
                try {
                    $lnk = $shell.CreateShortcut($f.FullName)   # liest die Verknüpfung nur (kein Speichern)
                    $target = "$($lnk.TargetPath) $($lnk.Arguments)"
                    if ($target -match $pattern) { $hits.Add("Verknüpfung $($f.FullName)") }
                    foreach ($p in (& $pathsIn $target)) { & $checkFile $p "Verknüpfung $($f.Name)" }
                    if ("$($lnk.TargetPath)" -match $scriptExt) { & $checkFile $lnk.TargetPath "Verknüpfung $($f.Name)" }
                } catch { }
            }
        }
    }
    return (New-BCObject @('Hits', $hits.ToArray(), 'ScannedFiles', $scanned.Count))
}

Register-BuyCheck -Id 'cpu.identity' -Category 'Prozessor (CPU)' -Order 10 -RunOrder 20 -Seconds 20 `
    -Title 'CPU-Echtheit (Namensfälschung)' `
    -Description 'Vergleicht den CPU-Namen aus vier unabhängigen Quellen (direkt vom Prozessor über den Windows-Kernel, Registry, WMI, Firmware) und prüft, ob die im Namen behauptete Generation zur tatsächlichen Chip-Architektur passt. Sucht außerdem nach Autostart-Einträgen, die den angezeigten CPU-Namen fälschen.' `
    -Profiles @('quick', 'thorough', 'linux', 'auto') `
    -Run {
    $c = Get-BCCpu
    if (-not $c) { throw 'Prozessordaten konnten nicht gelesen werden.' }
    $arch = Get-BCCpuArch -Vendor $c.Vendor -Family $c.Family -Model $c.Model -Stepping $c.Stepping
    Set-BCFact 'cpu.arch' $arch
    if ($arch.LaunchYear) { Set-BCFact 'cpu.launchYear' ([int]$arch.LaunchYear) }
    Set-BCSummary 'Prozessor' ("{0} · {1} Kerne / {2} Threads · {3}" -f $c.BestName, $c.Cores, $c.Threads, $arch.Codename)

    $facts = (New-BCOrdered @(
        'Name direkt vom Prozessor (Kernel)', $c.KernelName,
        'Name in Windows (Registry)', $c.RegistryName,
        'Name laut WMI', $c.WmiName,
        'Name laut Firmware (SMBIOS)', $c.SmbiosName,
        'Hersteller (abgeleitet)', $c.Vendor,
        'Familie / Modell / Stepping', ('0x{0:X2} / 0x{1:X2} / {2}' -f $c.Family, $c.Model, $c.Stepping),
        'Architektur / Codename', $arch.Codename,
        'Markteinführung ca.', $arch.LaunchYear,
        'Kerne / Threads (Kernel)', "$($c.Cores) / $($c.Threads)",
        'L2-Cache gesamt', $(Format-BCBytes $c.L2Bytes -Binary),
        'L3-Cache gesamt', $(Format-BCBytes $c.L3Bytes -Binary),
        'Basistakt (WMI)', $(if ($c.MaxClockMHz) { "$($c.MaxClockMHz) MHz" } else { '' }),
        'Kennung (Registry)', $c.RegistryIdentifier,
        'PROCESSOR_IDENTIFIER', $c.EnvIdentifier
    ))
    if ($c.SmbiosSignature) { $facts['Familie/Modell laut Firmware'] = ('0x{0:X2} / 0x{1:X2} / {2}' -f $c.SmbiosSignature[0], $c.SmbiosSignature[1], $c.SmbiosSignature[2]) }
    Add-BCFacts -Title 'Prozessor-Daten aus unabhängigen Quellen' -Data $facts

    # 1) Registry-Name gegen Name vom Prozessor
    if ($c.KernelName -and $c.RegistryName) {
        if ((ConvertTo-BCCpuKey $c.KernelName) -ne (ConvertTo-BCCpuKey $c.RegistryName)) {
            Add-BCFinding -Level Kritisch -Title 'CPU-Name in Windows wurde verändert' `
                -Detail "Windows zeigt '$($c.RegistryName)', der Prozessor selbst meldet '$($c.KernelName)'." `
                -Advice 'Das ist ein bekannter Betrugstrick, um eine schwächere CPU als stärkere auszugeben. Vom Kauf abraten bzw. Verkäufer darauf ansprechen.'
        } else {
            Add-BCFinding -Level OK -Title 'Windows zeigt den Namen, den der Prozessor selbst meldet' -Detail $c.KernelName
        }
    } elseif (-not $c.KernelName) {
        Add-BCFinding -Level Info -Title 'Name direkt vom Prozessor nicht abrufbar' -Detail 'Abgleich nur über Architektur und Firmware möglich.'
    }

    # 2) Kennungen in der Registry gegen Kernel-Signatur
    foreach ($pair in @(@('Registry-Kennung', $c.RegistryIdentifier), @('PROCESSOR_IDENTIFIER', $c.EnvIdentifier))) {
        $txt = "$($pair[1])"
        if ($txt -match 'Family\s+(\d+)\s+Model\s+(\d+)\s+Stepping\s+(\d+)') {
            if ([int]$Matches[1] -ne $c.Family -or [int]$Matches[2] -ne $c.Model) {
                Add-BCFinding -Level Kritisch -Title "$($pair[0]) passt nicht zum Prozessor" `
                    -Detail "Eingetragen: '$txt' – tatsächlich: Familie $($c.Family), Modell $($c.Model)." `
                    -Advice 'Hinweis auf manuelle Manipulation der Systemangaben.'
            }
        }
    }

    # 3) Firmware-Signatur gegen Kernel-Signatur
    if ($c.SmbiosSignature -and @('Intel', 'AMD') -contains $c.Vendor) {
        if ($c.SmbiosSignature[0] -ne $c.Family -or $c.SmbiosSignature[1] -ne $c.Model) {
            Add-BCFinding -Level Warnung -Title 'Firmware meldet eine andere CPU-Familie/-Modell als der Prozessor' `
                -Detail ('Firmware: 0x{0:X2}/0x{1:X2}, Prozessor: 0x{2:X2}/0x{3:X2}' -f $c.SmbiosSignature[0], $c.SmbiosSignature[1], $c.Family, $c.Model) `
                -Advice 'Ungewöhnlich (z. B. falsches BIOS nach Reparatur). Gerät genauer prüfen.'
        }
    }
    if ($c.SmbiosName -and $c.KernelName) {
        $a = Get-BCCpuModelToken $c.SmbiosName; $b = Get-BCCpuModelToken $c.KernelName
        if ($a -and $b -and $a -ne $b) {
            Add-BCFinding -Level Warnung -Title 'Firmware nennt ein anderes CPU-Modell als der Prozessor' -Detail "Firmware: '$($c.SmbiosName)' · Prozessor: '$($c.KernelName)'"
        }
    }

    # 4) Behauptete Generation gegen Architektur (deckt auch Firmware-Fälschungen wie bei Chuwi auf)
    $names = @($c.KernelName, $c.RegistryName, $c.SmbiosName) | Where-Object { $_ } | Select-Object -Unique
    $worst = $null
    foreach ($n in $names) {
        $claim = Get-BCCpuClaim $n
        if (-not $claim) { continue }
        $cmp = Compare-BCCpuClaim -Claim $claim -Arch $arch -Model $c.Model
        if (@('newer', 'vendor', 'mismatch-soft') -contains $cmp.Status) { $worst = @{ Name = $n; Cmp = $cmp }; break }
        if (-not $worst) { $worst = @{ Name = $n; Cmp = $cmp } }
    }
    if ($worst) {
        switch ($worst.Cmp.Status) {
            'match' { Add-BCFinding -Level OK -Title 'CPU-Name passt zur Chip-Architektur' -Detail $worst.Cmp.Text }
            'older' { Add-BCFinding -Level Info -Title 'CPU-Name nennt ältere Generation als der Chip' -Detail $worst.Cmp.Text }
            'mismatch-soft' { Add-BCFinding -Level Warnung -Title 'CPU-Name passt nicht eindeutig zur Architektur' -Detail $worst.Cmp.Text -Advice 'Kerne, Takt und Cache mit den Herstellerangaben vergleichen (Links unten).' }
            'unknown' { Add-BCFinding -Level Info -Title 'Architektur-Abgleich nicht möglich' -Detail $worst.Cmp.Text }
            default {
                Add-BCFinding -Level Kritisch -Title 'CPU-Name passt NICHT zur tatsächlichen Chip-Architektur' -Detail ("'{0}': {1}" -f $worst.Name, $worst.Cmp.Text) `
                    -Advice 'Starker Hinweis auf eine gefälschte CPU-Angabe (Registry- oder Firmware-Manipulation). Vom Kauf abraten.'
            }
        }
    } else {
        Add-BCFinding -Level Info -Title 'Automatischer Generationsabgleich nicht möglich' -Detail "Modell nicht in der Datenbank. Daten für den Handabgleich: $($c.Cores) Kerne, $($c.Threads) Threads, L3 $(Format-BCBytes $c.L3Bytes -Binary), Architektur $($arch.Codename)."
    }

    # 5) Autostart-Einträge, die den CPU-Namen überschreiben
    Write-BCStep 'Suche Autostart-Einträge, die den CPU-Namen verändern …'
    $t = Find-BCCpuNameTampering
    if ($t.Hits.Count -gt 0) {
        Add-BCFinding -Level Kritisch -Title 'Autostart-Eintrag verändert den angezeigten CPU-Namen' -Detail ($t.Hits -join ' · ') `
            -Advice 'Eindeutiger Manipulationsversuch. Vom Kauf abraten.'
    } else {
        Add-BCFinding -Level OK -Title 'Keine Autostart-Manipulation des CPU-Namens gefunden' -Detail "Geprüft: Run-Schlüssel, geplante Aufgaben, Autostart-Ordner, Startskripte ($($t.ScannedFiles) Skriptdateien)."
    }

    # 6) Links für den Handabgleich
    $q = [uri]::EscapeDataString(($c.BestName -replace '\((R|TM)\)', '' -replace '\s+CPU.*$', '' -replace '\s+with.*$', '' -replace '\s+w/.*$', '').Trim())
    if ($c.Vendor -eq 'Intel') { Add-BCLink -Title 'Intel ARK: offizielle Daten (Kerne, Takt, Cache) zum Vergleich' -Url "https://ark.intel.com/content/www/de/de/ark/search.html?_charset_=UTF-8&q=$q" }
    elseif ($c.Vendor -eq 'AMD') { Add-BCLink -Title 'AMD: offizielle Prozessordaten zum Vergleich' -Url 'https://www.amd.com/de/products/specifications/processors.html' }
}

Register-BuyCheck -Id 'cpu.stress' -Category 'Prozessor (CPU)' -Order 20 -RunOrder 300 -Seconds 40 -Interactive -NeedsAcPower `
    -Title 'Belastungstest: Kühlung, Drosselung, Stabilität' `
    -Description 'Lastet alle Prozessorkerne mit prüfbaren Rechenaufgaben aus. Gemessen werden die gehaltene Leistung relativ zum Basistakt, Temperaturen (soweit Windows sie liefert) und Rechenfehler. Verstaubte Lüfter oder ausgetrocknete Wärmeleitpaste zeigen sich als starke Drosselung. Bricht bei Überhitzung automatisch ab. Danach fragt das Programm, wie der Lüfter klang.' `
    -Profiles @('quick', 'thorough', 'linux') `
    -Options @(@{ Key = 'minutes'; Label = 'Dauer'; Default = 4; Min = 1; Max = 30; SecondsPerUnit = 60; Unit = 'Minuten' }) `
    -Run {
    param($Options)
    $duration = [int]([double]$Options['minutes'] * 60)
    $onAc = $true
    if ((Get-BCPowerStatus).AcOnline -eq $false) {
        $onAc = Wait-BCPower -Online $true -Message 'Bitte das Netzteil anschließen. Der Test soll die volle Leistung messen – im Akkubetrieb drosseln viele Laptops absichtlich.'
    }
    if (-not $onAc) { Add-BCFinding -Level Info -Title 'Test läuft im Akkubetrieb' -Detail 'Leistungswerte fallen dadurch niedriger aus als am Netzteil.' }

    Write-BCStep 'Leerlauf-Messung ...'
    [void](Get-BCPerfSample)
    Start-Sleep -Seconds 2
    $idle = Get-BCPerfSample
    $threads = [Environment]::ProcessorCount
    $durText = "$([int]($duration / 60)) Minuten"
    if ($duration -lt 60) { $durText = "$duration Sekunden" } elseif ($duration -lt 120) { $durText = '1 Minute' }
    Write-BCStep "Starte Last auf $threads Threads für $durText. Bitte auf das Lüftergeräusch achten! (Esc = abbrechen)"

    $stress = Start-BCCpuStress -Threads $threads
    $samples = New-Object 'System.Collections.Generic.List[object]'
    $abort = $null; $hot = 0; $lastUnits = 0.0; $lastT = 0.0
    try {
        while ($stress.Watch.Elapsed.TotalSeconds -lt $duration) {
            Start-Sleep -Milliseconds 2000
            $t = $stress.Watch.Elapsed.TotalSeconds; $u = Get-BCCpuStressUnits $stress
            $rate = ($u - $lastUnits) / [math]::Max(0.2, ($t - $lastT))
            $lastUnits = $u; $lastT = $t
            $ps = Get-BCPerfSample
            $samples.Add((New-BCObject @('T', $t, 'Rate', $rate, 'Perf', $ps.Perf, 'Temp', $ps.TempMax, 'Passive', $ps.PassiveMin, 'Throttle', $ps.Throttle)))
            $pTxt = 'n/v'; if ($null -ne $ps.Perf) { $pTxt = "$([int]$ps.Perf) % des Basistakts" }
            $tTxt = 'n/v'; if ($null -ne $ps.TempMax) { $tTxt = "$([int]$ps.TempMax) °C" }
            Write-BCProgress ("Belastungstest: Leistung $pTxt · Temperatur $tTxt · Rechenfehler $(Get-BCCpuStressErrors $stress) · noch $([int]($duration - $t)) s  (Esc = abbrechen)")
            if ($null -ne $ps.TempMax -and $ps.TempMax -ge 100) { $hot++ } else { $hot = 0 }
            if ($hot -ge 3) { $abort = 'Sicherheitsabbruch: Temperatur über 6 Sekunden ≥ 100 °C'; break }
            if (Test-BCEscape) { $abort = 'vom Benutzer abgebrochen'; break }
        }
    } finally {
        Stop-BCCpuStress $stress
        Complete-BCProgress
    }
    $errors = Get-BCCpuStressErrors $stress
    $elapsed = $stress.Watch.Elapsed.TotalSeconds
    Start-Sleep -Seconds 3
    $after = Get-BCPerfSample

    if ($abort) { Add-BCFinding -Level $(if ($abort -like 'Sicherheit*') { 'Kritisch' } else { 'Info' }) -Title "Test vorzeitig beendet: $abort" -Detail "Laufzeit: $([int]$elapsed) s" }

    # Auswertung
    $all = $samples.ToArray()
    if ($all.Count -lt 3) { Add-BCFinding -Level Fehler -Title 'Zu wenige Messwerte für eine Auswertung'; return }
    $steadyFrom = [math]::Min([double]60, $elapsed * 0.3)
    $steady = @($all | Where-Object { $_.T -ge $steadyFrom })
    if ($steady.Count -lt 2) { $steady = $all }
    $early = @($all | Where-Object { $_.T -le 16 })
    if ($early.Count -eq 0) { $early = @($all[0]) }
    $rateEarly = ($early | Measure-Object -Property Rate -Average).Average
    $rateSteady = ($steady | Measure-Object -Property Rate -Average).Average
    $drop = if ($rateEarly -gt 0) { [math]::Round((1 - $rateSteady / $rateEarly) * 100) } else { $null }
    $perfVals = @($steady | Where-Object { $null -ne $_.Perf } | ForEach-Object { [double]$_.Perf })
    $perfAvg = if ($perfVals.Count -gt 0) { ($perfVals | Measure-Object -Average).Average } else { $null }
    $temps = @($all | Where-Object { $null -ne $_.Temp } | ForEach-Object { [double]$_.Temp })
    $tMax = if ($temps.Count -gt 0) { ($temps | Measure-Object -Maximum).Maximum } else { $null }
    $passives = @($all | Where-Object { $null -ne $_.Passive } | ForEach-Object { [double]$_.Passive })
    $passMin = if ($passives.Count -gt 0) { ($passives | Measure-Object -Minimum).Minimum } else { $null }

    Add-BCFacts -Title 'Messwerte' -Data ((New-BCOrdered @(
        'Dauer', "$([int]$elapsed) s auf $threads Threads",
        'Netzteil', $(if ($onAc) { 'angeschlossen' } else { 'nein (Akku)' }),
        'Gehaltene Leistung (Ø, nach Anlaufphase)', $(if ($null -ne $perfAvg) { "$([int]$perfAvg) % des Basistakts" } else { 'nicht messbar' }),
        'Leistungsabfall Anfang → Dauerlast', $(if ($null -eq $drop) { '' } elseif ($drop -le 0) { 'kein Abfall' } else { "$drop %" }),
        'Temperatur Leerlauf / Maximum', $(if ($null -ne $tMax) { "$(if ($null -ne $idle.TempMax) { [int]$idle.TempMax } else { '?' }) °C / $([int]$tMax) °C (ACPI-Sensor)" } else { 'von Windows nicht geliefert' }),
        'Temperatur 3 s nach Lastende', $(if ($null -ne $after.TempMax) { "$([int]$after.TempMax) °C" } else { '' }),
        'Thermische Begrenzung (Passive Limit)', $(if ($null -ne $passMin) { "min. $([int]$passMin) %" } else { '' }),
        'Rechenfehler', $errors
    )))
    if ($perfVals.Count -gt 1) { Add-BCChart -Title 'Leistung über die Zeit (% des Basistakts)' -Values ([double[]]@($all | Where-Object { $null -ne $_.Perf } | ForEach-Object { [double]$_.Perf })) -Unit '%' -Reference 100 -ReferenceLabel 'Basistakt' }
    $rates = @($all | ForEach-Object { [double]$_.Rate })
    if ($rates.Count -gt 1 -and $rateEarly -gt 0) { Add-BCChart -Title 'Rechenleistung über die Zeit (% des Startwerts)' -Values ([double[]]@($rates | ForEach-Object { $_ / $rateEarly * 100 })) -Unit '%' -Reference 100 -ReferenceLabel 'Start' }
    if ($temps.Count -gt 1) { Add-BCChart -Title 'Temperatur (°C, ACPI-Sensor)' -Values ([double[]]$temps) -Unit '°C' }

    if ($errors -gt 0) {
        Add-BCFinding -Level Kritisch -Title "Rechenfehler unter Last ($errors)" -Detail 'Der Prozessor hat bei identischen Aufgaben unterschiedliche Ergebnisse geliefert.' `
            -Advice 'Hinweis auf instabile Hardware (CPU, Spannungsversorgung, RAM, Überhitzung). Vom Kauf abraten.'
    } else {
        Add-BCFinding -Level OK -Title 'Keine Rechenfehler unter Last'
    }

    if ($null -ne $perfAvg) {
        $p = [int]$perfAvg
        if (-not $onAc) {
            Add-BCFinding -Level Info -Title "Gehaltene Leistung im Akkubetrieb: $p % des Basistakts" -Detail 'Aussagekräftiger ist der Test mit Netzteil.'
        } elseif ($p -ge 90) {
            Add-BCFinding -Level OK -Title "Kühlung hält die Leistung: Ø $p % des Basistakts unter Dauerlast"
        } elseif ($p -ge 70) {
            Add-BCFinding -Level Info -Title "Leichte Drosselung: Ø $p % des Basistakts unter Dauerlast" -Detail 'Bei sehr dünnen Geräten konstruktionsbedingt normal.'
        } elseif ($p -ge 50) {
            Add-BCFinding -Level Warnung -Title "Deutliche Drosselung: Ø $p % des Basistakts unter Dauerlast" `
                -Detail 'Die CPU hält nicht einmal ihren Basistakt.' -Advice 'Typisch für verstaubte Lüfter/Kühlrippen oder ausgetrocknete Wärmeleitpaste. Reinigung/Wartung einplanen (Preis verhandeln).'
        } else {
            Add-BCFinding -Level Kritisch -Title "Massive Drosselung: Ø $p % des Basistakts unter Dauerlast" `
                -Advice 'Kühlsystem defekt oder stark verschmutzt (evtl. Lüfter/Heatpipe defekt). Nur mit Reparatur einplanen.'
        }
    } elseif ($null -ne $drop) {
        if ($drop -gt 50) { Add-BCFinding -Level Warnung -Title "Rechenleistung fällt unter Dauerlast um $drop %" -Advice 'Hinweis auf thermische Probleme.' }
        elseif ($drop -gt 30) { Add-BCFinding -Level Info -Title "Rechenleistung fällt unter Dauerlast um $drop %" -Detail 'Bei dünnen Laptops nach dem Turbo-Boost üblich.' }
        else { Add-BCFinding -Level OK -Title "Rechenleistung bleibt stabil (Abfall $drop %)" }
    }

    if ($null -ne $tMax) {
        $tIdle = $idle.TempMax
        if ($null -ne $tIdle -and [math]::Abs($tMax - $tIdle) -lt 3) {
            Add-BCFinding -Level Info -Title 'Temperatursensor über Windows nicht aussagekräftig' -Detail "Der ACPI-Wert blieb fast konstant ($([int]$tIdle) → $([int]$tMax) °C); er misst vermutlich nicht die CPU."
        } elseif ($tMax -ge 95) {
            Add-BCFinding -Level Warnung -Title "Sehr hohe Temperatur unter Last: $([int]$tMax) °C" -Advice 'Kühlung prüfen/reinigen lassen.'
        } else {
            Add-BCFinding -Level OK -Title "Temperatur unter Last: max. $([int]$tMax) °C"
        }
    }
    if ($null -ne $passMin -and $passMin -lt 100) {
        Add-BCFinding -Level Info -Title "Windows meldet thermische Begrenzung (Passive Limit min. $([int]$passMin) %)" -Detail 'Das Kühlsystem hat die Leistung zeitweise reduziert.'
    }

    # Lüftergeräusch
    $fan = Show-BCChoice -Title 'Lüfter' -Question 'Wie klang der Lüfter während des Belastungstests?' -Options @(
        'Lüfter drehte hörbar hoch, Geräusch gleichmäßig (normal)',
        'Lüfter blieb still bzw. war kaum zu hören',
        'Schleifen, Rattern, Klackern oder Pfeifen',
        'Nicht darauf geachtet / unklar') -Comment
    switch ($fan.Choice) {
        0 { Add-BCFinding -Level OK -Title 'Lüfter klingt normal' -Detail $fan.Comment }
        1 {
            $lvl = if (($null -ne $perfAvg -and $perfAvg -lt 70) -or ($null -ne $tMax -and $tMax -ge 90)) { 'Warnung' } else { 'Info' }
            Add-BCFinding -Level $lvl -Title 'Lüfter war unter Last kaum zu hören' -Detail $fan.Comment -Advice 'Bei hohen Temperaturen/Drosselung: Lüfter evtl. defekt. Ohne Auffälligkeiten: leises Kühlsystem oder passiv gekühltes Gerät.'
        }
        2 { Add-BCFinding -Level Warnung -Title 'Lüfter macht Schleif-/Rattergeräusche' -Detail $fan.Comment -Advice 'Lüfterlager verschlissen – Austausch einplanen (Preis verhandeln).' }
        default { Add-BCFinding -Level Info -Title 'Lüftergeräusch nicht bewertet' -Detail $fan.Comment }
    }
}
