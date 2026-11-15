# BuyCheck – Eingabe, Anschlüsse & Multimedia (interaktive Tests)

function Get-BCPnpByClass {
    param([string[]]$Classes)
    return @(Get-BCPnp | Where-Object { $Classes -contains "$($_.PNPClass)" })
}

Register-BuyCheck -Id 'input.keyboard' -Category 'Eingabe, Anschlüsse & Multimedia' -Order 10 -RunOrder 220 -Seconds 120 -Interactive `
    -Title 'Tastaturtest (jede Taste)' `
    -Description 'Zeigt eine deutsche Tastatur auf dem Bildschirm. Jede gedrückte Taste wird grün. So fallen tote oder klemmende Tasten sofort auf. Die Tasten haben in diesem Fenster keine Wirkung auf Windows.' `
    -Profiles @('quick', 'thorough', 'linux') `
    -Run {
    $kb = @(Get-BCPnpByClass @('Keyboard'))
    if ($kb.Count -eq 0) { Add-BCFinding -Level Warnung -Title 'Keine Tastatur als Gerät erkannt' }
    $f = New-Object BuyCheck.KeyboardTestForm
    $r = Show-BCTestForm $f
    Add-BCInteractiveResult -Result $r -OkTitle 'Alle Tasten funktionieren' -ProblemTitle 'Tastatur: defekte oder klemmende Tasten' -ProblemLevel Kritisch `
        -Advice 'Tastaturtausch kostet je nach Modell ca. 30–150 € (bei verklebten Tastaturen mehr). Klebrige Tasten können auf Flüssigkeitsschaden hindeuten.'
}

Register-BuyCheck -Id 'input.touchpad' -Category 'Eingabe, Anschlüsse & Multimedia' -Order 20 -RunOrder 230 -Seconds 60 -Interactive `
    -Title 'Touchpad-Test' `
    -Description 'Prüft Zeigerbewegung (alle Ecken), Links-/Rechtsklick, Doppelklick und Scrollen mit zwei Fingern. Eine Spur zeigt, ob der Zeiger springt.' `
    -Profiles @('quick', 'thorough', 'linux') `
    -Run {
    $pads = @(Get-BCPnp | Where-Object { "$($_.Name)" -match '(?i)touch ?pad|precision|trackpad|synaptics|elan|alps' -and "$($_.PNPClass)" -in @('Mouse', 'HIDClass') })
    if ($pads.Count -eq 0) { Add-BCFinding -Level Info -Title 'Kein Touchpad eindeutig als Gerät erkennbar' -Detail 'Manche Touchpads erscheinen nur als „HID-konforme Maus“.' }
    $f = New-Object BuyCheck.TouchpadTestForm
    $r = Show-BCTestForm $f
    Add-BCInteractiveResult -Result $r -OkTitle 'Touchpad funktioniert' -ProblemTitle 'Problem mit dem Touchpad' -ProblemLevel Kritisch `
        -Advice 'Ein nicht flach liegendes oder schwergängiges Touchpad kann auch auf einen aufgeblähten Akku hindeuten!'
}

Register-BuyCheck -Id 'ports.usb' -Category 'Eingabe, Anschlüsse & Multimedia' -Order 30 -RunOrder 240 -Seconds 90 -Interactive `
    -Title 'USB-Anschlüsse' `
    -Description 'Erkennt live jedes Einstecken eines USB-Geräts und zeigt die Anschluss-Position an. So prüfst du jeden USB-Port (auch USB-C) auf Funktion und Wackelkontakt. Du brauchst dafür ein zweites USB-Gerät (Stick, Maus, Handykabel).' `
    -Profiles @('quick', 'thorough', 'linux') `
    -Run {
    $ctrl = @(Get-BCPnp | Where-Object { "$($_.Name)" -match '(?i)xHCI|USB4|Thunderbolt|USB 3' -and "$($_.PNPClass)" -in @('USB', 'System', 'USBDevice') })
    if ($ctrl.Count -gt 0) { Add-BCText -Title 'USB-Controller' -Text ((@($ctrl | ForEach-Object { $_.Name }) | Select-Object -Unique) -join "`n") }
    $f = New-Object BuyCheck.UsbTestForm
    $r = Show-BCTestForm $f
    Add-BCInteractiveResult -Result $r -OkTitle 'USB-Anschlüsse funktionieren' -ProblemTitle 'Problem mit USB-Anschlüssen' -ProblemLevel Warnung -Advice 'Defekte Buchsen sind meist auf dem Mainboard verlötet – Reparatur aufwendig.'
}

