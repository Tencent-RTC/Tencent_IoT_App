#include "watch/app.h"

#include <stdlib.h>
#include <string.h>

struct watch_app {
  watch_app_config_t config;
  watch_signaling_t *signaling;
  watch_message_t *message;
  watch_call_option_t pending_option;
  uint64_t accept_at_ms;
  uint64_t now_ms;
  int started;
};

static void watch_app_notify(watch_app_t *app, watch_call_state_t state, const char *peer) {
  if (app->config.on_call_state) app->config.on_call_state(state, peer ? peer : "", app->config.user_data);
}

static int watch_app_send_signal(const char *to_user_id, const char *json, size_t length,
                                 void *user_data) {
  watch_app_t *app = (watch_app_t *)user_data;
  if (!app) return -1;
  if (app->config.send_signal) {
    return app->config.send_signal(to_user_id, json, length, app->config.send_signal_user_data);
  }
  if (!app->message) return -1;
  char text[1024];
  if (length >= sizeof(text)) return -1;
  memcpy(text, json, length);
  text[length] = '\0';
  return watch_message_send(app->message, to_user_id, text);
}

static void watch_app_call_requested(const char *peer, const watch_call_option_t *option,
                                     void *user_data) {
  watch_app_t *app = (watch_app_t *)user_data;
  if (!app || !option) return;
  app->pending_option = *option;
  app->accept_at_ms = app->now_ms + (uint64_t)app->config.auto_accept_delay_sec * 1000;
  // 0 在 tick 里表示“没有待接听”；延时为 0 且尚未 tick 过（now_ms=0）时避免被误判。
  if (app->accept_at_ms == 0) app->accept_at_ms = 1;
  watch_app_notify(app, WATCH_CALL_INCOMING, peer);
}

static void watch_app_call_accepted(const char *peer, void *user_data) {
  watch_app_t *app = (watch_app_t *)user_data;
  if (!app) return;
  if (!watch_media_is_active(app->config.media) &&
      watch_media_start(app->config.media, &app->pending_option, peer) != 0) {
    (void)watch_media_hangup(app->config.media, peer);
    return;
  }
  if (watch_media_accept(app->config.media, peer) != 0) {
    watch_media_stop(app->config.media);
    return;
  }
  watch_app_notify(app, WATCH_CALL_ACTIVE, peer);
}

static void watch_app_call_rejected(const char *peer, watch_signal_reason_t reason,
                                    void *user_data) {
  (void)reason;
  watch_app_t *app = (watch_app_t *)user_data;
  if (!app) return;
  watch_media_stop(app->config.media);
  watch_app_notify(app, WATCH_CALL_IDLE, peer);
}

static void watch_app_call_timeout(const char *peer, void *user_data) {
  watch_app_t *app = (watch_app_t *)user_data;
  if (!app) return;
  watch_media_stop(app->config.media);
  watch_app_notify(app, WATCH_CALL_IDLE, peer);
}

static void watch_app_call_hangup(const char *peer, void *user_data) {
  watch_app_t *app = (watch_app_t *)user_data;
  if (!app) return;
  watch_media_stop(app->config.media);
  watch_app_notify(app, WATCH_CALL_IDLE, peer);
}

watch_app_t *watch_app_create(const watch_app_config_t *config) {
  if (!config || !config->user_id || !config->user_id[0] || !config->media) return NULL;
  watch_app_t *app = (watch_app_t *)calloc(1, sizeof(*app));
  if (!app) return NULL;
  app->config = *config;
  watch_signaling_callbacks_t callbacks = {
      .on_call_requested = watch_app_call_requested,
      .on_call_accepted = watch_app_call_accepted,
      .on_call_rejected = watch_app_call_rejected,
      .on_call_timeout = watch_app_call_timeout,
      .on_call_hangup = watch_app_call_hangup,
  };
  app->signaling = watch_signaling_create(config->user_id, watch_app_send_signal, app,
                                          &callbacks, app);
  if (!app->signaling) {
    free(app);
    return NULL;
  }
  watch_signaling_set_timeout(app->signaling, (uint64_t)(config->call_timeout_sec ? config->call_timeout_sec : 30) * 1000);
  app->message = config->message;
  return app;
}

void watch_app_set_message(watch_app_t *app, watch_message_t *message) {
  if (app) app->message = message;
}

void watch_app_destroy(watch_app_t *app) {
  if (!app) return;
  watch_app_stop(app);
  watch_signaling_destroy(app->signaling);
  free(app);
}

int watch_app_start(watch_app_t *app) {
  if (!app || app->started) return -1;
  if (app->message && watch_message_start(app->message) != 0) return -1;
  app->started = 1;
  return 0;
}

void watch_app_stop(watch_app_t *app) {
  if (!app) return;
  if (app->signaling && watch_signaling_state(app->signaling) != WATCH_CALL_IDLE) {
    const char *peer = watch_signaling_peer(app->signaling);
    if (peer[0]) {
      (void)watch_media_hangup(app->config.media, peer);
      (void)watch_signaling_hangup(app->signaling, peer);
    } else {
      watch_media_stop(app->config.media);
    }
  }
  if (app->message) watch_message_stop(app->message, 3000);
  app->started = 0;
}

int watch_app_call(watch_app_t *app, const char *peer_user_id, const watch_call_option_t *option) {
  if (!app || !app->started || !option) return -1;
  app->pending_option = *option;
  int result = watch_signaling_call(app->signaling, peer_user_id, option);
  if (result == 0) watch_app_notify(app, WATCH_CALL_OUTGOING, peer_user_id);
  return result;
}

int watch_app_hangup(watch_app_t *app) {
  if (!app || !app->signaling) return -1;
  const char *peer = watch_signaling_peer(app->signaling);
  if (!peer[0]) return -1;
  (void)watch_media_hangup(app->config.media, peer);
  int result = watch_signaling_hangup(app->signaling, peer);
  watch_app_notify(app, WATCH_CALL_IDLE, peer);
  return result;
}

void watch_app_tick(watch_app_t *app, uint64_t now_ms) {
  if (!app || !app->signaling) return;
  app->now_ms = now_ms;
  watch_signaling_tick(app->signaling, now_ms);
  if (watch_signaling_state(app->signaling) == WATCH_CALL_INCOMING &&
      app->accept_at_ms != 0 && now_ms >= app->accept_at_ms) {
    const char *peer = watch_signaling_peer(app->signaling);
    if (watch_media_start(app->config.media, &app->pending_option, peer) == 0) {
      if (watch_signaling_accept(app->signaling, peer) != 0) watch_media_stop(app->config.media);
    } else {
      (void)watch_signaling_reject(app->signaling, peer);
    }
    app->accept_at_ms = 0;
  }
}

watch_call_state_t watch_app_state(const watch_app_t *app) {
  return app && app->signaling ? watch_signaling_state(app->signaling) : WATCH_CALL_IDLE;
}

void watch_app_receive_text(watch_app_t *app, const char *from_user_id, const char *text) {
  if (!app || !from_user_id || !text) return;
  watch_signal_message_t signal;
  if (watch_signal_decode(text, strlen(text), &signal)) {
    watch_signaling_receive(app->signaling, from_user_id, text, strlen(text));
  } else if (app->config.on_text) {
    app->config.on_text(from_user_id, text, app->config.user_data);
  }
}
