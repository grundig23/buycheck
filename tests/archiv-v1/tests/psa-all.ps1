Import-Module /tmp/bc-build/psa/mod/PSScriptAnalyzer/PSScriptAnalyzer.psd1 -ErrorAction Stop
$res = Invoke-ScriptAnalyzer -Path /home/user/buycheck -Recurse
$res | Group-Object RuleName | Sort-Object Count -Descending | ForEach-Object { "{0,4} x {1}" -f $_.Count, $_.Name }
""
$res | Where-Object { $_.RuleName -notin @('PSAvoidUsingWriteHost') } | Sort-Object ScriptName, Line | ForEach-Object { "{0}:{1} [{2}] {3}" -f $_.ScriptName, $_.Line, $_.RuleName, ($_.Message -replace '\s+',' ').Substring(0, [Math]::Min(170, ($_.Message -replace '\s+',' ').Length)) }