Register-BuyCheck -Id 'audio.speakers' -Category 'Eingabe, Anschlüsse & Multimedia' -Order 40 -RunOrder 250 -Seconds 60 -Interactive `
    -Title 'Lautsprecher (links/rechts)' `
    -Description 'Spielt Testtöne getrennt links und rechts sowie eine Tonfolge von tief nach hoch (deckt Scheppern und Kratzen auf).' `
    -Profiles @('quick', 'thorough', 'linux') `
    -Run {
    $audio = @(Get-BCPnpByClass @('MEDIA', 'AudioEndpoint') | Where-Object { [int]$_.ConfigManagerErrorCode -eq 0 })
    if ($audio.Count -eq 0) { Add-BCFinding -Level Warnung -Title 'Kein funktionsfähiges Audiogerät gefunden' -Detail 'Treiber fehlt oder Audiochip deaktiviert/defekt.' }
    $f = New-Object BuyCheck.SpeakerTestForm
    $r = Show-BCTestForm $f
    Add-BCInteractiveResult -Result $r -OkTitle 'Lautsprecher funktionieren (links und rechts, ohne Störgeräusche)' -ProblemTitle 'Problem mit den Lautsprechern' -ProblemLevel Warnung
}

Register-BuyCheck -Id 'audio.mic' -Category 'Eingabe, Anschlüsse & Multimedia' -Order 50 -RunOrder 260 -Seconds 60 -Interactive `
    -Title 'Mikrofon (Aufnahme & Wiedergabe)' `
    -Description 'Nimmt 5 Sekunden auf, zeigt den Pegel und spielt die Aufnahme ab. Die Aufnahme wird nur kurz im Berichtsordner auf dem USB-Stick abgelegt und danach gelöscht.' `
    -Profiles @('quick', 'thorough', 'linux') `
    -Run {
    $wav = Join-Path $script:BCReportDir ('mikrofontest-' + [guid]::NewGuid().ToString('N').Substring(0, 8) + '.wav')
    $f = New-Object BuyCheck.MicTestForm($wav)
    $r = Show-BCTestForm $f
    try { if (Test-Path -LiteralPath $wav) { Remove-Item -LiteralPath $wav -Force } } catch { }
    Add-BCInteractiveResult -Result $r -OkTitle 'Mikrofon funktioniert' -ProblemTitle 'Problem mit dem Mikrofon' -ProblemLevel Warnung `
        -Advice 'Vorher prüfen, ob ein Hardware-Schalter/Taste das Mikrofon stummschaltet oder der Mikrofonzugriff in den Datenschutzeinstellungen gesperrt ist.'
}

Register-BuyCheck -Id 'camera' -Category 'Eingabe, Anschlüsse & Multimedia' -Order 60 -RunOrder 270 -Seconds 60 -Interactive `
    -Title 'Webcam' `
    -Description 'Prüft, ob eine Kamera erkannt wird, und öffnet die Windows-Kamera-App für eine Sichtkontrolle des Bildes.' `
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
    if (-not (Show-BCInfo -Title 'Webcam' -Message "Gleich öffnet sich die Kamera-App.`n`n• Ist eine Abdeckung/ein Schieber vor der Kamera? Dann öffnen.`n• Prüfe, ob das Bild klar ist und die Kamera-LED leuchtet.`n• Schließe die Kamera-App danach wieder." -OkText 'Kamera öffnen' -CancelText 'Überspringen')) {
        Add-BCFinding -Level Info -Title 'Kamerabild nicht geprüft'; return
    }
    $opened = $false
    try { Start-Process 'microsoft.windows.camera:' -ErrorAction Stop; $opened = $true } catch { }
    if (-not $opened) { try { Start-Process 'ms-settings:camera' -ErrorAction Stop; $opened = $true } catch { } }
    $r = Show-BCChoice -Title 'Webcam' -Question 'Wie ist das Kamerabild?' -Options @(
        'Bild klar und scharf, Kamera-LED leuchtet',
        'Bild vorhanden, aber unscharf, verrauscht oder mit Streifen',
        'Kein Bild bzw. schwarzes Bild (Abdeckung geprüft)',
        'Kamera-App ließ sich nicht öffnen / nicht geprüft') -Comment
    switch ($r.Choice) {
        0 { Add-BCFinding -Level OK -Title 'Webcam funktioniert' -Detail $r.Comment }
        1 { Add-BCFinding -Level Warnung -Title 'Webcam-Bild mangelhaft' -Detail $r.Comment }
        2 { Add-BCFinding -Level Warnung -Title 'Webcam liefert kein Bild' -Detail $r.Comment -Advice 'Kameramodul/Kabel im Displaydeckel defekt?' }
        default { Add-BCFinding -Level Info -Title 'Webcam-Bild nicht geprüft' -Detail $r.Comment }
    }
}
