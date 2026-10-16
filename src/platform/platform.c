#include <moonbit.h>
#include <stdint.h>
#include <stdlib.h>
#include <string.h>
#ifdef _WIN32
#include <windows.h>
#include <process.h>
#else
#include <unistd.h>
#ifdef __APPLE__
#include <mach-o/dyld.h>
#endif
#endif

MOONBIT_FFI_EXPORT int32_t mr_windows(void) {
#ifdef _WIN32
  return 1;
#else
  return 0;
#endif
}

MOONBIT_FFI_EXPORT int32_t mr_pid(void) {
#ifdef _WIN32
  return (int32_t)_getpid();
#else
  return (int32_t)getpid();
#endif
}

/* Empty bytes indicate failure. No borrowed pointers escape this function. */
MOONBIT_FFI_EXPORT moonbit_bytes_t mr_executable(void) {
#ifdef _WIN32
  wchar_t buffer[32768];
  DWORD n = GetModuleFileNameW(NULL, buffer, 32768);
  if (n == 0 || n >= 32768) return moonbit_make_bytes(0, 0);
  int len = WideCharToMultiByte(CP_UTF8, WC_ERR_INVALID_CHARS, buffer, n,
                              NULL, 0, NULL, NULL);
  if (!len) return moonbit_make_bytes(0, 0);
  moonbit_bytes_t out = moonbit_make_bytes(len, 0);
  WideCharToMultiByte(CP_UTF8, WC_ERR_INVALID_CHARS, buffer, n,
                      (char *)out, len, NULL, NULL);
  return out;
#else
  char *buffer;
  size_t len;
#ifdef __APPLE__
  uint32_t size = 0;
  _NSGetExecutablePath(NULL, &size);
  buffer = malloc(size);
  if (!buffer) return moonbit_make_bytes(0, 0);
  if (_NSGetExecutablePath(buffer, &size) != 0) {
    free(buffer);
    return moonbit_make_bytes(0, 0);
  }
  len = strlen(buffer);
#else
  size_t size = 1024;
  buffer = NULL;
  for (;;) {
    char *next = realloc(buffer, size);
    if (!next) { free(buffer); return moonbit_make_bytes(0, 0); }
    buffer = next;
    ssize_t n = readlink("/proc/self/exe", buffer, size);
    if (n < 0) { free(buffer); return moonbit_make_bytes(0, 0); }
    if ((size_t)n < size) { len = (size_t)n; break; }
    if (size >= 1048576) { free(buffer); return moonbit_make_bytes(0, 0); }
    size *= 2;
  }
#endif
  moonbit_bytes_t out = moonbit_make_bytes((int32_t)len, 0);
  memcpy(out, buffer, len);
  free(buffer);
  return out;
#endif
}
