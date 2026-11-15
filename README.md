# BuyCheck – gebrauchten Windows-Laptop vor dem Kauf prüfen

BuyCheck ist ein Prüfprogramm für den Kauf eines gebrauchten Laptops, z. B. über Kleinanzeigen. Du
startest es vom USB-Stick direkt beim Verkäufer. Es prüft die Hardware gründlich: SSD-Gesundheit, Akku,
Prozessor, Kühlung, RAM, Display, Tastatur, Anschlüsse und mehr. Außerdem sucht es nach
**Manipulationen**, etwa gefälschtem CPU-Namen, gefälschter SSD, zurückgesetzten Zählern oder
getauschten Teilen, und nach **Sperren** wie BIOS-Passwort oder Firmen-Login. Am Ende entsteht ein
Bericht mit Gesamturteil und einem Textbaustein für den Kaufvertrag.

Hintergründe, Grenzwerte und Quellen stehen in [`RECHERCHE.md`](RECHERCHE.md). Für die körperliche
Prüfung vor Ort gibt es die Liste [`CHECKLISTE.md`](CHECKLISTE.md) zum Ausdrucken.

---

## Das Wichtigste vorab: BuyCheck verändert nichts am Gerät

Der Laptop gehört beim Test noch dem Verkäufer. BuyCheck ist deshalb **rein lesend**:

- **Keine Installation, kein Kompilieren.** BuyCheck besteht nur aus PowerShell-Skripten, die Windows
  von Haus aus mitbringt. Die wenigen direkten Windows-Funktionen werden nur im Arbeitsspeicher
  eingebunden. Es werden keine Programmteile übersetzt und keine Hilfsdateien angelegt.
- **Keine Schreibzugriffe auf interne Datenträger.** SSD und Festplatte werden nur mit Leserecht oder
  ganz ohne Zugriffsrechte geöffnet. Es gibt keine Schreib-, Lösch- oder Formatiertests.
- **Keine geänderten Einstellungen.** Energieoptionen, Lautstärke, Datenschutz, WLAN, BIOS und Treiber
  bleiben unberührt. BuyCheck verhindert nur während der Laufzeit den Standby; das endet automatisch.
- **Kein Neustart, keine Diagnoseprogramme beim Hochfahren.** Die Windows-Speicherdiagnose würde sich
  in die Startkonfiguration eintragen und wird deshalb nicht verwendet.
- **Keine Daten ins Internet.** BuyCheck sendet nichts. Die WLAN-Prüfung liest nur die Liste der
  Netze in der Umgebung.
- **Berichte landen auf dem USB-Stick** im Ordner `Berichte`.

Unvermeidbar sind nur die Spuren, die jedes gestartete Programm hinterlässt: Windows protokolliert den
Start von PowerShell, und PowerShell legt eigene Cache-Dateien im Benutzerprofil an. Startest du für den
Kameratest die Kamera-App, merkt sie sich eventuell eigene Einstellungen.

---

## Voraussetzungen

- **Windows 7 SP1, 8, 8.1, 10 oder 11.** Das gilt für 32 und 64 Bit sowie für ARM-Geräte.
- **Keine Updates nötig.** BuyCheck läuft mit jeder eingebauten Windows PowerShell ab Version 2.0.
  Auch ein nie aktualisiertes Windows funktioniert.
- **Administratorrechte.** Windows fragt beim Start einmal nach; der Verkäufer muss mit „Ja“ bestätigen
  (ggf. mit seinem Passwort).
- **Mitbringen:**
  - USB-Stick mit BuyCheck
  - ein zweites USB-Gerät für den Anschlusstest (Maus, zweiter Stick oder Handykabel)
  - Kopfhörer
  - Handy (für einen Hotspot beim WLAN-Test, als Taschenlampe)
  - optional ein Monitor/Fernseher mit Kabel für den Bildausgang
- **Das Netzteil des Laptops** muss dabei sein.

**Nicht möglich:** Windows XP/Vista. Geräte im **S-Modus** und Firmengeräte mit Skriptsperre erlauben
keine Skripte. Den S-Modus zu verlassen wäre eine dauerhafte Änderung, also Sache des Verkäufers.

