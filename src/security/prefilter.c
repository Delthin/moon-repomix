#include <moonbit.h>
#include "prefilter.h"
MOONBIT_FFI_EXPORT int32_t moon_repomix_credential_candidates(moonbit_string_t text) {
  return (int32_t)pf_candidates(text, (size_t)Moonbit_array_length(text));
}
