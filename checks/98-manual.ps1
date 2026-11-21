# BuyCheck – Sichtprüfung: Dinge, die kein Programm prüfen kann (Checkliste zum Abhaken)

Register-BuyCheck -Id 'manual.checklist' -Category 'Abschluss' -Order 10 -RunOrder 900 -Seconds 300 -Interactive `
    -Title 'Sichtprüfung (Checkliste)' `
    -Description 'Abhakliste für die körperliche Prüfung: aufgeblähter Akku, Flüssigkeitsschäden, Gehäuse, Scharniere, Display, Seriennummer auf dem Typenschild, Anschlüsse, Netzteil, Geruch, Herkunft. Tipp: Das meiste davon kannst du erledigen, während die langen Tests laufen.' `
    -Profiles @('quick', 'thorough', 'linux') `
    -Run {
    $sys = Get-BCSystem
    # Punkt, Hinweis, Schwere bei Problem, Titel des Befunds bei Problem, was zu tun ist
    $def = @(
        @('Akku nicht aufgebläht', 'Touchpad liegt flach und klickt normal, kein Spalt im Gehäuse, Gerät wackelt nicht auf dem Tisch. Ein aufgeblähter Akku ist ein Brandrisiko.', 'Kritisch', 'Verdacht auf aufgeblähten Akku (Brandgefahr)', 'Ein aufgeblähter Akku kann sich entzünden und drückt Touchpad und Gehäuse auseinander.'),
        @('Keine Flüssigkeitsspuren', 'Keine Korrosion/weißen Ablagerungen an Anschlüssen und Lüftungsschlitzen, keine klebrigen Tasten, kein muffiger Geruch.', 'Kritisch', 'Spuren eines Flüssigkeitsschadens', 'Korrosion breitet sich auf dem Mainboard weiter aus; Ausfälle kommen oft erst Wochen später.'),
        @('Kein Brand- oder Schmorgeruch', 'Besonders am Lüftungsauslass nach dem Belastungstest.', 'Kritisch', 'Brand- oder Schmorgeruch', 'Hinweis auf ein überhitztes oder verschmortes Bauteil (Netzteil, Akku, Mainboard).'),
        @('Gehäuse ohne Risse und Brüche', 'Ecken, Deckel, Unterseite und rund um die Scharniere (Sturzschäden).', 'Warnung', 'Risse oder Brüche im Gehäuse', 'Meist ein Sturzschaden; dabei können auch innen Teile beschädigt worden sein.'),
        @('Scharniere in Ordnung', 'Deckel hält jede Position, kein Knacken, kein Spiel, Deckel nicht verzogen.', 'Warnung', 'Scharniere beschädigt oder ausgeleiert', 'Defekte Scharniere brechen oft weiter aus dem Gehäuse und scheuern das Displaykabel durch.'),
        @('Display ohne Kratzer und Druckstellen', 'Auch Abdrücke der Tastatur auf dem Bildschirm prüfen (Gerät wurde zusammengedrückt).', 'Warnung', 'Kratzer oder Druckstellen am Display', 'Rein optisch, solange das Bild darunter in Ordnung ist.'),
        @('Seriennummer auf dem Typenschild = BIOS-Seriennummer', "BIOS meldet: $($sys.Serial)", 'Warnung', 'Seriennummer auf dem Typenschild passt nicht zum BIOS', 'Das Mainboard wurde getauscht oder das Gehäuse stammt von einem anderen Gerät.'),
        @('Anschlüsse fest', 'Stecker (Netzteil, USB, HDMI) sitzen fest, Buchsen wackeln nicht.', 'Warnung', 'Lockere bzw. wackelige Anschlüsse', 'Wackelige Buchsen werden meist schlimmer und sind auf dem Mainboard verlötet.'),
        @('Netzteil und Kabel unbeschädigt', 'Keine Knicke, abisolierten Stellen, Brandspuren. Wattzahl passt zum Gerät.', 'Warnung', 'Netzteil oder Kabel beschädigt', 'Beschädigte Netzteile und Kabel können gefährlich sein.'),
        @('Herkunft plausibel', 'Rechnung oder nachvollziehbare Erklärung; Verkäufer kennt das Gerät. Kein Firmen-Inventaraufkleber ohne Erklärung.', 'Warnung', 'Herkunft des Geräts unklar', 'Gestohlene Geräte können von der Polizei eingezogen werden, ohne Ersatz für den Käufer.'),
        @('Alle Schrauben vorhanden und unbeschädigt', 'Fehlende/vermurkste Schrauben = Gerät war geöffnet (Reparatur? Teiletausch?).', 'Info', 'Schrauben fehlen oder sind beschädigt (Gerät war geöffnet)', 'Das Gerät war geöffnet (Reparatur, Aufrüstung oder Teiletausch).'),
        @('Tastatur: keine fehlenden oder wackeligen Tasten', 'Stark glänzende Tasten zeigen intensive Nutzung.', 'Info', 'Tastenkappen fehlen oder wackeln', ''),
        @('BIOS lässt sich ohne Passwort öffnen (optional)', 'Erst NACH BuyCheck prüfen (ein Neustart beendet das Programm): beim Einschalten F2/Entf/F1/F10 – nur ansehen, NICHTS verändern. Jetzt mit S überspringen, wenn noch nicht geprüft.', 'Kritisch', 'BIOS fragt nach einem Passwort', 'Ohne BIOS-Zugang lassen sich wichtige Einstellungen nicht ändern (z. B. Start vom USB-Stick).'),
        @('Kopfhöreranschluss funktioniert (falls vorhanden)', 'Mit eigenen Kopfhörern kurz testen.', 'Info', 'Kopfhöreranschluss funktioniert nicht', 'Oft eine Einstellung oder ein Treiber, sonst die Buchse.'),
        @('Tastaturbeleuchtung / Fingerabdruckleser funktionieren (falls vorhanden)', '', 'Info', 'Tastaturbeleuchtung oder Fingerabdruckleser ohne Funktion', 'Oft nur eine Einstellung (Tastenkombination für die Beleuchtung) oder ein fehlender Treiber.'),
        @('Gummifüße vorhanden', 'Fehlende Füße verschlechtern die Belüftung von unten.', 'Info', 'Gummifüße fehlen', 'Ohne Füße kann das Gerät schlechter Luft ansaugen.')
    )
    $n = $def.Count
    $state = New-Object int[] $n
    $notes = New-Object string[] $n
    for ($i = 0; $i -lt $n; $i++) { $state[$i] = 2 }
    Write-BCOut -Text 'Bitte jeden Punkt am Gerät prüfen: J = in Ordnung, N = Problem, S = nicht geprüft, Z = zurück zum vorigen Punkt.' -Indent 3 -Color White
    $i = 0
    while ($i -lt $n) {
        Write-BCOut ''
        Write-BCOut -Text $def[$i][0] -Prefix ('   {0,2}/{1}  ' -f ($i + 1), $n) -Color White
        if ($def[$i][1]) { Write-BCOut -Text $def[$i][1] -Indent 10 -Color DarkGray }
        $k = Read-BCKey -Prompt '          [J] OK   [N] Problem   [S] nicht geprüft   [Z] zurück  ' -Allowed @('j', 'n', 's', 'z')
        if ($k -eq 'z') { if ($i -gt 0) { $i-- }; continue }
        if ($k -eq 'j') { $state[$i] = 0; $notes[$i] = '' }
        elseif ($k -eq 'n') { $state[$i] = 1; $notes[$i] = (Read-BCLine '          Was fällt auf? (optional): ').Trim() }
        else { $state[$i] = 2; $notes[$i] = '' }
        $i++
    }
    $open = @(); $okCount = 0
    $rows = @()
    for ($i = 0; $i -lt $n; $i++) {
        $lvl = $def[$i][2]
        $txt = 'nicht geprüft'
        switch ($state[$i]) {
            0 { $okCount++; $txt = 'OK' }
            1 {
                $txt = 'Problem'
                $detail = $notes[$i]
                if ($detail) { $detail = 'Deine Notiz: ' + $detail } else { $detail = 'Bei der Sichtprüfung als Problem markiert: ' + $def[$i][0] }
                Add-BCFinding -Level $lvl -Title ('Sichtprüfung: ' + $def[$i][3]) -Detail $detail -Advice $def[$i][4]
            }
            default { $open += $def[$i][0] }
        }
        $rows += New-BCObject @('Punkt', $def[$i][0], 'Ergebnis', $txt, 'Anmerkung', $notes[$i])
    }
    if ($okCount -gt 0) { Add-BCFinding -Level OK -Title "$okCount Punkte der Sichtprüfung in Ordnung" }
    if ($open.Count -gt 0) { Add-BCFinding -Level Info -Title "$($open.Count) Punkte der Sichtprüfung nicht geprüft" -Detail ($open -join ' · ') }
    Add-BCTable -Title 'Sichtprüfung' -Rows $rows
}
