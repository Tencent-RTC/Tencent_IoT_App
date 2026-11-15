#ifndef WATCH_SIGNALING_H
#define WATCH_SIGNALING_H

#include <stddef.h>
#include <stdint.h>

#include "watch/types.h"

#ifdef __cplusplus
extern "C" {
#endif

typedef enum {
  WATCH_SIGNAL_UNKNOWN = 0,
  WATCH_SIGNAL_CALL,
  WATCH_SIGNAL_ACCEPT,
  WATCH_SIGNAL_REJECT,
  WATCH_SIGNAL_HANGUP,
} watch_signal_type_t;

typedef enum {
  WATCH_SIGNAL_REASON_NONE = 0,
  WATCH_SIGNAL_REASON_DECLINE,
  WATCH_SIGNAL_REASON_BUSY,
  WATCH_SIGNAL_REASON_CANCEL,
  WATCH_SIGNAL_REASON_USER_HANGUP,
} watch_signal_reason_t;

typedef struct {
  watch_signal_type_t type;
  uint32_t sid;
  char to[WATCH_USER_ID_MAX];
  watch_call_option_t option;
  watch_signal_reason_t reason;
} watch_signal_message_t;

size_t watch_signal_encode(const watch_signal_message_t *message, char *buffer, size_t size);
int watch_signal_decode(const char *json, size_t length, watch_signal_message_t *message);
const char *watch_signal_reason_string(watch_signal_reason_t reason);

typedef enum {
  WATCH_CALL_IDLE = 0,
  WATCH_CALL_OUTGOING,
  WATCH_CALL_INCOMING,
  WATCH_CALL_ACTIVE,
} watch_call_state_t;

typedef struct watch_signaling watch_signaling_t;

typedef int (*watch_signaling_send_callback)(const char *to_user_id, const char *json,
                                             size_t length, void *user_data);

typedef struct {
  void (*on_call_requested)(const char *peer_user_id, const watch_call_option_t *option,
                            void *user_data);
  void (*on_call_accepted)(const char *peer_user_id, void *user_data);
  void (*on_call_rejected)(const char *peer_user_id, watch_signal_reason_t reason,
                           void *user_data);
  void (*on_call_timeout)(const char *peer_user_id, void *user_data);
  void (*on_call_hangup)(const char *peer_user_id, void *user_data);
} watch_signaling_callbacks_t;

watch_signaling_t *watch_signaling_create(const char *local_user_id,
                                          watch_signaling_send_callback send,
                                          void *send_user_data,
                                          const watch_signaling_callbacks_t *callbacks,
                                          void *callback_user_data);
void watch_signaling_set_timeout(watch_signaling_t *signaling, uint64_t timeout_ms);
void watch_signaling_destroy(watch_signaling_t *signaling);
int watch_signaling_call(watch_signaling_t *signaling, const char *peer_user_id,
                         const watch_call_option_t *option);
int watch_signaling_accept(watch_signaling_t *signaling, const char *peer_user_id);
int watch_signaling_reject(watch_signaling_t *signaling, const char *peer_user_id);
int watch_signaling_hangup(watch_signaling_t *signaling, const char *peer_user_id);
void watch_signaling_receive(watch_signaling_t *signaling, const char *from_user_id,
                             const char *json, size_t length);
void watch_signaling_tick(watch_signaling_t *signaling, uint64_t now_ms);
watch_call_state_t watch_signaling_state(const watch_signaling_t *signaling);
const char *watch_signaling_peer(const watch_signaling_t *signaling);
int watch_signaling_busy(const watch_signaling_t *signaling);

#ifdef __cplusplus
}
#endif

#endif
