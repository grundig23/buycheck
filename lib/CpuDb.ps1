# BuyCheck – CPU-Generationsdaten und Namensanalyse
# Quellen: Linux-Kernel arch/x86/include/asm/intel-family.h, LLVM llvm/lib/TargetParser/Host.cpp,
#          Microsoft HardwareReadiness.ps1 (siehe RECHERCHE.md, Abschnitt 4).
#
# Idee: Der CPU-Name lässt sich fälschen (Registry, Firmware), Familie/Modell aus dem Kernel kaum.
# Passt die im Namen behauptete Generation nicht zur Architektur des Chips, ist das ein starkes Warnsignal.

# Rangfolge für Intel: Core-Generation 1..14, N-Serie (Gracemont) = 12, Core 3/5/7 Serie 1/2 = 13,
# Core Ultra Serie 1 = 15, Serie 2 = 16, Serie 3 = 17.
$script:BCIntelModels = @{
    0x1E = @{ Name = 'Nehalem (Core i 1. Gen.)'; Gens = @(1); Year = 2009 }
    0x1F = @{ Name = 'Nehalem (Core i 1. Gen.)'; Gens = @(1); Year = 2009 }
    0x1A = @{ Name = 'Nehalem-EP'; Gens = @(1); Year = 2009 }
    0x25 = @{ Name = 'Westmere/Arrandale (Core i 1. Gen.)'; Gens = @(1); Year = 2010 }
    0x2C = @{ Name = 'Westmere-EP'; Gens = @(1); Year = 2010 }
    0x2A = @{ Name = 'Sandy Bridge (2. Gen.)'; Gens = @(2); Year = 2011 }
    0x2D = @{ Name = 'Sandy Bridge-E'; Gens = @(2, 3); Year = 2011 }
    0x3A = @{ Name = 'Ivy Bridge (3. Gen.)'; Gens = @(3); Year = 2012 }
    0x3E = @{ Name = 'Ivy Bridge-E'; Gens = @(3, 4); Year = 2013 }
    0x3C = @{ Name = 'Haswell (4. Gen.)'; Gens = @(4); Year = 2013 }
    0x45 = @{ Name = 'Haswell-ULT (4. Gen.)'; Gens = @(4); Year = 2013 }
    0x46 = @{ Name = 'Haswell-GT3e (4. Gen.)'; Gens = @(4); Year = 2013 }
    0x3F = @{ Name = 'Haswell-E'; Gens = @(4, 5); Year = 2014 }
    0x3D = @{ Name = 'Broadwell (5. Gen.)'; Gens = @(5); Year = 2015 }
    0x47 = @{ Name = 'Broadwell-H (5. Gen.)'; Gens = @(5); Year = 2015 }
    0x4F = @{ Name = 'Broadwell-E'; Gens = @(5, 6); Year = 2016 }
    0x56 = @{ Name = 'Broadwell-DE'; Gens = @(5); Year = 2015 }
    0x4E = @{ Name = 'Skylake-U/Y (6. Gen.)'; Gens = @(6); Year = 2015 }
    0x5E = @{ Name = 'Skylake-H/S (6. Gen.)'; Gens = @(6); Year = 2015 }
    0x55 = @{ Name = 'Skylake-X/Cascade Lake'; Gens = @(6, 7, 9, 10); Year = 2017 }
    0x66 = @{ Name = 'Cannon Lake (8. Gen.)'; Gens = @(8); Year = 2018 }
    0x7D = @{ Name = 'Ice Lake (10. Gen.)'; Gens = @(10); Year = 2019 }
    0x7E = @{ Name = 'Ice Lake (10. Gen.)'; Gens = @(10); Year = 2019 }
    0xA5 = @{ Name = 'Comet Lake-H/S (10. Gen.)'; Gens = @(10); Year = 2020 }
    0xA6 = @{ Name = 'Comet Lake-U (10. Gen.)'; Gens = @(10); Year = 2019 }
    0x8C = @{ Name = 'Tiger Lake-U (11. Gen.)'; Gens = @(11); Year = 2020 }
    0x8D = @{ Name = 'Tiger Lake-H (11. Gen.)'; Gens = @(11); Year = 2021 }
    0xA7 = @{ Name = 'Rocket Lake (11. Gen.)'; Gens = @(11); Year = 2021 }
    0x97 = @{ Name = 'Alder Lake-S (12. Gen., teils 13./14.)'; Gens = @(12, 13, 14); Year = 2021 }
    0x9A = @{ Name = 'Alder Lake-P/U/H (12. Gen., teils 13.)'; Gens = @(12, 13); Year = 2022 }
    0xB7 = @{ Name = 'Raptor Lake-S/HX (13./14. Gen.)'; Gens = @(13, 14); Year = 2022 }
    0xBA = @{ Name = 'Raptor Lake-P/U/H (13. Gen. / Core 1xx-2xx)'; Gens = @(13, 14); Year = 2023 }
    0xBF = @{ Name = 'Raptor Lake-S (13./14. Gen.)'; Gens = @(13, 14); Year = 2023 }
    0xBE = @{ Name = 'Alder Lake-N / Twin Lake (N-Serie)'; Gens = @(12); Year = 2023 }
    0xAA = @{ Name = 'Meteor Lake (Core Ultra Serie 1)'; Gens = @(15); Year = 2023 }
    0xAC = @{ Name = 'Meteor Lake (Core Ultra Serie 1)'; Gens = @(15); Year = 2023 }
    0xBD = @{ Name = 'Lunar Lake (Core Ultra Serie 2)'; Gens = @(16); Year = 2024 }
    0xC5 = @{ Name = 'Arrow Lake-H (Core Ultra Serie 2)'; Gens = @(16); Year = 2025 }
    0xC6 = @{ Name = 'Arrow Lake-S/HX (Core Ultra Serie 2)'; Gens = @(16); Year = 2024 }
    0xB5 = @{ Name = 'Arrow Lake-U (Core Ultra Serie 2)'; Gens = @(16); Year = 2025 }
    0xCC = @{ Name = 'Panther Lake (Core Ultra Serie 3)'; Gens = @(17); Year = 2026 }
    0xE5 = @{ Name = 'Panther Lake (Core Ultra Serie 3)'; Gens = @(17); Year = 2026 }
    0xD5 = @{ Name = 'Wildcat Lake'; Gens = @(17); Year = 2026 }
    0x8A = @{ Name = 'Lakefield'; Gens = @(10); Year = 2020 }
    0x37 = @{ Name = 'Bay Trail (Atom/Celeron/Pentium)'; Gens = @(); Year = 2013 }
    0x4C = @{ Name = 'Braswell/Cherry Trail (Atom/Celeron/Pentium)'; Gens = @(); Year = 2015 }
    0x5C = @{ Name = 'Apollo Lake (Celeron/Pentium)'; Gens = @(); Year = 2016 }
    0x7A = @{ Name = 'Gemini Lake (Celeron/Pentium Silver)'; Gens = @(); Year = 2017 }
    0x96 = @{ Name = 'Elkhart Lake'; Gens = @(); Year = 2021 }
    0x9C = @{ Name = 'Jasper Lake (Celeron/Pentium Silver)'; Gens = @(); Year = 2021 }
    0x17 = @{ Name = 'Penryn (Core 2)'; Gens = @(0); Year = 2008 }
    0x0F = @{ Name = 'Merom (Core 2)'; Gens = @(0); Year = 2006 }
}

