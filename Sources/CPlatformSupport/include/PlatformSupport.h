#include <stddef.h>
#include <stdint.h>
int bg_sha256(const uint8_t *bytes, int32_t length, uint8_t result[32]);

void *bg_lock_file(const char *path);
void bg_unlock_file(void *handle);
