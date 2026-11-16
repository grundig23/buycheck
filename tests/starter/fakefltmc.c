#include <stdlib.h>
int main(void) { const char *rc = getenv("FAKE_FLTMC_RC"); return rc ? atoi(rc) : 0; }
