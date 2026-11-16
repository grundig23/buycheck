# BuyCheck-Simulation: echtes BuyCheck (lib + checks) gegen nachgebautes Windows. Szenarien A, B, C (Windows 7).
param([ValidateSet('A', 'B', 'C')][string]$Scenario = 'A', [switch]$MenuTest)
$ErrorActionPreference = 'Continue'
$SIM = $PSScriptRoot; $root = (Resolve-Path (Join-Path $PSScriptRoot '../..')).Path
$env:windir = "$SIM/win"; $env:SystemDrive = "$SIM/c"; $env:ProgramData = "$SIM/pd"; $env:ProgramFiles = "$SIM/pf"; $env:TEMP = '/tmp'
$env:PATH = "$SIM/bin:" + $env:PATH
if ($Scenario -eq 'C') { $env:SIM_NO_BATTERYREPORT = '1' } else { Remove-Item Env:SIM_NO_BATTERYREPORT -ErrorAction SilentlyContinue }
if (-not ('BuyCheckSim.Win32' -as [type])) { Add-Type -Path "$SIM/SimWin32.cs" }
. "$SIM/simdata.ps1"

# ---------------------------------------------------------------- BuyCheck laden (gleiche Reihenfolge wie BuyCheck.ps1)
$script:BCRoot = $root; $script:BCVersion = '2.0.0-sim'
foreach ($f in @('lib/Core.ps1', 'lib/Win32.ps1', 'lib/Native.ps1', 'lib/Ui.ps1', 'lib/Interactive.ps1', 'lib/Workloads.ps1', 'lib/CpuDb.ps1', 'lib/Report.ps1')) { . "$root/$f" }
$script:BCW32 = [BuyCheckSim.Win32]     # statt der echten Windows-Funktionen
$W = [BuyCheckSim.Win32]

# ---------------------------------------------------------------- Szenariodaten
$S = @{}
switch ($Scenario) {
    'A' {
        $S = @{ Manufacturer = 'LENOVO'; Product = '20L5S00G00'; Version = 'ThinkPad T480'; SmbiosSerial = 'PF1ABCDE'; BiosVendor = 'LENOVO'; BiosVersion = 'N2IET98W (1.76 )'; BiosDateText = '05/12/2024'
            Chassis = 10; Cores = 4; Threads = 8; MaxMHz = 4200; CpuEax = 0x000806EA; CpuVendor = 'Intel(R) Corporation'; SmbiosCpuName = 'Intel(R) Core(TM) i7-8650U CPU @ 1.90GHz'
            Slots = 2; MemForm = 13; MemType = 26; BatDesignDiv10 = 5700; BatSbdsDate = 0 }
        $W::Brand = 'Intel(R) Core(TM) i7-8650U CPU @ 1.90GHz'; $W::Level = 6; $W::Revision16 = 0x8E0A; $W::Procs = 8; $W::Cores = 4; $W::ThreadsPerCore = 2; $W::L3 = 8MB
        $W::BusType = [int[]]@(17, 7); $W::Nvme = [bool[]]@($true, $false); $W::Product = [string[]]@('Samsung SSD 980 PRO 1TB', 'Ultra')
        $W::NvmeIdentify = New-SimNvmeIdentify -Vid 0x1E4B -Model 'Samsung SSD 980 PRO 1TB' -Serial 'S5GXNF0R123456' -Fw '5B2QGXA7' -Capacity 1000204886016
        $W::NvmeHealth = New-SimNvmeHealth -Used 12 -Spare 100 -Poh 3200 -Cycles 1500 -Unsafe 60 -Media 0 -WrittenTB 18.5
        $W::SlowFrom = 375GB; $W::SlowTo = 375GB + 256MB
        $regCpu = 'Intel(R) Core(TM) i7-1165G7 @ 2.80GHz'   # gefälschter Name in der Registry
    }
    'B' {
        $S = @{ Manufacturer = 'CHUWI Innovation And Technology(ShenZhen)co.,Ltd'; Product = 'CoreBook X'; Version = 'Default string'; SmbiosSerial = 'Default string'; BiosVendor = 'American Megatrends'; BiosVersion = 'CBX-1.05'; BiosDateText = '01/10/2025'
            Chassis = 10; Cores = 6; Threads = 12; MaxMHz = 4300; CpuEax = 0x00A50F00; CpuVendor = 'Advanced Micro Devices, Inc.'; SmbiosCpuName = 'AMD Ryzen 5 7430U with Radeon Graphics'
            Slots = 1; MemForm = 11; MemType = 30; BatDesignDiv10 = 4620; BatSbdsDate = 0 }
        $W::Brand = 'AMD Ryzen 5 7430U with Radeon Graphics'; $W::Level = 0x17; $W::Revision16 = 0x6801; $W::Procs = 12; $W::Cores = 6; $W::ThreadsPerCore = 2; $W::L2 = 512KB; $W::L3 = 8MB
        $W::BusType = [int[]]@(11, 7); $W::Nvme = [bool[]]@($false, $false); $W::Product = [string[]]@('KINGSTON SA400S37480G', 'Ultra'); $W::Size = [long[]]@(480103981056, 32000000000)
        $W::BadOffsets = [long[]]@(75GB + 3MB)
        $regCpu = 'AMD Ryzen 5 7430U with Radeon Graphics'
    }
    'C' {
        $S = @{ Manufacturer = 'LENOVO'; Product = '4180W1A'; Version = 'ThinkPad T420'; SmbiosSerial = 'R9ABCDE'; BiosVendor = 'LENOVO'; BiosVersion = '83ET82WW (1.52 )'; BiosDateText = '06/26/2018'
            Chassis = 10; Cores = 2; Threads = 4; MaxMHz = 2500; CpuEax = 0x000206A7; CpuVendor = 'Intel(R) Corporation'; SmbiosCpuName = 'Intel(R) Core(TM) i5-2520M CPU @ 2.50GHz'
            Slots = 2; MemForm = 13; MemType = 24; BatDesignDiv10 = 5616; BatSbdsDate = ((2012 - 1980) * 512 + 3 * 32 + 14) }
        $W::Brand = $null; $W::Level = 6; $W::Revision16 = 0x2A07; $W::Procs = 4; $W::Cores = 2; $W::ThreadsPerCore = 2; $W::L3 = 3MB
        $W::BusType = [int[]]@(11, 7); $W::Nvme = [bool[]]@($false, $false); $W::SeekPenalty = [bool[]]@($true, $false); $W::NvmeSupported = $false
        $W::Product = [string[]]@('HITACHI HTS725032A9A364', 'Ultra'); $W::Size = [long[]]@(320072933376, 32000000000); $W::BlockSleepMs = 20; $W::SlowSleepMs = 40
        $W::HasFirmwareTypeApi = $false; $W::FirmwareType = 1; $W::Sse42 = $false
        $W::MemTotal = 8GB; $W::MemAvail = 3GB; $W::InstalledKB = 8MB
        $regCpu = 'Intel(R) Core(TM) i5-2520M CPU @ 2.50GHz'
    }
}
$W::Smbios = New-SimSmbios $S
$global:Scenario = $Scenario
$global:SimS = $S
$global:RegCpu = $regCpu
. "$SIM/mocks2.ps1"