# Intel-Modelle 0x8E/0x9E: Generation hängt vom Stepping ab (Kaby/Coffee/Whiskey/Comet Lake)
function Get-BCIntelGensForKabyFamily {
    param([int]$Model, [int]$Stepping)
    if ($Model -eq 0x8E) {
        switch ($Stepping) {
            9  { return @{ Name = 'Kaby Lake-U/Y (7. Gen.) bzw. Amber Lake-Y (8. Gen.)'; Gens = @(7, 8); Year = 2016 } }
            10 { return @{ Name = 'Kaby Lake-R (8. Gen.)'; Gens = @(8); Year = 2017 } }
            11 { return @{ Name = 'Whiskey Lake (8. Gen.)'; Gens = @(8); Year = 2018 } }
            12 { return @{ Name = 'Comet Lake-U / Whiskey Lake (8./10. Gen.)'; Gens = @(8, 10); Year = 2019 } }
            default { return @{ Name = 'Kaby/Coffee/Whiskey/Comet Lake (7.-10. Gen.)'; Gens = @(7, 8, 10); Year = 2016 } }
        }
    }
    switch ($Stepping) {
        9  { return @{ Name = 'Kaby Lake-H/S (7. Gen.)'; Gens = @(7); Year = 2017 } }
        10 { return @{ Name = 'Coffee Lake (8. Gen.)'; Gens = @(8); Year = 2017 } }
        11 { return @{ Name = 'Coffee Lake (8./9. Gen.)'; Gens = @(8, 9); Year = 2018 } }
        12 { return @{ Name = 'Coffee Lake Refresh (8./9. Gen.)'; Gens = @(8, 9); Year = 2018 } }
        13 { return @{ Name = 'Coffee Lake Refresh (9. Gen.)'; Gens = @(9); Year = 2019 } }
        default { return @{ Name = 'Kaby/Coffee Lake (7.-9. Gen.)'; Gens = @(7, 8, 9); Year = 2017 } }
    }
}

