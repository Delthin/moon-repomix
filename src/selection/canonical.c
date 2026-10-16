#include <moonbit.h>

#ifdef _WIN32
#ifndef _WIN32_WINNT
#define _WIN32_WINNT 0x0600
#endif
#include <windows.h>
#include <stdlib.h>
#include <string.h>

/* Metadata-only handle: do not enumerate/read file contents. Share modes allow
 * other processes to keep using the output. Follow parent aliases deliberately;
 * traversal itself rejects reparse points before recursing/opening candidates. */
MOONBIT_FFI_EXPORT moonbit_string_t selection_windows_final_path(
    moonbit_string_t path, int32_t *code) {
  size_t len = Moonbit_array_length(path);
  wchar_t *name = malloc((len + 1) * sizeof(wchar_t));
  if (!name) {
    code[0] = ERROR_NOT_ENOUGH_MEMORY;
    return moonbit_make_string_raw(0);
  }
  memcpy(name, path, len * sizeof(wchar_t));
  name[len] = L'\0';
  HANDLE handle = CreateFileW(name, 0,
      FILE_SHARE_READ | FILE_SHARE_WRITE | FILE_SHARE_DELETE, NULL,
      OPEN_EXISTING, FILE_FLAG_BACKUP_SEMANTICS, NULL);
  free(name);
  if (handle == INVALID_HANDLE_VALUE) {
    code[0] = GetLastError();
    return moonbit_make_string_raw(0);
  }
  DWORD needed = GetFinalPathNameByHandleW(handle, NULL, 0, FILE_NAME_NORMALIZED);
  if (!needed) {
    code[0] = GetLastError();
    CloseHandle(handle);
    return moonbit_make_string_raw(0);
  }
  wchar_t *buffer = malloc((needed + 1) * sizeof(wchar_t));
  if (!buffer) {
    code[0] = ERROR_NOT_ENOUGH_MEMORY;
    CloseHandle(handle);
    return moonbit_make_string_raw(0);
  }
  DWORD written = GetFinalPathNameByHandleW(handle, buffer, needed + 1,
      FILE_NAME_NORMALIZED);
  DWORD error = GetLastError();
  CloseHandle(handle);
  if (!written || written > needed) {
    code[0] = written > needed ? ERROR_INSUFFICIENT_BUFFER : error;
    free(buffer);
    return moonbit_make_string_raw(0);
  }
  moonbit_string_t result = moonbit_make_string_raw(written);
  memcpy(result, buffer, written * sizeof(wchar_t));
  free(buffer);
  code[0] = 0;
  return result;
}
#endif
