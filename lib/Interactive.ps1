# BuyCheck – Mitmach-Tests in der Konsole (ohne Fenster)
# Alles hier liest nur Eingaben bzw. gibt Bild/Ton aus. Es werden keine Einstellungen geändert
# (auch nicht die Lautstärke) und keine Dateien angelegt.

# ============================================================== Netzteil abwarten
# Wartet, bis das Netzteil angeschlossen ($Online = $true) bzw. abgezogen ist. $false = übersprungen/Zeit abgelaufen.
function Wait-BCPower {
    param([bool]$Online, [string]$Message, [int]$TimeoutSeconds = 180)
    $state = Get-BCPowerStatus
    if ($state.AcOnline -eq $Online) { return $true }
    if ($null -eq $state.AcOnline) {
        $st = Get-BCBatteryStatus
        if ($st.PowerOnline -eq $Online) { return $true }
    }
    Write-BCOut ''
    Write-BCOut -Text $Message -Indent 3 -Color White
    $sw = [Diagnostics.Stopwatch]::StartNew()
    $result = $false
    while ($sw.Elapsed.TotalSeconds -lt $TimeoutSeconds) {
        $state = Get-BCPowerStatus
        $now = $state.AcOnline
        if ($null -eq $now) { $now = (Get-BCBatteryStatus).PowerOnline }
        if ($now -eq $Online) { $result = $true; break }
        $txt = 'Warte auf das Abziehen des Netzteils'
        if ($Online) { $txt = 'Warte auf das Netzteil' }
        Write-BCProgress ('{0} ... noch {1} s  (S = überspringen)' -f $txt, [int]($TimeoutSeconds - $sw.Elapsed.TotalSeconds))
        $skip = $false
        try {
            while ([Console]::KeyAvailable) {
                $k = [Console]::ReadKey($true)
                if ($k.Key -eq [ConsoleKey]::Escape -or $k.Key -eq [ConsoleKey]::S) { $skip = $true }
            }
        } catch { }
        if ($skip) { break }
        Start-Sleep -Milliseconds 400
    }
    Complete-BCProgress
    if ($result) {
        if ($Online) { Write-BCOut -Text 'Netzteil erkannt.' -Indent 3 -Color Green } else { Write-BCOut -Text 'Akkubetrieb erkannt.' -Indent 3 -Color Green }
    }
    return $result
}

# ============================================================== Pixeltest: Konsole vollflächig einfärben
function Invoke-BCColorScreens {
    $colors = @(
        @('Black', 'Schwarz: helle oder farbige Punkte = Dauerpixel, helle Ränder = Lichthöfe'),
        @('White', 'Weiß: dunkle Punkte = tote Pixel, Flecken oder Wolken'),
        @('Red', 'Rot'),
        @('Green', 'Grün'),
        @('Blue', 'Blau'),
        @('Gray', 'Grau: Streifen, ungleichmäßige Helligkeit'),
        @('DarkGray', 'Dunkelgrau: Wolken, Flecken, Druckstellen')
    )
    $raw = $Host.UI.RawUI
    $oldBg = $raw.BackgroundColor; $oldFg = $raw.ForegroundColor
    $cursor = $true
    try { $cursor = [Console]::CursorVisible; [Console]::CursorVisible = $false } catch { }
    Set-BCConsoleWindowState 3
    $completed = $true
    try {
        $i = 0
        while ($i -lt $colors.Count) {
            $raw.BackgroundColor = $colors[$i][0]
            $raw.ForegroundColor = 'White'
            if ($colors[$i][0] -eq 'White' -or $colors[$i][0] -eq 'Gray' -or $colors[$i][0] -eq 'Green') { $raw.ForegroundColor = 'Black' }
            Clear-Host
            Write-Host (ConvertTo-BCConsoleText (' Farbe {0}/{1} – {2}.  Leertaste = weiter, Pfeil links = zurück, Esc = beenden' -f ($i + 1), $colors.Count, $colors[$i][1]))
            # Hinweis nach 2,5 Sekunden ausblenden, damit die ganze Fläche sichtbar ist
            $sw = [Diagnostics.Stopwatch]::StartNew()
            $key = $null
            while ($sw.ElapsedMilliseconds -lt 2500 -and -not $key) {
                try { if ([Console]::KeyAvailable) { $key = [Console]::ReadKey($true) } } catch { $key = $null; break }
                Start-Sleep -Milliseconds 50
            }
            if (-not $key) { Clear-Host; try { $key = [Console]::ReadKey($true) } catch { break } }
            if ($key.Key -eq [ConsoleKey]::Escape) { $completed = ($i -ge $colors.Count - 1); break }
            if ($key.Key -eq [ConsoleKey]::LeftArrow -or $key.Key -eq [ConsoleKey]::Backspace) { if ($i -gt 0) { $i-- } }
            else { $i++ }
        }
    } finally {
        $raw.BackgroundColor = $oldBg; $raw.ForegroundColor = $oldFg
        Clear-Host
        try { [Console]::CursorVisible = $cursor } catch { }
    }
    return $completed
}

