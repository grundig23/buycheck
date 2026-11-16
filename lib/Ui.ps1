# BuyCheck – Text-Oberfläche (Konsole): Ausgabe, Fragen per Tastendruck, Auswahlmenü
# Keine Fenster, keine Grafik. Funktioniert ab Windows PowerShell 2.0 in der normalen Konsole
# und im Windows Terminal.

# Zeichen, die alte Konsolenschriften (Rasterschrift unter Windows 7) nicht darstellen können
$script:BCConsoleMap = @{}
foreach ($pair in @(
        @(0x2026, '...'), @(0x2013, '-'), @(0x2014, '-'), @(0x2011, '-'), @(0x201E, '"'), @(0x201C, '"'), @(0x201D, '"'), @(0x00AB, '"'), @(0x00BB, '"'),
        @(0x201A, "'"), @(0x2018, "'"), @(0x2019, "'"), @(0x2192, '->'), @(0x2190, '<-'), @(0x2191, '^'), @(0x2193, 'v'), @(0x2194, '<->'),
        @(0x2248, '~'), @(0x2265, '>='), @(0x2264, '<='), @(0x2260, '!='), @(0x2713, 'OK'), @(0x2714, 'OK'), @(0x2717, 'X'), @(0x2716, 'X'),
        @(0x2022, '-'), @(0x20AC, 'EUR'), @(0x00A0, ' '), @(0x00D7, 'x'), @(0x2009, ' ')
    )) { $script:BCConsoleMap[[string][char]$pair[0]] = $pair[1] }

function ConvertTo-BCConsoleText {
    param([string]$Text)
    if (-not $Text) { return '' }
    $t = $Text
    foreach ($k in $script:BCConsoleMap.Keys) { if ($t.Contains($k)) { $t = $t.Replace($k, $script:BCConsoleMap[$k]) } }
    return $t
}

function Get-BCWidth {
    try { $w = $Host.UI.RawUI.WindowSize.Width; if ($w -ge 40) { return [int]$w } } catch { }
    return 100
}

# Zeilenumbruch an Wortgrenzen
function Split-BCText {
    param([string]$Text, [int]$Width)
    if ($Width -lt 20) { $Width = 20 }
    $out = New-Object 'System.Collections.Generic.List[string]'
    $line = ''
    foreach ($w in ($Text -split ' ')) {
        if ($line.Length -eq 0) { $line = $w }
        elseif ($line.Length + 1 + $w.Length -le $Width) { $line += ' ' + $w }
        else { $out.Add($line); $line = $w }
        while ($line.Length -gt $Width) { $out.Add($line.Substring(0, $Width)); $line = $line.Substring($Width) }
    }
    $out.Add($line)
    return , $out.ToArray()
}

$script:BCProgressActive = $false

# Text ausgeben (mit Umbruch). -Prefix wird nur vor die erste Zeile gesetzt, Folgezeilen werden eingerückt.
function Write-BCOut {
    param([string]$Text = '', [string]$Color = 'Gray', [int]$Indent = 0, [string]$Prefix = '', [switch]$NoNewline)
    if ($script:BCProgressActive) { Complete-BCProgress }
    $t = ConvertTo-BCConsoleText $Text
    $p = ConvertTo-BCConsoleText $Prefix
    if ($NoNewline) { Write-Host ((' ' * $Indent) + $p + $t) -ForegroundColor $Color -NoNewline; return }
    $width = (Get-BCWidth) - 1
    $lead = (' ' * $Indent) + $p
    $pad = ' ' * $lead.Length
    $first = $true
    foreach ($para in $t.Split([char]10)) {
        foreach ($l in (Split-BCText $para.TrimEnd([char]13) ($width - $lead.Length))) {
            if ($first) { Write-Host ($lead + $l) -ForegroundColor $Color; $first = $false }
            else { Write-Host ($pad + $l) -ForegroundColor $Color }
        }
    }
}