# AMD: Zen-Stufe aus Familie/Modell (nach LLVM Host.cpp). Zen+ = 1.5, Zen 3+ = 3.5
function Get-BCAmdArch {
    param([int]$Family, [int]$Model)
    $zen = $null; $name = 'AMD'; $year = $null
    function InRange([int]$v, [int]$a, [int]$b) { return ($v -ge $a -and $v -le $b) }
    if ($Family -lt 0x17) {
        return @{ Zen = 0; Name = 'AMD vor Zen (Bulldozer/Jaguar o. ä.)'; Year = 2014 }
    }
    if ($Family -eq 0x17) {
        if ((InRange $Model 0x30 0x3F) -or $Model -eq 0x47 -or (InRange $Model 0x60 0x7F) -or (InRange $Model 0x84 0x87) -or (InRange $Model 0x90 0xAF)) {
            $zen = 2
        } elseif ($Model -eq 0x18 -or $Model -eq 0x08) { $zen = 1.5 } else { $zen = 1 }
        switch ($Model) {
            0x01 { $name = 'Summit Ridge (Zen)'; $year = 2017 }
            0x08 { $name = 'Pinnacle Ridge (Zen+)'; $year = 2018 }
            0x11 { $name = 'Raven Ridge (Zen)'; $year = 2018 }
            0x18 { $name = 'Picasso (Zen+)'; $year = 2019 }
            0x20 { $name = 'Dali (Zen)'; $year = 2020 }
            0x60 { $name = 'Renoir (Zen 2)'; $year = 2020 }
            0x68 { $name = 'Lucienne (Zen 2)'; $year = 2021 }
            0x71 { $name = 'Matisse (Zen 2)'; $year = 2019 }
            0x90 { $name = 'Van Gogh (Zen 2)'; $year = 2022 }
            0xA0 { $name = 'Mendocino (Zen 2)'; $year = 2022 }
        }
    } elseif ($Family -eq 0x19) {
        if (InRange $Model 0x40 0x4F) { $zen = 3.5 }
        elseif ((InRange $Model 0x10 0x1F) -or (InRange $Model 0x60 0x7F) -or (InRange $Model 0xA0 0xAF)) { $zen = 4 }
        else { $zen = 3 }
        switch ($Model) {
            0x21 { $name = 'Vermeer (Zen 3)'; $year = 2020 }
            0x40 { $name = 'Rembrandt (Zen 3+)'; $year = 2022 }
            0x44 { $name = 'Rembrandt (Zen 3+)'; $year = 2022 }
            0x50 { $name = 'Cezanne/Barcelo (Zen 3)'; $year = 2021 }
            0x61 { $name = 'Raphael/Dragon Range (Zen 4)'; $year = 2022 }
            0x74 { $name = 'Phoenix (Zen 4)'; $year = 2023 }
            0x75 { $name = 'Phoenix/Hawk Point (Zen 4)'; $year = 2023 }
            0x78 { $name = 'Phoenix 2 (Zen 4)'; $year = 2023 }
            0x7C { $name = 'Hawk Point (Zen 4)'; $year = 2024 }
        }
    } elseif ($Family -eq 0x1A) {
        if ((InRange $Model 0x50 0x5F) -or (InRange $Model 0x80 0xCF) -or (InRange $Model 0xD8 0xE7)) { $zen = 6 } else { $zen = 5 }
        switch ($Model) {
            0x20 { $name = 'Strix Point (Zen 5)'; $year = 2024 }
            0x24 { $name = 'Strix Point (Zen 5)'; $year = 2024 }
            0x44 { $name = 'Granite Ridge/Fire Range (Zen 5)'; $year = 2024 }
            0x60 { $name = 'Krackan Point (Zen 5)'; $year = 2025 }
            0x70 { $name = 'Strix Halo (Zen 5)'; $year = 2025 }
        }
    } else {
        $zen = 6
    }
    if ($name -eq 'AMD') { $name = 'AMD ' + (Format-BCZen $zen) + (' (Familie 0x{0:X2}, Modell 0x{1:X2})' -f $Family, $Model) }
    if (-not $year) {
        $year = switch ($zen) { 1 { 2017 } 1.5 { 2018 } 2 { 2019 } 3 { 2020 } 3.5 { 2022 } 4 { 2022 } 5 { 2024 } default { 2026 } }
    }
    return @{ Zen = $zen; Name = $name; Year = $year }
}

