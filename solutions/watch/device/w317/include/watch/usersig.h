#ifndef WATCH_USERSIG_H
#define WATCH_USERSIG_H

#include <stddef.h>
#include <stdint.h>

#ifdef __cplusplus
extern "C" {
#endif

#define WATCH_USERSIG_DEFAULT_EXPIRE_SEC 604800u

int watch_usersig_generate_at(uint32_t sdk_app_id, const char *secret_key,
                              const char *user_id, uint32_t expire_sec, int64_t now,
                              char *out, size_t out_size);
int watch_usersig_generate(uint32_t sdk_app_id, const char *secret_key, const char *user_id,
                           uint32_t expire_sec, char *out, size_t out_size);

void watch_usersig_sha256(const uint8_t *msg, size_t len, uint8_t out[32]);
void watch_usersig_hmac_sha256(const uint8_t *key, size_t key_len, const uint8_t *msg,
                               size_t msg_len, uint8_t out[32]);

#ifdef __cplusplus
}
#endif

#endif