function Write-BCHeader {
    param([string]$Text)
    $w = [math]::Min((Get-BCWidth) - 1, 78)
    Write-BCOut ''
    Write-BCOut ('=' * $w) -Color DarkCyan
    Write-BCOut -Text $Text -Indent 2 -Color Cyan
    Write-BCOut ('=' * $w) -Color DarkCyan
}

function Write-BCCheckTitle {
    param([int]$Index, [int]$Total, [string]$Title)
    Write-BCOut ''
    Write-BCOut -Text ('[{0}/{1}] {2}' -f $Index, $Total, $Title) -Color Cyan
}

function Write-BCFindingLine {
    param($Finding)
    $color = 'DarkYellow'
    switch ($Finding.Level) { 'OK' { $color = 'Green' } 'Info' { $color = 'Gray' } 'Warnung' { $color = 'Yellow' } 'Kritisch' { $color = 'Red' } }
    Write-BCOut -Text $Finding.Title -Prefix ('   [{0,-9}] ' -f $script:BCLevelLabel[$Finding.Level]) -Color $color
    if ($Finding.Detail) {
        $d = "$($Finding.Detail)"
        if ($d.Length -gt 600) { $d = $d.Substring(0, 597) + '...' }
        foreach ($dl in ($d -split "`r?`n")) { if ($dl) { Write-BCOut -Text $dl -Indent 16 -Color DarkGray } }
    }
    # Gleich sagen, was der Befund bedeutet bzw. was zu tun ist (bei OK nicht nötig)
    if ($Finding.Advice -and $Finding.Level -ne 'OK') {
        Write-BCOut -Text "$($Finding.Advice)" -Indent 16 -Prefix '-> ' -Color Cyan
    }
}

function Write-BCStep { param([string]$Text) Write-BCOut -Text $Text -Prefix '   ... ' -Color DarkGray }

# Einzeilige Fortschrittsanzeige (überschreibt sich selbst, landet nicht im Protokoll)
function Write-BCProgress {
    param([string]$Text)
    $w = (Get-BCWidth) - 1
    $t = '   ' + (ConvertTo-BCConsoleText $Text)
    if ($t.Length -gt $w) { $t = $t.Substring(0, $w) }
    try { [Console]::Write("`r" + $t.PadRight($w)); $script:BCProgressActive = $true } catch { }
}

function Complete-BCProgress {
    if (-not $script:BCProgressActive) { return }
    $script:BCProgressActive = $false
    try { [Console]::Write("`r" + (' ' * ((Get-BCWidth) - 1)) + "`r") } catch { }
}

# ESC gedrückt? (blockiert nicht)
function Test-BCEscape {
    try {
        while ([Console]::KeyAvailable) {
            $k = [Console]::ReadKey($true)
            if ($k.Key -eq [ConsoleKey]::Escape) { return $true }
        }
    } catch { }
    return $false
}

# ============================================================== Eingaben
function Clear-BCKeyBuffer { try { $Host.UI.RawUI.FlushInputBuffer() } catch { } }

# Liest eine einzelne erlaubte Taste. $Allowed: Kleinbuchstaben/Ziffern sowie 'enter' und 'esc'.
function Read-BCKey {
    param([string]$Prompt, [string[]]$Allowed)
    if ($Prompt) { Write-BCOut -Text $Prompt -Color White -NoNewline }
    Clear-BCKeyBuffer
    $raw = $null
    try { $raw = $Host.UI.RawUI; [void]$raw.KeyAvailable } catch { $raw = $null }
    if ($raw) {
        try {
            while ($true) {
                $k = $raw.ReadKey('NoEcho,IncludeKeyDown')
                if ($k.VirtualKeyCode -eq 13 -and $Allowed -contains 'enter') { Write-Host ''; return 'enter' }
                if ($k.VirtualKeyCode -eq 27 -and $Allowed -contains 'esc') { Write-Host ''; return 'esc' }
                $c = "$($k.Character)".ToLowerInvariant()
                if ($c -and $c -ne [string][char]0 -and $Allowed -contains $c) { Write-Host $c; return $c }
            }
        } catch { }
    }
    while ($true) {
        # Notlösung, falls keine echte Konsole vorhanden ist
        $a = "$(Read-Host)".Trim().ToLowerInvariant()
        if ($a -eq '' -and $Allowed -contains 'enter') { return 'enter' }
        if ($a.Length -ge 1 -and $Allowed -contains $a.Substring(0, 1)) { return $a.Substring(0, 1) }
    }
}