function Format-BCZen {
    param($Zen)
    if ($null -eq $Zen) { return 'unbekannt' }
    switch ([double]$Zen) {
        0 { return 'vor Zen' }
        1 { return 'Zen' }
        1.5 { return 'Zen+' }
        3.5 { return 'Zen 3+' }
        default { return 'Zen ' + [int]$Zen }
    }
}

# Tatsächliche Architektur aus Kernel-Daten
function Get-BCCpuArch {
    param([string]$Vendor, [int]$Family, [int]$Model, [int]$Stepping)
    $r = @{ Vendor = $Vendor; Codename = 'unbekannt'; IntelRanks = @(); Zen = $null; LaunchYear = $null; Known = $false }
    if ($Vendor -eq 'Intel') {
        if ($Family -eq 6) {
            $entry = $null
            if ($Model -eq 0x8E -or $Model -eq 0x9E) { $entry = Get-BCIntelGensForKabyFamily -Model $Model -Stepping $Stepping }
            elseif ($script:BCIntelModels.ContainsKey($Model)) { $entry = $script:BCIntelModels[$Model] }
            if ($entry) {
                $r.Codename = $entry.Name; $r.IntelRanks = @($entry.Gens); $r.LaunchYear = $entry.Year; $r.Known = $true
            }
        } elseif ($Family -ge 18) {
            $r.Codename = 'Nova Lake oder neuer'; $r.IntelRanks = @(18); $r.LaunchYear = 2026; $r.Known = $true
        }
    } elseif ($Vendor -eq 'AMD') {
        $a = Get-BCAmdArch -Family $Family -Model $Model
        $r.Codename = $a.Name; $r.Zen = $a.Zen; $r.LaunchYear = $a.Year; $r.Known = $true
    }
    return (New-Object PSObject -Property $r)
}

# Atom/Celeron/Pentium mit N-Nummern: erwartete Intel-Modelle
function Get-BCIntelNModels {
    param([string]$Number)
    $n = [int]$Number
    if ($Number.Length -eq 4) {
        if ($n -ge 2800 -and $n -lt 3000) { return @(0x37) }
        if ($n -ge 3500 -and $n -lt 3600) { return @(0x37) }
        if (@(3000, 3010, 3050, 3060, 3150, 3160, 3700, 3710) -contains $n) { return @(0x4C) }
        if (@(3350, 3450, 4200) -contains $n) { return @(0x5C) }
        if (@(4000, 4100, 5000, 4020, 4120, 5030) -contains $n) { return @(0x7A) }
        if (@(4500, 4505, 5100, 5105, 6000, 6005) -contains $n) { return @(0x9C) }
    }
    return $null
}

