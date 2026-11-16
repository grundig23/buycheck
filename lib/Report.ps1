# BuyCheck – HTML-Bericht (eine eigenständige Datei, funktioniert offline, druckbar)

function Get-BCLevelCounts {
    $c = @{ Kritisch = 0; Warnung = 0; Info = 0; OK = 0; Fehler = 0 }
    foreach ($r in $script:BCResults) { foreach ($f in $r.Findings) { $c[$f.Level]++ } }
    return $c
}

function Get-BCResultLevel {
    param($Result)
    $max = -1; $lvl = 'OK'
    foreach ($f in $Result.Findings) {
        $o = $script:BCLevelOrder[$f.Level]
        if ($o -gt $max) { $max = $o; $lvl = $f.Level }
    }
    if ($Result.Findings.Count -eq 0) { return 'Info' }
    return $lvl
}

function ConvertTo-BCSvgChart {
    param([double[]]$Values, [string]$Unit, [double]$Reference = [double]::NaN, [string]$ReferenceLabel = '')
    $w = 760; $h = 170; $pl = 52; $pr = 12; $pt = 12; $pb = 22
    $vals = @($Values | Where-Object { -not [double]::IsNaN($_) -and -not [double]::IsInfinity($_) })
    if ($vals.Count -lt 2) { return '' }
    $min = ($vals | Measure-Object -Minimum).Minimum
    $max = ($vals | Measure-Object -Maximum).Maximum
    if (-not [double]::IsNaN($Reference)) { $min = [math]::Min($min, $Reference); $max = [math]::Max($max, $Reference) }
    if ($min -gt 0 -and $min -lt $max * 0.5) { $min = 0 }
    if ($max -eq $min) { $max = $min + 1 }
    $lo = $min; $hi = $max
    $span = $max - $min; $min -= $span * 0.05; $max += $span * 0.05
    $inv = [Globalization.CultureInfo]::InvariantCulture
    $fx = { param($i) ($pl + ($w - $pl - $pr) * $i / ($vals.Count - 1)).ToString('0.0', $inv) }
    $fy = { param($v) ($pt + ($h - $pt - $pb) * (1 - ($v - $min) / ($max - $min))).ToString('0.0', $inv) }
    $pts = for ($i = 0; $i -lt $vals.Count; $i++) { "$(& $fx $i),$(& $fy $vals[$i])" }
    $sb = New-Object System.Text.StringBuilder
    [void]$sb.Append("<svg class='chart' viewBox='0 0 $w $h' role='img' aria-label='Diagramm'>")
    [void]$sb.Append("<rect x='$pl' y='$pt' width='$($w - $pl - $pr)' height='$($h - $pt - $pb)' class='plot'/>")
    # Achsenbeschriftung an echtem Minimum, Mitte und Maximum (Klammern nötig: das Komma bindet stärker als + und /)
    foreach ($t in @($lo, (($lo + $hi) / 2), $hi)) {
        $y = & $fy $t
        [void]$sb.Append("<line x1='$pl' x2='$($w - $pr)' y1='$y' y2='$y' class='grid'/><text x='$($pl - 6)' y='$y' class='ylab'>$(Get-BCHtml (Format-BCNum $t 0))</text>")
    }
    if (-not [double]::IsNaN($Reference)) {
        $y = & $fy $Reference
        [void]$sb.Append("<line x1='$pl' x2='$($w - $pr)' y1='$y' y2='$y' class='ref'/><text x='$($w - $pr - 4)' y='$y' class='reflab'>$(Get-BCHtml $ReferenceLabel)</text>")
    }
    [void]$sb.Append("<polyline points='$($pts -join ' ')' class='line'/>")
    [void]$sb.Append("<text x='$pl' y='$($h - 4)' class='xlab'>Start</text><text x='$($w - $pr)' y='$($h - 4)' class='xlab end'>Ende</text>")
    [void]$sb.Append("<text x='4' y='$($pt + 8)' class='unit'>$(Get-BCHtml $Unit)</text></svg>")
    return $sb.ToString()
}

