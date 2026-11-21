# Findet Zeichenketten, die PowerShell an typografischen Anführungszeichen („ “ ” ‚ ‘ ’) beginnen oder enden lässt.
# PowerShell behandelt diese Zeichen wie " bzw. ' – ein „ mitten in "…" beendet die Zeichenkette (Absturz zur Laufzeit).
param([string[]]$Files)
$typo = [char[]]@(0x201E, 0x201C, 0x201D, 0x201A, 0x2018, 0x2019)
$n = 0
foreach ($file in $Files) {
    $tokens = $null; $errs = $null
    [void][System.Management.Automation.Language.Parser]::ParseFile($file, [ref]$tokens, [ref]$errs)
    foreach ($t in $tokens) {
        $all = @($t)
        if ($t -is [System.Management.Automation.Language.StringExpandableToken] -and $t.NestedTokens) { $all += $t.NestedTokens }
        foreach ($x in $all) {
            if ($x -isnot [System.Management.Automation.Language.StringToken]) { continue }
            $txt = $x.Extent.Text
            if ($txt.Length -lt 1) { continue }
            if (($typo -contains $txt[0]) -or ($typo -contains $txt[$txt.Length - 1])) {
                "{0}:{1}: {2}" -f $file, $x.Extent.StartLineNumber, ($txt.Split("`n")[0].Trim())
                $n++
            }
        }
    }
}
"Gesamt: $n"
