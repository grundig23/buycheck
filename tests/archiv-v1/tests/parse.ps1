$files = Get-ChildItem -Path /home/user/buycheck -Recurse -Filter *.ps1
$bad = 0
foreach ($f in $files) {
    $tokens = $null; $errors = $null
    [void][System.Management.Automation.Language.Parser]::ParseFile($f.FullName, [ref]$tokens, [ref]$errors)
    if ($errors.Count -gt 0) {
        $bad++
        foreach ($e in $errors) { Write-Host ("{0}:{1}:{2}: {3}" -f $f.Name, $e.Extent.StartLineNumber, $e.Extent.StartColumnNumber, $e.Message) -ForegroundColor Red }
    } else { Write-Host "OK  $($f.Name)" }
}
"Dateien mit Fehlern: $bad"