function ConvertTo-BCSectionHtml {
    param($Section)
    $sb = New-Object System.Text.StringBuilder
    if ($Section.Title) { [void]$sb.Append("<h4>$(Get-BCHtml $Section.Title)</h4>") }
    switch ($Section.Type) {
        'facts' {
            [void]$sb.Append("<table class='kv'>")
            foreach ($k in $Section.Data.Keys) { [void]$sb.Append("<tr><th>$(Get-BCHtml $k)</th><td>$(Get-BCHtml $Section.Data[$k])</td></tr>") }
            [void]$sb.Append('</table>')
        }
        'table' {
            [void]$sb.Append("<div class='scroll'><table class='grid'><thead><tr>")
            foreach ($c in $Section.Columns) { [void]$sb.Append("<th>$(Get-BCHtml $c)</th>") }
            [void]$sb.Append('</tr></thead><tbody>')
            foreach ($row in $Section.Rows) {
                [void]$sb.Append('<tr>')
                foreach ($c in $Section.Columns) { [void]$sb.Append("<td>$(Get-BCHtml "$($row.$c)")</td>") }
                [void]$sb.Append('</tr>')
            }
            [void]$sb.Append('</tbody></table></div>')
        }
        'text' { [void]$sb.Append("<pre class='text'>$(Get-BCHtml $Section.Text)</pre>") }
        'chart' { [void]$sb.Append((ConvertTo-BCSvgChart -Values $Section.Values -Unit $Section.Unit -Reference $Section.Reference -ReferenceLabel $Section.ReferenceLabel)) }
        'link' { [void]$sb.Append("<p class='link'>🔗 <a href='$(Get-BCHtml $Section.Url)' target='_blank' rel='noopener'>$(Get-BCHtml $Section.Url)</a></p>") }
    }
    return $sb.ToString()
}

