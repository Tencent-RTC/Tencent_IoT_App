#include "watch/signaling.h"

#include <stdlib.h>
#include <string.h>

struct watch_signaling {
  char local_user_id[WATCH_USER_ID_MAX];
  char peer_user_id[WATCH_USER_ID_MAX];
  watch_call_state_t state;
  uint32_t sid;
  uint32_t next_sid;
  uint64_t deadline_ms;
  uint64_t timeout_ms;
  watch_call_option_t option;
  watch_signaling_send_callback send;
  void *send_user_data;
  watch_signaling_callbacks_t callbacks;
  void *callback_user_data;
};

static void watch_copy_id(char *destination, size_t size, const char *source) {
  if (!destination || size == 0) return;
  destination[0] = '\0';
  if (source) {
    strncpy(destination, source, size - 1);
    destination[size - 1] = '\0';
  }
}

watch_signaling_t *watch_signaling_create(const char *local_user_id,
                                          watch_signaling_send_callback send,
                                          void *send_user_data,
                                          const watch_signaling_callbacks_t *callbacks,
                                          void *callback_user_data) {
  if (!local_user_id || !local_user_id[0] || strlen(local_user_id) >= WATCH_USER_ID_MAX || !send) {
    return NULL;
  }
  watch_signaling_t *signaling = (watch_signaling_t *)calloc(1, sizeof(*signaling));
  if (!signaling) return NULL;
  watch_copy_id(signaling->local_user_id, sizeof(signaling->local_user_id), local_user_id);
  signaling->send = send;
  signaling->send_user_data = send_user_data;
  if (callbacks) signaling->callbacks = *callbacks;
  signaling->callback_user_data = callback_user_data;
  signaling->timeout_ms = 30000;
  signaling->next_sid = 1;
  return signaling;
}

void watch_signaling_set_timeout(watch_signaling_t *signaling, uint64_t timeout_ms) {
  if (signaling && timeout_ms > 0) signaling->timeout_ms = timeout_ms;
}

void watch_signaling_destroy(watch_signaling_t *signaling) { free(signaling); }

static int watch_signaling_send(watch_signaling_t *signaling, watch_signal_type_t type,
                                const char *peer_user_id, uint32_t sid,
                                watch_signal_reason_t reason, const watch_call_option_t *option) {
  watch_signal_message_t message;
  memset(&message, 0, sizeof(message));
  message.type = type;
  message.sid = sid;
  watch_copy_id(message.to, sizeof(message.to), peer_user_id);
  message.reason = reason;
  if (option) message.option = *option;
  char json[1024];
  size_t length = watch_signal_encode(&message, json, sizeof(json));
  if (!length) return -1;
  return signaling->send(peer_user_id, json, length, signaling->send_user_data);
}

static void watch_signaling_clear(watch_signaling_t *signaling) {
  signaling->state = WATCH_CALL_IDLE;
  signaling->peer_user_id[0] = '\0';
  signaling->sid = 0;
  signaling->deadline_ms = 0;
  memset(&signaling->option, 0, sizeof(signaling->option));
}

int watch_signaling_call(watch_signaling_t *signaling, const char *peer_user_id,
                         const watch_call_option_t *option) {
  if (!signaling || !peer_user_id || !peer_user_id[0] || strlen(peer_user_id) >= WATCH_USER_ID_MAX ||
      !option || signaling->state != WATCH_CALL_IDLE) return -1;
  watch_copy_id(signaling->peer_user_id, sizeof(signaling->peer_user_id), peer_user_id);
  signaling->sid = signaling->next_sid++;
  if (signaling->next_sid == 0) signaling->next_sid = 1;
  signaling->option = *option;
  signaling->state = WATCH_CALL_OUTGOING;
  if (watch_signaling_send(signaling, WATCH_SIGNAL_CALL, peer_user_id, signaling->sid,
                           WATCH_SIGNAL_REASON_NONE, option) != 0) {
    watch_signaling_clear(signaling);
    return -1;
  }
  signaling->deadline_ms = 0;
  return 0;
}

int watch_signaling_accept(watch_signaling_t *signaling, const char *peer_user_id) {
  if (!signaling || !peer_user_id || signaling->state != WATCH_CALL_INCOMING ||
      strcmp(signaling->peer_user_id, peer_user_id) != 0) return -1;
  uint32_t sid = signaling->sid;
  signaling->state = WATCH_CALL_ACTIVE;
  if (watch_signaling_send(signaling, WATCH_SIGNAL_ACCEPT, peer_user_id, sid,
                           WATCH_SIGNAL_REASON_NONE, NULL) != 0) {
    signaling->state = WATCH_CALL_INCOMING;
    return -1;
  }
  if (signaling->callbacks.on_call_accepted) {
    signaling->callbacks.on_call_accepted(peer_user_id, signaling->callback_user_data);
  }
  return 0;
}

int watch_signaling_reject(watch_signaling_t *signaling, const char *peer_user_id) {
  if (!signaling || !peer_user_id || signaling->state != WATCH_CALL_INCOMING ||
      strcmp(signaling->peer_user_id, peer_user_id) != 0) return -1;
  uint32_t sid = signaling->sid;
  char peer[WATCH_USER_ID_MAX];
  watch_copy_id(peer, sizeof(peer), peer_user_id);
  watch_signaling_clear(signaling);
  return watch_signaling_send(signaling, WATCH_SIGNAL_REJECT, peer, sid,
                              WATCH_SIGNAL_REASON_DECLINE, NULL);
}