function Read-BCLine {
    param([string]$Prompt)
    Write-BCOut -Text $Prompt -Color White -NoNewline
    Clear-BCKeyBuffer
    return "$(Read-Host)"
}

function Read-BCYesNo {
    param([string]$Question)
    $k = Read-BCKey -Prompt ("   $Question [J/N] ") -Allowed @('j', 'n', 'y')
    return ($k -eq 'j' -or $k -eq 'y')
}

function Wait-BCEnter { param([string]$Text = 'Weiter mit Enter') [void](Read-BCKey -Prompt ("   $Text ") -Allowed @('enter')) }

# Hinweis anzeigen; $true = weiter, $false = überspringen
function Show-BCInfo {
    param([string]$Title, [string]$Message, [string]$OkText = 'Weiter', [string]$CancelText = 'Überspringen')
    Write-BCOut ''
    if ($Title) { Write-BCOut -Text $Title -Indent 3 -Color Cyan }
    Write-BCOut -Text $Message -Indent 3 -Color White
    $k = Read-BCKey -Prompt ("   [Enter] $OkText   [S] $CancelText  ") -Allowed @('enter', 's', 'esc')
    return ($k -eq 'enter')
}

# Eine Antwort aus mehreren (Ziffer drücken)
function Show-BCChoice {
    param([string]$Title, [string]$Question, [string[]]$Options, [switch]$Comment)
    Write-BCOut ''
    Write-BCOut -Text $Question -Indent 3 -Color White
    $keys = @()
    for ($i = 0; $i -lt $Options.Count; $i++) {
        $key = [string]($i + 1)
        $keys += $key
        Write-BCOut -Text $Options[$i] -Prefix ("   [$key] ")
    }
    $k = Read-BCKey -Prompt '   Deine Antwort (Ziffer): ' -Allowed $keys
    $idx = [int]$k - 1
    $c = ''
    if ($Comment) { $c = (Read-BCLine '   Anmerkung (optional, Enter = keine): ').Trim() }
    return (New-BCObject @('Cancelled', $false, 'Choice', $idx, 'ChoiceText', $Options[$idx], 'Comment', $c))
}

# Mehrere Antworten (Nummern eintippen)
function Show-BCMulti {
    param([string]$Title, [string]$Question, [string[]]$Options, [switch]$Comment)
    Write-BCOut ''
    Write-BCOut -Text $Question -Indent 3 -Color White
    for ($i = 0; $i -lt $Options.Count; $i++) { Write-BCOut -Text $Options[$i] -Prefix ("   [$($i + 1)] ") }
    $line = Read-BCLine '   Nummern mit Leerzeichen getrennt (z. B. 2 5), Enter = nichts davon: '
    $checked = New-Object bool[] $Options.Count
    $texts = @()
    foreach ($t in ($line -split '[,; ]+')) {
        if ($t -match '^\d+$') {
            $i = [int]$t - 1
            if ($i -ge 0 -and $i -lt $Options.Count -and -not $checked[$i]) { $checked[$i] = $true; $texts += $Options[$i] }
        }
    }
    $c = ''
    if ($Comment) { $c = (Read-BCLine '   Anmerkung (optional, Enter = keine): ').Trim() }
    return (New-BCObject @('Cancelled', $false, 'Checked', $checked, 'CheckedTexts', $texts, 'Comment', $c))
}

