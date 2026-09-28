#include "PlatformSupport.h"
#ifdef _WIN32
#include <windows.h>
#include <bcrypt.h>
int bg_sha256(const uint8_t *bytes, int32_t length, uint8_t result[32]) {
    if (length < 0) return 0;
    BCRYPT_ALG_HANDLE algorithm = NULL;
    if (BCryptOpenAlgorithmProvider(&algorithm, BCRYPT_SHA256_ALGORITHM, NULL, 0) < 0) return 0;
    NTSTATUS status = BCryptHash(algorithm, NULL, 0, (PUCHAR)bytes, (ULONG)length, result, 32);
    BCryptCloseAlgorithmProvider(algorithm, 0);
    return status >= 0;
}
void *bg_lock_file(const char *path) {
    int length = MultiByteToWideChar(CP_UTF8, 0, path, -1, NULL, 0);
    if (length <= 0) return NULL;
    wchar_t *wide = (wchar_t *)HeapAlloc(GetProcessHeap(), 0, length * sizeof(wchar_t));
    if (!wide) return NULL;
    MultiByteToWideChar(CP_UTF8, 0, path, -1, wide, length);
    HANDLE handle = CreateFileW(wide, GENERIC_READ | GENERIC_WRITE, 0, NULL, OPEN_EXISTING, 0, NULL);
    HeapFree(GetProcessHeap(), 0, wide);
    return handle == INVALID_HANDLE_VALUE ? NULL : handle;
}
void bg_unlock_file(void *handle) { if (handle) CloseHandle(handle); }
int bg_file_status(const char *path) {
    int length = MultiByteToWideChar(CP_UTF8, 0, path, -1, NULL, 0);
    if (length <= 0) return -1;
    wchar_t *wide = (wchar_t *)HeapAlloc(GetProcessHeap(), 0, length * sizeof(wchar_t));
    if (!wide) return -1;
    MultiByteToWideChar(CP_UTF8, 0, path, -1, wide, length);
    DWORD attributes = GetFileAttributesW(wide);
    DWORD error = attributes == INVALID_FILE_ATTRIBUTES ? GetLastError() : ERROR_SUCCESS;
    HeapFree(GetProcessHeap(), 0, wide);
    if (attributes == INVALID_FILE_ATTRIBUTES) {
        return error == ERROR_FILE_NOT_FOUND || error == ERROR_PATH_NOT_FOUND ? 0 : -1;
    }
    return attributes & (FILE_ATTRIBUTE_DIRECTORY | FILE_ATTRIBUTE_REPARSE_POINT) ? 2 : 1;
}
#else
void *bg_lock_file(const char *path) { return NULL; }
void bg_unlock_file(void *handle) {}
int bg_file_status(const char *path) { return -1; }
int bg_sha256(const uint8_t *bytes, int32_t length, uint8_t result[32]) { return 0; }
#endif