# Im CPU-Namen behauptete Generation
function Get-BCCpuClaim {
    param([string]$Name)
    if ((Test-BCBlank $Name)) { return $null }
    $s = $Name -replace '\((R|TM|C)\)', ' ' -replace '\s+', ' '
    $c = @{ Vendor = $null; Rank = $null; Zen = $null; ExpectModels = $null; Label = $null; Model = $null }

    # ---- Intel
    if ($s -match 'Core\s+Ultra\s+X?\d+\s*-?\s*(\d)(\d{2})([A-Z]*)') {
        $series = [int]$Matches[1]
        $c.Vendor = 'Intel'; $c.Model = "Core Ultra $($Matches[1])$($Matches[2])$($Matches[3])"
        $c.Rank = switch ($series) { 1 { 15 } 2 { 16 } 3 { 17 } default { 18 } }
        $c.Label = "Core Ultra Serie $series"
        return (New-Object PSObject -Property $c)
    }
    if ($s -match 'Core\s+i\d-N(\d{3})') {
        $c.Vendor = 'Intel'; $c.Rank = 12; $c.ExpectModels = @(0xBE); $c.Label = 'N-Serie (Alder Lake-N/Twin Lake)'; $c.Model = "i3-N$($Matches[1])"
        return (New-Object PSObject -Property $c)
    }
    if ($s -match 'Core\s+i\d-(\d{3,5})([A-Z]{0,2}\d?)') {
        $num = $Matches[1]
        $gen = if ($num.Length -eq 3) { 1 } elseif ($num.Length -eq 5) { [int]$num.Substring(0, 2) } elseif ($num.StartsWith('1')) { [int]$num.Substring(0, 2) } else { [int]$num.Substring(0, 1) }
        $c.Vendor = 'Intel'; $c.Rank = $gen; $c.Label = "Core i $gen. Generation"; $c.Model = "i-$num$($Matches[2])"
        return (New-Object PSObject -Property $c)
    }
    if ($s -match 'Core\s+([357])\s+(\d)(\d{2})([A-Z]*)') {
        $c.Vendor = 'Intel'; $c.Rank = 13; $c.Label = "Core $($Matches[1]) (Serie $($Matches[2]), Raptor-Lake-Refresh)"; $c.Model = "Core $($Matches[1]) $($Matches[2])$($Matches[3])$($Matches[4])"
        return (New-Object PSObject -Property $c)
    }
    if ($s -match 'Intel\s+(?:Processor\s+)?N(\d{2,3})\b' -and $s -notmatch 'Celeron|Pentium|Atom') {
        $c.Vendor = 'Intel'; $c.Rank = 12; $c.ExpectModels = @(0xBE); $c.Label = 'N-Serie (Alder Lake-N/Twin Lake)'; $c.Model = "N$($Matches[1])"
        return (New-Object PSObject -Property $c)
    }
    if ($s -match '(Celeron|Pentium)\s+(?:Silver\s+)?N(\d{4})') {
        $exp = Get-BCIntelNModels -Number $Matches[2]
        if ($exp) {
            $c.Vendor = 'Intel'; $c.ExpectModels = $exp; $c.Label = "$($Matches[1]) N$($Matches[2])"; $c.Model = "N$($Matches[2])"
            return (New-Object PSObject -Property $c)
        }
        return $null
    }

    # ---- AMD
    if ($s -match 'Ryzen\s+AI\s') {
        $c.Vendor = 'AMD'; $c.Zen = 5; $c.Label = 'Ryzen AI (Zen 5)'; $c.Model = ($s -replace '^.*?(Ryzen\s+AI.*)$', '$1').Trim()
        return (New-Object PSObject -Property $c)
    }
    if ($s -match 'Ryzen\s+[3579]\s+(?:PRO\s+)?(\d)(\d)(\d)(\d)([A-Z]{1,2})?\b') {
        $d1 = [int]$Matches[1]; $d2 = [int]$Matches[2]; $d3 = [int]$Matches[3]; $d4 = [int]$Matches[4]; $suffix = "$($Matches[5])"
        $num = "$d1$d2$d3$d4"
        $mobile = $suffix -match '^(U|H|HS|HX|C|E)$'
        $zen = $null
        switch ($d1) {
            2 { if ($mobile) { $zen = 1 } }
            3 { if ($mobile) { if ($num -eq '3250') { $zen = 1 } else { $zen = 1.5 } } }
            4 { if ($mobile) { $zen = 2 } }
            5 {
                if ($mobile) {
                    if ($num.EndsWith('25')) { $zen = 3 }
                    elseif ($suffix -eq 'U' -and @(3, 5, 7) -contains $d2 -and $d3 -eq 0) { $zen = 2 }
                    else { $zen = 3 }
                }
            }
            6 { if ($mobile) { $zen = 3.5 } }
            default {
                if ($d1 -ge 7 -and $mobile) {
                    switch ($d3) {
                        1 { $zen = 1.5 }
                        2 { $zen = 2 }
                        3 { if ($d4 -eq 5) { $zen = 3.5 } else { $zen = 3 } }
                        4 { $zen = 4 }
                        5 { $zen = 5 }
                    }
                }
            }
        }
        if ($null -ne $zen) {
            $c.Vendor = 'AMD'; $c.Zen = $zen; $c.Label = "Ryzen $num$suffix ($(Format-BCZen $zen))"; $c.Model = "$num$suffix"
            return (New-Object PSObject -Property $c)
        }
        return $null
    }
    if ($s -match 'Ryzen\s+[3579]\s+(2\d0)\b') {
        $c.Vendor = 'AMD'; $c.Zen = 4; $c.Label = "Ryzen $($Matches[1]) (Zen 4)"; $c.Model = $Matches[1]
        return (New-Object PSObject -Property $c)
    }
    if ($s -match 'Athlon\s+(?:Silver\s+|Gold\s+)?(\d{4})([A-Z])?') {
        $num = $Matches[1]
        if ($num -match '^3\d50$') { $c.Vendor = 'AMD'; $c.Zen = 1; $c.Label = "Athlon $num (Zen)"; $c.Model = $num; return (New-Object PSObject -Property $c) }
        if ($num -match '^7\d20$') { $c.Vendor = 'AMD'; $c.Zen = 2; $c.Label = "Athlon $num (Zen 2)"; $c.Model = $num; return (New-Object PSObject -Property $c) }
    }
    return $null
}

