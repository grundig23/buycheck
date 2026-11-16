import os, sys
SIM = os.path.dirname(os.path.abspath(__file__))
root = sys.argv[1]; out = sys.argv[2]; keys = sys.argv[3] if len(sys.argv) > 3 else "'4','enter'"
s=open(root+'/BuyCheck.ps1',encoding='utf-8-sig').read()
a=s.index('# ---------------------------------------------------------------- Umgebung prüfen')
b=s.index('# ---------------------------------------------------------------- Bausteine laden')
s=s[:a]+"$script:BCIsAdmin = $true\n"+s[b:]
inject = r'''$SIM = 'SIMDIR'
$env:windir = "$SIM/win"; $env:SystemDrive = "$SIM/c"; $env:ProgramData = "$SIM/pd"; $env:ProgramFiles = "$SIM/pf"; $env:TEMP = '/tmp'; $env:PATH = "$SIM/bin:" + $env:PATH
if (-not ('BuyCheckSim.Win32' -as [type])) { Add-Type -Path "$SIM/SimWin32.cs" }
. "$SIM/simdata.ps1"
$global:Scenario = 'A'
$W = [BuyCheckSim.Win32]
$global:SimS = @{ Manufacturer = 'LENOVO'; Product = '20L5S00G00'; Version = 'ThinkPad T480'; SmbiosSerial = 'PF1ABCDE'; BiosVendor = 'LENOVO'; BiosVersion = 'N2IET98W'; BiosDateText = '05/12/2024'; Chassis = 10; Cores = 4; Threads = 8; MaxMHz = 4200; CpuEax = 0x000806EA; CpuVendor = 'Intel'; SmbiosCpuName = 'Intel(R) Core(TM) i7-8650U CPU @ 1.90GHz'; Slots = 2; MemForm = 13; MemType = 26; BatDesignDiv10 = 5700; BatSbdsDate = 0 }
$W::Smbios = New-SimSmbios $global:SimS
$W::NvmeIdentify = New-SimNvmeIdentify -Vid 0x144D -Model 'Samsung SSD 980 PRO 1TB' -Serial 'S5GX' -Fw '5B2Q' -Capacity 1000204886016
$W::NvmeHealth = New-SimNvmeHealth -Used 3 -Spare 100 -Poh 900 -Cycles 300 -Unsafe 5 -Media 0 -WrittenTB 4
$global:RegCpu = 'Intel(R) Core(TM) i7-8650U CPU @ 1.90GHz'
if ($env:SIM_NO_WIN32) { $script:BCNativeTried = $true } else { $script:BCW32 = $W }
. "$SIM/mocks2.ps1"
foreach ($k in @(KEYS)) { $global:SimKeyQueue.Enqueue($k) }
'''.replace('KEYS', keys).replace('SIMDIR', SIM)
anchor="Initialize-BCConsole -Title"
s=s.replace(anchor, inject+anchor,1)
s=s.replace("$checkFiles = @(Get-ChildItem -LiteralPath (Join-Path $script:BCRoot 'checks') -Filter '*.ps1'","$checkFiles = @(Microsoft.PowerShell.Management\\Get-ChildItem -LiteralPath (Join-Path $script:BCRoot 'checks') -Filter '*.ps1'")
s=s.replace("$script:BCRoot = Split-Path -Parent $script:BCScriptPath","$script:BCRoot = '%s'" % root)
open(out,'w',encoding='utf-8-sig').write(s)
