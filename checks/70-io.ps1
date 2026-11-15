# BuyCheck – Eingabe, Anschlüsse & Multimedia (Mitmach-Tests in der Konsole)

function Get-BCPnpByClass {
    param([string[]]$Classes)
    return @(Get-BCPnp | Where-Object { $_ -and $Classes -contains "$($_.PNPClass)" })
}

Register-BuyCheck -Id 'input.keyboard' -Category 'Eingabe, Anschlüsse & Multimedia' -Order 10 -RunOrder 220 -Seconds 120 -Interactive `
    -Title 'Tastaturtest (jede Taste)' `
    -Description 'Zeigt eine deutsche Tastatur als Text. Jede gedrückte Taste wird grün markiert, so fallen tote oder klemmende Tasten sofort auf. Die Tasten haben während des Tests keine Wirkung auf Windows (außer Windows-Taste und Alt+F4).' `
    -Profiles @('quick', 'thorough', 'linux') `
    -Run {
    $kb = @(Get-BCPnpByClass @('Keyboard'))
    if ($kb.Count -eq 0) { Add-BCFinding -Level Warnung -Title 'Keine Tastatur als Gerät erkannt' }
    if (-not (Show-BCInfo -Title 'Tastaturtest' -Message 'Gleich erscheint eine Tastatur-Übersicht. Drücke jede Taste einmal; erkannte Tasten werden grün. Zum Beenden Esc dreimal hintereinander drücken.' -OkText 'Test starten' -CancelText 'Überspringen')) {
        Add-BCFinding -Level Info -Title 'Tastaturtest übersprungen'; return
    }
    $k = Invoke-BCKeyboardCapture
    if (-not $k) { Add-BCFinding -Level Fehler -Title 'Tastaturtest in diesem Fenster nicht möglich' -Detail 'Die Konsole liefert keine Tastenereignisse (z. B. beim Start über eine Entwicklungsumgebung).'; return }
    $details = @("Gedrückt: $(@($k.Pressed).Count) Tasten in $($k.Seconds) s")
    if (@($k.Extra).Count -gt 0) { $details += 'Zusätzlich erkannt: ' + (@($k.Extra) -join ', ') }
    if (@($k.MissingOptional).Count -gt 0) { $details += 'Optionale Tasten nicht gedrückt: ' + (@($k.MissingOptional) -join ' ') }
    $problems = @()
    $missing = @($k.Missing)
    if ($missing.Count -gt 0) {
        $r = Show-BCChoice -Title 'Tastatur' -Question ("Diese Tasten wurden nicht erkannt: " + ($missing -join ' ') + "`nWas trifft zu?") -Options @(
            'Die Tasten reagieren nicht (defekt)',
            'Diese Tasten gibt es auf dem Gerät nicht (anderes Tastatur-Layout)',
            'Ich habe sie nicht alle gedrückt / nicht geprüft') -Comment
        switch ($r.Choice) {
            0 { $problems += 'Keine Reaktion: ' + ($missing -join ' ') }
            1 { $details += 'Laut Prüfer nicht vorhanden: ' + ($missing -join ' ') }
            default { Add-BCFinding -Level Info -Title 'Tastatur nicht vollständig geprüft' -Detail ('Nicht gedrückt: ' + ($missing -join ' ') + $(if ($r.Comment) { ' · ' + $r.Comment } else { '' })) }
        }
    }
    if (@($k.Stuck).Count -gt 0) {
        $details += 'Dauerdruck gemeldet: ' + (@($k.Stuck) -join ', ')
        Add-BCFinding -Level Info -Title ('Taste meldete Dauerdruck: ' + (@($k.Stuck) -join ', ')) -Detail 'Entweder lange festgehalten – oder die Taste klemmt. Bitte noch einmal von Hand prüfen.'
    }
    $feel = Show-BCChoice -Title 'Tastatur' -Question 'Wie fühlen sich die Tasten an?' -Options @(
        'Alle Tasten gleichmäßig, nichts klemmt oder klebt',
        'Einzelne Tasten klemmen, kleben oder sind schwergängig',
        'Tastenkappen fehlen oder wackeln') -Comment
    if ($feel.Choice -eq 1) { $problems += 'Tasten klemmen/kleben' + $(if ($feel.Comment) { ': ' + $feel.Comment } else { '' }) }
    if ($feel.Choice -eq 2) { $problems += 'Tastenkappen fehlen/wackeln' + $(if ($feel.Comment) { ': ' + $feel.Comment } else { '' }) }
    if ($problems.Count -gt 0) { $res = New-BCTestResult -Verdict 'Problem' -Problems $problems -Details $details }
    elseif ($missing.Count -gt 0 -and $r.Choice -eq 2) { return }
    else { $res = New-BCTestResult -Verdict 'OK' -Details $details }
    Add-BCInteractiveResult -Result $res -OkTitle 'Alle Tasten funktionieren' -ProblemTitle 'Tastatur: defekte oder klemmende Tasten' -ProblemLevel Kritisch `
        -Advice 'Tastaturtausch kostet je nach Modell ca. 30–150 € (bei verklebten Tastaturen mehr). Klebrige Tasten können auf einen Flüssigkeitsschaden hindeuten.'
}

Register-BuyCheck -Id 'input.touchpad' -Category 'Eingabe, Anschlüsse & Multimedia' -Order 20 -RunOrder 230 -Seconds 60 -Interactive `
    -Title 'Touchpad-Test' `
    -Description 'Prüft, ob der Mauszeiger mit dem Touchpad alle Bildschirmbereiche erreicht und ob Links-, Doppel- und Rechtsklick erkannt werden. Danach wird nach Scrollen mit zwei Fingern und Aussetzern gefragt.' `
    -Profiles @('quick', 'thorough', 'linux') `
    -Run {
    $pads = @(Get-BCPnp | Where-Object { $_ -and "$($_.Name)" -match '(?i)touch ?pad|precision|trackpad|synaptics|elan|alps' -and @('Mouse', 'HIDClass') -contains "$($_.PNPClass)" })
    if ($pads.Count -eq 0) { Add-BCFinding -Level Info -Title 'Kein Touchpad eindeutig als Gerät erkennbar' -Detail 'Manche Touchpads erscheinen nur als "HID-konforme Maus".' }
    $sys = Get-BCSystem
    if (-not $sys.IsPortable) {
        if (-not (Read-BCYesNo 'Das Gerät meldet sich nicht als Notebook. Hat es trotzdem ein Touchpad?')) { Add-BCFinding -Level Info -Title 'Kein Touchpad vorhanden (laut Prüfer)'; return }
    }
    if (-not (Show-BCInfo -Title 'Touchpad' -Message 'Bitte eine eventuell angeschlossene Maus abziehen und nur das Touchpad benutzen.' -OkText 'Test starten' -CancelText 'Überspringen')) {
        Add-BCFinding -Level Info -Title 'Touchpad-Test übersprungen'; return
    }
    $t = Invoke-BCTouchpadCapture
    if (-not $t) { Add-BCFinding -Level Fehler -Title 'Touchpad-Test nicht möglich' -Detail 'Zeigerposition nicht abfragbar.'; return }
    $details = @(('Bereiche erreicht: {0}/{1} · Linksklick: {2} · Doppelklick: {3} · Rechtsklick: {4}' -f $t.Visited, $t.Cells, $(if ($t.Left) { 'ja' } else { 'nein' }), $(if ($t.Double) { 'ja' } else { 'nein' }), $(if ($t.Right) { 'ja' } else { 'nein' })))
    $problems = @()
    if ($t.Visited -lt $t.Cells) { $problems += "Zeiger erreichte nur $($t.Visited) von $($t.Cells) Bildschirmbereichen" }
    if (-not $t.Left) { $problems += 'Linksklick nicht erkannt' }
    if (-not $t.Right) { $problems += 'Rechtsklick nicht erkannt' }
    $r = Show-BCChoice -Title 'Touchpad' -Question 'Funktionieren Scrollen mit zwei Fingern und die Zeigerbewegung ohne Aussetzer oder Springen?' -Options @(
        'Ja, alles reagiert gleichmäßig',
        'Zeiger springt, hakt oder reagiert in manchen Bereichen nicht',
        'Scrollen mit zwei Fingern funktioniert nicht',
        'Touchpad liegt nicht flach / Klick ist schwergängig oder klemmt',
        'Nicht geprüft') -Comment
    switch ($r.Choice) {
        1 { $problems += 'Zeiger springt/hakt' }
        2 { $problems += 'Scrollen mit zwei Fingern funktioniert nicht' }
        3 { $problems += 'Touchpad liegt nicht flach oder klemmt (aufgeblähter Akku?)' }
        default { }
    }
    if ($problems.Count -gt 0) {
        $level = 'Warnung'
        if ($r.Choice -eq 3) { $level = 'Kritisch' }
        Add-BCInteractiveResult -Result (New-BCTestResult -Verdict 'Problem' -Problems $problems -Comment $r.Comment -Details $details) -OkTitle 'Touchpad funktioniert' -ProblemTitle 'Problem mit dem Touchpad' -ProblemLevel $level `
            -Advice 'Ein nicht flach liegendes oder schwergängiges Touchpad kann auf einen aufgeblähten Akku hindeuten! Sonst: Touchpad/Kabel defekt oder Treiberproblem.'
    } else {
        Add-BCInteractiveResult -Result (New-BCTestResult -Verdict 'OK' -Comment $r.Comment -Details $details) -OkTitle 'Touchpad funktioniert' -ProblemTitle 'Problem mit dem Touchpad'
    }
}

