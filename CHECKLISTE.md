# BuyCheck – Checkliste für den Gebrauchtlaptop-Kauf

Zum Ausdrucken und Abhaken. Hintergründe stehen in `RECHERCHE.md`, die Bedienung von BuyCheck in `README.md`.

---

## A. Vor dem Termin

- [ ] Anzeige gesichert (Screenshot): Modell, Ausstattung, Preis, Zustandsbeschreibung, Fotos
- [ ] Dem Verkäufer vorab geschrieben:
  - [ ] Woher stammt das Gerät? Gibt es eine Rechnung?
  - [ ] Wurde etwas repariert oder getauscht (Akku, SSD, Display, Tastatur)?
  - [ ] Ist ein BIOS-Passwort gesetzt? Ist es ein ehemaliges Firmengerät?
  - [ ] Ist das Original-Netzteil dabei?
  - [ ] Darf ich das Gerät vor Ort etwa 45 Minuten mit einem Prüfprogramm vom USB-Stick testen?
- [ ] Treffpunkt mit Steckdose und Tisch (möglichst beim Verkäufer zu Hause, nicht auf der Straße)
- [ ] Vorab nur geschrieben, ohne Vorkasse, Links oder „Zahlungsseiten“ (Betrugsmaschen, siehe RECHERCHE 1.3)

## B. Mitnehmen

- [ ] USB-Stick mit BuyCheck (vorher am eigenen PC getestet!)
- [ ] Zweites USB-Gerät für den Anschlusstest (Maus, zweiter Stick oder Handy mit Kabel)
- [ ] Kopfhörer (Kopfhöreranschluss)
- [ ] Handy (Hotspot für den WLAN-Test, Taschenlampe für Anschlüsse und Lüftungsschlitze)
- [ ] Optional: Monitor/Fernseher-Zugang und Kabel (HDMI/USB-C) für den Bildausgang
- [ ] Ausgedruckt: diese Checkliste und ein einfacher Kaufvertrag zum Ausfüllen (Vordrucke für Privatverkäufe gibt es kostenlos im Internet)

## C. Vor Ort – erst ansehen (Gerät noch aus)

- [ ] **Akku nicht aufgebläht:** Touchpad liegt flach, kein Spalt im Gehäuse, Gerät wackelt nicht auf dem Tisch. Bei Verdacht nicht kaufen (Brandgefahr)!
- [ ] **Keine Flüssigkeitsspuren:** keine Korrosion oder weißen Ablagerungen an Anschlüssen und Lüftungsschlitzen, keine klebrigen Tasten, kein muffiger Geruch
- [ ] Gehäuse ohne Risse, Brüche und starke Dellen (Ecken, Deckel, rund um die Scharniere)
- [ ] Scharniere: Deckel hält jede Position, kein Knacken, kein Spiel, Deckel nicht verzogen
- [ ] Alle Schrauben vorhanden und nicht vermurkst (sonst war das Gerät geöffnet: nachfragen)
- [ ] Gummifüße vorhanden
- [ ] Display: keine Kratzer, Druckstellen, Tastaturabdrücke
- [ ] Tastatur: keine fehlenden oder wackeligen Tasten
- [ ] **Seriennummer vom Typenschild notieren:** ____________________
- [ ] Netzteil: Original? Wattzahl passt? Kabel ohne Knicke, Brandspuren oder abisolierte Stellen?

## D. Einschalten

- [ ] Startet ohne Fehlermeldung und Piepcodes
- [ ] Verkäufer meldet sich an (oder das Gerät steht in der Windows-Ersteinrichtung, siehe README)
- [ ] Netzteil angeschlossen lassen

## E. BuyCheck laufen lassen

- [ ] USB-Stick einstecken, `Start-BuyCheck.cmd` doppelklicken, Windows-Abfrage mit „Ja“ bestätigen
- [ ] Im Menü **[1] Schnellcheck** wählen (oder **[2] Gründlich**, wenn genug Zeit ist)
- [ ] Mitmach-Tests nach Anleitung erledigen (Tastatur, Touchpad, USB, Töne, Mikrofon, Kamera, Netzteil)
- [ ] Während der langen Tests die Punkte aus C vervollständigen
- [ ] Beim Belastungstest auf den Lüfter hören: dreht hörbar hoch, gleichmäßig, kein Schleifen oder Rattern?
- [ ] Am Ende die Sichtprüfung im Programm beantworten
- [ ] **BIOS-Passwort (nach BuyCheck, optional):** neu starten, BIOS-Taste (F2/Entf/F1/F10) drücken, nur ansehen, nichts ändern. Fragt es nach einem Passwort, ist eines gesetzt

## F. Ergebnis besprechen

- [ ] Alle **KRITISCH**-Befunde durchgehen (z. B. gefälschte CPU/SSD, BIOS-Supervisor-Passwort, Autopilot-Firmensperre, stark verschlissener Akku, Lesefehler der SSD)
- [ ] Alle **WARNUNG**-Befunde durchgehen
- [ ] Seriennummer im Bericht (BIOS) = Seriennummer vom Typenschild?
- [ ] Bericht liegt auf dem USB-Stick (`Berichte\…`)

## G. Kaufvertrag

- [ ] Namen und Anschriften beider Seiten (Ausweis zeigen lassen), Datum, Preis
- [ ] Gerät mit **Seriennummer**
- [ ] Zugesicherte Eigenschaften und bekannte Mängel (die wichtigsten Befunde aus dem Bericht)
- [ ] Versicherung des Verkäufers: Eigentümer, nicht gestohlen, kein BIOS-Passwort, keine Firmenverwaltung (Autopilot/Intune)
- [ ] Bezahlung erst bei Übergabe, Netzteil und Zubehör mitnehmen
- [ ] Verkäufer hat sein Microsoft-Konto vom Gerät entfernt (bzw. setzt das Gerät mit dir zusammen zurück)

## H. Zu Hause (siehe README, „Nach dem Kauf“)

- [ ] Windows neu installieren (oder Linux, falls geplant)
- [ ] SSD-Schreibtest mit H2testw (deckt Kapazitätsfälschungen auf)
- [ ] RAM-Test mit Windows-Speicherdiagnose oder MemTest86
- [ ] SSD-Werte mit CrystalDiskInfo (falls BuyCheck sie nicht lesen konnte)
- [ ] BIOS-Update von der Herstellerseite
