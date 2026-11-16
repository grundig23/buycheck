$root = (Resolve-Path (Join-Path $PSScriptRoot '../..')).Path
. "$root/lib/Core.ps1"; . "$root/lib/CpuDb.ps1"
$fail = 0
function Check($name, $cond) { if ($cond) { Write-Host "PASS $name" } else { Write-Host "FAIL $name" -ForegroundColor Red; $script:fail++ } }

# Name -> Claim
$c = Get-BCCpuClaim 'Intel(R) Core(TM) i7-8650U CPU @ 1.90GHz'; Check 'i7-8650U gen8' ($c.Rank -eq 8)
$c = Get-BCCpuClaim 'Intel(R) Core(TM) i5-1135G7 @ 2.40GHz'; Check 'i5-1135G7 gen11' ($c.Rank -eq 11)
$c = Get-BCCpuClaim 'Intel(R) Core(TM) i7-10510U CPU @ 1.80GHz'; Check 'i7-10510U gen10' ($c.Rank -eq 10)
$c = Get-BCCpuClaim 'Intel(R) Core(TM) i9-13900HX'; Check 'i9-13900HX gen13' ($c.Rank -eq 13)
$c = Get-BCCpuClaim 'Intel(R) Core(TM) Ultra 7 155H'; Check 'Ultra 7 155H rank15' ($c.Rank -eq 15)
$c = Get-BCCpuClaim 'Intel(R) Core(TM) Ultra 7 258V'; Check 'Ultra 7 258V rank16' ($c.Rank -eq 16)
$c = Get-BCCpuClaim 'Intel(R) Core(TM) 5 120U'; Check 'Core 5 120U rank13' ($c.Rank -eq 13)
$c = Get-BCCpuClaim 'Intel(R) N100'; Check 'N100 models' ($c.ExpectModels -contains 0xBE)
$c = Get-BCCpuClaim 'Intel(R) Celeron(R) N4020 CPU @ 1.10GHz'; Check 'N4020 gemini' ($c.ExpectModels -contains 0x7A)
$c = Get-BCCpuClaim 'AMD Ryzen 5 5500U with Radeon Graphics'; Check '5500U zen2' ($c.Zen -eq 2)
$c = Get-BCCpuClaim 'AMD Ryzen 5 7430U with Radeon Graphics'; Check '7430U zen3' ($c.Zen -eq 3)
$c = Get-BCCpuClaim 'AMD Ryzen 7 7735HS with Radeon Graphics'; Check '7735HS zen3+' ($c.Zen -eq 3.5)
$c = Get-BCCpuClaim 'AMD Ryzen 7 PRO 7840U w/ Radeon 780M Graphics'; Check '7840U zen4' ($c.Zen -eq 4)
$c = Get-BCCpuClaim 'AMD Ryzen 5 5625U with Radeon Graphics'; Check '5625U zen3' ($c.Zen -eq 3)
$c = Get-BCCpuClaim 'AMD Ryzen 5 5600H with Radeon Graphics'; Check '5600H zen3' ($c.Zen -eq 3)
$c = Get-BCCpuClaim 'AMD Ryzen 5 3500U with Radeon Vega Mobile Gfx'; Check '3500U zen+' ($c.Zen -eq 1.5)
$c = Get-BCCpuClaim 'AMD Ryzen 5 2500U with Radeon Vega Mobile Gfx'; Check '2500U zen1' ($c.Zen -eq 1)
$c = Get-BCCpuClaim 'AMD Ryzen AI 9 HX 370 w/ Radeon 890M'; Check 'AI 370 zen5' ($c.Zen -eq 5)
$c = Get-BCCpuClaim 'AMD Ryzen 7 250 w/ Radeon 780M Graphics'; Check 'Ryzen 250 zen4' ($c.Zen -eq 4)
$c = Get-BCCpuClaim 'AMD Ryzen 7 5800X 8-Core Processor'; Check '5800X desktop -> null' ($null -eq $c)

# Architektur
$a = Get-BCCpuArch -Vendor AMD -Family 0x17 -Model 0x68 -Stepping 1; Check 'Lucienne zen2' ($a.Zen -eq 2 -and $a.Codename -like 'Lucienne*')
$a = Get-BCCpuArch -Vendor AMD -Family 0x19 -Model 0x50 -Stepping 0; Check 'Cezanne zen3' ($a.Zen -eq 3)
$a = Get-BCCpuArch -Vendor AMD -Family 0x19 -Model 0x44 -Stepping 1; Check 'Rembrandt zen3+' ($a.Zen -eq 3.5)
$a = Get-BCCpuArch -Vendor AMD -Family 0x19 -Model 0x74 -Stepping 1; Check 'Phoenix zen4' ($a.Zen -eq 4)
$a = Get-BCCpuArch -Vendor AMD -Family 0x1A -Model 0x24 -Stepping 0; Check 'Strix zen5' ($a.Zen -eq 5)
$a = Get-BCCpuArch -Vendor Intel -Family 6 -Model 0x8E -Stepping 10; Check 'KBL-R gen8' (($a.IntelRanks -contains 8) -and $a.LaunchYear -eq 2017)
$a = Get-BCCpuArch -Vendor Intel -Family 6 -Model 0x8E -Stepping 9; Check 'KBL gen7/8' (($a.IntelRanks -contains 7) -and ($a.IntelRanks -contains 8))
$a = Get-BCCpuArch -Vendor Intel -Family 6 -Model 0x3A -Stepping 9; Check 'IvyBridge gen3' ($a.IntelRanks -contains 3)

