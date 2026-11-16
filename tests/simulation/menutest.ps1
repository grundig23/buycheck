# Test des Textmenüs: Profil wählen, anpassen, Dauer ändern, Bereiche umschalten, speichern und wieder laden
$checks = $script:BCChecks.ToArray()
$profiles = @(
    (New-BCObject @('Id', 'quick', 'Label', 'Schnellcheck vor Ort', 'Description', 'Test')),
    (New-BCObject @('Id', 'thorough', 'Label', 'Gründlich', 'Description', 'Test')),
    (New-BCObject @('Id', 'linux', 'Label', 'Linux-Plan', 'Description', 'Test')),
    (New-BCObject @('Id', 'auto', 'Label', 'Nur automatisch', 'Description', 'Test')))
foreach ($p in $profiles) { $st = Get-BCProfileStats -Checks $checks -ProfileId $p.Id; "PROFIL {0}: {1}" -f $p.Id, (Format-BCStats $st) }
# 1) Hauptmenü: A (anpassen) -> Zeilen: "?4", Enter, "d 7" (Belastungstest) -> 2, "1-3", "x9", "" -> Bestätigung Enter
$sorted = @($checks | Sort-Object { $_.Info.CategoryOrder }, { $_.Info.Order })
$idxStress = 1 + [array]::IndexOf(@($sorted | ForEach-Object { $_.Id }), 'cpu.stress')
"Belastungstest hat Nummer $idxStress"
foreach ($k in @('a')) { $global:SimKeyQueue.Enqueue($k) }
foreach ($l in @('?4', "d $idxStress", '7', '1-3', 'x9', '')) { $global:SimLineQueue.Enqueue($l) }
$global:SimKeyQueue.Enqueue('enter')   # Beschreibung schließen
$global:SimKeyQueue.Enqueue('enter')   # Starten
$label = Show-BCSelection -Checks $checks -Profiles $profiles -Settings $null
"ERGEBNIS: $label"
$sel = @($checks | Where-Object { $_.Info.Selected } | ForEach-Object { $_.Id })
"AUSGEWÄHLT ($($sel.Count)): $($sel -join ', ')"
$stress = $checks | Where-Object { $_.Id -eq 'cpu.stress' }
"STRESS-DAUER: $($stress.Info.Options[0].Value) (erwartet 7)"
$path = Join-Path $SIM 'auswahl-test.txt'
"GESPEICHERT: $(Save-BCSettings -Path $path -ProfileId 'custom' -Checks $checks)"
Get-Content $path | Select-Object -First 4
foreach ($c in $checks) { $c.Info.Selected = $false; foreach ($o in @($c.Info.Options)) { if ($o) { $o.Value = $o.Default } } }
$set = Read-BCSettings -Path $path
# 2) Hauptmenü mit gespeicherter Auswahl: Taste 5 = letzte eigene Auswahl, dann Enter
$global:SimKeyQueue.Enqueue('5'); $global:SimKeyQueue.Enqueue('enter')
$label2 = Show-BCSelection -Checks $checks -Profiles $profiles -Settings $set
$sel2 = @($checks | Where-Object { $_.Info.Selected } | ForEach-Object { $_.Id })
"NACH LADEN: $label2, $($sel2.Count) Tests, gleich: $((@(Compare-Object $sel $sel2)).Count -eq 0), Stress-Dauer $($stress.Info.Options[0].Value)"
# 3) Profil 2 (Gründlich) direkt, dann Zurück (z), dann Beenden (q)
$global:SimKeyQueue.Enqueue('2'); $global:SimKeyQueue.Enqueue('z'); $global:SimKeyQueue.Enqueue('q')
$label3 = Show-BCSelection -Checks $checks -Profiles $profiles -Settings $set
"BEENDEN liefert: [$label3]"
