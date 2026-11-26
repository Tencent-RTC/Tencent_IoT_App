#include "watch/media.h"

#include <stdlib.h>
#include <string.h>

struct watch_media {
  watch_media_backend_t backend;
  int started;
};

watch_media_t *watch_media_create(const watch_media_backend_t *backend) {
  if (!backend || !backend->start || !backend->accept || !backend->reject ||
      !backend->hangup || !backend->stop) return NULL;
  watch_media_t *media = (watch_media_t *)calloc(1, sizeof(*media));
  if (!media) return NULL;
  media->backend = *backend;
  return media;
}

int watch_media_start(watch_media_t *media, const watch_call_option_t *option,
                      const char *peer_user_id) {
  if (!media || !option || !peer_user_id || media->started) return -1;
  int result = media->backend.start(option, peer_user_id, media->backend.user_data);
  if (result == 0) media->started = 1;
  return result;
}

int watch_media_accept(watch_media_t *media, const char *peer_user_id) {
  if (!media || !peer_user_id || !media->started) return -1;
  return media->backend.accept(peer_user_id, media->backend.user_data);
}

int watch_media_reject(watch_media_t *media, const char *peer_user_id) {
  if (!media || !peer_user_id) return -1;
  return media->backend.reject(peer_user_id, media->backend.user_data);
}

int watch_media_hangup(watch_media_t *media, const char *peer_user_id) {
  if (!media || !peer_user_id || !media->started) return -1;
  int result = media->backend.hangup(peer_user_id, media->backend.user_data);
  media->started = 0;
  return result;
}

int watch_media_is_active(const watch_media_t *media) { return media && media->started; }

void watch_media_stop(watch_media_t *media) {
  if (!media) return;
  if (media->started) media->backend.stop(media->backend.user_data);
  media->started = 0;
}

void watch_media_destroy(watch_media_t *media) {
  if (!media) return;
  watch_media_stop(media);
  free(media);
}