int watch_signaling_hangup(watch_signaling_t *signaling, const char *peer_user_id) {
  if (!signaling || !peer_user_id ||
      (signaling->state != WATCH_CALL_OUTGOING && signaling->state != WATCH_CALL_ACTIVE) ||
      strcmp(signaling->peer_user_id, peer_user_id) != 0) return -1;
  uint32_t sid = signaling->sid;
  char peer[WATCH_USER_ID_MAX];
  watch_copy_id(peer, sizeof(peer), peer_user_id);
  watch_signal_reason_t reason = signaling->state == WATCH_CALL_OUTGOING
                                     ? WATCH_SIGNAL_REASON_CANCEL
                                     : WATCH_SIGNAL_REASON_USER_HANGUP;
  watch_signaling_clear(signaling);
  return watch_signaling_send(signaling, WATCH_SIGNAL_HANGUP, peer, sid, reason, NULL);
}

void watch_signaling_receive(watch_signaling_t *signaling, const char *from_user_id,
                             const char *json, size_t length) {
  if (!signaling || !from_user_id || !from_user_id[0] || !json) return;
  watch_signal_message_t message;
  if (!watch_signal_decode(json, length, &message) || strcmp(message.to, signaling->local_user_id) != 0) return;

  if (message.type == WATCH_SIGNAL_CALL) {
    if (signaling->state != WATCH_CALL_IDLE) {
      (void)watch_signaling_send(signaling, WATCH_SIGNAL_REJECT, from_user_id, message.sid,
                                 WATCH_SIGNAL_REASON_BUSY, NULL);
      return;
    }
    watch_copy_id(signaling->peer_user_id, sizeof(signaling->peer_user_id), from_user_id);
    signaling->sid = message.sid;
    signaling->option = message.option;
    signaling->state = WATCH_CALL_INCOMING;
    if (signaling->callbacks.on_call_requested) {
      signaling->callbacks.on_call_requested(from_user_id, &message.option,
                                             signaling->callback_user_data);
    }
    return;
  }

  if (signaling->state == WATCH_CALL_OUTGOING && strcmp(signaling->peer_user_id, from_user_id) == 0 &&
      signaling->sid == message.sid) {
    if (message.type == WATCH_SIGNAL_ACCEPT) {
      signaling->state = WATCH_CALL_ACTIVE;
      signaling->deadline_ms = 0;
      if (signaling->callbacks.on_call_accepted) {
        signaling->callbacks.on_call_accepted(from_user_id, signaling->callback_user_data);
      }
    } else if (message.type == WATCH_SIGNAL_REJECT) {
      watch_signal_reason_t reason = message.reason;
      watch_signaling_clear(signaling);
      if (signaling->callbacks.on_call_rejected) {
        signaling->callbacks.on_call_rejected(from_user_id, reason, signaling->callback_user_data);
      }
    } else if (message.type == WATCH_SIGNAL_HANGUP) {
      watch_signaling_clear(signaling);
      if (signaling->callbacks.on_call_hangup) {
        signaling->callbacks.on_call_hangup(from_user_id, signaling->callback_user_data);
      }
    }
    return;
  }

  if ((signaling->state == WATCH_CALL_INCOMING || signaling->state == WATCH_CALL_ACTIVE) &&
      strcmp(signaling->peer_user_id, from_user_id) == 0 && signaling->sid == message.sid &&
      message.type == WATCH_SIGNAL_HANGUP) {
    watch_signaling_clear(signaling);
    if (signaling->callbacks.on_call_hangup) {
      signaling->callbacks.on_call_hangup(from_user_id, signaling->callback_user_data);
    }
  }
}

void watch_signaling_tick(watch_signaling_t *signaling, uint64_t now_ms) {
  if (!signaling || signaling->state != WATCH_CALL_OUTGOING) return;
  if (signaling->deadline_ms == 0) {
    signaling->deadline_ms = now_ms + signaling->timeout_ms;
    return;
  }
  if (now_ms < signaling->deadline_ms) return;
  char peer[WATCH_USER_ID_MAX];
  watch_copy_id(peer, sizeof(peer), signaling->peer_user_id);
  uint32_t sid = signaling->sid;
  watch_signaling_clear(signaling);
  (void)watch_signaling_send(signaling, WATCH_SIGNAL_HANGUP, peer, sid,
                             WATCH_SIGNAL_REASON_CANCEL, NULL);
  if (signaling->callbacks.on_call_timeout) {
    signaling->callbacks.on_call_timeout(peer, signaling->callback_user_data);
  }
}

watch_call_state_t watch_signaling_state(const watch_signaling_t *signaling) {
  return signaling ? signaling->state : WATCH_CALL_IDLE;
}

const char *watch_signaling_peer(const watch_signaling_t *signaling) {
  return signaling ? signaling->peer_user_id : "";
}

int watch_signaling_busy(const watch_signaling_t *signaling) {
  return signaling && signaling->state != WATCH_CALL_IDLE;
}
