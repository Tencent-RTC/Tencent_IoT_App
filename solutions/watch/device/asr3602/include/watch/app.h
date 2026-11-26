#ifndef WATCH_APP_H
#define WATCH_APP_H

#include <stdint.h>

#include "watch/media.h"
#include "watch/message.h"
#include "watch/signaling.h"

#ifdef __cplusplus
extern "C" {
#endif

typedef struct watch_app watch_app_t;

typedef struct {
  const char *user_id;
  unsigned int auto_accept_delay_sec;
  unsigned int call_timeout_sec;
  watch_message_t *message;
  watch_media_t *media;
  watch_signaling_send_callback send_signal;
  void *send_signal_user_data;
  void (*on_text)(const char *from_user_id, const char *text, void *user_data);
  void (*on_call_state)(watch_call_state_t state, const char *peer_user_id, void *user_data);
  void *user_data;
} watch_app_config_t;

watch_app_t *watch_app_create(const watch_app_config_t *config);
void watch_app_set_message(watch_app_t *app, watch_message_t *message);
void watch_app_destroy(watch_app_t *app);
int watch_app_start(watch_app_t *app);
void watch_app_stop(watch_app_t *app);
int watch_app_call(watch_app_t *app, const char *peer_user_id,
                   const watch_call_option_t *option);
int watch_app_hangup(watch_app_t *app);
void watch_app_tick(watch_app_t *app, uint64_t now_ms);
watch_call_state_t watch_app_state(const watch_app_t *app);
void watch_app_receive_text(watch_app_t *app, const char *from_user_id, const char *text);

#ifdef __cplusplus
}
#endif

#endif
