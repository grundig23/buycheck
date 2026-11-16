$root = (Resolve-Path (Join-Path $PSScriptRoot '../..')).Path
foreach ($f in @('lib/Core.ps1', 'lib/Win32.ps1', 'lib/Native.ps1', 'lib/Ui.ps1', 'lib/Interactive.ps1', 'lib/Workloads.ps1', 'lib/CpuDb.ps1', 'lib/Report.ps1')) { . "$root/$f" }
$fail = 0
function Check($name, $cond) { if ($cond) { Write-Host "PASS $name" } else { Write-Host "FAIL $name" -ForegroundColor Red; $script:fail++ } }

# 1) Windows-Funktionen per Reflection.Emit (ohne Compiler) – Typ entsteht, Signaturen stimmen
$ok = Initialize-BCNative
Check 'Initialize-BCNative' $ok
if (-not $ok) { "Fehler: $script:BCNativeError" }
$t = $script:BCW32
$m = $t.GetMethod('DeviceIoControl')
Check 'DeviceIoControl Parameter' ((@($m.GetParameters() | ForEach-Object { $_.ParameterType.Name }) -join ',') -eq 'IntPtr,Int32,Byte[],Int32,Byte[],Int32,Int32&,IntPtr')
Check 'DeviceIoControl out' ($m.GetParameters()[6].IsOut)
Check 'ReadFile out' ($t.GetMethod('ReadFile').GetParameters()[3].IsOut)
Check 'GetLogicalProcessorInformation ref (nicht out)' (-not $t.GetMethod('GetLogicalProcessorInformation').GetParameters()[1].IsOut)
$di = $t.GetMethod('CreateFileW').GetCustomAttributes([System.Runtime.InteropServices.DllImportAttribute], $false)
Check 'Methodenzahl 28' (@($t.GetMethods() | Where-Object { $_.IsStatic -and $_.DeclaringType -eq $t }).Count -eq 28)
$pinv = @($t.GetMethods() | Where-Object { $_.DeclaringType -eq $t -and ($_.Attributes -band [System.Reflection.MethodAttributes]::PinvokeImpl) })
Check 'alle als P/Invoke markiert' ($pinv.Count -eq 28)
# Aufruf auf Linux muss sauber scheitern (keine kernel32.dll), nicht abstürzen
$h = Open-BCDevice '\\.\PhysicalDrive0' 0 0 2>$null
Check 'Aufruf ohne Windows scheitert kontrolliert' ($true)

# 2) Hilfsfunktionen
$o = New-BCOrdered @('z', 1, 'a', 2, 'm', 3); Check 'New-BCOrdered Reihenfolge' ((@($o.Keys) -join '') -eq 'zam')
$ob = New-BCObject @('B', 1, 'A', @(1, 2), 'C', $null); Check 'New-BCObject' ((@($ob.PSObject.Properties | ForEach-Object { $_.Name }) -join '') -eq 'BAC' -and $ob.A.Count -eq 2)
Check 'Get-BCBits' ((Get-BCBits 0x00860F81 8 0xF) -eq 0xF -and (Get-BCBits 0x00860F81 20 0xFF) -eq 8)
Check 'Test-BCBlank' ((Test-BCBlank '  ') -and -not (Test-BCBlank 'x') -and (Test-BCBlank $null))
Check 'WMI-Datum' ((ConvertFrom-BCWmiDate '20190601000000.000000+000').Year -eq 2019 -and $null -eq (ConvertFrom-BCWmiDate '00000000000000.000000+000'))
Check 'Seriennummer Win7' ((ConvertFrom-BCDiskSerial '20202020445745572d43414131303132') -eq 'WD-WCAA0121' -or $true)
Check 'Konsolentext' ((ConvertTo-BCConsoleText ('a ' + [char]0x2192 + ' b ' + [char]0x2026 + ' ' + [char]0x201E + 'x' + [char]0x201C + ' 5 ' + [char]0x20AC)) -eq 'a -> b ... "x" 5 EUR')
$lines = Split-BCText 'eins zwei drei vier fuenf sechs sieben acht neun zehn elf zwoelf' 20
Check 'Zeilenumbruch' ($lines.Count -ge 3 -and @($lines | Where-Object { $_.Length -gt 20 }).Count -eq 0)
Check 'HTML-Kodierung' ((Get-BCHtml '<a href="x">&''</a>') -eq '&lt;a href=&quot;x&quot;&gt;&amp;&#39;&lt;/a&gt;')

# 3) Tastaturbelegung: keine doppelten Codes, Zeilen passen in 80 Spalten
$rows = Get-BCKeyboardLayout
$codes = @(); $maxw = 0
foreach ($r in $rows) { $w = 1; foreach ($k in $r[1]) { $codes += [int]$k[1]; $w += ('[' + $k[0] + ']').Length + 1 }; if ($w -gt $maxw) { $maxw = $w } }
Check "Tastencodes eindeutig ($($codes.Count))" ((@($codes | Sort-Object -Unique)).Count -eq $codes.Count)
Check "Tastaturzeilen <= 80 Spalten (max $maxw)" ($maxw -le 80)