# ============================================================== Tastaturtest (liest Scancodes direkt aus der Konsole)
# Code = Scancode, +0x100 bei erweiterten Tasten; Sonderfälle über den Tastencode (VK): 0x1013 Pause, 0x1090 Num, 0x102C Druck
function Get-BCKeyboardLayout {
    $rows = @(
        @('', @(@('Esc', 0x01, 0), @('F1', 0x3B, 0), @('F2', 0x3C, 0), @('F3', 0x3D, 0), @('F4', 0x3E, 0), @('F5', 0x3F, 0), @('F6', 0x40, 0),
                @('F7', 0x41, 0), @('F8', 0x42, 0), @('F9', 0x43, 0), @('F10', 0x44, 0), @('F11', 0x57, 0), @('F12', 0x58, 0))),
        @('', @(@('^', 0x29, 0), @('1', 0x02, 0), @('2', 0x03, 0), @('3', 0x04, 0), @('4', 0x05, 0), @('5', 0x06, 0), @('6', 0x07, 0), @('7', 0x08, 0),
                @('8', 0x09, 0), @('9', 0x0A, 0), @('0', 0x0B, 0), @([string][char]0xDF, 0x0C, 0), @([string][char]0xB4, 0x0D, 0), @('Rück', 0x0E, 0))),
        @('', @(@('Tab', 0x0F, 0), @('Q', 0x10, 0), @('W', 0x11, 0), @('E', 0x12, 0), @('R', 0x13, 0), @('T', 0x14, 0), @('Z', 0x15, 0), @('U', 0x16, 0),
                @('I', 0x17, 0), @('O', 0x18, 0), @('P', 0x19, 0), @([string][char]0xDC, 0x1A, 0), @('+', 0x1B, 0), @('Enter', 0x1C, 0))),
        @('', @(@('Feststell', 0x3A, 0), @('A', 0x1E, 0), @('S', 0x1F, 0), @('D', 0x20, 0), @('F', 0x21, 0), @('G', 0x22, 0), @('H', 0x23, 0),
                @('J', 0x24, 0), @('K', 0x25, 0), @('L', 0x26, 0), @([string][char]0xD6, 0x27, 0), @([string][char]0xC4, 0x28, 0), @('#', 0x2B, 0))),
        @('', @(@('Umschalt', 0x2A, 0), @('<', 0x56, 0), @('Y', 0x2C, 0), @('X', 0x2D, 0), @('C', 0x2E, 0), @('V', 0x2F, 0), @('B', 0x30, 0),
                @('N', 0x31, 0), @('M', 0x32, 0), @(',', 0x33, 0), @('.', 0x34, 0), @('-', 0x35, 0), @('Umschalt-r', 0x36, 0))),
        @('', @(@('Strg', 0x1D, 0), @('Win', 0x15B, 0), @('Alt', 0x38, 0), @('Leertaste', 0x39, 0), @('AltGr', 0x138, 0), @('Menü', 0x15D, 1), @('Strg-r', 0x11D, 1))),
        @('', @(@('Pfeil hoch', 0x148, 0), @('Pfeil links', 0x14B, 0), @('Pfeil runter', 0x150, 0), @('Pfeil rechts', 0x14D, 0))),
        @('', @(@('Einfg', 0x152, 1), @('Entf', 0x153, 0), @('Pos1', 0x147, 1), @('Ende', 0x14F, 1), @('Bild hoch', 0x149, 1), @('Bild runter', 0x151, 1))),
        @('', @(@('Druck', 0x102C, 1), @('Rollen', 0x46, 1), @('Pause', 0x1013, 1), @('Win-r', 0x15C, 1))),
        @('Ziffernblock (falls vorhanden):', @(@('Num', 0x1090, 1), @('/', 0x135, 1), @('*', 0x37, 1), @('-', 0x4A, 1), @('7', 0x47, 1), @('8', 0x48, 1),
                @('9', 0x49, 1), @('+', 0x4E, 1), @('4', 0x4B, 1), @('5', 0x4C, 1), @('6', 0x4D, 1), @('1', 0x4F, 1), @('2', 0x50, 1), @('3', 0x51, 1),
                @('Enter', 0x11C, 1), @('0', 0x52, 1), @(',', 0x53, 1)))
    )
    return , $rows
}