# ---------------------------------------------------------------- Prüfmodule laden und kurz einstellen
foreach ($f in (Get-ChildItem "$root/checks" -Filter *.ps1 | Sort-Object Name)) { . $f.FullName }
"GELADEN: $($script:BCChecks.Count) Prüfmodule"

if ($MenuTest) { . "$SIM/menutest.ps1"; return }

foreach ($c in $script:BCChecks) {
    switch ($c.Id) {
        'cpu.stress' { $c.Info.Options[0].Value = 0.5 }
        'ram.test' { $c.Info.Options[0].Value = 0.2 }
        'battery.discharge' { $c.Info.Options[0].Value = 0.25 }
        'storage.readscan' { $c.Info.Options[0].Value = 2; $c.Info.Options[1].Value = 1 }
    }
}
$script:BCReportDir = "$SIM/report$Scenario"
New-Item -ItemType Directory -Force -Path $script:BCReportDir | Out-Null
Remove-Item "$($script:BCReportDir)/*" -Force -ErrorAction SilentlyContinue
$started = Get-Date
$sel = @($script:BCChecks | Sort-Object RunOrder)
Set-BCKeepAwake $true
$i = 0
foreach ($c in $sel) {
    $i++
    $global:SimCurrent = $c.Id
    if ($c.Id -eq 'battery.discharge') { $global:SimDischarge = $true }
    Invoke-BCCheck -Check $c -Index $i -Total $sel.Count
    $global:SimDischarge = $false
}
Set-BCKeepAwake $false
$path = New-BCReport -Directory $script:BCReportDir -ProfileLabel "Simulation $Scenario" -Started $started -NotRun @()
"BERICHT: $path"
$cnt = Get-BCLevelCounts; "ZÄHLER: $($cnt | ConvertTo-Json -Compress)"
"OFFENE HANDLES: $($W::OpenHandles)"
"SCHREIBZUGRIFF ANGEFORDERT: $($W::WriteAccessRequested)"
"ZUGRIFFE:"; $W::Log | Where-Object { $_ -match 'CreateFile|SetThread' } | Group-Object | ForEach-Object { "  $($_.Count)x $($_.Name)" }
"MCI:"; $W::Log | Where-Object { $_ -match '^MCI' } | Select-Object -Unique | ForEach-Object { "  $_" }
"FRAGEN OHNE REGEL:"; $global:SimUnmatched | Select-Object -Unique | ForEach-Object { "  $_" }
"DIAGNOSE:"; $script:BCDebug | Select-Object -First 40