# ============================================================== Konsole vorbereiten
function Initialize-BCConsole {
    param([string]$Title)
    try { $Host.UI.RawUI.WindowTitle = $Title } catch { }
    if ($env:WT_SESSION) { return }   # Windows Terminal: Größe bestimmt das Terminal selbst
    try {
        $raw = $Host.UI.RawUI
        $max = $raw.MaxPhysicalWindowSize
        $buf = $raw.BufferSize
        $win = $raw.WindowSize
        $wantW = [math]::Min([math]::Max($win.Width, 100), $max.Width)
        $wantH = [math]::Min([math]::Max($win.Height, 45), $max.Height)
        $changed = $false
        if ($buf.Width -lt $wantW) { $buf.Width = $wantW; $changed = $true }
        if ($buf.Height -lt 3000) { $buf.Height = 3000; $changed = $true }
        if ($changed) { $raw.BufferSize = $buf }
        $win.Width = $wantW; $win.Height = $wantH
        $raw.WindowSize = $win
    } catch { }
}

# ============================================================== Auswahlmenü (statt Kommandozeilen-Schalter)
function Get-BCProfileStats {
    param([object[]]$Checks, [string]$ProfileId)
    $n = 0; $sec = 0.0; $inter = 0
    foreach ($c in $Checks) {
        $sel = $c.Info.Selected
        if ($ProfileId) { $sel = Test-BCInProfile $c.Info $ProfileId }
        if ($sel) { $n++; $sec += (Get-BCCheckSeconds $c.Info); if ($c.Info.Interactive) { $inter++ } }
    }
    return (New-BCObject @('Count', $n, 'Seconds', $sec, 'Interactive', $inter))
}

function Set-BCProfile {
    param([object[]]$Checks, [string]$ProfileId)
    foreach ($c in $Checks) {
        $c.Info.Selected = Test-BCInProfile $c.Info $ProfileId
        foreach ($o in @($c.Info.Options)) { if ($o) { $o.Value = $o.Default } }
    }
}

function Format-BCStats {
    param($Stats)
    $t = '{0} Tests, ca. {1}' -f $Stats.Count, (Format-BCDuration $Stats.Seconds)
    if ($Stats.Interactive -gt 0) { $t += " + Zeit für deine Eingaben ($($Stats.Interactive) Tests mit Mithilfe)" } else { $t += ', ohne Rückfragen' }
    return $t
}

function Get-BCOptionText {
    param($Info)
    $parts = @()
    foreach ($o in @($Info.Options)) { if ($o) { $parts += ('{0} {1} {2}' -f $o.Label, (Format-BCNum $o.Value 0), $o.Unit) } }
    if ($parts.Count -eq 0) { return '' }
    return ' (' + ($parts -join ', ') + ')'
}

# Zeigt die ausgewählten Tests kompakt nach Bereichen
function Write-BCSelectionSummary {
    param([object[]]$Checks)
    $cats = New-BCOrdered @()
    foreach ($c in @($Checks | Sort-Object { $_.Info.CategoryOrder }, { $_.Info.Order })) {
        if (-not $c.Info.Selected) { continue }
        $k = $c.Info.Category
        if (-not $cats.Contains($k)) { $cats[$k] = @() }
        $cats[$k] = @($cats[$k]) + @($c.Info.Title + (Get-BCOptionText $c.Info))
    }
    foreach ($k in @($cats.Keys)) { Write-BCOut -Text (@($cats[$k]) -join ' · ') -Prefix ('  ' + $k + ': ') -Color Gray }
}

