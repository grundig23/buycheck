# Wandelt PS3+-Konstrukte in PS-2.0-kompatible Formen um (AST-basiert, Text-Ersetzungen von hinten nach vorn)
param([string[]]$Files)
$simpleTypes = @('VariableExpressionAst', 'StringConstantExpressionAst', 'ExpandableStringExpressionAst', 'ConstantExpressionAst',
    'MemberExpressionAst', 'InvokeMemberExpressionAst', 'IndexExpressionAst', 'ParenExpressionAst', 'SubExpressionAst',
    'ArrayExpressionAst', 'HashtableAst', 'TypeExpressionAst')
function Test-Simple($stmt) {
    if ($stmt -isnot [System.Management.Automation.Language.PipelineAst]) { return $false }
    if ($stmt.PipelineElements.Count -ne 1) { return $false }
    $el = $stmt.PipelineElements[0]
    if ($el -isnot [System.Management.Automation.Language.CommandExpressionAst]) { return $false }
    if ($el.Redirections.Count -gt 0) { return $false }
    $e = $el.Expression
    while ($e -is [System.Management.Automation.Language.ConvertExpressionAst]) { $e = $e.Child }
    return ($simpleTypes -contains $e.GetType().Name)
}
function Get-KeyText($k) {
    if ($k -is [System.Management.Automation.Language.StringConstantExpressionAst] -and $k.StringConstantType -eq 'BareWord') { return "'" + $k.Value + "'" }
    return $k.Extent.Text
}
function Get-Pairs($ht, [string]$indent, [bool]$multi) {
    $parts = @()
    foreach ($kv in $ht.KeyValuePairs) {
        $vt = $kv.Item2.Extent.Text
        if (-not (Test-Simple $kv.Item2)) { $vt = '$(' + $vt + ')' }
        $parts += ((Get-KeyText $kv.Item1) + ', ' + $vt)
    }
    if ($parts.Count -eq 0) { return '@()' }
    if ($multi) { return "@(`n" + (($parts | ForEach-Object { $indent + '    ' + $_ }) -join ",`n") + "`n" + $indent + ')' }
    return '@(' + ($parts -join ', ') + ')'
}
function Wrap($ast) {
    $t = $ast.Extent.Text
    if ($ast -is [System.Management.Automation.Language.VariableExpressionAst] -or $ast -is [System.Management.Automation.Language.MemberExpressionAst] -or
        $ast -is [System.Management.Automation.Language.ParenExpressionAst] -or $ast -is [System.Management.Automation.Language.ArrayExpressionAst] -or
        $ast -is [System.Management.Automation.Language.StringConstantExpressionAst] -or $ast -is [System.Management.Automation.Language.ExpandableStringExpressionAst]) { return $t }
    return '(' + $t + ')'
}
foreach ($file in $Files) {
    $text = [IO.File]::ReadAllText($file)
    $tokens = $null; $errs = $null
    $ast = [System.Management.Automation.Language.Parser]::ParseInput($text, [ref]$tokens, [ref]$errs)
    if ($errs.Count) { Write-Host "PARSEFEHLER vorher: $file"; continue }
    $edits = New-Object System.Collections.Generic.List[object]
    $all = $ast.FindAll({ $true }, $true)
    foreach ($n in $all) {
        if ($n -is [System.Management.Automation.Language.ConvertExpressionAst]) {
            $tn = $n.Type.TypeName.FullName.ToLowerInvariant()
            if ($tn -eq 'ordered' -or $tn -eq 'pscustomobject') {
                $lineStart = $text.LastIndexOf("`n", [Math]::Max(0, $n.Extent.StartOffset - 1)) + 1
                $indent = ([regex]::Match($text.Substring($lineStart), '^[ \t]*')).Value
                if ($n.Child -is [System.Management.Automation.Language.HashtableAst]) {
                    $multi = $n.Child.Extent.StartLineNumber -ne $n.Child.Extent.EndLineNumber
                    $fn = if ($tn -eq 'ordered') { 'New-BCOrdered' } else { 'New-BCObject' }
                    $new = '(' + $fn + ' ' + (Get-Pairs $n.Child $indent $multi) + ')'
                } elseif ($tn -eq 'pscustomobject') {
                    $new = '(New-Object PSObject -Property ' + $n.Child.Extent.Text + ')'
                } else { Write-Host "MANUELL (${file}:$($n.Extent.StartLineNumber)): $($n.Extent.Text)"; continue }
                # Kommentare innerhalb gehen verloren -> melden
                foreach ($tk in $tokens) { if ($tk.Kind -eq 'Comment' -and $tk.Extent.StartOffset -gt $n.Extent.StartOffset -and $tk.Extent.EndOffset -lt $n.Extent.EndOffset) { Write-Host "KOMMENTAR verloren (${file}:$($tk.Extent.StartLineNumber)): $($tk.Text)" } }
                $edits.Add(@($n.Extent.StartOffset, $n.Extent.EndOffset, $new))
            }
        } elseif ($n -is [System.Management.Automation.Language.BinaryExpressionAst]) {
            $op = "$($n.Operator)"
            if ($op -match '^(I|C)?(In|NotIn)$' -or $op -in @('In', 'NotIn', 'Iin', 'Inotin', 'Cin', 'Cnotin')) {
                $neg = $op -match 'not'
                $new = (Wrap $n.Right) + $(if ($neg) { ' -notcontains ' } else { ' -contains ' }) + (Wrap $n.Left)
                $edits.Add(@($n.Extent.StartOffset, $n.Extent.EndOffset, $new))
            } elseif ($op -match '^Sh[lr]$') { Write-Host "SHIFT manuell (${file}:$($n.Extent.StartLineNumber)): $($n.Extent.Text)" }
        } elseif ($n -is [System.Management.Automation.Language.InvokeMemberExpressionAst] -and $n.Static -and
            $n.Expression.Extent.Text -match '^\[(System\.)?String\]$' -and $n.Member.Extent.Text -eq 'IsNullOrWhiteSpace') {
            $new = '(Test-BCBlank ' + (Wrap $n.Arguments[0]) + ')'
            $edits.Add(@($n.Extent.StartOffset, $n.Extent.EndOffset, $new))
        }
    }
    # verschachtelte Bearbeitungen vermeiden: nur äußerste behalten
    $sorted = @($edits | Sort-Object { $_[0] }, { - $_[1] })
    $keep = New-Object System.Collections.Generic.List[object]; $lastEnd = -1
    foreach ($e in $sorted) { if ($e[0] -ge $lastEnd) { $keep.Add($e); $lastEnd = $e[1] } else { Write-Host "VERSCHACHTELT übersprungen (${file} @ $($e[0])) – zweiter Durchlauf nötig" } }
    $sb = $text
    foreach ($e in @($keep | Sort-Object { $_[0] } -Descending)) { $sb = $sb.Substring(0, $e[0]) + $e[2] + $sb.Substring($e[1]) }
    $t2 = $null; $e2 = $null
    [void][System.Management.Automation.Language.Parser]::ParseInput($sb, [ref]$t2, [ref]$e2)
    if ($e2.Count) { Write-Host "PARSEFEHLER nachher: $file"; $e2 | Select-Object -First 3 | ForEach-Object { Write-Host "  $($_.Extent.StartLineNumber): $($_.Message)" }; continue }
    if ($sb -ne $text) { [IO.File]::WriteAllText($file, $sb, (New-Object Text.UTF8Encoding($false))); Write-Host ("{0}: {1} Ersetzungen" -f $file, $keep.Count) }
}
