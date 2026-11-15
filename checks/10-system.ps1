# BuyCheck – Grunddaten: Steckbrief des Geräts, Seriennummer, Windows-Stand

Register-BuyCheck -Id 'system.info' -Category 'Grunddaten & Sperren' -Order 10 -RunOrder 10 -Seconds 10 `
    -Title 'Geräte-Steckbrief & Seriennummer' `
    -Description 'Liest Hersteller, Modell, Seriennummer (aus dem BIOS), Mainboard, BIOS-Stand und Windows-Version aus. Die Seriennummer brauchst du für den Abgleich mit dem Typenschild und für die Herstellerseite (Originalausstattung, Garantie).' `
    -Profiles @('quick', 'thorough', 'linux', 'auto') `
    -Run {
    $s = Get-BCSystem
    if (-not $s) { throw 'Systemdaten konnten nicht gelesen werden.' }

    Set-BCSummary 'Gerät' "$($s.Manufacturer) $($s.DisplayModel)".Trim()
    Set-BCSummary 'Seriennummer (BIOS)' $s.Serial
    Set-BCFact 'bios.date' $s.BiosDate
    Set-BCFact 'os.installDate' $s.OsInstallDate

    $facts = [ordered]@{
        'Hersteller'            = $s.Manufacturer
        'Modell'                = $s.DisplayModel
        'Produktfamilie'        = $s.Family
        'SKU / Produktnummer'   = $s.Sku
        'Seriennummer (BIOS)'   = $s.Serial
        'UUID'                  = $s.Uuid
        'Mainboard'             = "$($s.BoardVendor) $($s.BoardProduct)".Trim()
        'Mainboard-Seriennr.'   = $s.BoardSerial
        'BIOS'                  = "$($s.BiosVendor) $($s.BiosVersion)".Trim()
        'BIOS-Datum'            = Format-BCDate $s.BiosDate
        'Gehäusetyp (SMBIOS)'   = ($s.ChassisTypes -join ', ')
        'Inventarnummer'        = $s.AssetTag
        'Windows'               = "$($s.OsCaption) $($s.OsDisplayVersion) (Build $($s.OsBuild), $($s.OsArchitecture))".Trim()
        'Windows installiert am' = Format-BCDate $s.OsInstallDate
        'Letzter Start'         = if ($s.LastBoot) { ([datetime]$s.LastBoot).ToString('dd.MM.yyyy HH:mm') } else { '' }
        'Registrierter Besitzer' = $s.RegisteredOwner
        'Organisation'          = $s.RegisteredOrg
        'Computername'          = $s.ComputerName
    }
    $fw = [BuyCheck.Firmware]::FirmwareType()
    $facts['Firmware'] = switch ($fw) { 1 { 'BIOS (Legacy)' } 2 { 'UEFI' } default { 'unbekannt' } }
    Add-BCFacts -Title 'Steckbrief' -Data $facts

    Add-BCFinding -Level Info -Title "$($s.Manufacturer) $($s.DisplayModel)" -Detail "Seriennummer: $($s.Serial) · BIOS $($s.BiosVersion) vom $(Format-BCDate $s.BiosDate)"

    # Seriennummer plausibel?
    if (Test-BCPlaceholder $s.Serial) {
        Add-BCFinding -Level Warnung -Title 'Keine gültige Seriennummer im BIOS' `
            -Detail "Gelesen: '$($s.Serial)'. Bei Markengeräten ist das ungewöhnlich (z. B. Mainboard-Tausch ohne Neuprogrammierung)." `
            -Advice 'Herkunft erfragen; Seriennummer auf dem Typenschild notieren. Ohne Seriennummer ist auch keine Herstellerabfrage möglich.'
    } else {
        Add-BCFinding -Level OK -Title 'Seriennummer im BIOS vorhanden' -Detail "Bitte mit dem Aufkleber/Typenschild auf der Unterseite vergleichen: $($s.Serial)" `
            -Advice 'Weicht sie ab, wurde das Mainboard getauscht oder das Typenschild gehört nicht zum Gerät.'
    }
    if ($s.SerialSmbios -and $s.Serial -and ($s.SerialSmbios -ne $s.Serial) -and -not (Test-BCPlaceholder $s.SerialSmbios)) {
        Add-BCFinding -Level Info -Title 'Zwei unterschiedliche Seriennummern in den Firmware-Daten' -Detail "Windows: $($s.Serial) · SMBIOS: $($s.SerialSmbios)"
    }

    if (-not $s.IsPortable -and $s.ChassisTypes.Count -gt 0) {
        Add-BCFinding -Level Info -Title 'Gerät meldet sich nicht als Notebook' -Detail "Gehäusetyp laut Firmware: $($s.ChassisTypes -join ', ')"
    }

    if ($s.OsInstallDate) {
        $age = (New-TimeSpan -Start ([datetime]$s.OsInstallDate) -End (Get-Date)).TotalDays
        if ($age -lt 14) {
            Add-BCFinding -Level Info -Title 'Windows wurde kürzlich (neu) installiert bzw. zurückgesetzt' `
                -Detail "Installationsdatum: $(Format-BCDate $s.OsInstallDate). Fehlerprotokolle und Akku-Verlauf reichen daher nicht weit zurück."
        }
    }

    if ($s.AssetTag) {
        Add-BCFinding -Level Info -Title 'Inventarnummer (Asset-Tag) hinterlegt' -Detail "'$($s.AssetTag)' – typisch für ehemalige Firmengeräte. Herkunft erfragen (Leasing-Rückläufer sind normal)."
    }

    # Herstellerseiten für Originalausstattung/Garantie
    $sn = [uri]::EscapeDataString($s.Serial)
    switch -Regex ($s.Manufacturer) {
        'LENOVO' {
            Add-BCLink -Title 'Lenovo: Garantie & Originalausstattung (Seriennummer eingeben)' -Url 'https://pcsupport.lenovo.com/de/de/warranty-lookup'
            Add-BCLink -Title 'Lenovo PSREF: technische Daten zum Modell' -Url ('https://psref.lenovo.com/search?kw=' + [uri]::EscapeDataString($s.Model))
        }
        'Dell' { Add-BCLink -Title 'Dell: Originalausstattung zum Service-Tag' -Url "https://www.dell.com/support/home/de-de/product-support/servicetag/$sn/overview" }
        'HP|Hewlett' { Add-BCLink -Title 'HP: Garantie & Produktinfo (Seriennummer eingeben)' -Url 'https://support.hp.com/de-de/check-warranty' }
        'ASUS' { Add-BCLink -Title 'ASUS: Garantieabfrage' -Url 'https://www.asus.com/de/support/warranty-status-inquiry/' }
        'Acer' { Add-BCLink -Title 'Acer: Garantieabfrage' -Url 'https://www.acer.com/de-de/support/warranty' }
        'Microsoft' { Add-BCLink -Title 'Microsoft: Geräteservice' -Url 'https://mybusinessservice.surface.com/' }
        default { }
    }
}
