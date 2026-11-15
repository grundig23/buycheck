# BuyCheck – Windows: Windows-11-Tauglichkeit und Lizenz (beides abwählbar, z. B. bei Linux-Plänen)

Register-BuyCheck -Id 'win.win11' -Category 'Windows' -Order 10 -RunOrder 120 -Seconds 10 `
    -Title 'Windows-11-Tauglichkeit' `
    -Description 'Prüft die offiziellen Windows-11-Anforderungen mit der Logik aus Microsofts Prüfskript: unterstützte CPU, TPM 2.0, Secure-Boot-fähiges UEFI, mindestens 4 GB RAM und 64 GB Speicher. Hintergrund: Windows 10 bekommt nur noch über das ESU-Programm Sicherheitsupdates, längstens bis 12.10.2027. Für reine Linux-Nutzung unerheblich.' `
    -Profiles @('quick', 'thorough', 'auto') `
    -Run {
    $sys = Get-BCSystem; $c = Get-BCCpu
    $rows = New-Object 'System.Collections.Generic.List[object]'
    $add = {
        param($name, $value, $ok)
        $rows.Add((New-BCObject @('Anforderung', $name, 'Gefunden', $value, 'Erfüllt', $(if ($null -eq $ok) { 'unklar' } elseif ($ok) { 'ja' } else { 'NEIN' }))))
        if ($ok -eq $false) { $script:BCw11Fails += $name } elseif ($null -eq $ok) { $script:BCw11Unknown += $name }
    }
    $script:BCw11Fails = @(); $script:BCw11Unknown = @()

    $cpuRes = Test-BCWin11Cpu -Vendor $c.Vendor -Arch $c.Architecture -Family $c.Family -Model $c.Model -Stepping $c.Stepping -CpuName $c.BestName -SystemModel $sys.Model
    & $add 'Prozessor (Microsoft-Liste)' "$($c.BestName) – $($cpuRes.Text)" $cpuRes.Ok
    & $add '64-Bit, ≥ 2 Kerne, ≥ 1 GHz' "$($c.Threads) Threads, $($c.MaxClockMHz) MHz" ([bool]($c.Threads -ge 2 -and ($c.MaxClockMHz -gt 1000 -or $c.MaxClockMHz -eq 0)))
    $sse42 = Test-BCCpuFeature 38
    if (@('Intel', 'AMD') -contains $c.Vendor) { & $add 'SSE4.2 (seit 24H2 Pflicht)' $(if ($sse42) { 'vorhanden' } else { 'nicht gemeldet' }) $(if ($sse42) { $true } else { $null }) }
    $ram = [double](Get-BCInstalledMemoryBytes)
    if ($ram -le 0) { $ram = [double]$sys.TotalPhysicalMemory }
    & $add 'Arbeitsspeicher ≥ 4 GB' (Format-BCBytes $ram -Binary) ($ram -ge 3.8GB)
    $sysDisk = @(Get-BCInternalDisks | Where-Object { $_.IsBoot -or $_.IsSystem } | Select-Object -First 1)
    if ($sysDisk.Count -gt 0) { & $add 'Systemdatenträger ≥ 64 GB' (Format-BCBytes $sysDisk[0].SizeBytes) ($sysDisk[0].SizeBytes -ge 64GB) }
    $tpmVer = $null; $tpmPresent = $null
    try { $t = Get-Tpm -ErrorAction Stop; $tpmPresent = [bool]$t.TpmPresent } catch { }
    $wt = Get-BCWmi -Namespace 'root/cimv2/Security/MicrosoftTpm' -ClassName Win32_Tpm | Select-Object -First 1
    if ($wt) { $tpmPresent = $true; $tpmVer = "$($wt.SpecVersion)".Split(',')[0].Trim() }
    if ($tpmPresent) { & $add 'TPM 2.0' "TPM $tpmVer" ([double]("0$tpmVer" -replace '[^\d.]', '') -ge 2) }
    elseif ($tpmPresent -eq $false) { & $add 'TPM 2.0' 'kein TPM aktiv (evtl. im BIOS abgeschaltet)' $false }
    else { & $add 'TPM 2.0' 'nicht ermittelbar' $null }
    $sbCap = $null; $sbText = ''
    try { $sbOn = Confirm-SecureBootUEFI -ErrorAction Stop; $sbCap = $true; $sbText = if ($sbOn) { 'UEFI, Secure Boot aktiv' } else { 'UEFI, Secure Boot aus (aber möglich)' } }
    catch [System.PlatformNotSupportedException] { $sbCap = $false; $sbText = 'kein UEFI/Secure Boot' }
    catch {
        # z. B. Windows 7: dort gibt es die Abfrage nicht – dann wenigstens den Firmware-Typ auswerten
        switch (Get-BCFirmwareType) {
            1 { $sbCap = $false; $sbText = 'altes BIOS (kein UEFI)' }
            2 { $sbText = 'UEFI vorhanden, Secure Boot hier nicht abfragbar' }
            default { $sbText = 'nicht ermittelbar' }
        }
    }
    & $add 'UEFI mit Secure-Boot-Fähigkeit' $sbText $sbCap
    Add-BCTable -Title 'Windows-11-Anforderungen' -Rows $rows.ToArray()

    $isWin11 = $sys.OsBuildNumber -ge 22000
    $os = "$($sys.OsCaption) $($sys.OsDisplayVersion)".Trim()
    $fails = @($script:BCw11Fails); $unk = @($script:BCw11Unknown)
    if ($fails.Count -eq 0 -and $unk.Count -eq 0) {
        Add-BCFinding -Level OK -Title 'Erfüllt die Windows-11-Anforderungen' -Detail "Installiert: $os"
        Set-BCSummary 'Windows 11' 'tauglich'
    } elseif ($fails.Count -eq 0) {
        Add-BCFinding -Level Info -Title 'Windows-11-Tauglichkeit nicht vollständig bestimmbar' -Detail ("Unklar: " + ($unk -join ', '))
        Set-BCSummary 'Windows 11' 'vermutlich tauglich'
    } else {
        Set-BCSummary 'Windows 11' ('nicht tauglich (' + ($fails -join ', ') + ')')
        Add-BCFinding -Level Warnung -Title ('Nicht offiziell Windows-11-tauglich: ' + ($fails -join ', ')) `
            -Detail "Installiert: $os" -Advice 'Windows 10 erhält über das ESU-Programm (Microsoft-Konto) nur noch bis 12.10.2027 Sicherheitsupdates. Danach bleibt Linux oder eine inoffizielle Windows-11-Installation ohne Update-Garantie. Im Preis berücksichtigen.'
        if ($isWin11) { Add-BCFinding -Level Warnung -Title 'Windows 11 läuft auf nicht offiziell unterstützter Hardware' -Advice 'Microsoft garantiert hier keine Updates; große Funktionsupdates können scheitern.' }
    }
    if (-not $isWin11 -and $sys.OsCaption -match 'Windows 10') {
        Add-BCFinding -Level Info -Title 'Windows 10 ist installiert' -Detail 'Regulärer Support endete am 14.10.2025; Sicherheitsupdates nur noch per ESU bis 12.10.2027.' -Advice $(if ($fails.Count -eq 0) { 'Kostenloses Upgrade auf Windows 11 ist möglich.' } else { '' })
    }
    if ($sbCap -and $sbText -match 'aus') { Add-BCFinding -Level Info -Title 'Secure Boot ist ausgeschaltet' -Detail 'Für Windows 11 sollte es eingeschaltet sein (BIOS-Einstellung).' }
}

$script:BCKmsHosts = @('kms.digiboy.ir', 'kms8.msguides.com', 'kms.03k.org', 's8.uk.to', 'kms.loli.beer', 'kms.srv.crsoo.com', 'e8.us.to',
    'kms.lotro.cc', 'kms.chinancce.com', 'kms.ddns.net', 'k.zpale.com', 'm.zpale.com', 'kms.shuax.com', 'kms789.com', 'kms.cangshui.net',
    'kms.library.hk', 'hq1.chinancce.com', 'kms.zhuxiaole.org', 'kms.msgang.com', 'kms.bige0.com', 'zh.us.to', 'xykz.f3322.org')

Register-BuyCheck -Id 'win.license' -Category 'Windows' -Order 20 -RunOrder 130 -Seconds 20 `
    -Title 'Windows-Lizenz & Aktivierung' `
    -Description 'Prüft, ob Windows aktiviert ist, über welchen Weg (OEM, Retail, Volumenlizenz) und ob ein Produktschlüssel im BIOS hinterlegt ist (dann aktiviert sich eine Neuinstallation automatisch). Erkennt außerdem Spuren illegaler KMS-Aktivatoren, die oft Schadsoftware mitbringen.' `
    -Profiles @('quick', 'thorough', 'auto') `
    -Run {
    $sys = Get-BCSystem
    Write-BCStep 'Lizenzdaten abfragen (kann einige Sekunden dauern) …'
    $svc = Get-BCWmi SoftwareLicensingService | Select-Object -First 1
    $prod = @(Get-BCWmi SoftwareLicensingProduct -Filter "ApplicationID='55c92734-d682-4d71-983e-d6ec3f16059f' AND PartialProductKey IS NOT NULL")
    $p = $prod | Where-Object { [int]$_.LicenseStatus -eq 1 } | Select-Object -First 1
    if (-not $p) { $p = $prod | Select-Object -First 1 }
    $statusNames = @{ 0 = 'nicht lizenziert'; 1 = 'aktiviert'; 2 = 'Kulanzzeit'; 3 = 'Kulanzzeit'; 4 = 'nicht echt (Kulanzzeit)'; 5 = 'Benachrichtigungsmodus'; 6 = 'erweiterte Kulanzzeit' }
    $oemDesc = "$($svc.OA3xOriginalProductKeyDescription)"
    $channel = "$($p.ProductKeyChannel)"
    if (-not $channel -and "$($p.Description)" -match '(\w+)\s+channel') { $channel = $Matches[1] }
    $kmsHost = @("$($p.KeyManagementServiceMachine)", "$($p.DiscoveredKeyManagementServiceMachineName)", "$($svc.KeyManagementServiceMachine)") | Where-Object { $_ } | Select-Object -First 1
    Add-BCFacts -Title 'Lizenz' -Data ((New-BCOrdered @(
        'Produkt', "$($p.Name)",
        'Status', $(if ($p) { $statusNames[[int]$p.LicenseStatus] } else { 'kein Produktschlüssel gefunden' }),
        'Lizenzkanal', $channel,
        'Schlüssel (letzte 5 Zeichen)', "$($p.PartialProductKey)",
        'Im BIOS hinterlegte Lizenz', $(if ($oemDesc) { $oemDesc } else { 'keine' }),
        'KMS-Server', "$kmsHost"
    )))
    if ($oemDesc) { Add-BCFinding -Level OK -Title 'Windows-Lizenz ist im BIOS hinterlegt' -Detail "$oemDesc – eine Neuinstallation dieser Edition aktiviert sich automatisch." }

    if (-not $p) { Add-BCFinding -Level Info -Title 'Kein Windows-Produktschlüssel installiert' }
    elseif ([int]$p.LicenseStatus -eq 1) { Add-BCFinding -Level OK -Title "Windows ist aktiviert ($channel)" }
    else { Add-BCFinding -Level Info -Title "Windows ist nicht aktiviert ($($statusNames[[int]$p.LicenseStatus]))" -Detail $(if ($oemDesc) { 'Mit dem BIOS-Schlüssel sollte eine Neuinstallation aktiviert werden können.' } else { 'Lizenz muss ggf. gekauft werden – im Preis berücksichtigen.' }) }

    # Illegale Aktivierung erkennen
    $isGvlk = $channel -match '(?i)GVLK|KMSCLIENT'
    $suspHost = $kmsHost -and ($kmsHost -match '^(127\.|localhost|0\.0\.0\.0|::1)' -or $script:BCKmsHosts -contains $kmsHost.ToLowerInvariant())
    $artifacts = @()
    foreach ($f in @("$env:windir\System32\SppExtComObjHook.dll", "$env:windir\System32\SppExtComObjPatcher.exe", "$env:windir\KMSAutoS", "$env:ProgramData\KMSAutoS",
            "$env:ProgramFiles\KMSpico", "${env:ProgramFiles(x86)}\KMSpico", "$env:windir\AAct_Tools", "$env:windir\SECOH-QAD.exe", "$env:windir\SECOH-QAD.dll")) {
        if ($f -and (Test-Path -LiteralPath $f)) { $artifacts += $f }
    }
    $ifeo = Get-BCRegValue 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Image File Execution Options\SppExtComObj.exe' 'VerifierDlls'
    if ($ifeo) { $artifacts += "IFEO SppExtComObj.exe → $ifeo" }
    try {
        # Aufgabendefinitionen direkt lesen (Get-ScheduledTask gibt es erst ab Windows 8)
        $taskDir = Join-Path $env:windir 'System32\Tasks'
        foreach ($t in @(Get-ChildItem -LiteralPath $taskDir -Recurse -Force -ErrorAction SilentlyContinue | Where-Object { -not $_.PSIsContainer -and $_.Name -match '(?i)KMS|AutoPico|AutoKMS|KMSAuto|AAct|Activation.?Renew' })) { $artifacts += "Aufgabe $($t.FullName.Substring($taskDir.Length))" }
    } catch { }
    try {
        foreach ($s in @(Get-Service -ErrorAction SilentlyContinue | Where-Object { $_.Name -match '(?i)KMSELDI|Service_KMS|KMSAuto|KMSpico|AutoPico' })) { $artifacts += "Dienst $($s.Name)" }
    } catch { Write-BCDebug "Dienste: $($_.Exception.Message)" }
    if ($artifacts.Count -gt 0 -or ($isGvlk -and $suspHost)) {
        Add-BCFinding -Level Warnung -Title 'Hinweise auf einen illegalen Aktivierungs-Crack (KMS-Aktivator)' -Detail ((@($artifacts) + @($(if ($suspHost) { "KMS-Server: $kmsHost" }))) -join ' · ') `
            -Advice 'Solche Werkzeuge bringen häufig Schadsoftware mit. Windows nach dem Kauf komplett neu installieren; Lizenz klären.'
    } elseif ($isGvlk) {
        if ($sys.PartOfDomain) { Add-BCFinding -Level Info -Title 'Firmen-Volumenlizenz (KMS)' -Detail 'Gilt nur im Firmennetz; nach Verkauf nicht nutzbar. Mit BIOS-Schlüssel neu installieren.' }
        else { Add-BCFinding -Level Warnung -Title 'Volumenlizenz (KMS) auf einem Privatgerät' -Detail "KMS-Server: $(if ($kmsHost) { $kmsHost } else { 'nicht hinterlegt' })" -Advice 'Ungewöhnlich außerhalb von Firmen – oft illegale Aktivierung. Neuinstallation empfohlen.' }
    }
}
