# BuyCheck – Sichtprüfung: Dinge, die kein Programm prüfen kann (Checkliste zum Abhaken)

Register-BuyCheck -Id 'manual.checklist' -Category 'Abschluss' -Order 10 -RunOrder 900 -Seconds 300 -Interactive `
    -Title 'Sichtprüfung (Checkliste)' `
    -Description 'Abhakliste für die körperliche Prüfung: aufgeblähter Akku, Flüssigkeitsschäden, Gehäuse, Scharniere, Display, Seriennummer auf dem Typenschild, Anschlüsse, Netzteil, Geruch, Herkunft. Tipp: Das meiste davon kannst du erledigen, während die langen Tests laufen.' `
    -Profiles @('quick', 'thorough', 'linux') `
    -Run {
    $sys = Get-BCSystem
    # Punkt, Hinweis, Schwere bei Problem, Titel des Befunds bei Problem
    $def = @(
        @('Akku nicht aufgebläht', 'Touchpad liegt flach und klickt normal, kein Spalt im Gehäuse, Gerät wackelt nicht auf dem Tisch. Bei Verdacht: NICHT kaufen (Brandgefahr).', 'Kritisch', 'Verdacht auf aufgeblähten Akku (Brandgefahr)'),
        @('Keine Flüssigkeitsspuren', 'Keine Korrosion/weißen Ablagerungen an Anschlüssen und Lüftungsschlitzen, keine klebrigen Tasten, kein muffiger Geruch.', 'Kritisch', 'Spuren eines Flüssigkeitsschadens'),
        @('Kein Brand- oder Schmorgeruch', 'Besonders am Lüftungsauslass nach dem Belastungstest.', 'Kritisch', 'Brand- oder Schmorgeruch'),
        @('Gehäuse ohne Risse und Brüche', 'Ecken, Deckel, Unterseite und rund um die Scharniere (Sturzschäden).', 'Warnung', 'Risse oder Brüche im Gehäuse'),
        @('Scharniere in Ordnung', 'Deckel hält jede Position, kein Knacken, kein Spiel, Deckel nicht verzogen.', 'Warnung', 'Scharniere beschädigt oder ausgeleiert'),
        @('Display ohne Kratzer und Druckstellen', 'Auch Abdrücke der Tastatur auf dem Bildschirm prüfen (Gerät wurde zusammengedrückt).', 'Warnung', 'Kratzer oder Druckstellen am Display'),
        @('Seriennummer auf dem Typenschild = BIOS-Seriennummer', "BIOS meldet: $($sys.Serial)", 'Warnung', 'Seriennummer auf dem Typenschild passt nicht zum BIOS'),
        @('Anschlüsse fest', 'Stecker (Netzteil, USB, HDMI) sitzen fest, Buchsen wackeln nicht.', 'Warnung', 'Lockere bzw. wackelige Anschlüsse'),
        @('Netzteil und Kabel unbeschädigt', 'Keine Knicke, abisolierten Stellen, Brandspuren. Wattzahl passt zum Gerät.', 'Warnung', 'Netzteil oder Kabel beschädigt'),
        @('Herkunft plausibel', 'Rechnung oder nachvollziehbare Erklärung; Verkäufer kennt das Gerät. Kein Firmen-Inventaraufkleber ohne Erklärung.', 'Warnung', 'Herkunft des Geräts unklar'),
        @('Alle Schrauben vorhanden und unbeschädigt', 'Fehlende/vermurkste Schrauben = Gerät war geöffnet (Reparatur? Teiletausch?) – nachfragen.', 'Info', 'Schrauben fehlen oder sind beschädigt (Gerät war geöffnet)'),
        @('Tastatur: keine fehlenden oder wackeligen Tasten', 'Stark glänzende Tasten zeigen intensive Nutzung.', 'Info', 'Tastenkappen fehlen oder wackeln'),
        @('BIOS lässt sich ohne Passwort öffnen (optional)', 'Beim Neustart F2/Entf/F1/F10 – nur ansehen, NICHTS verändern.', 'Kritisch', 'BIOS fragt nach einem Passwort'),
        @('Kopfhöreranschluss funktioniert (falls vorhanden)', 'Mit eigenen Kopfhörern kurz testen.', 'Info', 'Kopfhöreranschluss funktioniert nicht'),
        @('Tastaturbeleuchtung / Fingerabdruckleser funktionieren (falls vorhanden)', '', 'Info', 'Tastaturbeleuchtung oder Fingerabdruckleser ohne Funktion'),
        @('Gummifüße vorhanden', 'Fehlende Füße verschlechtern die Belüftung von unten.', 'Info', 'Gummifüße fehlen')
    )
    $items = New-Object 'System.Collections.Generic.List[BuyCheck.ChecklistItem]'
    foreach ($d in $def) { $items.Add((New-Object BuyCheck.ChecklistItem -ArgumentList $d[0], $d[1])) }
    $dlg = New-Object BuyCheck.ChecklistDialog -ArgumentList 'Sichtprüfung', 'Bitte jeden Punkt prüfen und auf „OK“ oder „Problem“ setzen. Bei Problemen kurz notieren, was auffällt. Nicht geprüfte Punkte bleiben auf „nicht geprüft“.', ([BuyCheck.ChecklistItem[]]$items.ToArray())
    try { [void]$dlg.ShowDialog() } finally { $dlg.Dispose() }
    $open = @(); $okCount = 0
    for ($i = 0; $i -lt $items.Count; $i++) {
        $it = $items[$i]; $lvl = $def[$i][2]
        switch ($it.State) {
            0 { $okCount++ }
            1 { Add-BCFinding -Level $lvl -Title "Sichtprüfung: $($def[$i][3])" -Detail $(if ($it.Comment) { $it.Comment } else { "Beim Punkt „$($it.Text)“ wurde ein Problem festgestellt." }) }
            default { $open += $it.Text }
        }
    }
    if ($okCount -gt 0) { Add-BCFinding -Level OK -Title "$okCount Punkte der Sichtprüfung in Ordnung" }
    if ($open.Count -gt 0) { Add-BCFinding -Level Info -Title "$($open.Count) Punkte der Sichtprüfung nicht geprüft" -Detail ($open -join ' · ') }
    Add-BCTable -Title 'Sichtprüfung' -Rows @($items | ForEach-Object { [pscustomobject]@{ 'Punkt' = $_.Text; 'Ergebnis' = switch ($_.State) { 0 { 'OK' } 1 { 'Problem' } default { 'nicht geprüft' } }; 'Anmerkung' = $_.Comment } })
}