# Einzelne Tests an-/abwählen und Dauer ändern
function Edit-BCSelection {
    param([object[]]$Checks, [object[]]$Profiles)
    $list = @($Checks | Sort-Object { $_.Info.CategoryOrder }, { $_.Info.Order })
    $profileKeys = @{ 's' = 'quick'; 'g' = 'thorough'; 'l' = 'linux'; 'a' = 'auto' }
    $msg = ''
    while ($true) {
        Clear-Host
        Write-BCHeader 'Tests einzeln auswählen'
        $cat = ''
        $width = (Get-BCWidth) - 1
        for ($i = 0; $i -lt $list.Count; $i++) {
            $info = $list[$i].Info
            if ($info.Category -ne $cat) { $cat = $info.Category; Write-BCOut -Text $cat -Indent 1 -Color Cyan }
            $mark = '[ ]'; $color = 'DarkGray'
            if ($info.Selected) { $mark = '[x]'; $color = 'White' }
            $star = ''; if ($info.Interactive) { $star = ' *' }
            $line = ('  {0} {1,2}  {2}{3}{4}' -f $mark, ($i + 1), $info.Title, (Get-BCOptionText $info), $star)
            $line = ConvertTo-BCConsoleText $line
            if ($line.Length -gt $width) { $line = $line.Substring(0, $width - 3) + '...' }
            Write-Host $line -ForegroundColor $color
        }
        $st = Get-BCProfileStats -Checks $Checks -ProfileId ''
        Write-BCOut ''
        Write-BCOut -Text ('Ausgewählt: ' + (Format-BCStats $st) + '.  * = mit Mithilfe') -Indent 2 -Color Green
        if ($msg) { Write-BCOut -Text $msg -Indent 2 -Color Yellow; $msg = '' }
        Write-BCOut -Text 'Nummern an-/abwählen (z. B. "4 7 12" oder "3-9")   ?4 = Beschreibung   D4 = Dauer/Umfang ändern' -Indent 2 -Color DarkGray
        Write-BCOut -Text 'S/G/L/A = Voreinstellung Schnell/Gründlich/Linux/Automatisch   Enter = fertig' -Indent 2 -Color DarkGray
        $in = (Read-BCLine '  > ').Trim().ToLowerInvariant()
        if ($in -eq '') { return }
        if ($profileKeys.ContainsKey($in)) { Set-BCProfile -Checks $Checks -ProfileId $profileKeys[$in]; continue }
        if ($in -match '^\?\s*(\d+)$') {
            $n = [int]$Matches[1] - 1
            if ($n -ge 0 -and $n -lt $list.Count) {
                $info = $list[$n].Info
                Write-BCOut ''
                Write-BCOut -Text $info.Title -Indent 2 -Color Cyan
                Write-BCOut -Text $info.Description -Indent 2
                $extra = 'Dauer ca. ' + (Format-BCDuration (Get-BCCheckSeconds $info))
                if ($info.Interactive) { $extra += ' · braucht deine Mithilfe' }
                if ($info.NeedsAcPower) { $extra += ' · Netzteil nötig' }
                Write-BCOut -Text $extra -Indent 2 -Color DarkGray
                Wait-BCEnter
            }
            continue
        }
        if ($in -match '^d\s*(\d+)$') {
            $n = [int]$Matches[1] - 1
            if ($n -lt 0 -or $n -ge $list.Count) { continue }
            $info = $list[$n].Info
            if (@($info.Options).Count -eq 0) { $msg = "Bei '$($info.Title)' gibt es nichts einzustellen."; continue }
            foreach ($o in @($info.Options)) {
                $v = Read-BCLine ('  {0} – {1} in {2} ({3} bis {4}, jetzt {5}): ' -f $info.Title, $o.Label, $o.Unit, (Format-BCNum $o.Min 0), (Format-BCNum $o.Max 0), (Format-BCNum $o.Value 0))
                $num = 0.0
                if ([double]::TryParse($v.Trim().Replace(',', '.'), [Globalization.NumberStyles]::Float, [Globalization.CultureInfo]::InvariantCulture, [ref]$num)) {
                    $o.Value = [math]::Max($o.Min, [math]::Min($o.Max, [math]::Round($num)))
                }
            }
            $info.Selected = $true
            continue
        }
        $tokens = @($in -split '[,; ]+' | Where-Object { $_ })
        $bad = @()
        foreach ($t in $tokens) {
            if ($t -match '^(\d+)-(\d+)$') {
                $a = [int]$Matches[1]; $b = [int]$Matches[2]
                if ($a -gt $b) { $x = $a; $a = $b; $b = $x }
                for ($n = $a; $n -le $b; $n++) { if ($n -ge 1 -and $n -le $list.Count) { $list[$n - 1].Info.Selected = -not $list[$n - 1].Info.Selected } }
            } elseif ($t -match '^\d+$') {
                $n = [int]$t
                if ($n -ge 1 -and $n -le $list.Count) { $list[$n - 1].Info.Selected = -not $list[$n - 1].Info.Selected } else { $bad += $t }
            } else { $bad += $t }
        }
        if ($bad.Count -gt 0) { $msg = 'Nicht verstanden: ' + ($bad -join ' ') }
    }
}

