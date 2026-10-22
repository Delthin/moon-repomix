#include <wctype.h>

/* The upstream ASI scanner checks iswblank before '\n', but standard C does
 * not classify '\r' as blank. Treat CR as horizontal whitespace for this
 * scanner only; token byte positions and original CRLF fragments stay intact. */
static int moonbit_iswblank(wint_t c) {
  return c == '\r' || iswblank(c);
}

#ifdef iswblank
#undef iswblank
#endif
#define iswblank moonbit_iswblank
#include "vendor/moonbit/src/scanner.c"
#undef iswblank
