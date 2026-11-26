#ifndef WATCH_MEDIA_H
#define WATCH_MEDIA_H

#include "watch/types.h"

#ifdef __cplusplus
extern "C" {
#endif

typedef struct watch_media watch_media_t;

typedef struct {
  int (*start)(const watch_call_option_t *option, const char *peer_user_id, void *user_data);
  int (*accept)(const char *peer_user_id, void *user_data);
  int (*reject)(const char *peer_user_id, void *user_data);
  int (*hangup)(const char *peer_user_id, void *user_data);
  void (*stop)(void *user_data);
  void *user_data;
} watch_media_backend_t;

watch_media_t *watch_media_create(const watch_media_backend_t *backend);
int watch_media_start(watch_media_t *media, const watch_call_option_t *option,
                      const char *peer_user_id);
int watch_media_accept(watch_media_t *media, const char *peer_user_id);
int watch_media_reject(watch_media_t *media, const char *peer_user_id);
int watch_media_hangup(watch_media_t *media, const char *peer_user_id);
int watch_media_is_active(const watch_media_t *media);
void watch_media_stop(watch_media_t *media);
void watch_media_destroy(watch_media_t *media);

#ifdef __cplusplus
}
#endif

#endif
