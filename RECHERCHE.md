# Recherche: Gebrauchten Laptop vor dem Kauf prüfen

**Stand:** 15.11.2026 · **Zweck:** Grundlage für das Prüfskript in diesem Repo (`BuyCheck.ps1`).
Dieses Dokument erklärt, **welche Risiken** es beim Kauf eines gebrauchten Laptops (z. B. über
Kleinanzeigen) gibt, **woran man sie erkennt** und **mit welchen Grenzwerten** das Skript arbeitet.
Quellen stehen jeweils am Abschnittsende und gesammelt am Schluss.

> **Lesehilfe:** Abschnitte mit 🔧 beschreiben, wie das Skript den Punkt technisch prüft.
> Abschnitte mit 👀 sind Dinge, die nur ein Mensch vor Ort prüfen kann (siehe auch `CHECKLISTE.md`).

---

## Inhalt

0. [Kurzfassung: Die 15 wichtigsten Punkte](#0-kurzfassung-die-15-wichtigsten-punkte)
1. [Rahmen: Privatkauf über Kleinanzeigen](#1-rahmen-privatkauf-über-kleinanzeigen)
2. [Datenträger (SSD/HDD)](#2-datenträger-ssdhdd)
3. [Akku und Netzteil](#3-akku-und-netzteil)
4. [Prozessor (CPU) und Kühlung](#4-prozessor-cpu-und-kühlung)
5. [Arbeitsspeicher (RAM)](#5-arbeitsspeicher-ram)
6. [Display und Grafik](#6-display-und-grafik)
7. [Firmen- und Diebstahlsperren, Herkunft](#7-firmen--und-diebstahlsperren-herkunft)
8. [Windows: Support-Ende, Windows 11, Lizenz](#8-windows-support-ende-windows-11-lizenz)
9. [Linux-Eignung](#9-linux-eignung)
10. [Eingabegeräte, Anschlüsse, Funk, Audio, Kamera](#10-eingabegeräte-anschlüsse-funk-audio-kamera)
11. [Physische Prüfung (was kein Skript kann)](#11-physische-prüfung-was-kein-skript-kann)
12. [Grenzen von Software-Tests](#12-grenzen-von-software-tests)
13. [Von der Recherche zum Skript: Zuordnung Risiko → Test](#13-von-der-recherche-zum-skript-zuordnung-risiko--test)
14. [Quellen](#14-quellen)

---

## 0. Kurzfassung: Die 15 wichtigsten Punkte

1. **SSD-Zustand ist der wichtigste Einzelwert.** NVMe-SSDs melden „Percentage Used“ (verbrauchte
   Lebensdauer), „Available Spare“ (Reserveblöcke) und „Media and Data Integrity Errors“
   (nicht korrigierbare Fehler). Jeder Medienfehler und jede kritische Warnung ist ein klares Warnsignal.
2. **SMART-Werte können manipuliert sein.** Bei Festplatten ist das 2025 im großen Stil passiert
   (Seagate-„FARM“-Skandal). Bei SSDs ist es seltener, aber technisch möglich. Deshalb prüft man
   die Werte **auf Plausibilität** gegeneinander und gegen das Alter des Geräts.
3. **Gefälschte SSDs gibt es in zwei Varianten:** Fake-Kapazität (meldet 1 TB, speichert viel weniger)
   und Marken-Fälschungen (z. B. falsche „Samsung 990 Pro“ mit fremdem Controller). Vor dem Kauf
   erkennbar über den **PCI-Hersteller-Code des Controllers** und die vom Controller gemeldete Kapazität;
   Schreib-/Prüftests (H2testw/f3) und Dauerschreibrate gehören erst **nach** dem Kauf dazu, weil sie auf
   die SSD schreiben.
4. **Akku:** Verhältnis aktuelle Vollkapazität zu Designkapazität (≥ 80 % gut, < 60 % Tausch einplanen).
   Der Windows-Akkubericht zeigt zusätzlich den **Kapazitätsverlauf**. Sprünge nach oben deuten auf
   Akkutausch oder umprogrammierte Akku-Elektronik hin.
5. **Aufgeblähter Akku = nicht kaufen.** Erkennbar an angehobenem Touchpad, Spalt im Gehäuse oder einem
   Laptop, der auf dem Tisch wackelt. Das ist ein Sicherheitsrisiko.
6. **CPU-Namensfälschung ist real.** Einfach per Registry (Name in „Systemeigenschaften“) oder
   raffinierter per Firmware. 2025/2026 wurden so z. B. bei Chuwi und Ninkear Ryzen 5 5500U als
   „Ryzen 5 7430U“ verkauft; sogar CPU-Z/HWiNFO/AIDA64 fielen darauf herein. Entlarvt wird das über
   die **Architektur des Chips** (Familie/Modell, Codename, L3-Cache).
7. **Kühlung:** Verstaubte Lüfter und ausgetrocknete Wärmeleitpaste führen zu **Drosselung**
   (Throttling). Erkennbar mit einem Belastungstest, der Taktrate und Leistung über die Zeit misst.
8. **BIOS-Supervisor-Passwort:** Bei Business-Geräten (v. a. ThinkPad) ist ein unbekanntes
   Supervisor-Passwort praktisch nicht entfernbar. Ohne Zugriff aufs BIOS kann man z. B. nicht
   von einem USB-Stick booten. **Für eine Linux-Installation ist das K.-o.-Kriterium.**
9. **Firmensperren:** Ehemalige Firmengeräte können per **Windows Autopilot** an die alte Firma gebunden
   sein. Nach dem Zurücksetzen verlangt Windows dann einen Firmen-Login. Der einzig sichere Test ist ein
   Reset mit Internetverbindung.
10. **Diebstahl:** Gestohlene Sachen kann man in Deutschland **nicht gutgläubig erwerben** (§ 935 BGB).
    Der Eigentümer kann den Laptop zurückverlangen. Deshalb: Herkunft und Rechnung erfragen,
    Seriennummer im BIOS mit dem Aufkleber vergleichen.
11. **Windows 10** hat seit 14.10.2025 keinen regulären Support mehr. Privatnutzer bekommen über das
    ESU-Programm Sicherheitsupdates **bis 12.10.2027** (offiziell von Microsoft verlängert). Wer
    Windows nutzen will, braucht ein Windows-11-taugliches Gerät (TPM 2.0, Secure Boot, unterstützte CPU).
12. **Für Linux** sind andere Punkte wichtig: Webcams mit Intel IPU6/IPU7 (oft nicht nutzbar),
    Intel-VMD/RAID-Modus der SSD (Installer sieht die SSD evtl. nicht), Broadcom-WLAN,
    Fingerabdruckleser, Snapdragon/ARM-Geräte (Linux nur eingeschränkt).
13. **Privatkauf heißt meist: keine Gewährleistung.** Aber: Zusicherungen gelten, und verschwiegene
    bekannte Mängel sind arglistige Täuschung. **Prüfergebnisse in den Kaufvertrag schreiben**
    (z. B. „Akku 85 %, SSD-Lebensdauer 92 %“).
14. **Vor Ort testen, bar oder per Echtzeitüberweisung erst nach dem Test zahlen.** Keine Vorkasse
    an Unbekannte. PayPal-Käuferschutz gilt nicht bei Abholung.
15. **Software kann nicht alles prüfen.** Ein präpariertes Windows kann lügen. Deshalb vergleicht das
    Skript mehrere unabhängige Quellen (Registry ↔ Kernel ↔ Firmware ↔ Gerät selbst), und es gibt
    eine Checkliste für die physische Prüfung.

---

## 1. Rahmen: Privatkauf über Kleinanzeigen

### 1.1 Gewährleistung und Zusicherungen
- Bei Privatverkäufen ist ein **Gewährleistungsausschluss** üblich und zulässig („unter Ausschluss
  jeglicher Gewährleistung“). Ein bloßes „keine Garantie“ ist allerdings kein wirksamer Ausschluss.
- Der Ausschluss gilt **nicht**, wenn der Verkäufer einen Mangel **arglistig verschweigt**, also einen
  bekannten Defekt bewusst nicht nennt.
- Was ausdrücklich **vereinbart** wurde (Beschaffenheitsvereinbarung), muss stimmen, auch bei
  Gewährleistungsausschluss. Ob eine Aussage eine Vereinbarung war, muss im Streitfall der Käufer
  beweisen (BGH VIII ZR 186/12). → **Prüfergebnisse und Zusagen schriftlich festhalten.**
  Das Skript erzeugt dafür einen Bericht mit Seriennummer und Datum.

### 1.2 Gestohlene Geräte
- **§ 935 BGB:** Kein gutgläubiger Erwerb an Sachen, die dem Eigentümer gestohlen wurden, verloren
  gingen oder sonst abhandengekommen sind. Der Eigentümer kann den Laptop nach § 985 BGB herausverlangen,
  auch wenn man ihn ahnungslos gekauft hat.
- Warnsignale: Preis deutlich unter Marktwert, keine Rechnung/Originalverpackung, Verkäufer weiß wenig
  über das Gerät, Firmen-Inventaraufkleber, BIOS-Seriennummer passt nicht zum Aufkleber,
  Sperren wie Computrace/Absolute oder ein Firmen-Login (siehe Kapitel 7).
- Empfehlung: Rechnung oder Herkunft erfragen, Kaufvertrag mit Personalien, Seriennummer notieren.

### 1.3 Typische Betrugsmaschen
- Vorkasse an Unbekannte, gefälschte „Kleinanzeigen/PayPal-Bezahlseiten“ (Phishing),
  Wechsel zu WhatsApp/E-Mail, unrealistisch günstige Angebote (Betrug oder Hehlerware).
- **Abholung mit Test vor Ort und Zahlung erst danach** gilt als sicherste Variante.
  PayPal-Käuferschutz greift bei Abholung nicht.
- Seriennummern notieren und Geräte bei Übergabe testen.

### 1.4 Praktische Vorbereitung
- Mit dem Verkäufer **Zeit für den Test vereinbaren** (Schnellcheck ca. 25–30 Min., gründlich 60–90 Min.).
- **Netzteil** muss dabei sein, Steckdose vor Ort.
- Mitbringen: USB-Stick mit dem Skript (und Platz für den Bericht), Kopfhörer, ggf. Handy-Hotspot
  (WLAN-Test), ggf. USB-Maus als Ersatz, falls das Touchpad defekt ist.
- Wenn das Gerät schon zurückgesetzt ist (Windows-Ersteinrichtung): An der Einrichtungsseite öffnet
  **Umschalt+F10** eine Eingabeaufforderung mit Admin-Rechten, aus der das Skript gestartet werden kann.
  Siehe README.

**Quellen:** [ra-kotz.de – Gewährleistungsausschluss](https://www.ra-kotz.de/gewaehrleistungsausschluss-bei-privatkauf-bei-angabe-keine-sonstigen-beschaedigungen.htm) ·
[t3n – Gebrauchtkauf mit Risiko](https://t3n.de/news/gebrauchtkauf-mit-risiko-diese-rechte-haben-kaeufer-wirklich-1722410/) ·
[BGH VIII ZR 186/12](https://rewis.io/urteile/urteil/k2o-12-03-2013-viii-zr-18612/) ·
[§ 935 BGB](https://www.gesetze-im-internet.de/bgb/__935.html) ·
[Verbraucherzentrale Niedersachsen – Betrugsmaschen](https://www.verbraucherzentrale-niedersachsen.de/themen/kaufen-reklamieren/produkte-kaufen/betrugsmaschen-auf-kleinanzeigenportalen-im-internet) ·
[vzhh – Betrug bei Kleinanzeigen](https://www.vzhh.de/themen/einkauf-reise-freizeit/einkauf-online-shopping/betrugsmaschen-kleinanzeigen-im-internet) ·
[GIGA – Abholung bei Kleinanzeigen](https://www.giga.de/artikel/abholung-bei-kleinanzeigen-ist-das-gefaehrlich-welche-betrugsmaschen-gibt-es/)

---

## 2. Datenträger (SSD/HDD)

### 2.1 Wie SSDs altern
- Flash-Speicherzellen vertragen nur eine begrenzte Zahl an Schreib-/Löschzyklen. Hersteller geben die
  Haltbarkeit als **TBW** (Terabytes Written) an. Typische Größenordnung bei Consumer-SSDs:
  grob 150–600 TBW je nach Kapazität.
- Verschlissene Blöcke werden durch **Reserveblöcke** ersetzt. Sind die aufgebraucht, schaltet die SSD
  oft in einen Nur-Lese-Modus oder fällt aus.
- Neben dem Verschleiß gibt es **plötzliche Controller-Ausfälle** ohne Vorwarnung. Diese kann man
  per Software nicht vorhersagen. SMART reduziert das Risiko, schließt es aber nicht aus.

### 2.2 NVMe-Gesundheitswerte (SMART/Health-Log)
NVMe-SSDs liefern ein standardisiertes Gesundheitsprotokoll (Log-Page 02h). Windows kann es ohne
Zusatzsoftware auslesen (siehe 🔧 unten).

| Wert | Bedeutung | Bewertung im Skript |
|---|---|---|
| **Critical Warning** | Bit-Feld: Reserve unter Schwelle, Temperatur, Zuverlässigkeit beeinträchtigt, Nur-Lese-Modus, Backup-Speicher defekt | ≠ 0 → **Kritisch** |
| **Available Spare** / **Threshold** | Verbleibende Reserveblöcke in %, Schwelle vom Hersteller (oft 10 %) | unter Schwelle → **Kritisch**; < 50 % → **Warnung** |
| **Percentage Used** | Herstellerschätzung der verbrauchten Lebensdauer (kann > 100 % gehen) | < 30 % OK · 30–69 % Hinweis · 70–89 % **Warnung** · ≥ 90 % **Kritisch** |
| **Media and Data Integrity Errors** | Nicht korrigierbare Datenfehler (ECC, CRC usw.) | > 0 → **Kritisch** |
| **Error Information Log Entries** | Anzahl Fehlerprotokoll-Einträge. Auch gesunde SSDs zählen hier harmlose Befehlsfehler | nur Info |
| **Power On Hours** | Betriebsstunden | Info + Plausibilität |
| **Power Cycles / Unsafe Shutdowns** | Einschaltvorgänge / harte Abschaltungen (z. B. leerer Akku) | viele unsichere Abschaltungen → Hinweis |
| **Data Units Written/Read** | Geschriebene/gelesene Datenmenge (1 Einheit = 512 000 Byte) | Info + Plausibilität |
| **Temperatur**, Warn-/Kritisch-Zeiten | Aktuelle Temperatur, Minuten über Warn-/Kritischschwelle | Kritisch-Zeit > 0 → Warnung |

Laut Intel bedeutet „Percentage Used = 100“, dass die geschätzte Haltbarkeit verbraucht ist, aber nicht
zwingend einen Defekt. Die Spezifikation legt keine festen Grenzwerte fest. Die Werte oben sind
konservative Faustregeln für eine Kaufentscheidung.

🔧 *Umsetzung:* `IOCTL_STORAGE_QUERY_PROPERTY` mit `StorageDeviceProtocolSpecificProperty` (50),
`ProtocolTypeNvme` (3), `NVMeDataTypeLogPage` (2), Log 02h. Identify Controller über
`StorageAdapterProtocolSpecificProperty` (49) / `NVMeDataTypeIdentify` (1). Das ist der von Microsoft
dokumentierte Weg über den Windows-Standardtreiber `stornvme`. Fallback: `Get-StorageReliabilityCounter`.

### 2.3 SATA-SSDs: SMART-Attribute
SATA-SMART-Attribute sind **herstellerspezifisch**. Wichtige Kennzahlen:

| ID | Name (typisch) | Bedeutung |
|---|---|---|
| 5 | Reallocated Sectors/Blocks | ersetzte defekte Blöcke → > 0 Warnung |
| 9 / 12 | Power-On Hours / Power Cycles | Nutzung, Plausibilität |
| 169, 177, 202, 231, 233 | Remaining Life / Wear Leveling / Percent Lifetime Remain / SSD Life Left / Media Wearout | **Restlebensdauer** (normalisierter Wert meist 100 → 0; Richtung je Hersteller prüfen) |
| 171, 172, 181, 182 | Program/Erase Fail Count | Schreib-/Löschfehler → > 0 Warnung |
| 187 | Reported Uncorrectable Errors | **> 0 → Kritisch** |
| 196, 197, 198 | Reallocation Events / Pending / Offline Uncorrectable | > 0 → Warnung bis Kritisch |
| 199 | UDMA CRC Error Count | Übertragungsfehler (Kabel/Stecker), nicht Verschleiß |
| 241, 242 | Total LBAs Written/Read | Datenmenge (Einheit je Hersteller!) |

Zusätzlich gilt das klassische SMART-Ausfallkriterium: **normalisierter Wert ≤ Schwellwert →
Kritisch** (dann meldet das Laufwerk selbst „Ausfall wahrscheinlich“).

🔧 *Umsetzung:* WMI `root\wmi:MSStorageDriver_FailurePredictData/-Thresholds/-Status`
(12-Byte-Attributblöcke ab Offset 2), Fallback `Get-StorageReliabilityCounter`.

### 2.4 Festplatten (HDD) in älteren Laptops
- Backblaze (Daten von zehntausenden Laufwerken): Die aussagekräftigsten Attribute sind
  **5, 187, 188, 197, 198**. Rund 77 % der ausgefallenen Platten hatten mindestens einen Wert > 0,
  aber nur ca. 4 % der funktionierenden. Backblaze tauscht Platten, sobald 187 > 0 ist.
- Eine HDD im Laptop ist heute vor allem **langsam**. Ein Tausch gegen eine SSD ist sinnvoll und günstig,
  sollte aber in den Preis einfließen.

### 2.5 Manipulation: zurückgesetzte SMART-Werte
- **Belegt bei Festplatten:** Anfang 2025 wurden gebrauchte Seagate-Exos-Platten (u. a. aus
  Krypto-Minen) als Neuware verkauft. Die SMART-Werte waren zurückgesetzt, nur das Seagate-eigene
  FARM-Protokoll zeigte 10 000–15 000 Betriebsstunden. Seagate bestätigte gegenüber heise, dass sich
  SMART-Werte zurücksetzen lassen. Später wurden sogar manipulierte FARM-Werte gefunden.
- **SSDs:** Ein dokumentierter Großfall ist nicht bekannt. Technisch ist das Zurücksetzen per
  Hersteller-/Produktionswerkzeugen (Controller-„MPTools“) möglich. Es gibt Berichte über
  Aufbereiter, die so Verschleiß verbergen.
- **Erkennung über Plausibilität** (macht das Skript):
  - Betriebsstunden, Einschaltzyklen, geschriebene Datenmenge und unsichere Abschaltungen müssen
    zueinander passen. Beispiel: 10 Stunden, aber 20 TB geschrieben, ist unmöglich.
  - Die SSD kann nicht älter sein als die Plattform: Mehr Betriebsstunden als seit Markteinführung
    der CPU vergangen sind, heißt, die SSD stammt aus einem anderen Gerät.
  - Eine „fabrikneue“ SSD (fast 0 Stunden) in einem mehrere Jahre alten Laptop heißt: Sie wurde
    getauscht oder zurückgesetzt. Dann Marke/Modell besonders prüfen (siehe 2.6).

### 2.6 Gefälschte SSDs
1. **Kapazitätsfälschung:** Eine SSD meldet z. B. 1 TB, hat aber nur einen Bruchteil echten Speicher.
   Daten jenseits der echten Kapazität überschreiben ältere Daten oder gehen verloren. Sicher erkennbar
   nur mit einem **Schreib-/Prüftest** über den freien Speicher (Prinzip von H2testw/f3). Weil ein
   Schreibtest den fremden Datenträger verändert, macht BuyCheck ihn **nicht**; empfohlen wird er direkt
   nach dem Kauf. Vor dem Kauf hilft der Abgleich: Bei NVMe-SSDs meldet der Controller seine physische
   Kapazität (TNVMCAP) – ist sie kleiner als die angezeigte Größe, ist die SSD gefälscht.
2. **Marken-Fälschung:** Eine sehr gute Fälschung der Samsung 990 Pro (2026) bestand sogar H2testw und
   war in kurzen Benchmarks fast so schnell wie das Original. Entlarvt wurde sie durch
   - den **Controller**: Maxio MAP1602 statt Samsung (ohne DRAM-Cache),
   - die **Dauerschreibrate**: ca. 261 MB/s statt ca. 1 861 MB/s beim großen Kopiervorgang,
   - die Seriennummer „8888888888“ und Samsung Magician („Non-Samsung“).

   Für den Windows-Check heißt das: Jeder NVMe-Controller hat einen **PCI-Hersteller-Code (VID)**.
   Samsung = `144D`, WD/SanDisk = `15B7`, SK hynix = `1C5C`, Kioxia/Toshiba = `1179`/`1E0F`,
   Micron = `1344`, Intel = `8086`, Solidigm = `025E`; Fremd-Controller z. B. Phison `1987`,
   Silicon Motion `126F`, Maxio `1E4B`, Realtek `10EC`. Eine „Samsung“-SSD mit Nicht-Samsung-VID ist
   praktisch sicher gefälscht. Marken wie Kingston, Crucial (teilweise), Corsair oder Lexar nutzen
   legitim Fremd-Controller. Dort ist eine fremde VID normal.
3. **Billig-SSD statt Marken-SSD:** Kein Betrug im engeren Sinn, aber ein Wertverlust. Ohne DRAM und
   mit QLC-Speicher bricht die Schreibrate nach dem schnellen Zwischenspeicher (SLC-Cache) stark ein.
   Sichtbar wird das im Dauerschreibtest – den macht man aus demselben Grund erst nach dem Kauf. Vor dem
   Kauf geben Modellname, Controller und die (rein lesende) Geschwindigkeitsmessung einen Anhaltspunkt.

### 2.7 Lesbarkeit alter Daten
- Bei manchen TLC-SSDs (bekanntester Fall: Samsung 840 EVO) wurden **lange nicht neu geschriebene
  Daten immer langsamer lesbar**, bis auf ca. 30 MB/s. Ursache war nachlassende Ladung in den Zellen.
- Ein **vollständiger Lesetest** der SSD zeigt solche schwachen Bereiche und echte **Lesefehler**.
  Achtung: Ungenutzte (getrimmte) Bereiche liest der Controller ohne Zugriff auf den Flash „blitzschnell“.
  Aussagekräftig sind die belegten Bereiche.
- JEDEC-Zielwert für Consumer-SSDs: Daten müssen am Ende der Lebensdauer mindestens 1 Jahr stromlos
  bei 30 °C erhalten bleiben. Stark genutzte SSDs halten Daten also kürzer.

### 2.8 Hinweise im Windows-Ereignisprotokoll
Wenn Windows nicht frisch installiert ist, verraten die System-Protokolle Probleme der Vergangenheit:

| Quelle / ID | Bedeutung |
|---|---|
| disk 7 | fehlerhafter Block |
| disk 11 | Controller-/Gerätefehler |
| disk 51 | Fehler bei Auslagerungsvorgang (nicht zwingend Laufwerksdefekt) |
| disk 153 | E/A-Vorgang wiederholt (Timeout) |
| stornvme/storahci/iaStor 129 | Gerät zurückgesetzt (reagierte nicht) |
| Ntfs 55/98/140 | Dateisystemfehler |
| WHEA-Logger | Hardwarefehler (CPU, PCIe, Speicher) |
| Kernel-Power 41 | unerwarteter Neustart (Absturz, Stromausfall, leerer Akku) |
| BugCheck 1001 | Bluescreen |
| MemoryDiagnostics-Results 1202 | Windows-Speicherdiagnose fand Fehler |

Ein einzelner Eintrag ist kein Beweis. Häufungen derselben Art sind ein Warnsignal.

**Quellen:** [Microsoft – Working with NVMe drives](https://learn.microsoft.com/windows/win32/fileio/working-with-nvme-devices) ·
[Microsoft – NVME_HEALTH_INFO_LOG](https://learn.microsoft.com/windows/win32/api/nvme/ns-nvme-nvme_health_info_log) ·
[Intel – NVMe SMART-Attribute](https://www.intel.com/content/www/us/en/support/articles/000056596/processors.html) ·
[libnvme nvme_smart_log](https://man.archlinux.org/man/nvme_smart_log-libnvme3.2.en) ·
[Backblaze – Making Sense of SSD SMART Stats](https://www.backblaze.com/blog/making-sense-of-ssd-smart-stats) ·
[Backblaze – Hard Drive SMART Stats](https://www.backblaze.com/blog/hard-drive-smart-stats/) ·
[Backblaze – What SMART Stats Indicate Hard Drive Failures](https://www.backblaze.com/blog/what-smart-stats-indicate-hard-drive-failures/) ·
[Kingston – SMART-Attribute (PDF)](https://media.kingston.com/kingston/pdf/SMART-attribute.pdf) ·
[Samsung – SSD Application Note SMART (PDF)](https://download.semiconductor.samsung.com/resources/others/SSD_Application_Note_SMART_final.pdf) ·
[Thomas-Krenn – SMART Attributes](https://www.thomas-krenn.com/en/wiki/SMART_Attributes_documentation) ·
[heise – Gebrauchte Seagate-Platten als Neuware](https://heise.de/-10254518) ·
[heise – Manipulierte FARM-Werte](https://heise.de/-10308297) ·
[Tom's Hardware – Seagate-Betrüger manipulieren FARM](https://www.tomshardware.com/pc-components/hdds/seagate-hard-drive-controversy-persists-as-scammers-discover-methods-to-alter-reliability-metrics) ·
[gHacks – Seagate-Betriebsstunden prüfen](https://www.ghacks.net/2025/01/30/how-to-verify-seagate-hard-drives-running-hours-after-used-sold-as-new-scandal/) ·
[PCSP – Used SSD Health Check 2026](https://pcserverandparts.com/news/used-ssd-health-check-2026/) ·
[Tom's Hardware – Fake Samsung 990 Pro](https://www.tomshardware.com/pc-components/ssds/exceptional-fake-ssd-clone-of-samsung-990-pro-is-almost-impossible-to-spot-near-identical-performance-blurs-the-line-between-real-and-fake-as-ai-crunch-drives-knock-off-market) ·
[TechSpot – Fake Samsung 990 Pro](https://www.techspot.com/news/111861-fake-samsung-990-pro-ssd-good-enough-fool.html) ·
[TechSpot – Samsung 840 Lesegeschwindigkeit](https://www.techspot.com/article/997-samsung-ssd-read-performance-degradation/) ·
[PCPer – 840 EVO Read Degradation](https://pcper.com/2014/09/samsung-840-840-evo-susceptible-to-flash-read-speed-degradation-over-time/) ·
[Microsoft – Event ID 51](https://support.microsoft.com/kb/244780/) ·
[TheWindowsClub – Event ID 153](https://thewindowsclub.com/the-io-operation-at-logical-block-address-for-disk-0-was-retried-event-id-153)

---

## 3. Akku und Netzteil

### 3.1 Kennzahlen
- **Designkapazität** (neu) und **aktuelle Vollladekapazität** in mWh. **Gesundheit = Voll ÷ Design.**
- **Ladezyklen:** Ein Zyklus entspricht einer vollen Entladung, auch verteilt auf mehrere Teilentladungen.
  Nicht jedes Gerät meldet Zyklen.
- Bewertung im Skript (orientiert an gängigen Ratgebern, die 70–80 % als Grenze nennen):
  **≥ 80 % OK · 70–79 % Hinweis · 60–69 % Warnung · < 60 % Kritisch (Tausch einplanen).**
- Vollkapazität deutlich **über** der Designkapazität (> 10 %) ist ungewöhnlich. Ein paar Prozent sind
  bei neuen Akkus normal. Mehr deutet auf Nachbau-Akkus mit falschen Daten oder umprogrammierte Werte hin.

### 3.2 Windows-Akkubericht
`powercfg /batteryreport` erzeugt einen Bericht mit installierten Akkus, Kapazitäten und Zyklen sowie
dem **Kapazitätsverlauf seit der Windows-Installation**. Die XML-Variante ist sprachunabhängig und
maschinenlesbar.
- **Sprung der Vollkapazität nach oben** (z. B. von 35 auf 55 Wh) → Akku getauscht oder umprogrammiert.
  Das Skript wertet den Verlauf aus.

### 3.3 Manipulation der Akku-Elektronik
- Akkus haben einen Chip (Fuel Gauge, z. B. TI bq20zxx), der Zyklen, Vollkapazität und Herstelldatum
  speichert. In der Reparaturszene gibt es Werkzeuge, die nach dem „Entsiegeln“ **Zyklenzahl,
  Vollkapazität und Datum ändern** können.
- Das Zurücksetzen der Zyklen macht verschlissene Zellen nicht besser. Missbrauch zum Verschleiern ist
  daher möglich.
- **Erkennung:** Kapazitätsverlauf (s. o.), Plausibilität (0 Zyklen bei mehrere Jahre altem Akku),
  Vergleich mit der Herstellerangabe, Abgleich mit den BIOS-Angaben (SMBIOS-Typ 22) und vor allem ein
  **echter Entladetest**: Unter definierter Last wird gemessen, wie schnell die Ladung sinkt
  (%/min, Watt, Spannung). Schwache Zellen zeigen Spannungseinbrüche und **plötzliche Prozentsprünge**.

### 3.4 Nachbau-Akkus
Generische oder leere Herstellernamen, ungewöhnliche Designkapazitäten und Warnmeldungen
(z. B. Lenovo „nicht originaler Akku“) sind Hinweise auf Nachbau-Akkus. Die halten oft deutlich kürzer.

### 3.5 Aufgeblähter Akku (Sicherheitsrisiko!) 👀
Warnzeichen laut Dell und Razer: angehobenes oder schwergängiges **Touchpad**, gewölbte Tastatur,
**Spalt im Gehäuse**, Laptop **wackelt** auf ebenem Tisch. Ein solches Gerät **nicht kaufen**. Nicht
auf die Wölbung drücken, nicht weiter laden.

### 3.6 Netzteil 👀🔧
- Original-Netzteil mit passender **Leistung** (Watt) mitgeben lassen. Kabel auf Knicke und
  Beschädigungen prüfen.
- Dell meldet beim Start z. B. „The AC power adapter wattage and type cannot be determined“. Ursachen:
  falsches/defektes Netzteil, defekte Buchse oder Ladeschaltung. Folge: kein Laden, Drosselung.
- Ladefunktion testen: Netzteil ab und wieder an. Wird das erkannt und lädt der Akku? Achtung: Viele
  Laptops haben einen **Akkuschonmodus** (lädt nur bis 60/80 %). Das ist kein Defekt.

**Quellen:** [Microsoft – BATTERY_WMI_STATIC_DATA](https://github.com/MicrosoftDocs/sdk-api/blob/docs/sdk-api-src/content/batclass/ns-batclass-battery_wmi_static_data.md) ·
[How-To Geek – Battery Report](https://www.howtogeek.com/217010/how-to-generate-a-battery-health-report-on-windows-8-or-windows-10/) ·
[Tom's Hardware – Battery Report](https://www.tomshardware.com/how-to/battery-health-report-windows) ·
[laptopu.ro – Zyklenzahl im EEPROM ändern](https://www.laptopu.ro/community/laptop-battery-chip-reset-and-repair/modifying-cycle-count-in-eeprom/) ·
[GitHub – Reverse Engineering bq20z70 BMS](https://github.com/omarKmekkawy/Reverse_Engineering_BQ20z70_Laptop_BMS) ·
[HP Community – Zyklen zurücksetzen](https://h30434.www3.hp.com/t5/Notebook-Hardware-and-Upgrade-Questions/To-reset-battery-cycle-count/td-p/8278471) ·
[Dell – Swollen Battery Guidance](https://www.dell.com/support/kbdoc/en-us/000128491/swollen-battery-information-and-guidance) ·
[Razer – Battery issue](https://mysupport.razer.com/app/answers/detail/a_id/3209) ·
[Dell Community – AC adapter type cannot be determined](https://dell.com/community/Latitude/ALERT-The-AC-adapter-wattage-and-type-cannot-be-determined-quot/m-p/7357817)

---

## 4. Prozessor (CPU) und Kühlung

### 4.1 Namensfälschung per Registry
- Windows zeigt den CPU-Namen in „Systemeigenschaften“ und `msinfo32` aus dem Registry-Wert
  `HKLM\HARDWARE\DESCRIPTION\System\CentralProcessor\0\ProcessorNameString`. Dieser Wert wird bei
  jedem Start neu geschrieben. Betrüger überschreiben ihn deshalb per **Autostart/Aufgabenplanung**
  nach jedem Boot, z. B. „Core i7“ statt „Core i3“.
- **Gegenprüfung:** Der Windows-Kernel liefert den echten Namen direkt von der CPU
  (`NtQuerySystemInformation`, Klasse 105 „SystemProcessorBrandString“, intern per CPUID-Befehl). Weicht
  die Registry davon ab, ist sie manipuliert. Das Skript sucht außerdem nach Autostart-Einträgen und
  geplanten Aufgaben, die diesen Wert ändern.

### 4.2 Fälschung per Firmware (Fall Chuwi/Ninkear 2025/2026)
- heise (16.03.2026): Chuwi CoreBook X/Plus und Ninkear A15 Pro wurden mit „Ryzen 5 7430U“ (Zen 3)
  beworben, enthielten aber den älteren **Ryzen 5 5500U** (Zen 2, ca. 15 % langsamer, halber L3-Cache).
- Die **Firmware** war so manipuliert, dass **CPU-Z, AIDA64 und HWiNFO64** den falschen Namen zeigten.
  Bei AMD lässt sich der Namensstring der CPU per Firmware überschreiben.
- Entlarvt wurde das über Details: Codename **Lucienne** (Zen 2) statt Barcelo-R, Basistakt
  ca. 2,1 GHz statt 2,3 GHz, L3-Cache 8 statt 16 MB. Endgültig klar wurde es durch die Teilenummer auf
  dem Chip (100-000000375 statt 100-000001471). Chuwi startete einen Rückruf, CPU-Z 2.19 erkennt den
  Fall inzwischen.
- **Konsequenz fürs Skript:** Nicht nur den Namen lesen, sondern die **Architektur** (CPU-Familie/Modell
  aus dem Kernel) gegen die aus dem Namen erwartete Generation prüfen. Grundlage sind die
  Modelltabellen des Linux-Kernels (Intel) und von LLVM (AMD). Eine CPU kann nie „neuer“ sein als ihre
  Architektur. Außerdem werden L3-Cache, Kerne und Threads für den manuellen Abgleich ausgegeben.

### 4.3 Kühlung und Drosselung (Throttling)
- Mit den Jahren verstopfen Lüfter und Kühlrippen, und die Wärmeleitpaste trocknet aus. Folge: hohe
  Temperaturen, und die CPU **senkt ihren Takt** (Throttling). Ein Neuauftragen der Paste bringt
  laut Berichten oft 8–20 °C. Geräte ab ca. 3 Jahren ohne Wartung gelten als Kandidaten.
- Messbar mit einem **Dauerlasttest**: Leistung und Takt über mehrere Minuten aufzeichnen. Längere
  Zeit 95–100 °C deuten auf ein Kühlproblem. Dünne Ultrabooks drosseln konstruktionsbedingt nach
  dem kurzen Turbo-Boost. Das ist normal und kein Defekt.
- 🔧 Das Skript misst den **effektiven Takt relativ zum Basistakt** (Leistungsindikator „% Processor
  Performance“: 100 % = Basistakt). Unter Dauerlast sollte ein gesundes Gerät mindestens ungefähr den
  Basistakt halten. Zusätzlich: ACPI-Temperaturzonen und deren Drosselanzeige, Leistung pro Zeitabschnitt.
- 👀 Lüftergeräusch während des Tests: Schleifen, Rattern oder Pfeifen deutet auf ein defektes Lüfterlager.

### 4.4 Rechenstabilität
Defekte CPUs, Spannungswandler oder RAM können unter Last **falsch rechnen**. Der Belastungstest des
Skripts rechnet deshalb deterministische Aufgaben und vergleicht die Prüfsummen. Jede Abweichung ist
**kritisch**.

**Quellen:** [heise – Chinesische Notebooks mit falschen Prozessoren (16.03.2026)](https://heise.de/-11212505) ·
[Notebookcheck – Chuwi CoreBook Plus betroffen](https://www.notebookcheck.net/CPU-fraud-next-round-Chuwi-CoreBook-Plus-with-supposed-AMD-Ryzen-5-7430U-also-affected.1248660.0.html) ·
[Notebookcheck – Weitere Marke betroffen](https://www.notebookcheck.net/Another-laptop-brand-affected-by-CPU-fraud-Manufacturer-promises-clarification.1256384.0.html) ·
[Tom's Hardware – Chuwi CPU-Betrug](https://www.tomshardware.com/laptops/popular-budget-friendly-chinese-brand-exposed-for-shocking-cpu-scam-in-its-laptops-advertised-cpu-secretly-swapped-for-an-outdated-chip) ·
[PCWorld – Mislabeled Ryzen CPUs](https://www.pcworld.com/article/3089788/mislabeled-ryzen-cpus-spotted-in-chuwi-and-ninkear-laptops.html) ·
[phnt – SYSTEM_INFORMATION_CLASS (SystemProcessorBrandString)](https://github.com/winsiderss/phnt/blob/master/ntexapi.h) ·
[Linux – intel-family.h](https://github.com/torvalds/linux/blob/master/arch/x86/include/asm/intel-family.h) ·
[LLVM – Host.cpp (AMD-Familien)](https://github.com/llvm/llvm-project/blob/main/llvm/lib/TargetParser/Host.cpp) ·
[Digital Citizen – Thermal Throttling](https://www.digitalcitizen.life/what-is-thermal-throttling-and-how-to-tell-if-your-pc-is-doing-it/) ·
[RTINGS – Performance over time](https://rtings.com/laptop/tests/performance/performance-over-time)

---

## 5. Arbeitsspeicher (RAM)

- **Ausstattung prüfen:** Gesamtgröße, Anzahl/Belegung der Steckplätze, verlötet oder steckbar,
  Takt, Hersteller/Teilenummer (SMBIOS Typ 17). Ein einzelnes Modul in einem Gerät mit zwei Slots
  bedeutet **Single-Channel**. Das bremst vor allem die integrierte Grafik spürbar, ist aber leicht
  nachrüstbar.
- **Speicherfehler** äußern sich in Abstürzen und Datenfehlern. Tests:
  - im laufenden Windows: Test des freien Speichers mit Bitmustern (das Skript, Abdeckung typisch
    60–80 % des RAM),
  - Windows-Speicherdiagnose (`mdsched.exe`, Neustart nötig, Ergebnis im Ereignisprotokoll 1201/1202),
  - MemTest86 vom USB-Stick (vollständigste Prüfung, braucht Boot vom Stick).
  - BuyCheck startet die Windows-Speicherdiagnose bewusst **nicht**: Sie trägt sich in die
    Startkonfiguration des fremden Geräts ein. Beides gehört zu den Schritten nach dem Kauf.
- Eine Manipulation der RAM-Größe per Software ist in Windows praktisch nicht relevant. Wichtiger ist der
  Abgleich der **Anzeige** mit der **Realität**.

---

## 6. Display und Grafik

### 6.1 Pixelfehler und Bildqualität 👀🔧
- Die meisten Notebook-Displays fallen unter **ISO 9241-307 Klasse II**, also eine gewisse Anzahl
  Pixelfehler pro Million Pixel ist zulässig. Beim Gebrauchtkauf zählt aber, was man selbst akzeptiert.
  Helle Dauerpixel stören am meisten.
- Testen: Vollbildfarben (Schwarz, Weiß, Rot, Grün, Blau, Grau) für tote/helle Pixel, Flecken,
  ungleichmäßige Ausleuchtung (Lichthöfe), **Druckstellen** und Streifen.
- **Deckel langsam bewegen:** Flackern oder Streifen deuten auf ein defektes Displaykabel oder Scharnier.

### 6.2 Getauschtes, schlechteres Panel
- Bei Reparaturen wird manchmal ein billigeres Panel eingebaut (TN statt IPS, ca. 45 % NTSC statt
  100 % sRGB, geringere Helligkeit, 60 statt 144 Hz).
- Die **EDID** des Panels (Datenblock im Display) verrät oft **Panelhersteller** (z. B. BOE, AUO, LG
  Display, Innolux/CMN, Sharp, Samsung), die **Panel-Teilenummer** und das **Herstellungsjahr**. Mit der
  Teilenummer lässt sich das Datenblatt (z. B. auf panelook.com) finden. Manche Hersteller überschreiben
  die EDID mit ihrem eigenen Namen.
- Ein Panel, das **deutlich jünger** ist als der Rest des Laptops, wurde vermutlich getauscht. Das ist
  nicht schlimm, wenn die Qualität stimmt.
- 👀 Blickwinkeltest: Bei TN-Panels kippen die Farben schon bei leicht geändertem Blickwinkel.

### 6.3 Grafikkarte
- Gefälschte Grafikkarten (ältere Chips mit neuem Namen) sind vor allem bei Desktop-Grafikkarten
  bekannt. GPU-Z kennzeichnet solche Fälle mit „[FAKE]“. Bei Laptops ist die GPU verlötet. Eine
  Umbenennung wäre nur per Treiber/Registry möglich.
- 🔧 Das Skript zeigt den Namen **und** die PCI-IDs (Hersteller/Gerät) und prüft den Hersteller.
  Die Geräte-ID lässt sich online nachschlagen. Treiberfehler wie **Code 43** („Gerät hat Probleme
  gemeldet“) können auf einen GPU-Defekt hinweisen.

**Quellen:** [GameStar – Pixelfehler bei Laptops](https://www.gamestar.de/artikel/der-tote-punkt-alles-was-ihr-ueber-pixelfehler-bei-laptops-wissen-muesst,3450808.html) ·
[Medion-Handbuch – ISO 9241-307 Klasse II](https://www.manualslib.com/manual/3124669/Medion-E14304.html?page=47) ·
[ThinkPads-Forum – Panel per EDID erkennen](https://www.forum.thinkpads.com/viewtopic.php?p=799850) ·
[HP Community – Falsches Panel nach Reparatur](https://h30434.www3.hp.com/t5/Unanswered-Topics-Notebook/They-replaced-my-screen-with-the-wrong-panel-type/td-p/5793982) ·
[Tom's Hardware – GPU-Z erkennt Fake-GPUs](https://www.tomshardware.com/news/gpu-z-update-detect-fake-nvidia-graphics-cards,37934.html) ·
[PC Gamer – GPU-Z Fake-Erkennung](https://www.pcgamer.com/gpu-z-will-now-tell-you-if-the-nvidia-graphics-card-you-bought-is-a-fake)

---

## 7. Firmen- und Diebstahlsperren, Herkunft

Gebrauchte Business-Laptops (ThinkPad, Latitude, EliteBook/ProBook) sind beliebt und robust. Sie
stammen aber oft aus Firmen-Leasing und haben deshalb eigene Risiken:

| Sperre | Folge | Prüfung |
|---|---|---|
| **BIOS-Supervisor-/Admin-Passwort** | BIOS-Einstellungen gesperrt (Bootreihenfolge, Secure Boot, VMD). Bei ThinkPads ohne Passwort praktisch nicht entfernbar | 🔧 Lenovo/Dell/HP-WMI; 👀 BIOS öffnen (F1/F2/F10/Entf) |
| **Windows Autopilot** (Intune) | Nach Reset verlangt Windows den **Firmen-Login**, das Gerät hängt an der alten Firma | 🔧 Registry `…\Provisioning\Diagnostics\Autopilot` (`CloudAssignedTenantDomain`). Sicher nur: **Reset mit Internet** und die Ersteinrichtung ansehen |
| **Entra ID/Domäne/MDM** | Richtlinien, Fernverwaltung, eventuell Fernlöschung | 🔧 `dsregcmd /status`, Registry `Enrollments` |
| **Absolute/Computrace** | Diebstahlschutz im BIOS. Ein als gestohlen gemeldetes Gerät kann gesperrt werden. Entfernen nur über Absolute/Hersteller | 🔧 Agent-Dateien `rpcnet*.exe` im System; 👀 BIOS-Sicherheitsseite |
| **BitLocker** | Ohne Wiederherstellungsschlüssel sind Daten weg (nach Reset unkritisch) | 🔧 Status anzeigen |
| **Intel AMT/vPro** | Fernwartung auf Hardware-Ebene, falls bereitgestellt | 🔧 Hinweis, falls AMT-Gerät vorhanden |

- Microsoft: Die Autopilot-Profildaten liegen unter `HKLM\SOFTWARE\Microsoft\Provisioning\Diagnostics\Autopilot`.
  `CloudAssignedTenantDomain` ist leer, wenn das Gerät nicht registriert ist (oder das Profil noch nicht
  geladen wurde, deshalb der Reset-Test).
- Absolute: Die Verwaltung des Supervisor-Passworts über Absolute setzt bei Lenovo eine aktivierte
  Absolute Persistence voraus. Foren raten bei aktiviertem Computrace, Absolute mit Seriennummer zu
  kontaktieren. Bei abgemeldeten Leasing-Geräten ist das meist lösbar, bei gestohlenen nicht.
- **Seriennummer:** BIOS-Seriennummer mit dem **Aufkleber** vergleichen. Eine Abweichung heißt:
  Mainboard getauscht oder Aufkleber gefälscht. Über die Herstellerseite (Lenovo/Dell/HP) lässt sich
  mit der Seriennummer oft die **Originalausstattung** und das Garantie-/Auslieferungsdatum abfragen.
  Das ist der beste Abgleich gegen eine geschönte Anzeige.
- **Asset-Tag/Organisation** in den Systemdaten verraten ein ehemaliges Firmengerät. Das ist nicht
  schlimm, aber dann nach der Freigabe fragen.

**Quellen:** [Microsoft – Troubleshoot Autopilot OOBE](https://learn.microsoft.com/en-us/autopilot/troubleshoot-oobe) ·
[Microsoft – Autopilot Troubleshooting FAQ](https://learn.microsoft.com/autopilot/troubleshooting-faq) ·
[Microsoft Q&A – Firmen-Login nach Neuinstallation](https://learn.microsoft.com/en-us/answers/questions/537083/10-pro-asks-for-company-login-after-clean-install) ·
[Microsoft Q&A – Gebrauchter Laptop in Intune registriert](https://learn.microsoft.com/en-us/answers/questions/1348857/used-laptop-microsoft-intune-registered) ·
[Notebookcheck – Buying a used laptop: check these locks](https://www.notebookcheck.net/Buying-a-used-laptop-Check-these-locks-before-you-pay.1442942.0.html) ·
[Absolute – Supervisor-Passwörter verwalten](https://help.absolute.com/corporate/html5/en-en/Content/Device%20Actions/DA_ManageSupervisorPassword.htm) ·
[ThinkPads-Forum – Computrace](https://forum.thinkpads.com/viewtopic.php?p=775374) ·
[Kaspersky Securelist – Absolute Computrace Revisited](https://securelist.com/absolute-computrace-revisited/58278/) ·
[Black Hat 2014 – Computrace Backdoor Revisited (PDF)](https://www.blackhat.com/docs/us-14/materials/us-14-Kamluk-Computrace-Backdoor-Revisited-WP.pdf) ·
[Lenovo – ThinkPad BIOS Setup using WMI (PDF)](https://download.lenovo.com/pccbbs/thinkvantage_en/cdrt_resources/2020_supplement.pdf) ·
[Dell – Prüfen, ob ein BIOS-Passwort gesetzt ist](https://dell.com/support/kbdoc/de-de/000146401/check-if-a-bios-password-is-set) ·
[Swappa – BitLocker bei gebrauchten Laptops](https://swappa.com/blog/bitlocker-recovery-key-used-laptop/)

---

## 8. Windows: Support-Ende, Windows 11, Lizenz

> Im Skript **abwählbar**: Wer Linux installieren will, braucht diese Punkte nicht.

### 8.1 Support-Ende Windows 10
- Windows 10 erreichte das Support-Ende am **14.10.2025**.
- Microsoft hat das **Consumer-ESU-Programm** (kostenlose bzw. günstige Sicherheitsupdates für
  Privatnutzer) laut eigener Seite bis **12.10.2027** verlängert. Teilnahme mit Microsoft-Konto,
  bis zu 10 Geräte. Danach gibt es keine Updates mehr.

### 8.2 Windows-11-Anforderungen
- **TPM 2.0**, **UEFI mit Secure-Boot-Fähigkeit**, ≥ 4 GB RAM, ≥ 64 GB Speicher, 64-Bit-CPU mit
  ≥ 2 Kernen und ≥ 1 GHz, CPU muss die Instruktionen SSE4.2/POPCNT haben (seit 24H2 zwingend).
- **CPU-Liste** laut Microsofts offiziellem Prüfskript (`HardwareReadiness.ps1`):
  - **Intel:** Modelle bis Familie 6 / Modell 95 nicht unterstützt (also bis 7. Generation).
    Ausnahme: Kaby Lake (Modell 142/158, Stepping 9) nur mit bestimmter Plattform-ID
    (z. B. i7-7820HQ im Surface Studio 2/Precision 5520). Ab 8. Generation unterstützt.
  - **AMD:** Familie < 23 nicht unterstützt, außerdem Familie 23 Modell 1 (Ryzen 1000) und
    Modell 17 (Ryzen 2000-APUs/Raven Ridge, z. B. Ryzen 5 2500U). Ab Zen+ (z. B. Ryzen 3000-Mobile) ok.
- Nicht unterstützte Geräte lassen sich per Umgehung installieren, haben aber keinen offiziellen
  Anspruch auf Updates. Für einen Kauf zählt das als Wertminderung.

### 8.3 Lizenz
- Bei Geräten mit vorinstalliertem Windows steckt der Produktschlüssel meist in der Firmware
  (ACPI-Tabelle **MSDM**). Damit aktiviert sich eine Neuinstallation derselben Edition automatisch.
- Aktivierungskanal (`slmgr /dli`): **OEM** ist normal für vorinstallierte Geräte. **Retail** ist bei
  Laptops ungewöhnlich, aber möglich. **Volume:GVLK/KMS** auf einem Privatgerät, besonders mit einem
  KMS-Server auf `127.0.0.x` oder einem unbekannten Host, deutet auf einen **illegalen KMS-Aktivator**
  hin. Die sind auch ein Malware-Risiko. → Neuinstallation einplanen.

**Quellen:** [Microsoft – Windows 10 Extended Security Updates](https://www.microsoft.com/en-us/windows/extended-security-updates) ·
[BleepingComputer – ESU bis Oktober 2027](https://www.bleepingcomputer.com/news/microsoft/microsoft-quietly-extends-free-windows-10-esu-support-to-october-2027/) ·
[Microsoft – HardwareReadiness.ps1](https://aka.ms/HWReadinessScript) ·
[Pureinfotech – Windows 11 system requirements 2026](https://pureinfotech.com/windows-11-system-requirements/) ·
[Dell – Windows 11 Mindestanforderungen](https://www.dell.com/support/kbdoc/en-us/000189820) ·
[Microsoft – OEM-Aktivierungsschlüssel validieren](https://learn.microsoft.com/en-us/troubleshoot/windows-client/licensing-and-activation/validate-oem-activation-key)

---

## 9. Linux-Eignung

> Im Skript als eigener, **abwählbarer** Test „Linux-Eignung“.

| Bauteil | Risiko unter Linux (Stand 2026) | Erkennung unter Windows |
|---|---|---|
| **Webcam mit Intel IPU6/IPU7** (MIPI-Kamera, viele Business-Geräte ab ca. Intel 12. Gen) | Häufigster Problemfall: oft nicht oder nur mit sehr neuem Kernel + libcamera nutzbar | Gerät „Intel(R) AVStream Camera“/IPU-Geräte; USB-Kameras (UVC) sind unproblematisch |
| **Intel VMD / RST „RAID On“** | Installer sieht die NVMe-SSD evtl. nicht. Lösung: VMD im BIOS abschalten (→ **BIOS-Zugang nötig**), vorher Windows vorbereiten | Speicher-Controller „Intel RST VMD“/`iaStorVD` |
| **WLAN Broadcom** | Häufig proprietärer Treiber nötig, teils nicht unterstützt | PCI-Hersteller `14E4` |
| **WLAN Intel** | Sehr gut unterstützt | `8086` |
| **WLAN Realtek/MediaTek** | Meist ok mit aktuellem Kernel, ältere Distributionen evtl. nicht | `10EC` / `14C3` |
| **Fingerabdruckleser** | Oft nicht unterstützt (libfprint-Liste prüfen) | Geräteklasse „Biometric“, USB-ID |
| **NVIDIA-Hybridgrafik** | Funktioniert mit proprietärem Treiber, Einrichtung aufwendiger | PCI `10DE` |
| **Snapdragon X (ARM)** | 1. Generation: laut Phoronix (Ubuntu 26.04) weiterhin „lackluster“. Offizieller Qualcomm-Support erst für X2 | CPU-Architektur ARM64 |

**Quellen:** [Intel ipu6-drivers Issue #356](https://github.com/intel/ipu6-drivers/issues/356) ·
[IPU6-Kamera unter Ubuntu (2026)](https://www.mathiashove.com/blog/2026/getting-ipu6-camera-working-on-ubuntu) ·
[Launchpad – Storage mit Intel RAID On nicht sichtbar](https://answers.launchpad.net/bugs/1871812) ·
[Fedora Discussion – Intel RST](https://discussion.fedoraproject.org/t/intel-rapid-storage-technology-rst-and-fedora/130024) ·
[ubuntu.fan – Intel RST](https://ubuntu.fan/en/docs/guide/installation/intel-rst) ·
[Qubes OS – Hardware Compatibility List](https://www.qubes-os.org/hcl/) ·
[Phoronix – Snapdragon X Elite unter Ubuntu 26.04](https://phoronix.com/review/ubuntu-2604-snapdragon-x-elite) ·
[OSnews – Tuxedo stoppt Snapdragon-Linux-Laptop](https://www.osnews.com/story/143893/tuxedo-cancels-snapdragon-x-elite-linux-laptop-project/) ·
[Tom's Hardware – Qualcomm Linux-Support](https://www.tomshardware.com/software/linux/qualcomm-goes-where-apple-wont-readies-official-linux-support-for-snapdragon-x-elite)

---

## 10. Eingabegeräte, Anschlüsse, Funk, Audio, Kamera

| Komponente | Typische Probleme | Test im Skript |
|---|---|---|
| Tastatur | einzelne tote Tasten, klebende Tasten (Flüssigkeit!), glänzende Tasten (viel Nutzung) | Tastaturtest: jede Taste drücken, Layout färbt sich |
| Touchpad | Klicks, Mehrfinger-Scrollen, „Springen“ | Bewegung, Links/Rechtsklick, Scrollen |
| USB-Ports | Wackelkontakt, tote Ports | Live-Erkennung beim Einstecken in jeden Port |
| Bildausgang (HDMI/USB-C) | defekte Buchse | externer Monitor wird erkannt? |
| Lautsprecher | Kratzen, ein Kanal tot | Ton links/rechts |
| Mikrofon | tot, Rauschen | Aufnahme + Wiedergabe + Pegel |
| Webcam | defekt, im BIOS deaktiviert | Kamera-App, Gerätestatus |
| WLAN/Bluetooth | Antennenkabel ab (schwacher Empfang), Karte defekt | Adapter vorhanden, Netze/Signal |
| Geräte-Manager | Fehlercodes, **deaktivierte Geräte** (können Defekte verbergen) | automatische Auswertung |

Hinweis WLAN: Seit Windows 11 24H2 brauchen WLAN-Scans (auch `netsh wlan show networks`) die
**Standortberechtigung**. Ist der Standortdienst aus, kann das Skript keine Netze auflisten. Dann
manuell mit einem Netz (z. B. Handy-Hotspot) verbinden.

**Quellen:** [ElevenForum – netsh wlan Zugriff verweigert](https://www.elevenforum.com/t/netsh-wlan-query-access-is-denied.45302/) ·
[Citrix – Location and Network improvements in Windows 11 24H2](https://docs.citrix.com/en-us/device-trust/23-1/kb/properties/location_and_network_improvements_in_windows11_24h2/) ·
[Swappa – How to inspect a used laptop](https://swappa.com/blog/how-to-inspect-a-used-laptop)

---

## 11. Physische Prüfung (was kein Skript kann) 👀

Ausführlich und zum Abhaken in `CHECKLISTE.md`. Das Skript fragt die Punkte am Ende auch interaktiv ab.

- **Gehäuse:** Risse, Dellen (Sturz), verzogener Deckel, fehlende Gummifüße.
- **Scharniere:** Deckel hält jede Position, kein Knacken, kein Spiel. Gebrochene Scharniere sind
  ein häufiger, teurer Schaden.
- **Schrauben:** fehlende oder vermurkste Schrauben → Gerät war offen (Reparatur? Teiletausch?).
- **Flüssigkeitsschaden:** Korrosion/weiße Ablagerungen an Ports und Lüftungsschlitzen, klebrige Tasten,
  muffiger Geruch. Flüssigkeitsschäden können erst Wochen später zum Totalausfall führen.
- **Akku-Schwellung:** siehe 3.5.
- **Display:** Druckstellen, Kratzer, Tastaturabdrücke auf dem Bildschirm (bei Druck auf den Deckel).
- **Lüfter:** Schleifgeräusche, Dauerbetrieb im Leerlauf.
- **Netzteil:** Original? Wattzahl passend? Kabel unbeschädigt?
- **Typenschild:** Seriennummer mit BIOS vergleichen (Skript zeigt sie an).

**Quellen:** [Swappa – How to inspect a used laptop](https://swappa.com/blog/how-to-inspect-a-used-laptop) ·
[MacRumors – Liquid Contact Indicators](https://forums.macrumors.com/threads/buying-used-evaluting-lci-liquid-contact-indicators-mbp-2012-13.1781699) ·
[Dell – Swollen Battery Guidance](https://www.dell.com/support/kbdoc/en-us/000128491/swollen-battery-information-and-guidance)

---

## 12. Grenzen von Software-Tests

- **Ein präpariertes Windows kann lügen.** Registry-Werte, Gerätenamen und Treiberbeschreibungen sind
  änderbar. Theoretisch sogar Abfrageschnittstellen per Treiber („Spoofer“). Das Skript vergleicht
  deshalb **mehrere unabhängige Quellen**: Registry ↔ Kernel ↔ Firmware (SMBIOS/ACPI) ↔ Gerät selbst
  (NVMe-Identify, CPUID).
- **Am manipulationssichersten** ist ein Test von einem **eigenen Boot-Medium** (z. B. Linux-Live-USB).
  Dort hat das Betriebssystem des Verkäufers keinen Einfluss. Das ist eine mögliche spätere Erweiterung.
- **Nicht vorhersagbar:** plötzlicher Ausfall eines SSD-Controllers, Mainboard-Defekte durch alte
  Flüssigkeitsschäden, Wackelkontakte, die erst später auftreten.
- **Frisch installiertes Windows** hat keine Ereignis- und Akkuhistorie. Diese Prüfungen sind dann
  wenig aussagekräftig (das Skript weist darauf hin).

---

## 13. Von der Recherche zum Skript: Zuordnung Risiko → Test

**Grundsatz:** Das Gerät gehört beim Test noch dem Verkäufer. Alle Tests sind deshalb rein lesend:
keine Schreibtests auf Datenträger, keine geänderten Einstellungen, keine Installation, kein Neustart in
Diagnoseprogramme. Was nur mit Schreiben oder Neustart geht (H2testw, Windows-Speicherdiagnose,
MemTest86), steht in der README unter „Nach dem Kauf“.

**Ältere Geräte:** BuyCheck läuft ab Windows 7 (PowerShell 2.0) ohne Updates am Gerät. Unter Windows 7
fehlen einige Windows-Abfragen (NVMe-Gesundheitswerte erst ab Windows 10, Akkuverlauf ab Windows 8,
CPU-Name direkt vom Prozessor ab Windows 8.1/10, Secure-Boot-Status ab Windows 8). Der Bericht weist
solche Lücken als „nicht prüfbar“ bzw. Hinweis aus.

| Risiko | Test-Baustein im Skript | Kritisch, wenn … |
|---|---|---|
| SSD verschlissen/defekt | `storage.health` | Critical Warning, Medienfehler, Reserve < Schwelle, ≥ 90 % verbraucht, SMART-Schwelle unterschritten, 187/197/198 > 0 |
| SMART zurückgesetzt | `storage.health` + `summary.plausibility` | Werte unplausibel zueinander oder zum Gerätealter |
| Fake-SSD (Marke) | `storage.health` | „Samsung“ ohne Samsung-Controller-VID |
| Fake-SSD (Kapazität), Billig-SSD | `storage.health` (TNVMCAP), `storage.speed` (nur lesend) | gemeldete Größe > physische Kapazität; sehr niedrige Lesewerte. Schreibtests (H2testw) erst nach dem Kauf |
| Schwache/defekte Flash-Bereiche | `storage.readscan` | Lesefehler; sehr langsame Bereiche |
| Akku verschlissen/manipuliert | `battery.health`, `battery.discharge` | < 60 %; Sprünge im Verlauf; Prozentsprünge unter Last |
| Ladeproblem/Netzteil | `power.charging` | Netzteil nicht erkannt / lädt nicht |
| CPU-Name gefälscht | `cpu.identity` | Registry ≠ Kernel; Name passt nicht zur Architektur; Autostart ändert CPU-Namen |
| Kühlung/Throttling, Rechenfehler | `cpu.stress` | < 50 % Basistakt unter Last; Rechenfehler |
| RAM-Fehler / falsche Ausstattung | `ram.info`, `ram.test` | Bitfehler |
| Display (Pixel, Panel-Tausch) | `display.info`, `display.pixeltest` | vom Nutzer gemeldete Fehler |
| GPU-Fälschung/-Defekt | `gpu.info` | Hersteller-ID passt nicht; Fehlercode 43 |
| Ein-/Ausgabe defekt | `input.keyboard`, `input.touchpad`, `ports.usb`, `ports.video`, `audio.speakers`, `audio.mic`, `camera`, `net.wifi` | vom Nutzer gemeldete Fehler / Gerät fehlt |
| Versteckte Defekte | `system.devices`, `system.eventlog` | Gerätefehler, deaktivierte Geräte, Hardwarefehler im Protokoll |
| BIOS-Passwort, Computrace | `lock.bios` | Supervisor-Passwort gesetzt |
| Firmen-Sperre | `lock.mdm` | Autopilot-Tenant gefunden |
| Windows 11 / Support | `win.win11` (abwählbar) | nicht kompatibel (Warnung) |
| Lizenz | `win.license` (abwählbar) | KMS-Aktivator-Verdacht (Warnung) |
| Linux-Probleme | `linux.compat` (abwählbar) | ARM-CPU; Hinweise zu Kamera/WLAN/VMD |
| Physische Mängel | `manual.checklist` | vom Nutzer gemeldet |
| Gesamtbild | `summary.plausibility` | Widersprüche zwischen den Altersangaben |

---

## 14. Quellen

Alle Quellen sind in den Abschnitten verlinkt. Wichtigste Primärquellen:

- Microsoft: [Working with NVMe drives](https://learn.microsoft.com/windows/win32/fileio/working-with-nvme-devices),
  [NVME_HEALTH_INFO_LOG](https://learn.microsoft.com/windows/win32/api/nvme/ns-nvme-nvme_health_info_log),
  [Battery WMI structures](https://github.com/MicrosoftDocs/sdk-api/blob/docs/sdk-api-src/content/batclass/ns-batclass-battery_wmi_static_data.md),
  [Windows 10 ESU](https://www.microsoft.com/en-us/windows/extended-security-updates),
  [HardwareReadiness.ps1](https://aka.ms/HWReadinessScript),
  [Autopilot Troubleshooting](https://learn.microsoft.com/en-us/autopilot/troubleshoot-oobe)
- heise: [Fake-Prozessoren in Notebooks (2026)](https://heise.de/-11212505),
  [Seagate-Betrug (2025)](https://heise.de/-10254518), [FARM-Manipulation](https://heise.de/-10308297)
- Backblaze: [SSD SMART](https://www.backblaze.com/blog/making-sense-of-ssd-smart-stats),
  [HDD SMART](https://www.backblaze.com/blog/hard-drive-smart-stats/)
- Kernel/Compiler-Tabellen: [Linux intel-family.h](https://github.com/torvalds/linux/blob/master/arch/x86/include/asm/intel-family.h),
  [LLVM Host.cpp](https://github.com/llvm/llvm-project/blob/main/llvm/lib/TargetParser/Host.cpp),
  [phnt ntexapi.h](https://github.com/winsiderss/phnt/blob/master/ntexapi.h),
  [mingw-w64 winioctl.h](https://github.com/mingw-w64/mingw-w64/blob/master/mingw-w64-headers/include/winioctl.h)
- Recht: [§ 935 BGB](https://www.gesetze-im-internet.de/bgb/__935.html),
  [BGH VIII ZR 186/12](https://rewis.io/urteile/urteil/k2o-12-03-2013-viii-zr-18612/)

*Hinweis: Rechtliche Angaben sind allgemeine Informationen und keine Rechtsberatung.*
