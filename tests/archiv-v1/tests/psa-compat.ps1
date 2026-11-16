Import-Module /tmp/bc-build/psa/mod/PSScriptAnalyzer/PSScriptAnalyzer.psd1 -ErrorAction Stop
$settings = @{
    IncludeRules = @('PSUseCompatibleSyntax')
    Rules = @{ PSUseCompatibleSyntax = @{ Enable = $true; TargetVersions = @('5.1') } }
}
$res = Invoke-ScriptAnalyzer -Path /home/user/buycheck -Recurse -Settings $settings
$res | Sort-Object ScriptName, Line | ForEach-Object { "{0}:{1} [{2}] {3}" -f $_.ScriptName, $_.Line, $_.RuleName, $_.Message }
"Kompatibilitätsprobleme (PS 5.1): $(@($res).Count)"