function Invoke-BCKeyboardCapture {
    $in = Get-BCConsoleInputHandle
    if (-not $in) { return $null }
    $rows = Get-BCKeyboardLayout
    $keys = @{}
    $order = New-Object 'System.Collections.Generic.List[object]'
    Clear-Host
    Write-BCOut -Text 'TASTATURTEST' -Indent 1 -Color Cyan
    Write-BCOut -Text 'Drücke nacheinander JEDE Taste einmal – erkannte Tasten werden grün. F-Tasten ggf. zusammen mit Fn drücken. Grau = optional (nicht jeder Laptop hat sie). Bitte Tasten einzeln drücken (nicht Alt+F4!). Die Windows-Taste zuletzt drücken und das Startmenü danach mit Esc schließen. Die Fn-Taste allein kann kein Programm erkennen.' -Indent 1 -Color Gray
    Write-BCOut -Text 'Fertig: Esc dreimal hintereinander drücken.' -Indent 1 -Color White
    Write-Host ''
    foreach ($row in $rows) {
        if ($row[0]) { Write-Host (' ' + (ConvertTo-BCConsoleText $row[0])) -ForegroundColor DarkGray }
        $x = 1
        $y = [Console]::CursorTop
        foreach ($k in $row[1]) {
            $label = '[' + $k[0] + ']'
            $o = New-BCObject @('Label', [string]$k[0], 'Code', [int]$k[1], 'Optional', ([int]$k[2] -eq 1), 'X', $x, 'Y', $y, 'Text', $label, 'Pressed', $false, 'Downs', 0)
            $keys[[int]$k[1]] = $o
            $order.Add($o)
            [Console]::SetCursorPosition($x, $y)
            if ($o.Optional) { [Console]::ForegroundColor = 'DarkGray' } else { [Console]::ForegroundColor = 'White' }
            [Console]::Write($label)
            $x += $label.Length + 1
        }
        [Console]::ResetColor()
        [Console]::WriteLine()
    }
    Write-Host ''
    $statusY = [Console]::CursorTop
    Write-Host ''; Write-Host ''
    $endY = [Console]::CursorTop

    $mode = Get-BCConsoleMode $in
    [void](Set-BCConsoleMode $in 0x80)            # nur rohe Tastenereignisse (Strg+C wird zur normalen Taste)
    Clear-BCConsoleInput $in
    $extras = @{}
    $held = @{}
    $stuck = @{}
    $escRun = 0
    $lastCtrl = $null; $lastCtrlTime = 0L
    $sw = [Diagnostics.Stopwatch]::StartNew()
    $dirty = $true
    try {
        while ($escRun -lt 3) {
            $events = Read-BCConsoleEvents $in
            if ($events.Count -eq 0) {
                if ($dirty) {
                    $missing = @($order | Where-Object { -not $_.Pressed -and -not $_.Optional } | ForEach-Object { $_.Label })
                    $txt = 'Alle Pflichttasten erkannt. Weitere Tasten testen oder 3x Esc zum Beenden.'
                    if ($missing.Count -gt 0) { $txt = 'Noch nicht gedrückt (' + $missing.Count + '): ' + ($missing -join ' ') }
                    $w = (Get-BCWidth) - 2
                    $txt = ConvertTo-BCConsoleText $txt
                    [Console]::SetCursorPosition(1, $statusY)
                    [Console]::ForegroundColor = 'Yellow'
                    [Console]::Write($txt.PadRight($w * 2).Substring(0, $w * 2))
                    [Console]::ResetColor()
                    $dirty = $false
                }
                Start-Sleep -Milliseconds 15
                continue
            }
            foreach ($e in $events) {
                if ($e.Type -ne 'Key') { continue }
                $vk = [int]$e.VK
                $code = [int]$e.Scan
                if (($e.State -band 0x100) -ne 0) { $code = $code -bor 0x100 }
                if ($vk -eq 0x13) { $code = 0x1013 } elseif ($vk -eq 0x90) { $code = 0x1090 } elseif ($vk -eq 0x2C) { $code = 0x102C }
                if (-not $e.Down) { $held[$code] = 0; continue }
                $held[$code] = 1 + [int]$held[$code]
                if ([int]$held[$code] -gt 40) { $stuck[$code] = $true }
                if ([int]$held[$code] -gt 1) { continue }      # automatische Wiederholung beim Festhalten
                if ($code -eq 0x01) { $escRun++ } else { $escRun = 0 }
                $now = $sw.ElapsedMilliseconds
                # AltGr erzeugt unter Windows zusätzlich ein künstliches "Strg links" – das nicht mitzählen
                if ($code -eq 0x138 -and $lastCtrl -and ($now - $lastCtrlTime) -lt 60) {
                    $lastCtrl.Pressed = $false
                    $lastCtrl.Downs = 0
                    [Console]::SetCursorPosition($lastCtrl.X, $lastCtrl.Y)
                    [Console]::ForegroundColor = 'White'; [Console]::Write($lastCtrl.Text); [Console]::ResetColor()
                }
                $lastCtrl = $null
                if ($keys.ContainsKey($code)) {
                    $k = $keys[$code]
                    $k.Downs++
                    if ($code -eq 0x1D -and -not $k.Pressed) { $lastCtrl = $k; $lastCtrlTime = $now }
                    if (-not $k.Pressed) {
                        $k.Pressed = $true
                        [Console]::SetCursorPosition($k.X, $k.Y)
                        [Console]::ForegroundColor = 'Black'; [Console]::BackgroundColor = 'Green'
                        [Console]::Write($k.Text)
                        [Console]::ResetColor()
                    }
                } else {
                    $name = "VK $vk / Scan $('{0:X}' -f $code)"
                    $extras[$name] = $true
                }
                $dirty = $true
            }
        }
    } finally {
        if ($null -ne $mode) { [void](Set-BCConsoleMode $in $mode) }
        Clear-BCConsoleInput $in
        try { [Console]::ResetColor(); [Console]::SetCursorPosition(0, $endY) } catch { }
    }
    Write-Host ''
    $stuckNames = @()
    foreach ($c in @($stuck.Keys)) { if ($keys.ContainsKey($c)) { $stuckNames += $keys[$c].Label } else { $stuckNames += ('Scan {0:X}' -f $c) } }
    return (New-BCObject @(
            'Pressed', @($order | Where-Object { $_.Pressed } | ForEach-Object { $_.Label }),
            'Missing', @($order | Where-Object { -not $_.Pressed -and -not $_.Optional } | ForEach-Object { $_.Label }),
            'MissingOptional', @($order | Where-Object { -not $_.Pressed -and $_.Optional } | ForEach-Object { $_.Label }),
            'Extra', @($extras.Keys),
            'Stuck', $stuckNames,
            'Seconds', [int]$sw.Elapsed.TotalSeconds
        ))
}

