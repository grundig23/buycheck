# BuyCheck – Tests und Arbeitsdateien

BuyCheck wurde ohne echten Windows-Laptop entwickelt. Damit trotzdem nachvollziehbar ist, was geprüft
wurde, liegen hier alle Testwerkzeuge, die Windows-Nachbildung und die Ausgaben des letzten Testlaufs.

Dieser Ordner ist **nicht** in der ZIP-Datei von „Code → Download ZIP“ enthalten (siehe
`.gitattributes`, `export-ignore`). Zum Prüfen eines Laptops wird er nicht gebraucht.

## Alle Tests ausführen

Unter Linux mit PowerShell 7 (`pwsh`) und Python 3:

```bash
pwsh -NoProfile -File tests/Run-AllTests.ps1
```

Für den Test des Starters (`Start-BuyCheck.cmd`) werden zusätzlich `wine` und
`x86_64-w64-mingw32-gcc` gebraucht. Fehlen sie, wird dieser Teil übersprungen.

Die Ausgaben landen in [`ergebnisse/`](ergebnisse/), die Übersicht in
[`ergebnisse/ZUSAMMENFASSUNG.txt`](ergebnisse/ZUSAMMENFASSUNG.txt).

## Was geprüft wird

| Test | Was er zeigt |
|---|---|
| PowerShell-2.0-Kompatibilität | Kein Sprachmittel und keine .NET-Funktion, die es unter Windows 7 (PowerShell 2.0, .NET 2.0) nicht gibt. Neuere Befehle nur mit Absicherung |
| UTF-8-BOM | Alle Skripte haben die Kennung, ohne die Windows PowerShell 5.1 und älter Umlaute falsch lesen |
| Anführungszeichen | Keine Zeichenkette wird durch ein typografisches Anführungszeichen („ “ ‚ ‘) beendet. PowerShell behandelt diese wie " bzw. ' – das fiele erst beim Lauf auf |
| Einzeltests | Byte-Auswertung (NVMe, SMBIOS, EDID, Seriennummern), Puffer, Tonerzeugung, Vergleichsfunktionen |
| Prozessor-Datenbank | Generation und Architektur aus dem CPU-Namen, Windows-11-Liste |
| Szenario A | ThinkPad T480 mit NVMe-SSD und **gefälschtem CPU-Namen** in der Registry |
| Szenario B | Billig-Laptop mit SATA-SSD, „Default string“-Firmware und **Lesefehler** auf der SSD |
| Szenario C | ThinkPad T420 mit **Windows 7**, Festplatte und BIOS statt UEFI |
| Textmenü | Profil wählen, Tests an- und abwählen, Dauer ändern, Auswahl speichern und wieder laden |
| Hauptprogramm | `BuyCheck.ps1` im Ganzen: normal, ohne `lib/Win32.ps1` (Virenscanner blockiert sie) und mit blockiertem `lib/Core.ps1` (Meldung bleibt stehen, `BuyCheck-Fehler.txt` wird geschrieben) |
| Starter | `Start-BuyCheck.cmd` mit echter `cmd.exe`-Logik: Adminrechte vorhanden/fehlen, Windows-Abfrage abgebrochen, negative Fehlercodes, ZIP nicht entpackt, Pfad mit Leerzeichen |

Bei allen Szenarien wird zusätzlich kontrolliert, dass **nie mit Schreibrechten** auf einen
Datenträger zugegriffen wird und alle geöffneten Zugriffe wieder geschlossen werden.

## Was die Simulation nicht zeigen kann

- wie sich echte Hardware und echte Treiber verhalten (die Antworten sind nach Dokumentation und
  Beispieldaten nachgebaut)
- wie Virenscanner auf BuyCheck reagieren
- Darstellung im echten Windows-Konsolenfenster (Schriftart, Farben, Fenstergröße)

Deshalb vor dem Termin beim Verkäufer den Probelauf am eigenen PC machen (README, Abschnitt 1).

## Aufbau

```
Run-AllTests.ps1          führt alles aus, schreibt ergebnisse/
simulation/
  SimWin32.cs             nachgebaute Windows-Funktionen (gleiche Aufrufe wie lib/Win32.ps1),
                          protokolliert jeden Zugriff und meldet Schreibzugriffe
  simdata.ps1             Erzeugung von Beispieldaten (SMBIOS, NVMe, EDID …)
  mocks2.ps1              nachgebaute Windows-Befehle (WMI, Registry, powercfg …) und Tastatureingaben
  run-sim2.ps1            Szenarien A/B/C und Menütest
  menutest.ps1            Ablauf des Menütests
  unittests.ps1           Einzeltests
  cpudb.tests.ps1         Tests der Prozessor-Datenbank
  gen-main.py             baut aus dem echten BuyCheck.ps1 eine Simulationsfassung
  bin/, win/, c/, pd/, pf/  nachgebildete Windows-Ordner und -Programme
starter/
  Test-Starter.sh         Test von Start-BuyCheck.cmd unter Wine
  fakeps.c, fakefltmc.c   Attrappen für powershell.exe und fltmc.exe
werkzeuge/
  ps2check.ps1            Prüfung auf PowerShell-2.0-Kompatibilität
  quotecheck.ps1          findet Zeichenketten, die an typografischen Anführungszeichen („ “) enden
  convert-ps2.ps1         einmalige Umwandlung von PowerShell-5-Sprachmitteln (für Windows 7)
  emit-test.ps1           Nachweis, dass Windows-Funktionen ohne Compiler eingebunden werden können
ergebnisse/               Ausgaben des letzten Laufs
archiv-v1/                Tests der ersten Fassung (Fensteroberfläche mit C#-Teilen, Commit 0fe4c80).
                          Laufen mit der heutigen Fassung nicht mehr, bleiben zur Nachvollziehbarkeit.
                          Kompilierte Dateien und Bildschirmfotos sind nicht enthalten.
```
