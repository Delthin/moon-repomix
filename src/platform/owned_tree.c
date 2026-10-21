#include <moonbit.h>
#include <errno.h>
#include <stdlib.h>
#include <string.h>

#ifdef _WIN32
#include <windows.h>
#include <wchar.h>

/* Keep every ancestor open without FILE_SHARE_DELETE while enumerating it.
 * OPEN_REPARSE_POINT ensures attributes and deletion apply to the link itself,
 * including junctions, never to its target. Do not use path-based chmod. */
static DWORD remove_tree(const wchar_t *path, int root) {
  HANDLE file = CreateFileW(path,
    DELETE | FILE_READ_ATTRIBUTES | FILE_WRITE_ATTRIBUTES,
    FILE_SHARE_READ | FILE_SHARE_WRITE, NULL, OPEN_EXISTING,
    FILE_FLAG_BACKUP_SEMANTICS | FILE_FLAG_OPEN_REPARSE_POINT, NULL);
  if (file == INVALID_HANDLE_VALUE) return GetLastError();
  DWORD error = 0;
  FILE_BASIC_INFO basic;
  if (!GetFileInformationByHandleEx(file, FileBasicInfo, &basic, sizeof(basic))) {
    error = GetLastError();
    goto done;
  }
  int directory = (basic.FileAttributes & FILE_ATTRIBUTE_DIRECTORY) != 0;
  int link = (basic.FileAttributes & FILE_ATTRIBUTE_REPARSE_POINT) != 0;
  if (root && (!directory || link)) {
    error = ERROR_DIRECTORY;
    goto done;
  }
  if (directory && !link) {
    size_t length = wcslen(path);
    wchar_t *child = malloc((length + MAX_PATH + 3) * sizeof(wchar_t));
    if (!child) { error = ERROR_NOT_ENOUGH_MEMORY; goto done; }
    memcpy(child, path, length * sizeof(wchar_t));
    child[length] = L'\\';
    wcscpy(child + length + 1, L"*");
    WIN32_FIND_DATAW entry;
    HANDLE search = FindFirstFileW(child, &entry);
    if (search == INVALID_HANDLE_VALUE) {
      error = GetLastError();
      if (error == ERROR_FILE_NOT_FOUND) error = 0;
    } else {
      do {
        if (!wcscmp(entry.cFileName, L".") || !wcscmp(entry.cFileName, L".."))
          continue;
        wcscpy(child + length + 1, entry.cFileName);
        error = remove_tree(child, 0);
        if (error) break;
      } while (FindNextFileW(search, &entry));
      if (!error && GetLastError() != ERROR_NO_MORE_FILES) error = GetLastError();
      FindClose(search);
    }
    free(child);
    if (error) goto done;
  }
  if (basic.FileAttributes & FILE_ATTRIBUTE_READONLY) {
    /* A read-only hardlink may share attributes with a file outside the tree.
     * Refuse to change those attributes; ownership stays with the caller. */
    BY_HANDLE_FILE_INFORMATION identity;
    if (!GetFileInformationByHandle(file, &identity)) {
      error = GetLastError();
      goto done;
    }
    if (!directory && identity.nNumberOfLinks > 1) {
      error = ERROR_TOO_MANY_LINKS;
      goto done;
    }
    /* Zero timestamps mean unchanged. Only clear READONLY on this exact handle. */
    FILE_BASIC_INFO writable = {0};
    writable.FileAttributes = basic.FileAttributes &
      ~(FILE_ATTRIBUTE_READONLY | FILE_ATTRIBUTE_DIRECTORY | FILE_ATTRIBUTE_REPARSE_POINT);
    if (!writable.FileAttributes) writable.FileAttributes = FILE_ATTRIBUTE_NORMAL;
    if (!SetFileInformationByHandle(file, FileBasicInfo, &writable, sizeof(writable))) {
      error = GetLastError();
      goto done;
    }
  }
  FILE_DISPOSITION_INFO disposition = { TRUE };
  if (!SetFileInformationByHandle(file, FileDispositionInfo, &disposition, sizeof(disposition)))
    error = GetLastError();
done:
  CloseHandle(file);
  return error;
}

MOONBIT_FFI_EXPORT int32_t mr_remove_owned_tree(moonbit_bytes_t path) {
  int length = MultiByteToWideChar(CP_UTF8, MB_ERR_INVALID_CHARS, (char *)path, -1, NULL, 0);
  if (!length) return (int32_t)GetLastError();
  wchar_t *wide = malloc((size_t)length * sizeof(wchar_t));
  if (!wide) return ERROR_NOT_ENOUGH_MEMORY;
  if (!MultiByteToWideChar(CP_UTF8, MB_ERR_INVALID_CHARS, (char *)path, -1, wide, length)) {
    DWORD error = GetLastError();
    free(wide);
    return (int32_t)error;
  }
  DWORD error = remove_tree(wide, 1);
  free(wide);
  return (int32_t)error;
}
#else
#include <dirent.h>
#include <fcntl.h>
#include <sys/stat.h>
#include <unistd.h>

/* All child lookups are relative to pinned directory descriptors. Never open a
 * directory through a symlink, even if an entry changes after fstatat. Unix
 * unlink does not require making read-only Git objects writable. */
static int remove_children(int fd) {
  DIR *directory = fdopendir(fd); /* consumes fd on success */
  if (!directory) { int error = errno; close(fd); return error; }
  int error = 0;
  for (;;) {
    errno = 0;
    struct dirent *entry = readdir(directory);
    if (!entry) { error = errno; break; }
    if (!strcmp(entry->d_name, ".") || !strcmp(entry->d_name, "..")) continue;
    struct stat info;
    if (fstatat(fd, entry->d_name, &info, AT_SYMLINK_NOFOLLOW) < 0) {
      error = errno;
      break;
    }
    int is_directory = S_ISDIR(info.st_mode);
    if (is_directory) {
      int child = openat(fd, entry->d_name, O_RDONLY | O_DIRECTORY | O_NOFOLLOW | O_CLOEXEC);
      if (child < 0) { error = errno; break; }
      error = remove_children(child);
      if (error) break;
    }
    if (unlinkat(fd, entry->d_name, is_directory ? AT_REMOVEDIR : 0) < 0) {
      error = errno;
      break;
    }
  }
  closedir(directory);
  return error;
}

MOONBIT_FFI_EXPORT int32_t mr_remove_owned_tree(moonbit_bytes_t path) {
  int fd = open((char *)path, O_RDONLY | O_DIRECTORY | O_NOFOLLOW | O_CLOEXEC);
  if (fd < 0) return errno;
  int error = remove_children(fd);
  if (error) return error;
  if (rmdir((char *)path) < 0) return errno;
  return 0;
}
#endif