Register-BuyCheck -Id 'ports.usb' -Category 'Eingabe, Anschlüsse & Multimedia' -Order 30 -RunOrder 240 -Seconds 90 -Interactive `
    -Title 'USB-Anschlüsse' `
    -Description 'Erkennt jedes Einstecken eines USB-Geräts und zeigt die Anschluss-Position an. So prüfst du jeden USB-Port (auch USB-C) auf Funktion und Wackelkontakt. Du brauchst dafür ein zweites USB-Gerät (Maus, Stick, Handykabel) – nicht den BuyCheck-Stick selbst abziehen!' `
    -Profiles @('quick', 'thorough', 'linux') `
    -Run {
    $ctrl = @(Get-BCPnp | Where-Object { $_ -and "$($_.Name)" -match '(?i)xHCI|USB4|Thunderbolt|USB 3' -and @('USB', 'System', 'USBDevice') -contains "$($_.PNPClass)" })
    if ($ctrl.Count -gt 0) { Add-BCText -Title 'USB-Controller' -Text ((@($ctrl | ForEach-Object { $_.Name }) | Select-Object -Unique) -join "`n") }
    if (-not (Show-BCInfo -Title 'USB-Anschlüsse' -Message 'Nimm ein USB-Gerät (Maus, zweiter Stick, Handy mit Kabel) und stecke es nacheinander in jeden USB-Anschluss. Den BuyCheck-Stick bitte NICHT abziehen, solange der Test läuft.' -OkText 'Test starten' -CancelText 'Überspringen')) {
        Add-BCFinding -Level Info -Title 'USB-Test übersprungen'; return
    }
    $found = @(Invoke-BCUsbWatch)
    $ports = @($found | ForEach-Object { $_.Location } | Where-Object { $_ } | Select-Object -Unique)
    $details = @($found | ForEach-Object { if ($_.Location) { "$($_.Name) – $($_.Location)" } else { "$($_.Name)" } })
    $r = Show-BCChoice -Title 'USB' -Question ("Erkannt: $($found.Count) Einsteckvorgänge an $($ports.Count) verschiedenen Anschlüssen. Haben alle USB-Anschlüsse funktioniert?") -Options @(
        'Ja, jeder Anschluss wurde erkannt, Stecker sitzen fest',
        'Ein oder mehrere Anschlüsse funktionieren nicht',
        'Anschluss wackelt / Gerät trennt sich beim Bewegen',
        'Nicht vollständig geprüft') -Comment
    switch ($r.Choice) {
        0 {
            if ($found.Count -eq 0) { Add-BCFinding -Level Warnung -Title 'Kein eingestecktes USB-Gerät erkannt' -Detail $r.Comment -Advice 'Mit einem anderen Gerät wiederholen; erkennt Windows gar nichts, sind die Anschlüsse oder der USB-Controller defekt.' }
            else { Add-BCInteractiveResult -Result (New-BCTestResult -Verdict 'OK' -Comment $r.Comment -Details $details) -OkTitle 'USB-Anschlüsse funktionieren' -ProblemTitle 'Problem mit USB-Anschlüssen' }
        }
        1 { Add-BCInteractiveResult -Result (New-BCTestResult -Verdict 'Problem' -Problems @('Anschluss ohne Funktion') -Comment $r.Comment -Details $details) -OkTitle 'USB-Anschlüsse funktionieren' -ProblemTitle 'Problem mit USB-Anschlüssen' -ProblemLevel Warnung -Advice 'Defekte Buchsen sind meist auf dem Mainboard verlötet – Reparatur aufwendig.' }
        2 { Add-BCInteractiveResult -Result (New-BCTestResult -Verdict 'Problem' -Problems @('Wackelkontakt') -Comment $r.Comment -Details $details) -OkTitle 'USB-Anschlüsse funktionieren' -ProblemTitle 'Problem mit USB-Anschlüssen' -ProblemLevel Warnung -Advice 'Lockere Buchsen verschlechtern sich meist mit der Zeit.' }
        default { Add-BCFinding -Level Info -Title 'USB-Anschlüsse nicht vollständig geprüft' -Detail (@($details + @($r.Comment)) -join ' · ') }
    }
}

