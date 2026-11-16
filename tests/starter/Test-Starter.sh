#!/usr/bin/env bash
# Prüft Start-BuyCheck.cmd unter Wine (echte cmd.exe-Logik), ohne echtes PowerShell:
#   - powershell.exe ist eine Attrappe (fakeps.c): schreibt ihren Aufruf nach C:\pslog.txt und
#     gibt den Fehlercode aus FAKE_PS_RC zurück
#   - fltmc.exe ist eine Attrappe (fakefltmc.c): Fehlercode aus FAKE_FLTMC_RC (0 = Administrator)
# Der BuyCheck-Ordner liegt absichtlich in einem Pfad mit Leerzeichen.
#
# Benötigt: wine, x86_64-w64-mingw32-gcc
# Aufruf:   tests/starter/Test-Starter.sh            (Wine-Umgebung in ${TMPDIR:-/tmp}/buycheck-wine)
set -u
HERE="$(cd "$(dirname "$0")" && pwd)"
ROOT="$(cd "$HERE/../.." && pwd)"
export WINEPREFIX="${WINEPREFIX:-${TMPDIR:-/tmp}/buycheck-wine}" WINEDEBUG=-all
BUILD="$WINEPREFIX/../buycheck-wine-build"
mkdir -p "$BUILD"

x86_64-w64-mingw32-gcc -O2 -o "$BUILD/powershell.exe" "$HERE/fakeps.c" || exit 2
x86_64-w64-mingw32-gcc -O2 -o "$BUILD/fltmc.exe" "$HERE/fakefltmc.c" || exit 2
[ -d "$WINEPREFIX/drive_c/windows/system32" ] || wineboot -i >/dev/null 2>&1
SYS="$WINEPREFIX/drive_c/windows/system32"
mkdir -p "$SYS/WindowsPowerShell/v1.0"
cp "$BUILD/powershell.exe" "$SYS/WindowsPowerShell/v1.0/powershell.exe"
cp "$BUILD/fltmc.exe" "$SYS/fltmc.exe"

DIR="$WINEPREFIX/drive_c/Users/Test Nutzer/Downloads/buycheck-main"
rm -rf "$DIR"; mkdir -p "$DIR/lib" "$DIR/checks"
sed 's/\r$//; s/$/\r/' "$ROOT/Start-BuyCheck.cmd" > "$DIR/Start-BuyCheck.cmd"   # wie im ZIP: CRLF
cp "$ROOT/BuyCheck.ps1" "$DIR/"; cp "$ROOT/lib/Core.ps1" "$DIR/lib/"; cp "$ROOT/checks/10-system.ps1" "$DIR/checks/"
CMDP='C:\Users\Test Nutzer\Downloads\buycheck-main\Start-BuyCheck.cmd'
LOG="$WINEPREFIX/drive_c/pslog.txt"
PS='"C:\windows\System32\WindowsPowerShell\v1.0\powershell.exe" -NoProfile -ExecutionPolicy Bypass'
RUN="$PS -File \"C:\\Users\\Test Nutzer\\Downloads\\buycheck-main\\BuyCheck.ps1\" -NoElevate"
ELEV="$PS -Command \"Start-Process -FilePath \$env:BC_SELF -ArgumentList '/erhoeht' -Verb RunAs\""
FAIL=0

# $1 Name, $2 fltmc-Code, $3 PowerShell-Code, $4 Argument, $5 erwartete Aufrufe (Zeilen), $6 erwarteter Text ("" = keiner), $7 Text, der NICHT kommen darf
check() {
    rm -f "$LOG"
    local out calls
    out="$(printf '\r\n\r\n\r\n' | timeout 60 env FAKE_FLTMC_RC="$2" FAKE_PS_RC="$3" wine cmd /c "$CMDP" $4 2>&1 | tr -d '\r')"
    calls=""; [ -f "$LOG" ] && calls="$(tr -d '\r' < "$LOG" | sed 's/^PS: //')"
    local ok=1
    [ "$calls" == "$5" ] || ok=0
    if [ -n "$6" ] && ! grep -qF -- "$6" <<<"$out"; then ok=0; fi
    if [ -n "$7" ] && grep -qF -- "$7" <<<"$out"; then ok=0; fi
    if [ $ok -eq 1 ]; then echo "PASS $1"; else
        echo "FAIL $1"; FAIL=$((FAIL + 1))
        echo "  Ausgabe:"; sed 's/^/    /' <<<"$out"; echo "  Aufrufe:"; sed 's/^/    /' <<<"$calls"; echo "  erwartet:"; sed 's/^/    /' <<<"$5"
    fi
}

check 'Admin, BuyCheck endet normal -> kein Halt'          0 0 '' "$RUN" '' 'Press any key'
check 'Admin, negativer Fehlercode -> Meldung + Halt'      0 -196608 '' "$RUN" 'Fehlercode -196608' ''
check 'Admin, Fehlercode 1 -> Meldung + Halt'               0 1 '' "$RUN" 'Fehlercode 1)' ''
check 'kein Admin -> Windows-Abfrage, Fenster schließt'     1 0 '' "$ELEV" 'Administratorrechte' 'Fehlercode'
check 'kein Admin (negativer fltmc-Code) -> Abfrage'        -2147024891 0 '' "$ELEV" 'Administratorrechte' 'Fehlercode'
check 'Abfrage abgebrochen -> eingeschränkt starten'        1 1 '' "$ELEV
$RUN" 'abgebrochen' ''
check 'erhöhter Neustart (/erhoeht) -> direkt BuyCheck'     1 0 '/erhoeht' "$RUN" '' 'Administratorrechte'

mv "$DIR/BuyCheck.ps1" "$BUILD/BuyCheck.ps1.bak"
check 'nicht entpackt (BuyCheck.ps1 fehlt) -> Hinweis'      0 0 '' '' 'nicht vollstaendig vorhanden' ''
mv "$BUILD/BuyCheck.ps1.bak" "$DIR/BuyCheck.ps1"
rm "$DIR/lib/Core.ps1"
check 'nicht entpackt (lib fehlt) -> Hinweis'               0 0 '' '' 'Alle extrahieren' ''

echo "FEHLER GESAMT: $FAIL"
exit $FAIL
