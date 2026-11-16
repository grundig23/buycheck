$ErrorActionPreference = 'Continue'
$root = '/home/user/buycheck'
Add-Type -Path "$root/lib/Native.cs", "$root/lib/Workloads.cs", '/tmp/bc-build/tests/ModelStub.cs'
$script:BCRoot = $root
$script:BCVersion = 'test'
. "$root/lib/Core.ps1"; . "$root/lib/CpuDb.ps1"; . "$root/lib/Report.ps1"
foreach ($f in (Get-ChildItem "$root/checks" -Filter *.ps1 | Sort-Object Name)) { . $f.FullName }
"Registrierte Tests: $($script:BCChecks.Count)"
$script:BCChecks | Sort-Object { $_.Info.CategoryOrder }, { $_.Info.Order } | ForEach-Object {
  "{0,-22} {1,-34} run={2,-4} {3,-6}s inter={4,-5} profiles={5} opts={6}" -f $_.Id, $_.Info.Category, $_.RunOrder, $_.Info.EstimatedSeconds(), $_.Info.Interactive, ($_.Info.Profiles -join ','), (($_.Info.Options | ForEach-Object { "$($_.Key)=$($_.Value)" }) -join ';')
}
foreach ($p in 'quick','thorough','linux','auto') {
  $sel = @($script:BCChecks | Where-Object { $_.Info.InProfile($p) })
  $secs = ($sel | ForEach-Object { $_.Info.EstimatedSeconds() } | Measure-Object -Sum).Sum
  "Profil {0,-9}: {1,2} Tests, ca. {2} Min." -f $p, $sel.Count, [int]($secs/60)
}
# Alle nicht-interaktiven Tests ohne Windows-Schnittstellen laufen lassen (Robustheit)
$script:BCReportDir = '/tmp/bc-build/report'; New-Item -ItemType Directory -Force $script:BCReportDir | Out-Null
$auto = @($script:BCChecks | Where-Object { -not $_.Info.Interactive } | Sort-Object RunOrder)
$i = 0
foreach ($c in $auto) { $i++; Invoke-BCCheck -Check $c -Index $i -Total $auto.Count *>&1 | Out-Null }
"--- Ergebnisse ohne Windows-Schnittstellen ---"
foreach ($r in $script:BCResults) {
  $errs = @($r.Findings | Where-Object { $_.Level -eq 'Fehler' })
  "{0,-22} status={1,-7} findings={2} fehler={3} {4}" -f $r.Id, $r.Status, $r.Findings.Count, $errs.Count, (($errs | ForEach-Object { $_.Detail }) -join ' | ')
}
"--- Diagnose (erste 25) ---"
$script:BCDebug | Select-Object -First 25