Register-BuyCheck -Id 'audio.speakers' -Category 'Eingabe, Anschlüsse & Multimedia' -Order 40 -RunOrder 250 -Seconds 60 -Interactive `
    -Title 'Lautsprecher (links/rechts)' `
    -Description 'Spielt Testtöne getrennt links und rechts sowie eine Tonfolge von tief nach hoch (deckt Scheppern und Kratzen auf). Die Lautstärke wird nicht verändert.' `
    -Profiles @('quick', 'thorough', 'linux') `
    -Run {
    $audio = @(Get-BCPnpByClass @('MEDIA', 'AudioEndpoint') | Where-Object { [int]$_.ConfigManagerErrorCode -eq 0 })
    if ($audio.Count -eq 0) { Add-BCFinding -Level Warnung -Title 'Kein funktionsfähiges Audiogerät gefunden' -Detail 'Treiber fehlt oder Audiochip deaktiviert/defekt.' }
    if (-not (Show-BCInfo -Title 'Lautsprecher' -Message 'Kopfhörer abziehen. Stelle die Lautstärke mit den Lautstärketasten auf etwa die Hälfte (BuyCheck ändert sie nicht selbst) und hör genau hin.' -OkText 'Töne abspielen' -CancelText 'Überspringen')) {
        Add-BCFinding -Level Info -Title 'Lautsprechertest übersprungen'; return
    }
    $segments = @(
        @('Links', @(, @(441, 1.5, 1, 0))),
        @('Rechts', @(, @(441, 1.5, 0, 1))),
        @('Tonfolge tief -> hoch (beide Seiten)', @(@(105, 0.8, 1, 1), @(210, 0.8, 1, 1), @(441, 0.8, 1, 1), @(882, 0.8, 1, 1), @(2205, 0.8, 1, 1), @(4410, 0.8, 1, 1)))
    )
    $played = $true
    foreach ($seg in $segments) {
        Write-BCOut -Text ('Jetzt: ' + $seg[0]) -Indent 3 -Color White
        try { Invoke-BCPlayWav (New-BCToneWav -Segments $seg[1]) }
        catch { $played = $false; Add-BCFinding -Level Fehler -Title 'Testton konnte nicht abgespielt werden' -Detail "$($_.Exception.Message)"; break }
        Start-Sleep -Milliseconds 300
    }
    if (-not $played) { return }
    $r = Show-BCMulti -Title 'Lautsprecher' -Question 'Was hast du gehört? (alles Zutreffende)' -Options @(
        'Linker Ton nur links und klar',
        'Rechter Ton nur rechts und klar',
        'Tonfolge sauber, ohne Scheppern',
        'Scheppern, Kratzen oder Rauschen',
        'Eine Seite fehlt oder ist deutlich leiser',
        'Gar nichts gehört') -Comment
    $c = $r.Checked
    $problems = @()
    if ($c[3]) { $problems += 'Scheppern/Kratzen/Rauschen' }
    if ($c[4]) { $problems += 'Eine Seite fehlt oder ist leiser' }
    if ($c[5]) { $problems += 'Kein Ton zu hören' }
    if ($problems.Count -eq 0 -and -not ($c[0] -and $c[1])) { $problems += 'Links/rechts nicht eindeutig getrennt hörbar' }
    if ($problems.Count -gt 0) {
        Add-BCInteractiveResult -Result (New-BCTestResult -Verdict 'Problem' -Problems $problems -Comment $r.Comment) -OkTitle 'Lautsprecher funktionieren (links und rechts, ohne Störgeräusche)' -ProblemTitle 'Problem mit den Lautsprechern' -ProblemLevel Warnung `
            -Advice 'Vorher Lautstärke und Stummschaltung prüfen. Defekte Lautsprecher lassen sich meist tauschen (je nach Modell 20–60 €).'
    } else {
        Add-BCInteractiveResult -Result (New-BCTestResult -Verdict 'OK' -Comment $r.Comment) -OkTitle 'Lautsprecher funktionieren (links und rechts, ohne Störgeräusche)' -ProblemTitle 'Problem mit den Lautsprechern'
    }
}

Register-BuyCheck -Id 'audio.mic' -Category 'Eingabe, Anschlüsse & Multimedia' -Order 50 -RunOrder 260 -Seconds 60 -Interactive `
    -Title 'Mikrofon (Aufnahme & Wiedergabe)' `
    -Description 'Nimmt 5 Sekunden auf und spielt die Aufnahme sofort wieder ab. Die Aufnahme bleibt nur im Arbeitsspeicher; es wird keine Datei angelegt.' `
    -Profiles @('quick', 'thorough', 'linux') `
    -Run {
    if (-not (Show-BCInfo -Title 'Mikrofon' -Message 'Nach dem Start 5 Sekunden lang normal sprechen (z. B. zählen). Danach wird die Aufnahme abgespielt.' -OkText 'Aufnahme starten' -CancelText 'Überspringen')) {
        Add-BCFinding -Level Info -Title 'Mikrofontest übersprungen'; return
    }
    $m = Invoke-BCMicTest -Seconds 5
    if (-not $m.Ok) {
        Add-BCFinding -Level Warnung -Title 'Mikrofon-Aufnahme nicht möglich' -Detail $m.Error `
            -Advice 'Prüfen, ob ein Mikrofon vorhanden und nicht deaktiviert ist. Unter Windows 10/11 kann auch der Datenschutz (Mikrofonzugriff für Desktop-Apps) die Aufnahme sperren.'
        return
    }
    $r = Show-BCChoice -Title 'Mikrofon' -Question 'Wie klang die Wiedergabe deiner Aufnahme?' -Options @(
        'Stimme klar und deutlich zu hören',
        'Stimme leise, verrauscht oder verzerrt',
        'Nichts zu hören (Stille)',
        'Nicht geprüft') -Comment
    $det = @()
    if ($null -ne $m.MaxLevel) { $det += "Höchster gemessener Pegel: $($m.MaxLevel)" }
    switch ($r.Choice) {
        0 { $res = New-BCTestResult -Verdict 'OK' -Comment $r.Comment -Details $det }
        1 { $res = New-BCTestResult -Verdict 'Problem' -Problems @('Aufnahme leise/verrauscht/verzerrt') -Comment $r.Comment -Details $det }
        2 { $res = New-BCTestResult -Verdict 'Problem' -Problems @('Aufnahme stumm') -Comment $r.Comment -Details $det }
        default { $res = New-BCTestResult -Verdict 'Skip' -Comment $r.Comment }
    }
    Add-BCInteractiveResult -Result $res -OkTitle 'Mikrofon funktioniert' -ProblemTitle 'Problem mit dem Mikrofon' -ProblemLevel Warnung `
        -Advice 'Vorher prüfen, ob ein Mikrofon-Schalter/eine Taste stummschaltet oder der Mikrofonzugriff in den Datenschutzeinstellungen gesperrt ist (das ändert BuyCheck bewusst nicht).'
}

Register-BuyCheck -Id 'camera' -Category 'Eingabe, Anschlüsse & Multimedia' -Order 60 -RunOrder 270 -Seconds 60 -Interactive `
    -Title 'Webcam' `
    -Description 'Prüft, ob eine Kamera erkannt wird und funktioniert. Für die Sichtkontrolle wird die Kamera-App von Windows geöffnet (ab Windows 8).' `
    -Profiles @('quick', 'thorough', 'linux') `
    -Run {
    $cams = @(Get-BCPnpByClass @('Camera', 'Image') | Where-Object { "$($_.Name)" -notmatch '(?i)scanner|printer' })
    $disabled = @($cams | Where-Object { [int]$_.ConfigManagerErrorCode -eq 22 })
    $broken = @($cams | Where-Object { @(0, 22) -notcontains [int]$_.ConfigManagerErrorCode })
    if ($cams.Count -eq 0) {
        Add-BCFinding -Level Warnung -Title 'Keine Kamera erkannt' -Detail 'Kamera fehlt, ist defekt oder im BIOS deaktiviert.' -Advice 'Manche Geräte haben einen Kamera-Schalter oder eine Tastenkombination (z. B. F8/F10).'
    } else {
        Add-BCText -Title 'Erkannte Kameras' -Text ((@($cams | ForEach-Object { "$($_.Name) (Status: Code $($_.ConfigManagerErrorCode))" })) -join "`n")
    }
    if ($disabled.Count -gt 0) { Add-BCFinding -Level Warnung -Title 'Kamera ist in Windows deaktiviert' -Detail (@($disabled | ForEach-Object { $_.Name }) -join ', ') -Advice 'Deaktivierte Geräte können einen Defekt verbergen – Verkäufer bitten, sie zu aktivieren.' }
    if ($broken.Count -gt 0) { Add-BCFinding -Level Warnung -Title 'Kamera meldet einen Fehler' -Detail (@($broken | ForEach-Object { "$($_.Name) (Code $($_.ConfigManagerErrorCode))" }) -join ', ') }
    if ($cams.Count -eq 0) { return }
    $sys = Get-BCSystem
    if ($sys.OsBuildNumber -gt 0 -and $sys.OsBuildNumber -lt 9200) {
        Add-BCFinding -Level Info -Title 'Kamerabild unter Windows 7 nicht automatisch prüfbar' -Detail 'Windows 7 hat keine eingebaute Kamera-App. Bild z. B. in einer Videotelefonie-App des Verkäufers zeigen lassen.'
        return
    }
    if (-not (Show-BCInfo -Title 'Webcam' -Message "Gleich öffnet sich die Kamera-App von Windows.`n- Ist eine Abdeckung/ein Schieber vor der Kamera? Dann öffnen.`n- Prüfe, ob das Bild klar ist und die Kamera-LED leuchtet.`n- Schließe die Kamera-App danach wieder (Fragen der App, z. B. nach dem Standort, mit Nein beantworten)." -OkText 'Kamera öffnen' -CancelText 'Überspringen')) {
        Add-BCFinding -Level Info -Title 'Kamerabild nicht geprüft'; return
    }
    $opened = $false
    try { Start-Process 'microsoft.windows.camera:' -ErrorAction Stop; $opened = $true } catch { }
    $r = Show-BCChoice -Title 'Webcam' -Question 'Wie ist das Kamerabild?' -Options @(
        'Bild klar und scharf, Kamera-LED leuchtet',
        'Bild vorhanden, aber unscharf, verrauscht oder mit Streifen',
        'Kein Bild bzw. schwarzes Bild (Abdeckung geprüft)',
        'Kamera-App ließ sich nicht öffnen / nicht geprüft') -Comment
    switch ($r.Choice) {
        0 { Add-BCFinding -Level OK -Title 'Webcam funktioniert' -Detail $r.Comment }
        1 { Add-BCFinding -Level Warnung -Title 'Webcam-Bild mangelhaft' -Detail $r.Comment }
        2 { Add-BCFinding -Level Warnung -Title 'Webcam liefert kein Bild' -Detail $r.Comment -Advice 'Kameramodul/Kabel im Displaydeckel defekt?' }
        default {
            $d = $r.Comment
            if (-not $opened) { $d = (@('Kamera-App nicht verfügbar') + @($r.Comment) | Where-Object { $_ }) -join ' · ' }
            Add-BCFinding -Level Info -Title 'Webcam-Bild nicht geprüft' -Detail $d
        }
    }
}