# ============================================================== Touchpad: Zeigerposition und Maustasten abfragen
function Invoke-BCTouchpadCapture {
    param([int]$TimeoutSeconds = 120)
    $screen = Get-BCScreenSize
    if (-not $screen -or $screen.Width -le 0) { return $null }
    $cols = 4; $rows = 3
    $visited = New-Object bool[] ($cols * $rows)
    $in = Get-BCConsoleInputHandle
    $mode = $null
    if ($in) { $mode = Get-BCConsoleMode $in; if ($null -ne $mode) { [void](Set-BCConsoleMode $in ((($mode -bor 0x80) -band (-bnot 0x40)) -band (-bnot 0x10))) } }   # Schnellbearbeitung aus
    Clear-Host
    Write-BCOut -Text 'TOUCHPADTEST' -Indent 1 -Color Cyan
    Write-BCOut -Text 'Fahre mit dem Finger über das Touchpad, bis der Mauszeiger in allen Bereichen des Bildschirms war (auch in den Ecken) und alle Felder grün sind. Bitte dabei NICHT klicken. Nach Klicks und Scrollen wirst du danach gefragt.' -Indent 1
    Write-BCOut -Text 'Beenden: Esc oder Enter. Der Test endet von selbst, wenn alle Felder grün sind.' -Indent 1 -Color White
    Write-Host ''
    $gridY = [Console]::CursorTop
    for ($r = 0; $r -lt $rows; $r++) { Write-Host ('   ' + ('[      ] ' * $cols)) -ForegroundColor DarkGray }
    Write-Host ''
    $statusY = [Console]::CursorTop
    Write-Host ''; Write-Host ''
    $endY = [Console]::CursorTop
    $sw = [Diagnostics.Stopwatch]::StartNew()
    $doneAt = $null
    $dirty = $true
    try {
        while ($sw.Elapsed.TotalSeconds -lt $TimeoutSeconds) {
            $pos = Get-BCCursorPos
            if ($pos) {
                $cx = [int][math]::Floor([double]$pos.X / $screen.Width * $cols)
                $cy = [int][math]::Floor([double]$pos.Y / $screen.Height * $rows)
                $cx = [math]::Max(0, [math]::Min($cols - 1, $cx)); $cy = [math]::Max(0, [math]::Min($rows - 1, $cy))
                $idx = $cy * $cols + $cx
                if (-not $visited[$idx]) {
                    $visited[$idx] = $true
                    [Console]::SetCursorPosition(3 + $cx * 9, $gridY + $cy)
                    [Console]::ForegroundColor = 'Black'; [Console]::BackgroundColor = 'Green'
                    [Console]::Write('[  OK  ]')
                    [Console]::ResetColor()
                    $dirty = $true
                }
            }
            $stop = $false
            try { while ([Console]::KeyAvailable) { $k = [Console]::ReadKey($true); if ($k.Key -eq [ConsoleKey]::Escape -or $k.Key -eq [ConsoleKey]::Enter) { $stop = $true } } } catch { }
            if ($stop) { break }
            if ($dirty) {
                $n = @($visited | Where-Object { $_ }).Count
                $txt = 'Bildschirmbereiche erreicht: {0} von {1}' -f $n, $visited.Length
                [Console]::SetCursorPosition(1, $statusY)
                [Console]::ForegroundColor = 'Yellow'
                [Console]::Write((ConvertTo-BCConsoleText $txt).PadRight((Get-BCWidth) - 2))
                [Console]::ResetColor()
                $dirty = $false
            }
            if (-not $doneAt -and @($visited | Where-Object { -not $_ }).Count -eq 0) { $doneAt = $sw.ElapsedMilliseconds }
            if ($doneAt -and ($sw.ElapsedMilliseconds - $doneAt) -gt 1500) { break }
            Start-Sleep -Milliseconds 40
        }
    } finally {
        if ($in -and $null -ne $mode) { [void](Set-BCConsoleMode $in $mode) }
        if ($in) { Clear-BCConsoleInput $in }     # versehentlich eingefügten Text (z. B. nach Rechtsklick) verwerfen
        Clear-BCKeyBuffer
        try { [Console]::ResetColor(); [Console]::SetCursorPosition(0, $endY) } catch { }
    }
    return (New-BCObject @('Cells', $visited.Length, 'Visited', @($visited | Where-Object { $_ }).Count,
            'TimedOut', ($sw.Elapsed.TotalSeconds -ge $TimeoutSeconds), 'Seconds', [int]$sw.Elapsed.TotalSeconds))
}