# Hauptmenü. Gibt die Bezeichnung der Auswahl zurück oder $null (Beenden).
function Show-BCSelection {
    param([object[]]$Checks, [object[]]$Profiles, $Settings)
    while ($true) {
        Clear-Host
        Write-BCHeader 'Was soll geprüft werden?'
        $keys = @('a', 'q')
        $n = 0
        foreach ($p in $Profiles) {
            $n++
            $keys += [string]$n
            $st = Get-BCProfileStats -Checks $Checks -ProfileId $p.Id
            Write-BCOut -Text $p.Label -Prefix ("  [$n] ") -Color White
            Write-BCOut -Text ($p.Description + ' ' + (Format-BCStats $st) + '.') -Indent 6 -Color DarkGray
        }
        $savedKey = $null
        if ($Settings -and @($Settings.Selected).Count -gt 0) {
            $n++; $savedKey = [string]$n; $keys += $savedKey
            Write-BCOut -Text ('Letzte eigene Auswahl (' + @($Settings.Selected).Count + ' Tests)') -Prefix ("  [$n] ") -Color White
        }
        Write-BCOut ''
        Write-BCOut -Text 'Auswahl anpassen: einzelne Tests an-/abwählen, Dauer ändern' -Prefix '  [A] ' -Color White
        Write-BCOut -Text 'Beenden' -Prefix '  [Q] ' -Color White
        Write-BCOut ''
        $k = Read-BCKey -Prompt '  Deine Wahl: ' -Allowed $keys
        if ($k -eq 'q') { return $null }
        $label = 'Eigene Auswahl'
        if ($k -eq 'a') {
            if (@($Checks | Where-Object { $_.Info.Selected }).Count -eq 0) { Set-BCProfile -Checks $Checks -ProfileId 'quick' }
            Edit-BCSelection -Checks $Checks -Profiles $Profiles
        } elseif ($savedKey -and $k -eq $savedKey) {
            Set-BCSettingsToChecks -Settings $Settings -Checks $Checks
        } else {
            $p = $Profiles[[int]$k - 1]
            Set-BCProfile -Checks $Checks -ProfileId $p.Id
            $label = $p.Label
        }
        # Bestätigung
        while ($true) {
            Clear-Host
            Write-BCHeader ("Auswahl: $label")
            $st = Get-BCProfileStats -Checks $Checks -ProfileId ''
            Write-BCOut -Text (Format-BCStats $st) -Indent 2 -Color Green
            Write-BCOut ''
            Write-BCSelectionSummary -Checks $Checks
            Write-BCOut ''
            Write-BCOut -Text 'Netzteil bitte angeschlossen lassen. Lange Tests lassen sich mit Esc abbrechen. Was BuyCheck NICHT tut: nichts installieren, keine Einstellungen ändern, nichts auf die interne SSD schreiben.' -Indent 2 -Color DarkGray
            Write-BCOut ''
            $c = Read-BCKey -Prompt '  [Enter] Starten   [A] Anpassen   [Z] Zurück  ' -Allowed @('enter', 'a', 'z', 'esc')
            if ($c -eq 'enter') {
                if ($st.Count -eq 0) { continue }
                return $label
            }
            if ($c -eq 'a') { Edit-BCSelection -Checks $Checks -Profiles $Profiles; $label = 'Eigene Auswahl'; continue }
            break
        }
    }
}