# Der Chuwi-Fall: Name 7430U, Chip Lucienne (17h/68h)
$claim = Get-BCCpuClaim 'AMD Ryzen 5 7430U with Radeon Graphics'
$arch = Get-BCCpuArch -Vendor AMD -Family 0x17 -Model 0x68 -Stepping 1
$cmp = Compare-BCCpuClaim -Claim $claim -Arch $arch -Model 0x68
Check 'Chuwi-Fall erkannt (newer)' ($cmp.Status -eq 'newer'); Write-Host "   -> $($cmp.Text)"
# Registry-Fälschung: i7-8650U behauptet, Chip ist Ivy Bridge
$cmp = Compare-BCCpuClaim -Claim (Get-BCCpuClaim 'Intel(R) Core(TM) i7-8650U CPU') -Arch (Get-BCCpuArch -Vendor Intel -Family 6 -Model 0x3A -Stepping 9) -Model 0x3A
Check 'i7-8650U auf Ivy Bridge erkannt' ($cmp.Status -eq 'newer'); Write-Host "   -> $($cmp.Text)"
# Echt: i5-8250U auf KBL-R
$cmp = Compare-BCCpuClaim -Claim (Get-BCCpuClaim 'Intel(R) Core(TM) i5-8250U CPU @ 1.60GHz') -Arch (Get-BCCpuArch -Vendor Intel -Family 6 -Model 0x8E -Stepping 10) -Model 0x8E
Check 'i5-8250U echt -> match' ($cmp.Status -eq 'match')
# Echt: i5-1335U auf Raptor Lake-P
$cmp = Compare-BCCpuClaim -Claim (Get-BCCpuClaim 'Intel(R) Core(TM) i5-1335U') -Arch (Get-BCCpuArch -Vendor Intel -Family 6 -Model 0xBA -Stepping 3) -Model 0xBA
Check 'i5-1335U echt -> match' ($cmp.Status -eq 'match')
# Echt: i5-13420H auf Alder-Lake-Die
$cmp = Compare-BCCpuClaim -Claim (Get-BCCpuClaim 'Intel(R) Core(TM) i5-13420H') -Arch (Get-BCCpuArch -Vendor Intel -Family 6 -Model 0x9A -Stepping 3) -Model 0x9A
Check 'i5-13420H auf ADL -> match' ($cmp.Status -eq 'match')
# Vendor-Mismatch
$cmp = Compare-BCCpuClaim -Claim (Get-BCCpuClaim 'Intel(R) Core(TM) i7-8650U') -Arch (Get-BCCpuArch -Vendor AMD -Family 0x17 -Model 0x18 -Stepping 1) -Model 0x18
Check 'Intel-Name auf AMD -> vendor' ($cmp.Status -eq 'vendor')

# Windows 11
Check 'Win11 KBL-R ok' ((Test-BCWin11Cpu -Vendor Intel -Arch 9 -Family 6 -Model 0x8E -Stepping 10).Ok -eq $true)
Check 'Win11 Skylake nein' ((Test-BCWin11Cpu -Vendor Intel -Arch 9 -Family 6 -Model 0x4E -Stepping 3).Ok -eq $false)
Check 'Win11 Raven Ridge nein' ((Test-BCWin11Cpu -Vendor AMD -Arch 9 -Family 23 -Model 17 -Stepping 0).Ok -eq $false)
Check 'Win11 Picasso ok' ((Test-BCWin11Cpu -Vendor AMD -Arch 9 -Family 23 -Model 24 -Stepping 1).Ok -eq $true)
Check 'Win11 Nova Lake ok' ((Test-BCWin11Cpu -Vendor Intel -Arch 9 -Family 18 -Model 1 -Stepping 0).Ok -eq $true)
Check 'Win11 Tiger Lake ok' ((Test-BCWin11Cpu -Vendor Intel -Arch 9 -Family 6 -Model 0x8C -Stepping 1).Ok -eq $true)
"FAILED: $fail"