# ============================================================== USB: neu eingesteckte Geräte erkennen
function Get-BCUsbSnapshot {
    $h = @{}
    foreach ($d in @(Get-BCWmi -ClassName Win32_PnPEntity -Filter "PNPDeviceID LIKE 'USB%'")) { if ($d) { $h["$($d.PNPDeviceID)"] = "$($d.Name)" } }
    return $h
}

function Get-BCUsbLocation {
    param([string]$InstanceId)
    if ($InstanceId -notmatch '^USB\\VID_') { return '' }
    $loc = Get-BCRegValue ('HKLM:\SYSTEM\CurrentControlSet\Enum\' + $InstanceId) 'LocationInformation'
    if ("$loc" -match 'Port_#0*(\d+)\.Hub_#0*(\d+)') { return ('Anschluss {0} an USB-Hub {1}' -f $Matches[1], $Matches[2]) }
    return "$loc"
}

function Invoke-BCUsbWatch {
    param([int]$TimeoutSeconds = 600)
    $base = Get-BCUsbSnapshot
    $found = New-Object 'System.Collections.Generic.List[object]'
    $evt = $false
    try { Register-WmiEvent -Class Win32_DeviceChangeEvent -SourceIdentifier 'BuyCheckUsb' -ErrorAction Stop | Out-Null; $evt = $true }
    catch { Write-BCDebug "USB-Ereignisse nicht verfügbar, frage regelmäßig ab: $($_.Exception.Message)" }
    Write-BCOut -Text 'Stecke jetzt ein USB-Gerät nacheinander in JEDEN USB-Anschluss (auch USB-C). Jeder erkannte Anschluss wird angezeigt. Fertig: Enter.' -Indent 3 -Color White
    $sw = [Diagnostics.Stopwatch]::StartNew()
    try {
        while ($sw.Elapsed.TotalSeconds -lt $TimeoutSeconds) {
            $changed = $false
            if ($evt) {
                $e = Wait-Event -SourceIdentifier 'BuyCheckUsb' -Timeout 1
                if ($e) {
                    Start-Sleep -Milliseconds 900
                    Get-Event -SourceIdentifier 'BuyCheckUsb' -ErrorAction SilentlyContinue | Remove-Event -ErrorAction SilentlyContinue
                    $changed = $true
                }
            } else {
                Start-Sleep -Milliseconds 2000
                $changed = $true
            }
            if ($changed) {
                $now = Get-BCUsbSnapshot
                foreach ($id in @($now.Keys)) {
                    if (-not $base.ContainsKey($id) -and $id -match '^USB\\VID_' -and $id -notmatch '&MI_') {
                        $loc = Get-BCUsbLocation $id
                        $found.Add((New-BCObject @('Name', $now[$id], 'Location', $loc, 'Instance', $id, 'Seconds', [int]$sw.Elapsed.TotalSeconds)))
                        $where = ''; if ($loc) { $where = " ($loc)" }
                        Complete-BCProgress
                        Write-BCOut -Text ("Erkannt: {0}{1}" -f $now[$id], $where) -Indent 3 -Color Green
                    }
                }
                $base = $now
            }
            $ports = @($found | ForEach-Object { $_.Location } | Where-Object { $_ } | Select-Object -Unique).Count
            Write-BCProgress ('Bisher {0} Einsteckvorgänge erkannt ({1} verschiedene Anschlüsse). Enter = fertig' -f $found.Count, $ports)
            $stop = $false
            try { while ([Console]::KeyAvailable) { $k = [Console]::ReadKey($true); if ($k.Key -eq [ConsoleKey]::Enter -or $k.Key -eq [ConsoleKey]::Escape) { $stop = $true } } } catch { }
            if ($stop) { break }
        }
    } finally {
        Complete-BCProgress
        if ($evt) {
            Unregister-Event -SourceIdentifier 'BuyCheckUsb' -ErrorAction SilentlyContinue
            Get-Event -SourceIdentifier 'BuyCheckUsb' -ErrorAction SilentlyContinue | Remove-Event -ErrorAction SilentlyContinue
        }
    }
    return $found.ToArray()
}

# ============================================================== Externer Bildschirm
function Get-BCMonitorCount { return @(Get-BCWmi -Namespace 'root\wmi' -ClassName WmiMonitorBasicDisplayParams | Where-Object { $_ -and $_.Active }).Count }

function Invoke-BCMonitorWatch {
    param([int]$TimeoutSeconds = 180)
    $before = Get-BCMonitorCount
    Write-BCOut -Text 'Schließe jetzt einen Monitor oder Fernseher an (HDMI, USB-C oder DisplayPort). Erscheint kein Bild, Windows-Taste+P drücken und "Duplizieren" wählen. Fertig: Enter.' -Indent 3 -Color White
    $sw = [Diagnostics.Stopwatch]::StartNew()
    $max = $before
    while ($sw.Elapsed.TotalSeconds -lt $TimeoutSeconds) {
        Start-Sleep -Milliseconds 1500
        $n = Get-BCMonitorCount
        if ($n -gt $max) { $max = $n; Complete-BCProgress; Write-BCOut -Text "Zusätzlicher Bildschirm erkannt (jetzt $n aktiv)." -Indent 3 -Color Green }
        Write-BCProgress ('Aktive Bildschirme: {0} (vorher {1}). Enter = fertig' -f $n, $before)
        $stop = $false
        try { while ([Console]::KeyAvailable) { $k = [Console]::ReadKey($true); if ($k.Key -eq [ConsoleKey]::Enter -or $k.Key -eq [ConsoleKey]::Escape) { $stop = $true } } } catch { }
        if ($stop) { break }
    }
    Complete-BCProgress
    return (New-BCObject @('Before', $before, 'Max', $max))
}

# ============================================================== Testtöne (werden im Arbeitsspeicher erzeugt, keine Datei)
# Segmente: @(Frequenz in Hz, Sekunden, links 0/1, rechts 0/1). Frequenzen sollten 44100 ohne Rest teilen.
function New-BCToneWav {
    param([object[]]$Segments)
    $rate = 44100
    $chunks = New-Object 'System.Collections.Generic.List[object]'
    $total = 0
    foreach ($s in $Segments) {
        $freq = [double]$s[0]; $sec = [double]$s[1]; $lOn = [int]$s[2]; $rOn = [int]$s[3]
        $frames = [int]($rate * $sec)
        $period = [int][math]::Round($rate / $freq)
        $data = New-Object byte[] ($frames * 4)
        # eine Schwingung berechnen, dann per Kopie vervielfältigen (schnell, auch auf schwachen Geräten)
        for ($i = 0; $i -lt $period; $i++) {
            $v = [int]([math]::Sin(2 * [math]::PI * $i / $period) * 11000)
            $b = [BitConverter]::GetBytes([int16]$v)
            $o = $i * 4
            if ($lOn) { $data[$o] = $b[0]; $data[$o + 1] = $b[1] }
            if ($rOn) { $data[$o + 2] = $b[0]; $data[$o + 3] = $b[1] }
        }
        $filled = $period * 4
        while ($filled -lt $data.Length) {
            $n = [math]::Min($filled, $data.Length - $filled)
            [Array]::Copy($data, 0, $data, $filled, $n)
            $filled += $n
        }
        # weiches Ein-/Ausblenden (gegen Knacken)
        $fade = [math]::Min(882, [int]($frames / 4))
        for ($i = 0; $i -lt $fade; $i++) {
            $f = $i / [double]$fade
            foreach ($o in @(($i * 4), (($frames - 1 - $i) * 4))) {
                for ($c = 0; $c -lt 4; $c += 2) {
                    $v = [BitConverter]::ToInt16($data, $o + $c)
                    $b = [BitConverter]::GetBytes([int16]([int]($v * $f)))
                    $data[$o + $c] = $b[0]; $data[$o + $c + 1] = $b[1]
                }
            }
        }
        $chunks.Add($data); $total += $data.Length
    }
    $ms = New-Object System.IO.MemoryStream
    $w = New-Object System.IO.BinaryWriter($ms)
    $w.Write([Text.Encoding]::ASCII.GetBytes('RIFF')); $w.Write([int](36 + $total)); $w.Write([Text.Encoding]::ASCII.GetBytes('WAVE'))
    $w.Write([Text.Encoding]::ASCII.GetBytes('fmt ')); $w.Write([int]16); $w.Write([int16]1); $w.Write([int16]2)
    $w.Write([int]$rate); $w.Write([int]($rate * 4)); $w.Write([int16]4); $w.Write([int16]16)
    $w.Write([Text.Encoding]::ASCII.GetBytes('data')); $w.Write([int]$total)
    foreach ($c in $chunks) { $w.Write([byte[]]$c) }
    $w.Flush()
    return , $ms.ToArray()
}

function Invoke-BCPlayWav {
    param([byte[]]$Wav)
    $ms = New-Object System.IO.MemoryStream(, $Wav)
    $sp = New-Object System.Media.SoundPlayer($ms)
    try { $sp.PlaySync() } finally { $sp.Dispose(); $ms.Dispose() }
}

# ============================================================== Mikrofon (Aufnahme nur im Arbeitsspeicher, Wiedergabe direkt danach)
function Invoke-BCMicTest {
    param([int]$Seconds = 5)
    $r = Invoke-BCMci 'open new type waveaudio alias bcmic'
    if ($r.Code -ne 0) { return (New-BCObject @('Ok', $false, 'Error', "Kein Aufnahmegerät verfügbar (MCI-Fehler $($r.Code))", 'MaxLevel', $null)) }
    $maxLevel = $null
    try {
        [void](Invoke-BCMci 'set bcmic bitspersample 16 samplespersec 22050 channels 1')
        $rec = Invoke-BCMci 'record bcmic'
        if ($rec.Code -ne 0) { return (New-BCObject @('Ok', $false, 'Error', "Aufnahme ließ sich nicht starten (MCI-Fehler $($rec.Code))", 'MaxLevel', $null)) }
        $sw = [Diagnostics.Stopwatch]::StartNew()
        while ($sw.Elapsed.TotalSeconds -lt $Seconds) {
            $lv = Invoke-BCMci 'status bcmic level'
            $val = 0
            if ($lv.Code -eq 0 -and [int]::TryParse("$($lv.Text)".Trim(), [ref]$val)) {
                if ($null -eq $maxLevel -or $val -gt $maxLevel) { $maxLevel = $val }
                $bar = [int][math]::Min(40, $val / 32767.0 * 40 * 4)
                Write-BCProgress ('Aufnahme läuft ({0} s) – Pegel: {1}' -f [int]($Seconds - $sw.Elapsed.TotalSeconds), ('#' * $bar))
            } else {
                Write-BCProgress ('Aufnahme läuft ({0} s) – bitte sprechen ...' -f [int]($Seconds - $sw.Elapsed.TotalSeconds))
            }
            Start-Sleep -Milliseconds 120
        }
        [void](Invoke-BCMci 'stop bcmic')
        Complete-BCProgress
        Write-BCOut -Text 'Wiedergabe der Aufnahme ...' -Indent 3 -Color White
        $pl = Invoke-BCMci 'play bcmic from 0 wait'
        if ($pl.Code -ne 0) { return (New-BCObject @('Ok', $false, 'Error', "Wiedergabe fehlgeschlagen (MCI-Fehler $($pl.Code))", 'MaxLevel', $maxLevel)) }
    } finally {
        Complete-BCProgress
        [void](Invoke-BCMci 'close bcmic')
    }
    return (New-BCObject @('Ok', $true, 'Error', '', 'MaxLevel', $maxLevel))
}
