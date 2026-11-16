$ErrorActionPreference = 'Continue'
$SIM = '/tmp/bc-build/sim'; $root = '/home/user/buycheck'
$env:windir = "$SIM/win"; $env:SystemDrive = "$SIM/c"; $env:ProgramData = "$SIM/pd"; $env:ProgramFiles = "$SIM/pf"; $env:TEMP = '/tmp'
$env:PATH = "$SIM/bin:" + $env:PATH
Add-Type -Path "$SIM/SimStubs.cs"
$script:BCRoot = $root; $script:BCVersion = '1.0.0-sim'
. "$root/lib/Core.ps1"; . "$root/lib/CpuDb.ps1"; . "$root/lib/Report.ps1"
. "$SIM/mocks.ps1"
# Entladetest: dynamischer Akku
$global:SimDischarge = $false; $global:SimPct = 80.0; $global:SimMWh = 36000.0; $global:SimN = 0
$origCim = ${function:Get-CimInstance}
function Get-CimInstance {
    [CmdletBinding()] param([string]$Namespace = 'root/cimv2', [Parameter(Position = 0)][string]$ClassName, [string]$Filter)
    if ($global:SimDischarge -and $ClassName -eq 'BatteryStatus') {
        $global:SimN++; $global:SimMWh -= 160; $global:SimPct -= $(if ($global:SimN -eq 12) { 5 } else { 0.3 })
        return [pscustomobject]@{ RemainingCapacity = [int]$global:SimMWh; Voltage = 11800 - $global:SimN * 8; ChargeRate = 0; DischargeRate = 19500; PowerOnline = $false; Charging = $false; Discharging = $true }
    }
    if ($global:SimDischarge -and $ClassName -eq 'Win32_Battery') { return [pscustomobject]@{ EstimatedChargeRemaining = [int]$global:SimPct } }
    & $origCim -Namespace $Namespace -ClassName $ClassName -Filter $Filter
}
function Start-Sleep { [CmdletBinding()] param([Parameter(Position = 0)][double]$Seconds, [int]$Milliseconds) $ms = if ($Milliseconds) { $Milliseconds } else { $Seconds * 1000 }; Microsoft.PowerShell.Utility\Start-Sleep -Milliseconds ([int]($ms / 10)) }

foreach ($f in (Get-ChildItem "$root/checks" -Filter *.ps1 | Sort-Object Name)) { . $f.FullName }
foreach ($c in $script:BCChecks) {
    switch ($c.Id) {
        'cpu.stress' { $c.Info.Options[0].Value = 0.5 }
        'ram.test' { $c.Info.Options[0].Value = 0.2 }
        'battery.discharge' { $c.Info.Options[0].Value = 0.25 }
    }
}
$script:BCReportDir = "$SIM/report"; Remove-Item "$SIM/report/*" -Force -ErrorAction SilentlyContinue
$started = Get-Date
$sel = @($script:BCChecks | Sort-Object RunOrder)
$i = 0
foreach ($c in $sel) {
    $i++
    if ($c.Id -eq 'battery.discharge') { $global:SimDischarge = $true }
    Invoke-BCCheck -Check $c -Index $i -Total $sel.Count
    $global:SimDischarge = $false
}
$path = New-BCReport -Directory $script:BCReportDir -ProfileLabel 'Gründlich (Simulation)' -Started $started -NotRun @()
"BERICHT: $path"
$cnt = Get-BCLevelCounts; "ZÄHLER: $($cnt | ConvertTo-Json -Compress)"
"DIAGNOSE:"; $script:BCDebug | Select-Object -First 30
