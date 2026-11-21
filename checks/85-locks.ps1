# BuyCheck – Sperren & Herkunft: BIOS-Passwörter, Diebstahlschutz (Computrace), Firmenverwaltung (Autopilot/MDM)
# Alle Abfragen sind lesend. Es werden keine BIOS-Einstellungen verändert.

function Get-BCBiosSettingRows {
    param([object[]]$Items)
    return @($Items | ForEach-Object { (New-BCObject @('Einstellung', $_.Name, 'Wert', $_.Value)) })
}

Register-BuyCheck -Id 'lock.bios' -Category 'Grunddaten & Sperren' -Order 20 -RunOrder 100 -Seconds 10 `
    -Title 'BIOS-Passwort, Diebstahlschutz, Verschlüsselung' `
    -Description 'Liest (bei Lenovo, Dell und HP über deren BIOS-Schnittstelle), ob ein BIOS-/Supervisor-Passwort gesetzt ist. Ein unbekanntes Supervisor-Passwort sperrt das BIOS dauerhaft (z. B. kein Booten vom USB-Stick für Linux). Sucht außerdem nach dem Diebstahlschutz Absolute/Computrace, Intel AMT und BitLocker-Verschlüsselung.' `
    -Profiles @('quick', 'thorough', 'linux', 'auto') `
    -Run {
    $sys = Get-BCSystem
    $manu = $sys.Manufacturer
    $known = $false
    $settings = @()
    if ($manu -match '(?i)LENOVO') {
        $pw = Get-BCWmi -Namespace 'root/wmi' -ClassName Lenovo_BiosPasswordSettings | Select-Object -First 1
        if ($pw) {
            $known = $true
            $state = [int]$pw.PasswordState
            if ($state -band 2) {
                Set-BCFact 'bios.supervisor' $true
                Add-BCFinding -Level Kritisch -Title 'BIOS-Supervisor-Passwort ist gesetzt' `
                    -Detail 'Das BIOS ist mit einem Verwalter-Passwort gesperrt. Ohne dieses Passwort lassen sich wichtige Einstellungen nicht ändern, z. B. für eine Neuinstallation oder Linux.' `
                    -Advice 'Bei ThinkPads lässt es sich ohne das Passwort praktisch nicht entfernen.'
            }
            if ($state -band 64) { Add-BCFinding -Level Warnung -Title 'Systemverwaltungs-Passwort (System Management) ist gesetzt' -Detail 'Ein Passwort sperrt Teile der BIOS-Einstellungen.' }
            if ($state -band 1) { Add-BCFinding -Level Warnung -Title 'Einschalt-Passwort ist gesetzt' -Detail 'Das Gerät fragt schon beim Einschalten nach einem Passwort.' }
            if ($state -band 4) { Add-BCFinding -Level Warnung -Title 'Festplatten-Passwort ist gesetzt' -Detail 'Die SSD ist mit einem Passwort gesperrt, das in ihr selbst gespeichert ist.' -Advice 'Ohne dieses Passwort ist die SSD auch in einem anderen Gerät unbrauchbar.' }
            if ($state -eq 0) { Add-BCFinding -Level OK -Title 'Keine BIOS-Passwörter gesetzt (Lenovo)' }
        }
        foreach ($s in @(Get-BCWmi -Namespace 'root/wmi' -ClassName Lenovo_BiosSetting | Where-Object { $_ })) {
            $cur = "$($s.CurrentSetting)"
            if ($cur -match '(?i)Computrace|Absolute|SecureBoot|VMD|SATA|BootOrderLock|AMT|TPM|SecurityChip|Thunderbolt') {
                $parts = ($cur -split ';')[0] -split ',', 2
                $settings += (New-BCObject @('Name', $parts[0], 'Value', $(if ($parts.Count -gt 1) { $parts[1] } else { '' })))
            }
        }
    } elseif ($manu -match '(?i)Dell') {
        $pws = @(Get-BCWmi -Namespace 'root/dcim/sysman/wmisecurity' -ClassName PasswordObject)
        if ($pws.Count -gt 0) {
            $known = $true
            foreach ($p in $pws) {
                if ([int]$p.IsPasswordSet -eq 1) {
                    $lvl = if ("$($p.NameId)" -match '(?i)Admin|Owner|MasterPassword') { 'Kritisch' } else { 'Warnung' }
                    if ($lvl -eq 'Kritisch') { Set-BCFact 'bios.supervisor' $true }
                    Add-BCFinding -Level $lvl -Title "BIOS-Passwort gesetzt: $($p.NameId)" -Detail 'Ein Passwort sperrt das BIOS oder den Start. Ohne Passwort lassen sich wichtige Einstellungen nicht ändern.'
                }
            }
            if (@($pws | Where-Object { [int]$_.IsPasswordSet -eq 1 }).Count -eq 0) { Add-BCFinding -Level OK -Title 'Keine BIOS-Passwörter gesetzt (Dell)' }
        } else {
            $old = @(Get-BCWmi -Namespace 'root/dcim/sysman' -ClassName DCIM_BIOSPassword)
            if ($old.Count -gt 0) {
                $known = $true
                $set = @($old | Where-Object { [int]$_.IsSet -eq 1 })
                foreach ($p in $set) { Add-BCFinding -Level Kritisch -Title "BIOS-Passwort gesetzt: $($p.AttributeName)" -Detail 'Ein Passwort sperrt das BIOS oder den Start. Ohne Passwort lassen sich wichtige Einstellungen nicht ändern.'; Set-BCFact 'bios.supervisor' $true }
                if ($set.Count -eq 0) { Add-BCFinding -Level OK -Title 'Keine BIOS-Passwörter gesetzt (Dell)' }
            }
        }
        foreach ($a in @(Get-BCWmi -Namespace 'root/dcim/sysman/biosattributes' -ClassName EnumerationAttribute | Where-Object { $_ })) {
            if ("$($a.AttributeName)" -match '(?i)Absolute|Computrace|SecureBoot|Vmd|SataOperation|EmbSataRaid|Amt|Tpm') { $settings += (New-BCObject @('Name', "$($a.AttributeName)", 'Value', "$($a.CurrentValue)")) }
        }
    } elseif ($manu -match '(?i)^HP|Hewlett') {
        $all = @(Get-BCWmi -Namespace 'root/HP/InstrumentedBIOS' -ClassName HP_BIOSSetting)
        if ($all.Count -gt 0) {
            $known = $true
            $pw = @($all | Where-Object { @('Setup Password', 'Power-On Password') -contains "$($_.Name)" })
            foreach ($p in $pw) {
                if ([int]$p.IsSet -eq 1) {
                    $lvl = if ("$($p.Name)" -eq 'Setup Password') { 'Kritisch' } else { 'Warnung' }
                    if ($lvl -eq 'Kritisch') { Set-BCFact 'bios.supervisor' $true }
                    Add-BCFinding -Level $lvl -Title "BIOS-Passwort gesetzt: $($p.Name)" -Detail 'Ein Passwort sperrt das BIOS oder den Start. Ohne Passwort lassen sich wichtige Einstellungen nicht ändern.'
                }
            }
            if (@($pw | Where-Object { [int]$_.IsSet -eq 1 }).Count -eq 0) { Add-BCFinding -Level OK -Title 'Keine BIOS-Passwörter gesetzt (HP)' }
            foreach ($s in @($all | Where-Object { "$($_.Name)" -match '(?i)Absolute|Computrace|LoJack|Secure Boot|SATA|VMD|Active Management|TPM' })) {
                $settings += (New-BCObject @('Name', "$($s.Name)", 'Value', "$($s.CurrentValue)$($s.Value)"))
            }
        }
    }
    if (-not $known) {
        Add-BCFinding -Level Info -Title 'BIOS-Passwortstatus nicht automatisch lesbar' -Detail "Für $manu gibt es keine allgemein verfügbare Abfrage." `
            -Advice 'Ob ein Passwort gesetzt ist, zeigt sich beim Öffnen des BIOS (je nach Hersteller F2, Entf, F1, F10 oder Esc beim Start).'
    }
    if ($settings.Count -gt 0) { Add-BCTable -Title 'Relevante BIOS-Einstellungen (nur gelesen)' -Rows (Get-BCBiosSettingRows $settings) }
    $abs = @($settings | Where-Object { $_.Name -match '(?i)Computrace|Absolute|LoJack' -and $_.Value -match '(?i)^Enable|Activ|^On$' })
    if ($abs.Count -gt 0) {
        Add-BCFinding -Level Warnung -Title 'Diebstahlschutz Absolute/Computrace im BIOS aktiviert' -Detail (@($abs | ForEach-Object { "$($_.Name)=$($_.Value)" }) -join ', ') `
            -Advice 'Typisch für ehemalige Firmengeräte. Meldet der Besitzer das Gerät als gestohlen, kann es aus der Ferne gesperrt werden. Freigeben kann es nur der eingetragene Besitzer.'
    }

    # Absolute/Computrace-Agent in Windows
    $agentFiles = @(); $agentSvc = @()
    try { $agentFiles = @(@('rpcnet.exe', 'rpcnetp.exe', 'rpcnet.dll', 'rpcnetp.dll') | ForEach-Object { Join-Path $env:windir "System32\$_" } | Where-Object { Test-Path -LiteralPath $_ }) } catch { Write-BCDebug "Computrace-Dateien: $($_.Exception.Message)" }
    try { $agentSvc = @(Get-Service -ErrorAction SilentlyContinue | Where-Object { $_.Name -match '(?i)^rpcnet|Absolute|Computrace|CTES' -or $_.DisplayName -match '(?i)Absolute|Computrace' }) } catch { Write-BCDebug "Dienste: $($_.Exception.Message)" }
    if ($agentFiles.Count -gt 0 -or $agentSvc.Count -gt 0) {
        Add-BCFinding -Level Warnung -Title 'Diebstahlschutz-Software (Absolute/Computrace) ist aktiv' `
            -Detail ((@($agentFiles) + @($agentSvc | ForEach-Object { "Dienst $($_.Name) ($($_.Status))" })) -join ' · ') `
            -Advice 'Der Agent meldet das Gerät regelmäßig beim Besitzer und kann es sperren. Er wird vom BIOS immer wieder nachinstalliert, auch nach einer Neuinstallation. Freigeben kann es nur der eingetragene Besitzer.'
    } else {
        Add-BCFinding -Level OK -Title 'Kein Diebstahlschutz-Agent (Absolute/Computrace) gefunden'
    }

    # Intel AMT (Fernwartung auf Hardware-Ebene)
    $amt = @(Get-BCPnp | Where-Object { "$($_.Name)" -match '(?i)Active Management Technology|AMT.*SOL|Intel\(R\) Management and Security' })
    if ($amt.Count -gt 0) {
        Add-BCFinding -Level Info -Title 'Intel AMT/vPro-Fernwartung vorhanden' -Detail (@($amt | ForEach-Object { $_.Name }) -join ', ') `
            -Advice 'Bei ehemaligen Firmengeräten kann AMT noch eingerichtet sein und eine Fernsteuerung erlauben. Einsehbar im BIOS bzw. in MEBx (Strg+P beim Start).'
    }

    # Secure Boot / Firmware
    $sb = $null; $sbText = 'unbekannt'
    try { $sb = Confirm-SecureBootUEFI -ErrorAction Stop; $sbText = if ($sb) { 'aktiv' } else { 'aus (aber verfügbar)' } }
    catch [System.PlatformNotSupportedException] { $sbText = 'nicht verfügbar (kein UEFI)' }
    catch { }
    Set-BCFact 'secureboot' $sb
    Add-BCFacts -Title 'Sicherheitsfunktionen' -Data ((New-BCOrdered @('Secure Boot', $sbText, 'Firmware', $(switch (Get-BCFirmwareType) { 1 { 'BIOS (Legacy)' } 2 { 'UEFI' } default { 'unbekannt' } }))))

    # BitLocker
    $prot = $null
    try {
        $bl = Get-BitLockerVolume -MountPoint $env:SystemDrive -ErrorAction Stop
        $prot = "$($bl.ProtectionStatus)" -eq 'On'
    } catch {
        $ev = Get-BCWmi -Namespace 'root/cimv2/Security/MicrosoftVolumeEncryption' -ClassName Win32_EncryptableVolume -Filter "DriveLetter='$env:SystemDrive'" | Select-Object -First 1
        if ($ev) { $prot = [int]$ev.ProtectionStatus -eq 1 }
    }
    if ($prot) {
        Add-BCFinding -Level Info -Title 'Systemlaufwerk ist mit BitLocker verschlüsselt' -Advice 'Nach einem Zurücksetzen bzw. einer Neuinstallation von Windows spielt das keine Rolle.'
    }
}

Register-BuyCheck -Id 'lock.mdm' -Category 'Grunddaten & Sperren' -Order 30 -RunOrder 110 -Seconds 10 `
    -Title 'Firmenverwaltung (Autopilot, Entra ID, Domäne, MDM)' `
    -Description 'Prüft, ob das Gerät noch einer Firma zugeordnet ist: Windows-Autopilot-Profil (nach dem Zurücksetzen würde Windows einen Firmen-Login verlangen), Anmeldung bei Microsoft Entra ID oder einer Domäne und Geräteverwaltung (MDM/Intune). Typisch bei gebrauchten Business-Laptops.' `
    -Profiles @('quick', 'thorough', 'linux', 'auto') `
    -Run {
    $sys = Get-BCSystem
    $ap = 'HKLM:\SOFTWARE\Microsoft\Provisioning\Diagnostics\Autopilot'
    $tenant = "$(Get-BCRegValue $ap 'CloudAssignedTenantDomain')"
    $apDisabled = Get-BCRegValue $ap 'IsAutoPilotDisabled'
    if ($tenant) {
        Set-BCFact 'autopilot' $tenant
        Add-BCFinding -Level Kritisch -Title "Gerät ist in Windows Autopilot registriert (Organisation: $tenant)" -Detail 'Das Gerät ist bei Microsoft als Eigentum dieser Firma eingetragen.' `
            -Advice 'Nach dem Zurücksetzen verlangt Windows den Login dieser Firma – das Gerät ist dann mit Windows kaum nutzbar. Austragen kann es nur die Firma.'
    } elseif (Test-Path -LiteralPath $ap) {
        Add-BCFinding -Level OK -Title 'Kein Autopilot-Profil gespeichert' -Detail $(if ("$apDisabled" -eq '1') { 'Beim letzten Abruf als „nicht registriert“ gemeldet.' } else { '' }) `
            -Advice 'Sicher ausschließen lässt sich eine Autopilot-Registrierung nur durch Zurücksetzen mit Internetverbindung (Firmen-Login erscheint?).'
    } else {
        Add-BCFinding -Level Info -Title 'Keine Autopilot-Informationen vorhanden' -Detail 'Das Profil wird nur bei der Windows-Ersteinrichtung mit Internet abgerufen.' `
            -Advice 'Bei Business-Geräten (ThinkPad, Latitude, EliteBook …) lässt sich eine Registrierung nur durch Zurücksetzen mit Internetverbindung sicher ausschließen.'
    }

    $out = ''
    $dsreg = Join-Path $env:windir 'System32\dsregcmd.exe'
    if (Test-Path -LiteralPath $dsreg) { try { $out = (& $dsreg /status 2>&1 | Out-String) } catch { } }   # gibt es erst ab Windows 10
    $get = { param($k) if ($out -match "(?im)^\s*$k\s*:\s*(.+?)\s*$") { return $Matches[1] } return $null }
    $aad = & $get 'AzureAdJoined'; $ent = & $get 'EnterpriseJoined'; $dom = & $get 'DomainJoined'; $wp = & $get 'WorkplaceJoined'
    $tname = & $get 'TenantName'; $dname = & $get 'DomainName'
    Add-BCFacts -Title 'Verwaltungsstatus (dsregcmd)' -Data ((New-BCOrdered @('Entra ID (Azure AD) beigetreten', $aad, 'Domäne beigetreten', $dom, 'Enterprise', $ent, 'Arbeits-/Schulkonto', $wp, 'Organisation', $tname, 'Domäne', $dname)))
    if ($aad -eq 'YES') { Add-BCFinding -Level Warnung -Title "Gerät ist bei Microsoft Entra ID einer Organisation angemeldet$(if ($tname) { " ($tname)" })" -Detail 'Das Gerät ist mit dem Firmenkonto einer Organisation verbunden (ehemaliges Firmen- oder Schulgerät).' -Advice 'Ob nach dem Zurücksetzen der Firmen-Login verlangt wird, hängt an der Autopilot-Registrierung (siehe oben).' }
    if ($dom -eq 'YES' -or $sys.PartOfDomain) { Add-BCFinding -Level Warnung -Title "Gerät ist Mitglied einer Firmendomäne ($($sys.Domain))" -Detail 'Das Windows auf diesem Gerät gehört zum Netzwerk einer Firma.' }
    if ($wp -eq 'YES') { Add-BCFinding -Level Info -Title 'Ein Arbeits- oder Schulkonto ist verbunden' }

    $mdm = @()
    foreach ($k in @(Get-ChildItem 'HKLM:\SOFTWARE\Microsoft\Enrollments' -ErrorAction SilentlyContinue)) {
        $prov = "$(Get-BCRegValue $k.PSPath 'ProviderID')"
        if ($prov -and $prov -notmatch '(?i)WMI_Bridge_Server') {
            $mdm += (New-BCObject @('Anbieter', $prov, 'Konto', "$(Get-BCRegValue $k.PSPath 'UPN')", 'Status', "$(Get-BCRegValue $k.PSPath 'EnrollmentState')"))
        }
    }
    if ($mdm.Count -gt 0) {
        Add-BCTable -Title 'Geräteverwaltung (MDM)' -Rows $mdm
        Add-BCFinding -Level Warnung -Title 'Gerät ist bei einer Geräteverwaltung (MDM/Intune) angemeldet' -Detail (@($mdm | ForEach-Object { "$($_.Anbieter) $($_.Konto)" }) -join ', ') `
            -Advice 'Die Firma kann das Gerät aus der Ferne verwalten und löschen, solange die Verwaltung eingerichtet ist.'
    }
    if (-not $tenant -and $aad -ne 'YES' -and $dom -ne 'YES' -and -not $sys.PartOfDomain -and $mdm.Count -eq 0) {
        Add-BCFinding -Level OK -Title 'Keine Firmenverwaltung (Entra ID, Domäne, MDM) erkannt'
    }
    if ($sys.RegisteredOrg -and $sys.RegisteredOrg -notmatch '^(|Microsoft|Default|HP Inc\.|Lenovo|Dell)$') {
        Add-BCFinding -Level Info -Title "Registrierte Organisation: $($sys.RegisteredOrg)" -Detail 'Hinweis auf ein (ehemaliges) Firmengerät.'
    }
    $oem = 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\OEMInformation'
    $oemManu = "$(Get-BCRegValue $oem 'Manufacturer')"; $oemModel = "$(Get-BCRegValue $oem 'Model')"
    if ($oemManu -or $oemModel) {
        Add-BCFacts -Title 'Hersteller-Informationen in Windows (vom Installierenden eingetragen)' -Data ((New-BCOrdered @('Hersteller', $oemManu, 'Modell', $oemModel, 'Support-Seite', "$(Get-BCRegValue $oem 'SupportURL')")))
        if ($oemModel -and $sys.Model -and $oemModel -notmatch [regex]::Escape($sys.Model) -and $sys.DisplayModel -notmatch [regex]::Escape($oemModel)) {
            Add-BCFinding -Level Info -Title 'Windows-Herstellerangabe weicht von der Firmware ab' -Detail "Windows: '$oemManu $oemModel' · Firmware: '$($sys.Manufacturer) $($sys.DisplayModel)'. Bei Aufbereitern (Refurbishern) üblich."
        }
    }
}