# Vergleich Behauptung (Name) gegen Realität (Architektur)
# Rückgabe: @{ Status = 'match'|'older'|'newer'|'vendor'|'unknown'; Text = ... }
function Compare-BCCpuClaim {
    param($Claim, $Arch, [int]$Model)
    if (-not $Claim -or -not $Arch -or -not $Arch.Known) {
        return @{ Status = 'unknown'; Text = 'Automatischer Abgleich nicht möglich (Name oder Architektur nicht in der Datenbank).' }
    }
    if ($Claim.Vendor -ne $Arch.Vendor) {
        return @{ Status = 'vendor'; Text = "Der Name nennt einen $($Claim.Vendor)-Prozessor, der Chip meldet sich aber als $($Arch.Vendor)." }
    }
    if ($Claim.Vendor -eq 'Intel') {
        if ($Claim.ExpectModels) {
            if ($Claim.ExpectModels -contains $Model) { return @{ Status = 'match'; Text = "Name ($($Claim.Label)) passt zur Architektur ($($Arch.Codename))." } }
            return @{ Status = 'mismatch-soft'; Text = "Name ($($Claim.Label)) passt nicht zur gemeldeten Architektur ($($Arch.Codename))." }
        }
        $ranks = @($Arch.IntelRanks)
        if ($ranks.Count -eq 0) { return @{ Status = 'unknown'; Text = "Architektur $($Arch.Codename) ohne Generationszuordnung." } }
        if ($ranks -contains $Claim.Rank) { return @{ Status = 'match'; Text = "Name ($($Claim.Label)) passt zur Architektur ($($Arch.Codename))." } }
        $max = ($ranks | Measure-Object -Maximum).Maximum
        if ($Claim.Rank -gt $max) {
            return @{ Status = 'newer'; Text = "Der Name behauptet $($Claim.Label), der Chip ist aber $($Arch.Codename) – also älter als angegeben." }
        }
        return @{ Status = 'older'; Text = "Der Name ($($Claim.Label)) ist älter als die Architektur ($($Arch.Codename)) – ungewöhnlich, aber kein Hinweis auf Betrug." }
    }
    if ($Claim.Vendor -eq 'AMD') {
        if ($null -eq $Arch.Zen -or $null -eq $Claim.Zen) { return @{ Status = 'unknown'; Text = 'Zen-Generation nicht bestimmbar.' } }
        if ([double]$Claim.Zen -eq [double]$Arch.Zen) { return @{ Status = 'match'; Text = "Name ($($Claim.Label)) passt zur Architektur ($($Arch.Codename))." } }
        if ([double]$Claim.Zen -gt [double]$Arch.Zen) {
            return @{ Status = 'newer'; Text = "Der Name behauptet $($Claim.Label), der Chip ist aber $($Arch.Codename) – also eine ältere Architektur als angegeben (so wie beim bekannten Chuwi-Betrug)." }
        }
        return @{ Status = 'older'; Text = "Der Name ($($Claim.Label)) nennt eine ältere Architektur als der Chip ($($Arch.Codename)) – ungewöhnlich, aber kein Hinweis auf Betrug." }
    }
    return @{ Status = 'unknown'; Text = 'Kein Abgleich möglich.' }
}

