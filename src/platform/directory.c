/* Atomic publication only: never emulate no-replace with an existence check.
 * All MoonBit arguments are borrowed for this call; no pointer is retained. */
#ifndef _GNU_SOURCE
#define _GNU_SOURCE
#endif
#include <moonbit.h>
#include <errno.h>
#include <stdint.h>

#ifdef _WIN32
#include <windows.h>
#include <stdlib.h>

static wchar_t *directory_wide(const char *path, DWORD *error) {
  int length = MultiByteToWideChar(CP_UTF8, MB_ERR_INVALID_CHARS, path, -1, NULL, 0);
  if (!length) { *error = GetLastError(); return NULL; }
  wchar_t *wide = malloc((size_t)length * sizeof(wchar_t));
  if (!wide) { *error = ERROR_NOT_ENOUGH_MEMORY; return NULL; }
  if (!MultiByteToWideChar(CP_UTF8, MB_ERR_INVALID_CHARS, path, -1, wide, length)) {
    *error = GetLastError();
    free(wide);
    return NULL;
  }
  return wide;
}

MOONBIT_FFI_EXPORT int32_t mr_directory_noreplace(
    moonbit_bytes_t source, moonbit_bytes_t target) {
  DWORD error = 0;
  wchar_t *from = directory_wide((const char *)source, &error);
  if (!from) return (int32_t)error;
  wchar_t *to = directory_wide((const char *)target, &error);
  if (!to) { free(from); return (int32_t)error; }
  /* MoveFileW never replaces an existing destination. No COPY_ALLOWED or
   * REPLACE_EXISTING flag: this is a same-volume sibling directory move. */
  if (!MoveFileW(from, to)) error = GetLastError();
  free(to);
  free(from);
  return (int32_t)error;
}
#else
#include <stdio.h>
#include <fcntl.h>
#include <unistd.h>
#ifdef __linux__
#include <sys/syscall.h>
#endif

MOONBIT_FFI_EXPORT int32_t mr_directory_noreplace(
    moonbit_bytes_t source, moonbit_bytes_t target) {
#if defined(__APPLE__)
  if (renamex_np((const char *)source, (const char *)target, RENAME_EXCL) < 0)
    return errno;
  return 0;
#elif defined(__linux__) && defined(SYS_renameat2)
  /* RENAME_NOREPLACE = 1, including systems with older libc headers. A kernel
   * or filesystem that cannot supply the primitive must fail, not fall back. */
  if (syscall(SYS_renameat2, AT_FDCWD, (const char *)source,
              AT_FDCWD, (const char *)target, 1U) < 0)
    return errno;
  return 0;
#else
  (void)source;
  (void)target;
  return ENOTSUP;
#endif
}
#endif