function New-BCReport {
    param([string]$Directory, [string]$ProfileLabel, [datetime]$Started, [object[]]$NotRun)
    $counts = Get-BCLevelCounts
    $sys = Get-BCSystem
    $device = if ($sys) { "$($sys.Manufacturer) $($sys.DisplayModel)".Trim() } else { 'Unbekanntes Gerät' }
    $serial = if ($sys) { $sys.Serial } else { '' }
    $ended = Get-Date
    $dur = New-TimeSpan -Start $Started -End $ended
    if ($counts.Kritisch -gt 0) { $vClass = 'red'; $vTitle = 'Schwerwiegende Befunde'; $vText = 'Mindestens ein Punkt spricht deutlich gegen den Kauf oder muss vorher geklärt bzw. im Preis berücksichtigt werden. Details unten.' }
    elseif ($counts.Warnung -gt 0) { $vClass = 'yellow'; $vTitle = 'Auffälligkeiten gefunden'; $vText = 'Keine K.-o.-Kriterien, aber Punkte, die du klären und beim Preis berücksichtigen solltest.' }
    else { $vClass = 'green'; $vTitle = 'Keine Auffälligkeiten'; $vText = 'In den durchgeführten Tests wurde nichts Bedenkliches gefunden. Die Sichtprüfung und die Herkunft bleiben trotzdem wichtig.' }

    $sb = New-Object System.Text.StringBuilder
    [void]$sb.Append(@"
<!doctype html>
<html lang="de"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width, initial-scale=1">
<title>BuyCheck-Bericht – $(Get-BCHtml $device)</title>
<style>
:root{--fg:#1f2328;--muted:#59636e;--line:#d1d9e0;--bg:#ffffff;--soft:#f6f8fa;--red:#cf222e;--redbg:#ffebe9;--yel:#9a6700;--yelbg:#fff8c5;--grn:#1a7f37;--grnbg:#dafbe1;--blu:#0969da;--blubg:#ddf4ff;--gry:#6e7781;--grybg:#eaeef2}
*{box-sizing:border-box}body{margin:0;background:var(--soft);color:var(--fg);font:15px/1.5 "Segoe UI",system-ui,-apple-system,Roboto,Arial,sans-serif}
.wrap{max-width:1000px;margin:0 auto;padding:24px 16px 48px}
header h1{margin:0;font-size:26px}header .sub{color:var(--muted)}
.card,.check{background:var(--bg);border:1px solid var(--line);border-radius:10px;padding:16px 20px;margin:16px 0}
.verdict{border-radius:12px;padding:18px 22px;margin:18px 0;border:2px solid}
.verdict h2{margin:0 0 6px;font-size:22px}.verdict.red{background:var(--redbg);border-color:var(--red)}.verdict.yellow{background:var(--yelbg);border-color:var(--yel)}.verdict.green{background:var(--grnbg);border-color:var(--grn)}
.counts span{display:inline-block;margin:6px 8px 0 0}
.badge{display:inline-block;min-width:78px;text-align:center;border-radius:999px;padding:1px 10px;font-size:12px;font-weight:600;letter-spacing:.02em;vertical-align:1px}
.lv-Kritisch{background:var(--red);color:#fff}.lv-Warnung{background:#bf8700;color:#fff}.lv-Info{background:var(--blubg);color:var(--blu)}.lv-OK{background:var(--grnbg);color:var(--grn)}.lv-Fehler{background:var(--grybg);color:var(--gry)}
h2.cat{margin:34px 0 4px;font-size:19px;border-bottom:2px solid var(--line);padding-bottom:4px}
details.check>summary{cursor:pointer;font-weight:600;font-size:16px;list-style:none}
details.check>summary::-webkit-details-marker{display:none}
details.check>summary .meta{float:right;font-weight:400;color:var(--muted);font-size:13px}
ul.findings{list-style:none;padding:0;margin:12px 0 4px}ul.findings li{padding:6px 0;border-top:1px solid var(--soft)}
ul.findings .t{font-weight:600}ul.findings .d{color:var(--muted);margin-left:92px;font-size:14px}ul.findings .a{margin-left:92px;font-size:14px}ul.findings .a::before{content:"→ "}
h4{margin:16px 0 6px;font-size:14px;color:var(--muted);text-transform:uppercase;letter-spacing:.03em}
table{border-collapse:collapse;width:100%;font-size:14px}table.kv th{text-align:left;width:38%;font-weight:600;color:var(--muted);vertical-align:top}
table.kv th,table.kv td{padding:4px 8px;border-bottom:1px solid var(--soft)}
table.grid th,table.grid td{padding:5px 8px;border:1px solid var(--line);text-align:left;vertical-align:top}table.grid th{background:var(--soft)}
.scroll{overflow-x:auto}pre.text{white-space:pre-wrap;background:var(--soft);padding:10px;border-radius:6px;font-size:13px}
svg.chart{width:100%;height:auto;max-width:760px;display:block}svg .plot{fill:#fbfcfd;stroke:var(--line)}svg .grid{stroke:#e6eaef}svg .line{fill:none;stroke:var(--blu);stroke-width:2}
svg .ref{stroke:var(--red);stroke-dasharray:5 4}svg text{font-size:11px;fill:var(--muted)}svg .ylab{text-anchor:end;dominant-baseline:middle}svg .reflab{text-anchor:end;fill:var(--red)}svg .end{text-anchor:end}
.top li{margin:6px 0}.contract{white-space:pre-wrap;background:var(--soft);border:1px dashed var(--line);padding:12px;border-radius:8px;font-size:14px}
.note{color:var(--muted);font-size:13px}a{color:var(--blu)}
@media print{body{background:#fff}.card,.check{break-inside:avoid;border-color:#bbb}details.check{display:block}details.check>summary{display:block}}
@media (max-width:640px){ul.findings .d,ul.findings .a{margin-left:0}.badge{min-width:0}}
</style></head><body><div class="wrap">
<header><h1>BuyCheck-Bericht</h1>
<div class="sub">$(Get-BCHtml $device) · Seriennummer $(Get-BCHtml $serial) · geprüft am $(Get-BCHtml ($Started.ToString('dd.MM.yyyy HH:mm'))) · Dauer $([int]$dur.TotalMinutes) Min. · Auswahl: $(Get-BCHtml $ProfileLabel) · BuyCheck $(Get-BCHtml $script:BCVersion)</div></header>
<section class="verdict $vClass"><h2>$vTitle</h2><div>$vText</div>
<div class="counts"><span class="badge lv-Kritisch">KRITISCH</span> $($counts.Kritisch) <span class="badge lv-Warnung">WARNUNG</span> $($counts.Warnung) <span class="badge lv-Info">HINWEIS</span> $($counts.Info) <span class="badge lv-OK">OK</span> $($counts.OK) <span class="badge lv-Fehler">NICHT PRÜFBAR</span> $($counts.Fehler)</div></section>
"@)
    # Steckbrief
    [void]$sb.Append("<section class='card'><h2>Steckbrief</h2><table class='kv'>")
    foreach ($k in $script:BCSummary.Keys) { [void]$sb.Append("<tr><th>$(Get-BCHtml $k)</th><td>$(Get-BCHtml $script:BCSummary[$k])</td></tr>") }
    [void]$sb.Append('</table></section>')

    # Wichtigste Befunde
    $top = @()
    foreach ($r in $script:BCResults) { foreach ($f in $r.Findings) { if (@('Kritisch', 'Warnung') -contains $f.Level) { $top += $f } } }
    $top = @($top | Sort-Object @{ Expression = { $script:BCLevelOrder[$_.Level] }; Descending = $true })
    [void]$sb.Append("<section class='card'><h2>Wichtigste Befunde</h2>")
    if ($top.Count -eq 0) { [void]$sb.Append('<p>Keine kritischen Befunde oder Warnungen.</p>') }
    else {
        [void]$sb.Append("<ul class='top'>")
        foreach ($f in $top) {
            [void]$sb.Append("<li><span class='badge lv-$($f.Level)'>$($script:BCLevelLabel[$f.Level])</span> <b>$(Get-BCHtml $f.Title)</b> <span class='note'>($(Get-BCHtml $f.CheckTitle))</span>")
            if ($f.Advice) { [void]$sb.Append("<br><span class='note'>→ $(Get-BCHtml $f.Advice)</span>") }
            [void]$sb.Append('</li>')
        }
        [void]$sb.Append('</ul>')
    }
    [void]$sb.Append('</section>')

    # Textbaustein Kaufvertrag
    $mangel = if ($top.Count -gt 0) { ($top | ForEach-Object { '- ' + $_.Title }) -join "`n" } else { '- keine festgestellt' }
    $contract = @"
Kaufgegenstand: $device, Seriennummer: $serial
Zustand laut Prüfung vom $($Started.ToString('dd.MM.yyyy')) (BuyCheck-Bericht):
$(($script:BCSummary.Keys | Where-Object { @('Gerät', 'Seriennummer (BIOS)') -notcontains $_ } | ForEach-Object { '- ' + $_ + ': ' + $script:BCSummary[$_] }) -join "`n")
Bei der Prüfung festgestellte Mängel/Auffälligkeiten:
$mangel

Der Verkäufer versichert, dass das Gerät sein Eigentum ist, nicht gestohlen wurde, keine ihm bekannten
weiteren Mängel hat (insbesondere keine Flüssigkeitsschäden), kein BIOS-/Supervisor-Passwort gesetzt ist
und das Gerät keiner Firmenverwaltung (z. B. Windows Autopilot/Intune) mehr unterliegt.
"@
    [void]$sb.Append("<section class='card'><h2>Textbaustein für den Kaufvertrag</h2><p class='note'>Zugesicherte Eigenschaften gelten auch bei Gewährleistungsausschluss. Anpassen, Personalien beider Seiten ergänzen, beide unterschreiben. Keine Rechtsberatung.</p><div class='contract'>$(Get-BCHtml $contract)</div></section>")

    # Einzelergebnisse nach Kategorien
    $groups = @($script:BCResults | Sort-Object CategoryOrder, Order | Group-Object Category)
    foreach ($g in $groups) {
        [void]$sb.Append("<h2 class='cat'>$(Get-BCHtml $g.Name)</h2>")
        foreach ($r in $g.Group) {
            $lvl = Get-BCResultLevel $r
            $open = if (@('Kritisch', 'Warnung', 'Fehler') -contains $lvl) { ' open' } else { '' }
            [void]$sb.Append("<details class='check'$open><summary><span class='badge lv-$lvl'>$($script:BCLevelLabel[$lvl])</span> $(Get-BCHtml $r.Title)<span class='meta'>$(Format-BCNum $r.Seconds 0) s</span></summary>")
            [void]$sb.Append("<ul class='findings'>")
            foreach ($f in $r.Findings) {
                [void]$sb.Append("<li><span class='badge lv-$($f.Level)'>$($script:BCLevelLabel[$f.Level])</span> <span class='t'>$(Get-BCHtml $f.Title)</span>")
                if ($f.Detail) { [void]$sb.Append("<div class='d'>$(Get-BCHtml $f.Detail)</div>") }
                if ($f.Advice) { [void]$sb.Append("<div class='a'>$(Get-BCHtml $f.Advice)</div>") }
                [void]$sb.Append('</li>')
            }
            [void]$sb.Append('</ul>')
            foreach ($s in $r.Sections) { [void]$sb.Append((ConvertTo-BCSectionHtml $s)) }
            [void]$sb.Append('</details>')
        }
    }
    if ($NotRun -and $NotRun.Count -gt 0) {
        [void]$sb.Append("<section class='card'><h2>Nicht ausgewählte Tests</h2><ul>")
        foreach ($n in $NotRun) { [void]$sb.Append("<li>$(Get-BCHtml $n.Info.Title) <span class='note'>($(Get-BCHtml $n.Info.Category))</span></li>") }
        [void]$sb.Append('</ul></section>')
    }
    [void]$sb.Append(@"
<section class="card note"><b>Hinweise:</b> Software kann nicht alles prüfen – ein plötzlicher Ausfall (z. B. SSD-Controller) ist nie ganz auszuschließen,
und ein gezielt präpariertes Windows kann Werte verfälschen. BuyCheck vergleicht deshalb mehrere unabhängige Quellen.
Hintergründe und Quellen: RECHERCHE.md auf https://github.com/grundig23/buycheck. BuyCheck verändert nichts am geprüften Gerät; die Tests sind lesend
(Datenträger nur lesend, keine Einstellungen geändert).</section>
</div></body></html>
"@)
    $path = Join-Path $Directory 'BuyCheck-Bericht.html'
    [IO.File]::WriteAllText($path, $sb.ToString(), (New-Object Text.UTF8Encoding($true)))

    # Textfassung (lässt sich mit jedem Editor öffnen, auch auf dem Handy)
    try {
        $t = New-Object System.Text.StringBuilder
        $nl = "`r`n"
        $line = { param($x) [void]$t.Append($x); [void]$t.Append($nl) }
        & $line 'BuyCheck-Bericht (Textfassung)'
        & $line '=============================='
        & $line ("Gerät:         $device")
        & $line ("Seriennummer:  $serial")
        & $line ("Geprüft am:    $($Started.ToString('dd.MM.yyyy HH:mm')) (Dauer $([int]$dur.TotalMinutes) Min.), Auswahl: $ProfileLabel, BuyCheck $($script:BCVersion)")
        & $line ("System:        $($sys.OsCaption) $($sys.OsDisplayVersion) (Build $($sys.OsBuild)), PowerShell $($sys.PowerShell)")
        & $line ''
        & $line ("GESAMTURTEIL: $vTitle")
        & $line ("  $vText")
        & $line ("  Kritisch: $($counts.Kritisch) · Warnungen: $($counts.Warnung) · Hinweise: $($counts.Info) · OK: $($counts.OK) · nicht prüfbar: $($counts.Fehler)")
        & $line ''
        & $line 'STECKBRIEF'
        foreach ($k in @($script:BCSummary.Keys)) { & $line ("  {0}: {1}" -f $k, $script:BCSummary[$k]) }
        & $line ''
        & $line 'WICHTIGSTE BEFUNDE'
        if ($top.Count -eq 0) { & $line '  Keine kritischen Befunde oder Warnungen.' }
        foreach ($f in $top) {
            & $line ("  [{0}] {1} ({2})" -f $script:BCLevelLabel[$f.Level], $f.Title, $f.CheckTitle)
            if ($f.Advice) { & $line ("      -> $($f.Advice)") }
        }
        & $line ''
        & $line 'TEXTBAUSTEIN FÜR DEN KAUFVERTRAG (anpassen, keine Rechtsberatung)'
        foreach ($l in ($contract -split "`r?`n")) { & $line ("  $l") }
        & $line ''
        & $line 'EINZELERGEBNISSE'
        foreach ($g in $groups) {
            & $line ''
            & $line ("--- $($g.Name) ---")
            foreach ($r in $g.Group) {
                & $line ''
                & $line ("* $($r.Title) ($(Format-BCNum $r.Seconds 0) s)")
                foreach ($f in $r.Findings) {
                    & $line ("  [{0,-9}] {1}" -f $script:BCLevelLabel[$f.Level], $f.Title)
                    if ($f.Detail) { & $line ("              $($f.Detail)") }
                    if ($f.Advice) { & $line ("              -> $($f.Advice)") }
                }
                foreach ($sec in $r.Sections) {
                    switch ($sec.Type) {
                        'facts' {
                            & $line ("  $($sec.Title):")
                            foreach ($k in @($sec.Data.Keys)) { & $line ("      {0}: {1}" -f $k, $sec.Data[$k]) }
                        }
                        'table' {
                            & $line ("  $($sec.Title):")
                            foreach ($row in $sec.Rows) { & $line ('      ' + (@($sec.Columns | ForEach-Object { "$($_): $($row.$_)" }) -join ' | ')) }
                        }
                        'text' {
                            & $line ("  $($sec.Title):")
                            foreach ($l in ("$($sec.Text)" -split "`r?`n")) { & $line ("      $l") }
                        }
                        'chart' {
                            $v = @($sec.Values)
                            if ($v.Count -gt 0) {
                                $mn = ($v | Measure-Object -Minimum).Minimum; $mx = ($v | Measure-Object -Maximum).Maximum
                                & $line ("  $($sec.Title): {0} Messwerte, von {1} bis {2} {3} (Diagramm im HTML-Bericht)" -f $v.Count, (Format-BCNum $mn 0), (Format-BCNum $mx 0), $sec.Unit)
                            }
                        }
                        'link' { & $line ("  Link: $($sec.Title) – $($sec.Url)") }
                    }
                }
            }
        }
        if ($NotRun -and $NotRun.Count -gt 0) {
            & $line ''
            & $line 'NICHT AUSGEWÄHLTE TESTS'
            foreach ($n in $NotRun) { & $line ("  - $($n.Info.Title) ($($n.Info.Category))") }
        }
        & $line ''
        & $line 'BuyCheck verändert nichts am geprüften Gerät; alle Tests sind lesend. Hintergründe: RECHERCHE.md auf https://github.com/grundig23/buycheck'
        [IO.File]::WriteAllText((Join-Path $Directory 'BuyCheck-Bericht.txt'), $t.ToString(), (New-Object Text.UTF8Encoding($true)))
    } catch { Write-BCDebug "Textbericht fehlgeschlagen: $($_.Exception.Message)" }

    # Maschinenlesbare Daten (nur wenn PowerShell JSON kann, also ab Version 3)
    if (Test-BCCommand 'ConvertTo-Json') {
        try {
            $results = @()
            foreach ($r in $script:BCResults) {
                $fl = @()
                foreach ($f in $r.Findings) { $fl += New-BCOrdered @('Level', $f.Level, 'Title', $f.Title, 'Detail', $f.Detail, 'Advice', $f.Advice) }
                $results += New-BCOrdered @('Id', $r.Id, 'Title', $r.Title, 'Category', $r.Category, 'Status', $r.Status, 'Seconds', $r.Seconds, 'Error', $r.Error, 'Findings', $fl)
            }
            $data = New-BCOrdered @('Version', $script:BCVersion, 'Device', $device, 'Serial', $serial, 'Started', $Started.ToString('s'),
                'Ended', $ended.ToString('s'), 'Profile', $ProfileLabel, 'Counts', $counts, 'Summary', $script:BCSummary, 'Results', $results)
            $json = $data | ConvertTo-Json -Depth 8
            [IO.File]::WriteAllText((Join-Path $Directory 'BuyCheck-Daten.json'), $json, (New-Object Text.UTF8Encoding($false)))
        } catch { Write-BCDebug "JSON-Export fehlgeschlagen: $($_.Exception.Message)" }
    }
    return $path
}