# Windows-11-CPU-Prüfung nach Microsofts HardwareReadiness.ps1 (Familie/Modell/Stepping)
function Test-BCWin11Cpu {
    param([string]$Vendor, [int]$Arch, [int]$Family, [int]$Model, [int]$Stepping, [string]$CpuName, [string]$SystemModel)
    # Arch: 9 = x64, 12 = ARM64, 0 = x86
    if ($Arch -eq 12) {
        if ($Vendor -eq 'Qualcomm') { return @{ Ok = $true; Text = 'Qualcomm-ARM-Prozessor (Windows 11 auf ARM).' } }
        return @{ Ok = $null; Text = 'ARM-Prozessor – Prüfung nicht möglich.' }
    }
    if ($Arch -ne 9 -and $Arch -ne 0) { return @{ Ok = $false; Text = 'Nicht unterstützte Prozessorarchitektur.' } }
    if ($Vendor -eq 'Intel') {
        # Microsoft prüft "Familie >= 6 und Modell <= 95"; neuere Intel-Familien (18/19, Nova Lake) haben wieder
        # kleine Modellnummern und würden fälschlich durchfallen – daher nur Familie 6 (und ältere) so prüfen.
        if ($Family -lt 6 -or $Family -eq 15) {
            return @{ Ok = $false; Text = 'Sehr alter Intel-Prozessor – von Windows 11 nicht unterstützt.' }
        }
        if ($Family -eq 6 -and $Model -le 95 -and $Model -ne 85) {
            return @{ Ok = $false; Text = 'Intel bis einschließlich 7. Generation (bzw. ältere Atom/Celeron) wird von Windows 11 nicht unterstützt.' }
        }
        if ($Family -eq 6 -and ($Model -eq 142 -or $Model -eq 158) -and $Stepping -eq 9) {
            $pf = $null
            try { $pf = (Get-ItemProperty -Path 'HKLM:\HARDWARE\DESCRIPTION\System\CentralProcessor\0' -Name 'Platform Specific Field 1' -ErrorAction Stop).'Platform Specific Field 1' } catch { }
            $ok = ($Model -eq 142 -and $pf -eq 16) -or ($Model -eq 158 -and $pf -eq 8)
            if (-not $ok -and $CpuName -match 'i7-7820HQ' -and @('surface studio 2', 'precision 5520') -contains ("$SystemModel".Trim().ToLower())) { $ok = $true }
            if ($ok) { return @{ Ok = $true; Text = 'Sonderfall Kaby Lake mit freigegebener Plattform.' } }
            return @{ Ok = $false; Text = 'Intel 7. Generation (Kaby Lake) – nicht unterstützt.' }
        }
        return @{ Ok = $true; Text = 'Intel ab 8. Generation – unterstützt.' }
    }
    if ($Vendor -eq 'AMD') {
        if ($Family -lt 23 -or ($Family -eq 23 -and ($Model -eq 1 -or $Model -eq 17))) {
            return @{ Ok = $false; Text = 'AMD vor Zen+ (z. B. Ryzen 1000 / Ryzen 2000-APUs) – nicht unterstützt.' }
        }
        return @{ Ok = $true; Text = 'AMD ab Zen+ – unterstützt.' }
    }
    return @{ Ok = $false; Text = "Unbekannter Prozessorhersteller ($Vendor)." }
}
