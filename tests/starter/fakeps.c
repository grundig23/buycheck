/* Test-Attrappe für powershell.exe: protokolliert die Argumente, Rückgabewert aus Umgebungsvariable FAKE_PS_RC */
#include <stdio.h>
#include <stdlib.h>
#include <windows.h>
int main(void) {
    FILE *f = fopen("C:\\pslog.txt", "a");
    if (f) { fprintf(f, "PS: %s\n", GetCommandLineA()); fclose(f); }
    const char *rc = getenv("FAKE_PS_RC");
    return rc ? atoi(rc) : 0;
}