---

## 1. USB-Stick vorbereiten (am eigenen PC)

1. Auf <https://github.com/grundig23/buycheck> auf **Code → Download ZIP** klicken.
2. Die ZIP-Datei mit Rechtsklick → **Eigenschaften** öffnen, unten **„Zulassen“** anhaken, OK.
   Sonst warnt Windows später bei jedem Start, dass die Dateien aus dem Internet stammen.
3. ZIP auf den USB-Stick entpacken, z. B. nach `E:\BuyCheck`.

   Alternativ mit Git:

   ```bash
   git clone https://github.com/grundig23/buycheck
   ```

4. **Probelauf am eigenen PC** (sehr empfohlen): `Start-BuyCheck.cmd` doppelklicken und im Menü
   **[4] Nur automatische Tests** wählen. Das dauert etwa 3 Minuten. So kennst du den Ablauf und
   merkst, ob alles funktioniert.

Auf dem Stick sollten danach etwa 100 MB frei bleiben (Berichte und Windows-Akkubericht).

---

## 2. Beim Verkäufer starten

1. Laptop **ans Netzteil**, einschalten, anmelden lassen.
2. USB-Stick einstecken, Ordner `BuyCheck` öffnen, **`Start-BuyCheck.cmd` doppelklicken**.
3. Die Windows-Abfrage („Möchten Sie zulassen, dass …“) mit **Ja** bestätigen.
4. Das Menü erscheint im Konsolenfenster.

**Das Gerät ist zurückgesetzt (Windows-Ersteinrichtung)?** In der Einrichtung öffnet **Umschalt+F10**
eine Eingabeaufforderung mit Administratorrechten. Dort nacheinander eingeben (Laufwerksbuchstabe des
Sticks anpassen):

```bat
E:
```

```bat
cd \BuyCheck
```

```bat
Start-BuyCheck.cmd
```

Dabei wird nichts eingerichtet und kein Konto angelegt.

**Doppelklick tut nichts / Fenster geht sofort zu?** Rechtsklick auf `Start-BuyCheck.cmd` →
„Als Administrator ausführen“. Oder in einer Eingabeaufforderung:

```bat
powershell -NoProfile -ExecutionPolicy Bypass -File E:\BuyCheck\BuyCheck.ps1
```

`-ExecutionPolicy Bypass` gilt nur für diesen einen Aufruf und ändert keine Einstellung.

---

## 3. Auswahl im Menü

```
==============================================================================
  Was soll geprüft werden?
==============================================================================
  [1] Schnellcheck vor Ort
      ... 26 Tests, ca. 23 Min. + Zeit für deine Eingaben (10 Tests mit Mithilfe).
  [2] Gründlich (mit Langzeittests)
  [3] Linux-Plan (ohne Windows-Themen)
  [4] Nur automatische Tests (ohne Mithilfe)

  [A] Auswahl anpassen: einzelne Tests an-/abwählen, Dauer ändern
  [Q] Beenden
```

| Voreinstellung | Tests | Dauer (ohne deine Eingaben) | Gedacht für |
|---|---|---|---|
| **[1] Schnellcheck** | 26 | ca. 23 Min. | den Termin beim Verkäufer |
| **[2] Gründlich** | 31 | ca. 55 Min. | mehr Zeit; zusätzlich RAM-Test, kompletter SSD-Lesetest, Entladetest, Bildausgang, Linux-Eignung |
| **[3] Linux-Plan** | 25 | ca. 23 Min. | wenn Linux statt Windows drauf soll: ohne Windows-11-/Lizenzprüfung, dafür mit Linux-Eignung |
| **[4] Nur automatisch** | 16 | ca. 3 Min. | ersten Überblick oder Probelauf, ohne Rückfragen |

Nach der Wahl zeigt BuyCheck die Tests und fragt: **Enter** = starten, **A** = anpassen, **Z** = zurück.

**Einzelne Tests anpassen (Taste A).** Alle Tests stehen mit Nummer in einer Liste. Eingaben:

- `4 7 12` oder `3-9`: Tests an- bzw. abwählen
- `?4`: Beschreibung von Test 4 anzeigen
- `D4`: Dauer bzw. Umfang von Test 4 ändern (z. B. Belastungstest 10 statt 4 Minuten)
- `S`, `G`, `L`, `A`: Voreinstellung Schnell, Gründlich, Linux oder Automatisch laden
- Enter: fertig

Mit `*` markierte Tests brauchen deine Mithilfe. Eine eigene Auswahl merkt sich BuyCheck in
`BuyCheck-Auswahl.txt` auf dem Stick. Beim nächsten Start erscheint sie als zusätzlicher Menüpunkt.

---

## 4. Während der Tests

Die automatischen Tests laufen von selbst. Lange Tests zeigen eine Fortschrittszeile und lassen sich mit
**Esc** abbrechen. Bei den Mitmach-Tests sagt BuyCheck jeweils, was zu tun ist:

| Test | Was du tust |
|---|---|
| Netzteil & Laden | Netzteil auf Aufforderung abziehen und wieder anstecken (Wackelkontakt?) |
| Pixeltest | Das Fenster wird nacheinander einfarbig. Mit **Alt+Enter** (Windows Terminal: auch F11) wird es Vollbild. Leertaste = nächste Farbe, Esc = Ende. Danach angeben, was dir aufgefallen ist |
| Tastatur | Jede Taste einmal drücken, erkannte Tasten werden grün. **Esc dreimal** = fertig. Windows-Taste zuletzt, Startmenü mit Esc schließen. Nicht Alt+F4 drücken |
| Touchpad | Mit dem Zeiger alle Bildschirmbereiche anfahren, dann Links-, Doppel- und Rechtsklick |
| USB | Ein **zweites** USB-Gerät nacheinander in jeden Anschluss stecken. **Den BuyCheck-Stick nicht abziehen!** Fertig mit Enter |
| Lautsprecher | Lautstärke selbst auf etwa die Hälfte stellen, Töne links/rechts und eine Tonfolge anhören |
| Mikrofon | 5 Sekunden sprechen, die Aufnahme wird sofort abgespielt. Sie bleibt nur im Arbeitsspeicher |
| Webcam | Die Kamera-App öffnet sich (ab Windows 8). Bild prüfen, App schließen |
| Belastungstest | Etwa 4 Minuten volle Last. Auf das Lüftergeräusch achten (Schleifen? Rattern?) |
| Sichtprüfung | Am Ende jeden Punkt der Checkliste mit J (ok), N (Problem) oder S (nicht geprüft) beantworten |

Tipp: Die Sichtprüfung aus `CHECKLISTE.md` kannst du erledigen, während Belastungs- oder Lesetests laufen.

---

## 5. Das Ergebnis