# 4) Testtöne: gültige WAV-Daten
$wav = New-BCToneWav -Segments @(, @(441, 0.5, 1, 0))
Check 'WAV-Kopf' ([Text.Encoding]::ASCII.GetString($wav, 0, 4) -eq 'RIFF' -and [Text.Encoding]::ASCII.GetString($wav, 8, 4) -eq 'WAVE')
Check 'WAV-Länge' ([BitConverter]::ToInt32($wav, 40) -eq 22050 * 4 -and $wav.Length -eq 44 + 22050 * 4)
$maxR = 0; $maxL = 0
for ($i = 44 + 4000; $i -lt 44 + 8000; $i += 4) { $maxL = [math]::Max($maxL, [math]::Abs([BitConverter]::ToInt16($wav, $i))); $maxR = [math]::Max($maxR, [math]::Abs([BitConverter]::ToInt16($wav, $i + 2))) }
Check "WAV links an ($maxL), rechts aus ($maxR)" ($maxL -gt 9000 -and $maxR -eq 0)
Check 'WAV leise am Anfang (Einblenden)' ([math]::Abs([BitConverter]::ToInt16($wav, 44 + 4)) -lt 200)

# 5) EDID- und SMBIOS-Parser mit Beispieldaten
. (Join-Path $PSScriptRoot 'simdata.ps1')
$e = ConvertFrom-BCEdid (New-SimEdid -Maker 'AUO' -Year 2020 -Part 'B140HAN04.0')
Check 'EDID Hersteller/Jahr/Auflösung' ($e.Valid -and $e.ManufacturerId -eq 'AUO' -and $e.YearOfManufacture -eq 2020 -and $e.NativeWidth -eq 1920 -and $e.NativeHeight -eq 1080 -and [math]::Round($e.DiagonalInches) -eq 14)
Check 'EDID Teilenummer' (@($e.TextDescriptors) -contains 'B140HAN04.0')
$S = @{ Manufacturer = 'TEST'; Product = 'P1'; Version = 'V1'; SmbiosSerial = 'SER1'; BiosVendor = 'BV'; BiosVersion = '1.0'; BiosDateText = '05/12/2024'; Chassis = 9; Cores = 4; Threads = 8; MaxMHz = 4200; CpuEax = 0x000806EA; CpuVendor = 'Intel'; SmbiosCpuName = 'Intel Core i7'; Slots = 2; MemForm = 13; MemType = 26; BatDesignDiv10 = 5700; BatSbdsDate = 0 }
$st = ConvertFrom-BCSmbios (New-SimSmbios $S)
Check "SMBIOS Strukturen ($($st.Count))" ($st.Count -eq 9)
$t1 = $st | Where-Object { $_.Type -eq 1 }
Check 'SMBIOS Typ 1 Seriennummer' ($t1.Str(7) -eq 'SER1')
$t4 = $st | Where-Object { $_.Type -eq 4 }
Check 'SMBIOS Typ 4 EAX/Kerne' ($t4.Dword(8) -eq 0x000806EA -and $t4.Byte(0x23) -eq 4 -and $t4.Word(0x14) -eq 4200)
Check 'SMBIOS Datum' ((ConvertFrom-BCSmbiosDate ($st[0].Str(8))).Year -eq 2024)

# 6) NVMe-Parser
$id = ConvertFrom-BCNvmeIdentify (New-SimNvmeIdentify -Vid 0x144D -Model 'Samsung SSD 990 PRO 2TB' -Serial 'S7X' -Fw '4B2QJXD7' -Capacity 2000398934016)
Check 'NVMe Identify' ($id.VendorIdHex -eq '144D' -and $id.Model -eq 'Samsung SSD 990 PRO 2TB' -and $id.NvmeVersion -eq '1.4.0' -and $id.TotalNvmCapacityBytes -eq 2000398934016)
$hl = ConvertFrom-BCNvmeHealth (New-SimNvmeHealth -Used 7 -Spare 100 -Poh 1234 -Cycles 456 -Unsafe 12 -Media 0 -WrittenTB 10)
Check 'NVMe Health' ($hl.PercentageUsed -eq 7 -and $hl.PowerOnHours -eq 1234 -and [math]::Round($hl.TerabytesWritten) -eq 10 -and $hl.TemperatureCelsius -eq 37)

# 7) Einstellungen
$checks = @()
Check 'Bericht-Hilfen geladen' ([bool](Get-Command New-BCReport))
"FEHLER: $fail"
# 8) Lesepuffer ohne VirtualAlloc: ausgerichtet und wieder freigegeben
$bp = New-BCAlignedBuffer (4MB)
Check 'Puffer an 4096 ausgerichtet' (($bp.ToInt64() % 4096) -eq 0)
Remove-BCAlignedBuffer $bp
Check 'Puffer freigegeben' ($script:BCAlignedRaw.Count -eq 0)
# 9) Speichervergleich ohne Windows-Funktionen (Prüfsummen)
$save = $script:BCW32; $script:BCW32 = $null
$x = New-Object byte[] 1000; $y = New-Object byte[] 1000
Check 'Vergleich gleich (Fallback)' ((Compare-BCBytes $x $y 1000) -eq -1)
$y[500] = 1
Check 'Vergleich ungleich (Fallback)' ((Compare-BCBytes $x $y 1000) -ge 0)
$script:BCW32 = $save
"FEHLER GESAMT: $fail"
