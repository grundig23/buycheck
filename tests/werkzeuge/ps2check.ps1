# Prüft Skripte auf Konstrukte, die es in Windows PowerShell 2.0 / .NET 2.0 nicht gibt
param([string[]]$Files)
$problems = New-Object System.Collections.Generic.List[string]
$guarded = @('Get-CimInstance', 'Invoke-CimMethod', 'Register-CimIndicationEvent', 'ConvertTo-Json', 'ConvertFrom-Json', 'Get-PhysicalDisk', 'Get-Disk',
    'Get-StorageReliabilityCounter', 'Get-PnpDeviceProperty', 'Get-PnpDevice', 'Get-NetAdapter', 'Get-Tpm', 'Confirm-SecureBootUEFI', 'Get-SecureBootUEFI',
    'Get-BitLockerVolume', 'Get-ScheduledTask', 'Invoke-WebRequest', 'Invoke-RestMethod', 'Get-ComputerInfo')
$net4 = @('IsNullOrWhiteSpace', 'Is64BitProcess', 'Is64BitOperatingSystem', 'EnumerateFiles', 'EnumerateDirectories', 'HasFlag', 'Restart', 'Clear')
$net4Types = @('WebUtility', 'HashSet', 'Tuple', 'Lazy', 'Task', 'BigInteger', 'Complex', 'ConcurrentDictionary', 'ConcurrentQueue')
foreach ($file in $Files) {
    $tokens = $null; $errs = $null
    $ast = [System.Management.Automation.Language.Parser]::ParseFile($file, [ref]$tokens, [ref]$errs)
    foreach ($e in $errs) { $problems.Add("${file}:$($e.Extent.StartLineNumber): PARSEFEHLER $($e.Message)") }
    $add = { param($n, $msg) $problems.Add("${file}:$($n.Extent.StartLineNumber): $msg  ->  $($n.Extent.Text.Split("`n")[0].Trim())") }
    foreach ($n in $ast.FindAll({ $true }, $true)) {
        switch ($n.GetType().Name) {
            'ConvertExpressionAst' { if (@('ordered', 'pscustomobject') -contains $n.Type.TypeName.FullName.ToLowerInvariant()) { & $add $n "[$($n.Type.TypeName.FullName)] (PS3+)" } }
            'TypeExpressionAst' { $tn = $n.TypeName.Name; foreach ($t in $net4Types) { if ($tn -match "(^|\.)$t(\[|$|``)") { & $add $n ".NET-4-Typ $tn" } } }
            'TypeConstraintAst' { $tn = $n.TypeName.Name; foreach ($t in $net4Types) { if ($tn -match "(^|\.)$t(\[|$|``)") { & $add $n ".NET-4-Typ $tn" } } }
            'BinaryExpressionAst' { if ("$($n.Operator)" -match '^(I|C)?(In|NotIn|Shl|Shr)$') { & $add $n "Operator -$($n.Operator) (PS3+)" } }
            'InvokeMemberExpressionAst' {
                $m = $n.Member.Extent.Text
                if ($n.Static -and $m -eq 'new') { & $add $n '::new() (PS5+)' }
                if (-not $n.Static -and @('Where', 'ForEach') -contains $m) { & $add $n ".$m() (PS4+)" }
                if ($net4 -contains $m) { & $add $n ".NET-4-Methode $m (prüfen)" }
            }
            'MemberExpressionAst' { if ($net4 -contains $n.Member.Extent.Text) { & $add $n ".NET-4-Eigenschaft $($n.Member.Extent.Text)" } }
            'VariableExpressionAst' {
                $v = $n.VariablePath.UserPath
                if (@('PSScriptRoot', 'PSCommandPath', 'PSItem') -contains $v) { & $add $n "`$$v (PS3+)" }
                if ($n.VariablePath.DriveName -eq 'using') { & $add $n '$using: (PS3+)' }
            }
            'NamedAttributeArgumentAst' { if ($n.ExpressionOmitted) { & $add $n "[...($($n.ArgumentName))] ohne = `$true (PS3+)" } }
            'ClassMemberAst' { & $add $n 'Klasse (PS5+)' }
            'TypeDefinitionAst' { & $add $n 'Klasse/Enum (PS5+)' }
            'UsingStatementAst' { & $add $n 'using (PS5+)' }
            'CommandAst' {
                $name = $n.GetCommandName()
                if (-not $name) { break }
                $params = @($n.CommandElements | Where-Object { $_ -is [System.Management.Automation.Language.CommandParameterAst] } | ForEach-Object { $_.ParameterName.ToLowerInvariant() })
                if ($guarded -contains $name) { & $add $n "NEUERES CMDLET $name (nur mit Absicherung)" }
                if ($name -match '^(Get-ChildItem|gci|dir|ls)$' -and ($params -contains 'file' -or $params -contains 'directory')) { & $add $n 'Get-ChildItem -File/-Directory (PS3+)' }
                if ($name -eq 'Get-Content' -and $params -contains 'raw') { & $add $n 'Get-Content -Raw (PS3+)' }
                if ($params -contains 'nonewline' -and $name -ne 'Write-Host') { & $add $n '-NoNewline (PS5+)' }
                if ($name -eq 'Add-Member' -and ($params -contains 'notepropertyname' -or $params -contains 'notepropertymembers')) { & $add $n 'Add-Member -NoteProperty* (PS3+)' }
                if (@('Where-Object', 'ForEach-Object', '?', '%', 'where', 'foreach') -contains $name) {
                    $args1 = @($n.CommandElements | Select-Object -Skip 1)
                    if ($args1.Count -gt 0 -and $args1[0] -isnot [System.Management.Automation.Language.ScriptBlockExpressionAst] -and $args1[0] -isnot [System.Management.Automation.Language.CommandParameterAst]) { & $add $n "$name ohne Skriptblock (PS3+)" }
                }
                foreach ($el in $n.CommandElements) {
                    if ($el -is [System.Management.Automation.Language.CommandParameterAst] -and $el.ParameterName -match '^(ErrorAction|ea|WarningAction|wa)$' -and $el.Argument -and $el.Argument.Extent.Text -match 'Ignore') { & $add $n '-ErrorAction Ignore (PS3+)' }
                }
                $idx = [array]::IndexOf(@($n.CommandElements), ($n.CommandElements | Where-Object { $_ -is [System.Management.Automation.Language.CommandParameterAst] -and $_.ParameterName -match '^(ErrorAction|ea)$' } | Select-Object -First 1))
                if ($idx -ge 0 -and $idx + 1 -lt $n.CommandElements.Count -and $n.CommandElements[$idx + 1].Extent.Text -match '^Ignore$') { & $add $n '-ErrorAction Ignore (PS3+)' }
            }
        }
    }
    # Unicode-Anführungszeichen in Strings mit doppelten Anführungszeichen beenden den String (PowerShell behandelt „ “ ” wie ")
    foreach ($tk in $tokens) {
        if ($tk.Kind -eq 'StringExpandable' -or $tk.Kind -eq 'StringLiteral') {
            $inner = $tk.Text.Substring(1, [Math]::Max(0, $tk.Text.Length - 2))
            if ($tk.Kind -eq 'StringExpandable' -and $inner -match '[“”„]') { $problems.Add("${file}:$($tk.Extent.StartLineNumber): typografisches Anführungszeichen in "" ""-String") }
            if ($tk.Kind -eq 'StringLiteral' -and $inner -match '[‘’‚‛]') { $problems.Add("${file}:$($tk.Extent.StartLineNumber): typografisches Apostroph in ' '-String") }
        }
    }
}
$problems | Sort-Object -Unique
"Gesamt: $($problems.Count)"