Am Ende zeigt BuyCheck das Gesamturteil und alle kritischen Befunde und Warnungen. Der Bericht liegt
auf dem Stick unter `Berichte\<Datum>_<Hersteller>_<Modell>_<Seriennummer>\`:

| Datei | Inhalt |
|---|---|
| `BuyCheck-Bericht.html` | Vollständiger Bericht für den Browser, mit Diagrammen, druckbar. Am besten zu Hause öffnen |
| `BuyCheck-Bericht.txt` | Derselbe Bericht als Text, z. B. für das Handy oder den Editor |
| `akkubericht-windows.html` | Der Akkubericht von Windows (ab Windows 8) |
| `protokoll.txt` | Mitschrift der Konsolenausgabe |
| `diagnose.txt` | Technische Details zu Abfragen, die auf diesem Gerät nicht möglich waren (für die Fehlersuche) |
| `BuyCheck-Daten.json` | Alle Befunde maschinenlesbar (ab PowerShell 3) |

**Bewertungsstufen:** **KRITISCH** spricht deutlich gegen den Kauf oder muss vorher geklärt werden.
**WARNUNG** sollte geklärt und im Preis berücksichtigt werden. **HINWEIS** dient zur Information.
**OK** ist in Ordnung. **N. PRÜFB.** konnte auf diesem Gerät nicht geprüft werden.

Der Bericht enthält einen **Textbaustein für den Kaufvertrag** mit Gerät, Seriennummer, Zustand und
festgestellten Mängeln. Zugesicherte Eigenschaften gelten auch bei „gekauft wie gesehen“. Das ist
keine Rechtsberatung.

---

## 6. Ältere und schwächere Geräte

BuyCheck ist bewusst sparsam gebaut, damit es auch auf langsamen Geräten (Celeron, 4 GB RAM,
eMMC-Speicher) flüssig läuft:

- nichts wird kompiliert, keine grafische Oberfläche, reine Textkonsole
- die Lasttests nutzen in Windows eingebaute Funktionen (Hashing, Speicherkopie, direktes Lesen)

Auf älterem Windows fehlen manche Abfragen. Der Bericht weist darauf hin:

| Einschränkung | betrifft |
|---|---|
| NVMe-Gesundheitswerte direkt aus Windows erst ab Windows 10 | Windows 7/8/8.1 mit NVMe-SSD (selten). SATA-SSDs und Festplatten werden über SMART geprüft |
| CPU-Name direkt vom Prozessor erst ab Windows 8.1/10 | Der Fälschungscheck läuft trotzdem über die Chip-Architektur |
| Windows-Akkubericht mit Kapazitätsverlauf erst ab Windows 8 | Gesundheit, Zyklen und Entladetest gehen trotzdem |
| Secure-Boot-Status erst ab Windows 8, Kamera-App erst ab Windows 8 | Windows 7 |
| Hinter Intel-RST/VMD-Treibern liefern manche SSDs keine Werte | einzelne Geräte aller Windows-Versionen |
| Eingelöteter eMMC-Speicher hat keine SMART-Werte | sehr günstige Geräte. Der Lesetest funktioniert trotzdem |

---

## 7. Probleme und Lösungen

| Problem | Lösung |
|---|---|
| Fenster öffnet sich und schließt sofort | `Start-BuyCheck.cmd` per Rechtsklick „Als Administrator ausführen“ oder den PowerShell-Befehl aus Abschnitt 2 nutzen. Die Fehlermeldung bleibt dann stehen |
| „Ausführung von Skripts ist deaktiviert“ / „eingeschränkte Skripte“ | Firmenrichtlinie oder S-Modus. Hier kann BuyCheck nicht laufen |
| Virenscanner meldet BuyCheck | BuyCheck liest sehr viele Systeminformationen, das wirkt für manche Scanner verdächtig. Quelltext ist offen einsehbar. Nicht den Scanner des Verkäufers abschalten! |
| Tastaturtest: F11 wird nicht grün | Im Windows Terminal ist F11 mit Vollbild belegt. F11 nochmal drücken, im Abschlussdialog „gibt es auf dem Gerät nicht“ wählen bzw. von Hand prüfen |
| Touchpad-Test: nach Rechtsklick erscheint Text | Das Terminal hat die Zwischenablage eingefügt. BuyCheck verwirft das, es ist harmlos |
| Mikrofon nimmt nur Stille auf | Mikrofon-Taste/-Schalter prüfen. Unter Windows 10/11 kann der Datenschutz („Mikrofonzugriff für Desktop-Apps“) sperren. Das ändert BuyCheck bewusst nicht |
| Keine SSD-Werte („nicht prüfbar“) | siehe Abschnitt 6. Nach dem Kauf mit CrystalDiskInfo prüfen |
| Bericht liegt in `%TEMP%` statt auf dem Stick | Der Stick war schreibgeschützt oder voll. Bericht von dort kopieren und den Ordner danach löschen |
| Etwas anderes geht schief | `diagnose.txt` und `protokoll.txt` aus dem Berichtsordner helfen bei der Fehlersuche |

---

## 8. Nach dem Kauf (zu Hause)

Diese Prüfungen schreiben auf das Gerät oder brauchen einen Neustart. Deshalb macht BuyCheck sie
nicht beim Verkäufer:

1. **Windows neu installieren**, damit keine Altlasten oder versteckte Software bleiben. Bei
   Geräten ab Windows 8 steckt der Lizenzschlüssel meist im BIOS (siehe Bericht) und die Aktivierung
   läuft automatisch.
2. **SSD-Schreibtest** mit H2testw (Windows) oder f3 (Linux) über den freien Speicher. Er deckt
   Kapazitätsfälschungen und eine sehr niedrige Dauerschreibrate auf.
3. **RAM vollständig testen**: Windows-Speicherdiagnose (`mdsched.exe`) oder MemTest86 vom USB-Stick.
4. **SSD-Werte** mit CrystalDiskInfo, falls BuyCheck sie nicht lesen konnte.
5. **BIOS/UEFI-Update** von der Herstellerseite.
6. Bei Drosselung oder Hitze im Belastungstest: Lüfter und Kühlkörper reinigen bzw. Wärmeleitpaste
   erneuern lassen.

---

## 9. Grenzen und Teststand

- Software kann nicht alles sehen. Ein plötzlicher Ausfall (z. B. SSD-Controller), alte
  Flüssigkeitsschäden oder Wackelkontakte, die erst später auftreten, sind nie ganz auszuschließen.
- Ein gezielt präpariertes Windows kann Werte verfälschen. BuyCheck vergleicht deshalb mehrere
  unabhängige Quellen: Registry, Windows-Kernel, Firmware (SMBIOS) und das Gerät selbst (NVMe, EDID,
  Akku-Chip). Details: [`RECHERCHE.md`](RECHERCHE.md), Abschnitt 12.
- **Teststand:** BuyCheck wurde ohne echten Windows-Laptop entwickelt. Geprüft wurde in einer
  Simulation, die Windows-Antworten Byte für Byte nachbildet:
  - drei Geräte-Szenarien mit eingebauten Fallen, darunter ein Windows-7-Gerät
  - das Textmenü und das Hauptskript im Ganzen
  - eine Kontrolle, dass nie mit Schreibrechten auf einen Datenträger zugegriffen wird
  - eine automatische Prüfung auf PowerShell-2.0-Kompatibilität

  Ein echter Lauf steht noch aus. Deshalb vor dem Termin unbedingt den **Probelauf am eigenen PC**
  machen (Abschnitt 1).

---

## 10. Aufbau (für Neugierige und eigene Erweiterungen)

```
Start-BuyCheck.cmd     Starter (Doppelklick)
BuyCheck.ps1           Hauptprogramm: Neustart mit Adminrechten, Menü, Ablauf, Bericht
lib/Core.ps1           Testregistrierung, Befunde, Datensammler (WMI, Registry, Datenträger, Akku …)
lib/Native.ps1         direkte Windows-Funktionen ohne Compiler (NVMe, SMBIOS, CPU, Konsole …)
lib/Ui.ps1             Textoberfläche und Auswahlmenü
lib/Interactive.ps1    Mitmach-Tests (Farben, Tastatur, Touchpad, USB, Töne, Mikrofon)
lib/Workloads.ps1      Belastungs- und Lesetests (nur lesend)
lib/CpuDb.ps1          Prozessor-Datenbank (Generation ↔ Architektur, Windows-11-Liste)
lib/Report.ps1         HTML- und Textbericht
checks/*.ps1           die einzelnen Tests
```

Ein neuer Test ist eine Datei in `checks/`. Er erscheint automatisch im Menü:

```powershell
Register-BuyCheck -Id 'beispiel.test' -Category 'System & Protokolle' -Title 'Mein Test' `
    -Description 'Was der Test prüft.' -Seconds 5 -Profiles @('quick', 'thorough') -Run {
    Add-BCFinding -Level OK -Title 'Alles in Ordnung'
}
```

Damit BuyCheck auch auf Windows 7 läuft, verwenden die Skripte nur Sprachmittel von PowerShell 2.0.
Also kein `[ordered]` und kein `[pscustomobject]` (stattdessen `New-BCOrdered` / `New-BCObject`), kein
`-in` und kein `Get-CimInstance` (stattdessen `Get-BCWmi`).
