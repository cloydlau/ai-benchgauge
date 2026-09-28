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
#else
int bg_sha256(const uint8_t *bytes, int32_t length, uint8_t result[32]) { return 0; }
#endif
